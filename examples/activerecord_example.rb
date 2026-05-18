#!/usr/bin/env ruby
#
# Example usage of the Trino ActiveRecord adapter
#
# This example demonstrates how to use ActiveRecord with Trino
#

require "bundler/setup"
require "activerecord-trino-adapter"

# Configure connection
ActiveRecord::Base.establish_connection(
  adapter: "trino",
  host: ENV["TRINO_HOST"] || "localhost",
  port: (ENV["TRINO_PORT"] || 8080).to_i,
  catalog: ENV["TRINO_CATALOG"] || "memory",
  schema: ENV["TRINO_SCHEMA"] || "default",
  username: ENV["TRINO_USER"] || "trino"
)

# Test connection
puts "Testing connection to Trino..."
if ActiveRecord::Base.connection.active?
  puts "✓ Connected successfully"
else
  puts "✗ Connection failed"
  exit 1
end

# Example 1: Execute raw SQL
puts "\n--- Example 1: Raw SQL Query ---"
result = ActiveRecord::Base.connection.execute("SELECT 1 as num, 'Hello' as message")
puts "Columns: #{result.columns.inspect}"
puts "Rows: #{result.rows.inspect}"

# Example 2: Query with exec_query
puts "\n--- Example 2: Structured Query ---"
result = ActiveRecord::Base.connection.exec_query(
  "SELECT * FROM (VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie')) AS users(id, name)"
)
puts "Columns: #{result.columns.inspect}"
result.rows.each do |row|
  puts "  Row: #{row.inspect}"
end

# Example 3: List tables
puts "\n--- Example 3: List Tables ---"
tables = ActiveRecord::Base.connection.tables
puts "Tables in #{ENV["TRINO_CATALOG"]}.#{ENV["TRINO_SCHEMA"]}:"
if tables.empty?
  puts "  (no tables found)"
else
  tables.each { |table| puts "  - #{table}" }
end

# Example 4: Define a model (for read-only queries)
puts "\n--- Example 4: ActiveRecord Model ---"
class User < ActiveRecord::Base
  self.table_name = "users"
  self.primary_key = nil # Trino doesn't support primary keys

  # If the table exists, you can query it like this:
  # User.where("age > ?", 25).limit(10)
end

puts "Model defined: #{User.name}"
puts "Table name: #{User.table_name}"

# Example 5: Complex query with CTE
puts "\n--- Example 5: Common Table Expression ---"
sql = <<-SQL
  WITH ranked_users AS (
    SELECT id, name, row_number() OVER (ORDER BY id) as rank
    FROM (VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie')) AS t(id, name)
  )
  SELECT * FROM ranked_users WHERE rank <= 2
SQL

result = ActiveRecord::Base.connection.exec_query(sql)
puts "Top 2 users:"
result.rows.each do |row|
  puts "  #{row.inspect}"
end

# Example 6: Type mapping demonstration
puts "\n--- Example 6: Type Mapping ---"
sql = <<-SQL
  SELECT
    'text value' as string_col,
    123 as int_col,
    456789012345 as bigint_col,
    3.14159 as double_col,
    true as bool_col,
    DATE '2024-01-15' as date_col,
    TIMESTAMP '2024-01-15 10:30:00' as timestamp_col
SQL

result = ActiveRecord::Base.connection.exec_query(sql)
row = result.rows.first
result.columns.each_with_index do |col, i|
  puts "  #{col}: #{row[i].inspect} (#{row[i].class})"
end

# Example 7: Schema inspection
puts "\n--- Example 7: Schema Inspection ---"
if tables.any?
  table_name = tables.first
  puts "Inspecting table: #{table_name}"
  columns = ActiveRecord::Base.connection.columns(table_name)
  columns.each do |col|
    puts "  - #{col.name}: #{col.sql_type}"
  end
else
  puts "No tables available to inspect"
end

puts "\n✓ All examples completed successfully!"
