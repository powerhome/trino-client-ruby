# ActiveRecord Trino Adapter Integration Guide

## Overview

The Trino ActiveRecord adapter allows you to use ActiveRecord with Trino as a data source. This is particularly useful for:

- Querying large analytical datasets with ActiveRecord's familiar API
- Building read-only models for data warehouse tables
- Integrating Trino data into Rails applications

## Installation

Add to your Gemfile:

```ruby
gem 'trino-client'
gem 'activerecord', '>= 6.0'
```

Then require the adapter:

```ruby
require 'activerecord-trino-adapter'
```

## Configuration

### Rails Application (config/database.yml)

```yaml
trino:
  adapter: trino
  host: trino.example.com
  port: 8080
  catalog: hive
  schema: production
  username: <%= ENV['TRINO_USER'] %>
  password: <%= ENV['TRINO_PASSWORD'] %>
  ssl: true
  properties:
    query_max_execution_time: "30m"
```

### Standalone Ruby Application

```ruby
require 'activerecord-trino-adapter'

ActiveRecord::Base.establish_connection(
  adapter: 'trino',
  host: 'trino.example.com',
  port: 8080,
  catalog: 'hive',
  schema: 'production',
  username: ENV['TRINO_USER'],
  password: ENV['TRINO_PASSWORD'],
  ssl: true
)
```

## Usage Patterns

### Read-Only Models

Since Trino is primarily for analytical queries, models should typically be read-only:

```ruby
class SalesTransaction < ActiveRecord::Base
  self.table_name = 'sales_transactions'
  self.primary_key = nil # Trino doesn't enforce primary keys

  # Optional: Define virtual attributes for computed columns
  def revenue
    quantity * unit_price
  end

  # Optional: Scopes for common queries
  scope :recent, -> { where("transaction_date >= DATE '2024-01-01'") }
  scope :by_region, ->(region) { where(region: region) }
end

# Query examples
SalesTransaction.where("amount > 1000").limit(100)
SalesTransaction.recent.by_region('US').count
```

### Complex Analytical Queries

Use ActiveRecord's query interface for complex analytics:

```ruby
# Aggregations
SalesTransaction
  .select("region, SUM(amount) as total_sales")
  .where("transaction_date >= DATE '2024-01-01'")
  .group("region")
  .order("total_sales DESC")

# Window functions (using raw SQL)
ActiveRecord::Base.connection.exec_query(<<-SQL)
  SELECT
    product_id,
    sales_date,
    revenue,
    SUM(revenue) OVER (
      PARTITION BY product_id
      ORDER BY sales_date
      ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as rolling_7day_revenue
  FROM sales
  WHERE sales_date >= DATE '2024-01-01'
SQL
```

### Multiple Catalogs/Schemas

Query across different catalogs or schemas:

```ruby
# Option 1: Use fully qualified table names
result = ActiveRecord::Base.connection.execute(
  "SELECT * FROM catalog_name.schema_name.table_name"
)

# Option 2: Establish separate connections
class HiveConnection < ActiveRecord::Base
  self.abstract_class = true
  establish_connection(
    adapter: 'trino',
    host: 'trino.example.com',
    port: 8080,
    catalog: 'hive',
    schema: 'production'
  )
end

class IcebergConnection < ActiveRecord::Base
  self.abstract_class = true
  establish_connection(
    adapter: 'trino',
    host: 'trino.example.com',
    port: 8080,
    catalog: 'iceberg',
    schema: 'analytics'
  )
end

class HiveTable < HiveConnection
  self.table_name = 'my_table'
end

class IcebergTable < IcebergConnection
  self.table_name = 'my_table'
end
```

### Working with Views

Trino views work seamlessly with ActiveRecord:

```ruby
class MonthlySalesSummary < ActiveRecord::Base
  self.table_name = 'monthly_sales_summary' # This is a Trino view
  self.primary_key = nil

  # Query the view like any other table
  # MonthlySalesSummary.where(year: 2024, month: 1)
end
```

### Raw SQL Queries

For complex Trino-specific queries:

```ruby
# Using exec_query (returns ActiveRecord::Result)
result = ActiveRecord::Base.connection.exec_query(<<-SQL)
  WITH regional_sales AS (
    SELECT region, SUM(amount) as total
    FROM sales
    WHERE sale_date >= DATE '2024-01-01'
    GROUP BY region
  )
  SELECT
    region,
    total,
    total * 100.0 / SUM(total) OVER () as percentage
  FROM regional_sales
  ORDER BY total DESC
SQL

result.rows.each do |row|
  puts "#{row[0]}: #{row[1]} (#{row[2]}%)"
end

# Using execute (returns TrinoResult)
result = ActiveRecord::Base.connection.execute("SELECT * FROM large_table")
result.rows.each { |row| process(row) }
```

