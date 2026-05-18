# Trino client library for Ruby

[![Ruby](https://github.com/treasure-data/trino-client-ruby/actions/workflows/ruby.yml/badge.svg)](https://github.com/treasure-data/trino-client-ruby/actions/workflows/ruby.yml) [![Gem](https://img.shields.io/gem/v/trino-client)](https://rubygems.org/gems/trino-client) [![Gem](https://img.shields.io/gem/dt/trino-client)](https://rubygems.org/gems/trino-client) [![GitHub](https://img.shields.io/github/license/treasure-data/trino-client-ruby)]()
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/treasure-data/trino-client-ruby)

Trino is a distributed SQL query engine for big data:
https://trino.io/

This is a client library for Ruby to run queries on Trino.

## Example

```ruby
require 'trino-client'

# create a client object:
client = Trino::Client.new(
  server: "localhost:8880",   # required option
  ssl: {verify: false},
  catalog: "native",
  schema: "default",
  user: "frsyuki",
  password: "********",
  time_zone: "US/Pacific",
  language: "English",
  properties: {
    "hive.force_local_scheduling": true,
    "raptor.reader_stream_buffer_size": "32MB"
  },
  http_proxy: "proxy.example.com:8080",
  http_debug: true
)

# run a query and get results as an array of arrays:
columns, rows = client.run("select * from sys.node")
rows.each {|row|
  p row  # row is an array
}

# run a query and get results as an array of hashes:
results = client.run_with_names("select alpha, 1 AS beta from tablename")
results.each {|row|
  p row['alpha']   # access by name
  p row['beta']
  p row.values[0]  # access by index
  p row.values[1]
}

# run a query and fetch results streamingly:
client.query("select * from sys.node") do |q|
  # get columns:
  q.columns.each {|column|
    puts "column: #{column.name}.#{column.type}"
  }

  # get query results. it feeds more rows until
  # query execution finishes:
  q.each_row {|row|
    p row  # row is an array
  }
end

# killing a query
query = client.query("select * from sys.node")
query_id = query.query_info.query_id
query.each_row {|row| ... }  # when a thread is processing the query,
client.kill(query_id)  # another thread / process can kill the query.

# Use Query#transform_row to parse Trino ROW types into Ruby Hashes.
# You can also set a scalar_parser to parse scalars how you'd like them.
scalar_parser = -> (data, type) { (type === 'json') ? JSON.parse(data) : data }
client.query("select * from sys.node") do |q|
  q.scalar_parser = scalar_parser

  # get query results. it feeds more rows until
  # query execution finishes:
  q.each_row {|row|
    p q.transform_row(row)
  }
end
```

## ActiveRecord Adapter (Optional)

This library includes an optional ActiveRecord adapter for using Trino as a data source with ActiveRecord. This allows you to use familiar ActiveRecord query interfaces to interact with Trino tables.

### Installation

To use the ActiveRecord adapter, you need to install ActiveRecord separately:

```ruby
# In your Gemfile
gem 'trino-client'
gem 'activerecord', '>= 6.0'
```

Then require the adapter in your code:

```ruby
require 'activerecord-trino-adapter'
```

### Configuration

You can configure the Trino connection in your `database.yml`:

```yaml
# config/database.yml
development:
  adapter: trino
  host: localhost
  port: 8080
  catalog: hive
  schema: default
  username: trino_user
  # Optional settings:
  # password: secret
  # ssl: false
  # time_zone: UTC
  # http_proxy: proxy.example.com:8080
  # properties:
  #   hive.force_local_scheduling: true
```

Or establish a connection programmatically:

```ruby
ActiveRecord::Base.establish_connection(
  adapter: 'trino',
  host: 'localhost',
  port: 8080,
  catalog: 'hive',
  schema: 'default',
  username: 'trino_user'
)
```

### Usage Examples

#### Basic Queries

```ruby
# Execute raw SQL
result = ActiveRecord::Base.connection.execute("SELECT * FROM my_table LIMIT 10")
result.rows.each do |row|
  puts row.inspect
end

# Using exec_query for structured results
result = ActiveRecord::Base.connection.exec_query("SELECT name, age FROM users")
result.columns # => ["name", "age"]
result.rows    # => [["Alice", 30], ["Bob", 25]]
```

#### Defining Models

```ruby
class User < ActiveRecord::Base
  self.table_name = 'users'

  # Note: Trino doesn't support primary keys, so you may need to handle IDs differently
  self.primary_key = nil
end

# Query with ActiveRecord methods
User.where("age > 25").limit(10).each do |user|
  puts "#{user.name} is #{user.age} years old"
end

# Select specific columns
User.select(:name, :email).where("created_at > DATE '2024-01-01'")
```

#### Schema Inspection

```ruby
connection = ActiveRecord::Base.connection

# List all tables
connection.tables
# => ["users", "orders", "products"]

# Get columns for a table
connection.columns('users')
# => [#<ActiveRecord::ConnectionAdapters::TrinoColumn...>]

# Check if table exists
connection.table_exists?('users')
# => true
```

#### Working with Different Catalogs and Schemas

```ruby
# Query from a different catalog/schema
result = ActiveRecord::Base.connection.execute(
  "SELECT * FROM other_catalog.other_schema.table_name"
)

# Or establish a new connection for a different catalog
ActiveRecord::Base.establish_connection(
  adapter: 'trino',
  host: 'localhost',
  port: 8080,
  catalog: 'memory',  # Different catalog
  schema: 'analytics',
  username: 'analyst'
)
```

### Important Limitations

Since Trino is primarily designed for analytical queries, the ActiveRecord adapter has some limitations:

- **Read-only**: Write operations (INSERT, UPDATE, DELETE) may not work with all catalogs
- **No Transactions**: Trino doesn't support traditional transactions
- **No Primary Keys**: Trino doesn't enforce primary key constraints
- **No Migrations**: Schema migrations are not supported
- **No Indexes**: Traditional database indexes don't exist in Trino
- **Limited DDL**: CREATE/DROP table support depends on the catalog/connector

### Supported Features

- ✅ SELECT queries with WHERE, ORDER BY, LIMIT, etc.
- ✅ JOINs (INNER, LEFT, RIGHT, FULL)
- ✅ Aggregations (COUNT, SUM, AVG, etc.)
- ✅ Common Table Expressions (CTEs)
- ✅ Subqueries
- ✅ Schema inspection (tables, columns)
- ✅ Views and materialized views
- ✅ Type mapping for common SQL types
- ✅ Query explain

### Type Mapping

The adapter maps Trino types to Ruby/ActiveRecord types:

| Trino Type | Ruby Type | ActiveRecord Type |
|------------|-----------|-------------------|
| `varchar`, `char` | String | :string |
| `integer`, `int` | Integer | :integer |
| `bigint` | Integer | :bigint |
| `double`, `real` | Float | :float |
| `decimal` | BigDecimal | :decimal |
| `boolean` | Boolean | :boolean |
| `date` | Date | :date |
| `time` | Time | :time |
| `timestamp` | Time | :datetime |
| `varbinary` | String | :binary |
| `json` | String (parsed) | :json |

## Build models

```
$ bundle exec rake modelgen:latest
```

## Options

* **server** sets address (and port) of a Trino coordinator server.
* **ssl** enables https.
  * Setting `true` enables SSL and verifies server certificate using system's built-in certificates.
  * Setting `{verify: false}` enables SSL but doesn't verify server certificate.
  * Setting a Hash object enables SSL and verify server certificate with options:
    * **ca_file**: path of a CA certification file in PEM format
    * **ca_path**: path of a CA certification directory containing certifications in PEM format
    * **cert_store**: a `OpenSSL::X509::Store` object used for verification
    * **client_cert**: a `OpenSSL::X509::Certificate` object as client certificate
    * **client_key**: a `OpenSSL::PKey::RSA` or `OpenSSL::PKey::DSA` object used for client certificate
* **catalog** sets catalog (connector) name of Trino such as `hive-cdh4`, `hive-hadoop1`, etc.
* **schema** sets default schema name of Trino. You need to use qualified name like `FROM myschema.table1` to use non-default schemas.
* **source** sets source name to connect to a Trino. This name is shown on Trino web interface.
* **client_info** sets client info to queries. It can be a string to pass a raw string, or an object that can be encoded to JSON.
* **client_tags** sets client tags to queries. It needs to be an array of strings. The tags are shown on web interface.
* **user** sets user name to connect to a Trino.
* **password** sets a password to connect to Trino using basic auth.
* **time_zone** sets time zone of queries. Time zone affects some functions such as `format_datetime`.
* **language** sets language of queries. Language affects some functions such as `format_datetime`.
* **properties** set session properties. Session properties affect internal behavior such as `hive.force_local_scheduling: true`, `raptor.reader_stream_buffer_size: "32MB"`, etc.
* **query_timeout** sets timeout in seconds for the entire query execution (from the first API call until there're no more output data). If timeout happens, client raises TrinoQueryTimeoutError. Default is nil (disabled).
* **plan_timeout** sets timeout in seconds for query planning execution (from the first API call until result columns become available). If timeout happens, client raises TrinoQueryTimeoutError. Default is nil (disabled).
* **http_headers** sets custom HTTP headers. It must be a Hash of string to string.
* **http_proxy** sets host:port of a HTTP proxy server.
* **http_debug** enables debug message to STDOUT for each HTTP requests.
* **http_open_timeout** sets timeout in seconds to open new HTTP connection.
* **http_timeout** sets timeout in seconds to read data from a server.
* **gzip** enables gzip compression.
* **follow_redirect** enables HTTP redirection support.
* **model_version** set the Trino version to which a job is submitted. Supported versions are 351, 316, 303, 0.205, 0.178, 0.173, 0.153 and 0.149. Default is 351.

See [RDoc](http://www.rubydoc.info/gems/presto-client/) for the full documentation.

## Development

### Releasing a new version

1. First update `lib/trino/client/version.rb` to the next version.
2. Run the following command which will update `ChangeLog.md` file automatically.
```
$ ruby release.rb
```

3. Create tag
```
$ git commit -am "vX.Y.Z"
$ git tag "vX.Y.Z"
% git push --tags
```

4. Push package by the following command which will build and push `trino-client-X.Y.Z.gem` and `trino-client-ruby-X.Y.Z.gem` automatically.
```
$ ruby publish.rb
```