## Best Practices

### 1. Use Appropriate Data Types

Map Trino types to Ruby types correctly:

```ruby
class EventLog < ActiveRecord::Base
  # Trino timestamp -> Ruby Time
  # Trino date -> Ruby Date
  # Trino json -> String (parse manually)

  def metadata_hash
    JSON.parse(metadata) if metadata
  end
end
```

### 2. Limit Result Sets

Trino queries can return large datasets. Always use limits:

```ruby
# Good
User.where("signup_date >= DATE '2024-01-01'").limit(1000)

# Bad - could return millions of rows
User.where("signup_date >= DATE '2024-01-01'").to_a
```

### 3. Use Batch Processing

For large result sets, process in batches:

```ruby
# Using find_each (may not work well with Trino)
# Instead, use manual pagination:

offset = 0
batch_size = 1000

loop do
  batch = SalesTransaction
    .where("date >= DATE '2024-01-01'")
    .limit(batch_size)
    .offset(offset)
    .to_a

  break if batch.empty?

  batch.each { |record| process(record) }
  offset += batch_size
end
```

### 4. Avoid N+1 Queries

Since Trino queries can be expensive, minimize the number of queries:

```ruby
# Bad - N+1 queries
users = User.limit(100)
users.each do |user|
  user.orders.count # Separate query for each user
end

# Good - Single query with aggregation
ActiveRecord::Base.connection.exec_query(<<-SQL)
  SELECT
    user_id,
    COUNT(*) as order_count
  FROM orders
  GROUP BY user_id
SQL
```

### 5. Handle NULL Values

Trino columns are nullable by default:

```ruby
class Product < ActiveRecord::Base
  # Always check for nil
  def display_price
    price&.round(2) || 'N/A'
  end
end
```

## Limitations

### What Doesn't Work

- **Migrations**: `rake db:migrate` and schema modifications
- **Transactions**: `ActiveRecord::Base.transaction { }` blocks
- **Callbacks on writes**: `before_save`, `after_create`, etc.
- **Validations on save**: Model validations won't prevent writes
- **Associations with foreign keys**: No referential integrity
- **Auto-incrementing IDs**: No sequence support
- **find_by_id**: Primary keys don't exist

### Workarounds

#### For Associations

Use manual queries instead of ActiveRecord associations:

```ruby
class Order < ActiveRecord::Base
  self.primary_key = nil

  def customer
    Customer.where(id: customer_id).first
  end

  def line_items
    LineItem.where(order_id: id)
  end
end
```

#### For Writes

Write operations may work with some catalogs (like Iceberg) but should be tested:

```ruby
# May work with writable catalogs
ActiveRecord::Base.connection.execute(<<-SQL)
  INSERT INTO events (event_type, user_id, timestamp)
  VALUES ('login', 123, current_timestamp)
SQL
```

## Troubleshooting

### Connection Issues

```ruby
# Test the connection
if ActiveRecord::Base.connection.active?
  puts "Connected successfully"
else
  puts "Connection failed"
end

# Check Trino server
result = ActiveRecord::Base.connection.execute("SELECT version()")
puts "Trino version: #{result.rows.first.first}"
```

### Query Errors

```ruby
begin
  result = ActiveRecord::Base.connection.exec_query("SELECT * FROM invalid_table")
rescue ActiveRecord::StatementInvalid => e
  puts "Query failed: #{e.message}"
end
```

### Performance Issues

- Use EXPLAIN to understand query execution:

```ruby
result = ActiveRecord::Base.connection.exec_query(
  "EXPLAIN SELECT * FROM large_table WHERE date >= DATE '2024-01-01'"
)
puts result.rows
```

## Additional Resources

- [Trino Documentation](https://trino.io/docs/current/)
- [ActiveRecord Query Interface](https://guides.rubyonrails.org/active_record_querying.html)
- [Trino SQL Reference](https://trino.io/docs/current/sql.html)

## Contributing

If you encounter issues or have improvements for the adapter, please file an issue or submit a pull request on the [GitHub repository](https://github.com/treasure-data/trino-client-ruby).
