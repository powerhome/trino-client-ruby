#
# ActiveRecord adapter for Trino
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

require "trino-client"
require "active_record"
require "active_record/connection_adapters/abstract_adapter"

module ActiveRecord
  module ConnectionHandling
    # Establishes a connection to the database that's used by all Active Record objects
    def trino_connection(config)
      ConnectionAdapters::TrinoAdapter.new(nil, logger, nil, config)
    end

    # For Rails 7.1+ compatibility
    def trino_adapter_class
      ConnectionAdapters::TrinoAdapter
    end
  end

  module ConnectionAdapters
    class TrinoAdapter < AbstractAdapter
      ADAPTER_NAME = "Trino"

      NATIVE_DATABASE_TYPES = {
        primary_key: "bigint",
        string: {name: "varchar"},
        text: {name: "varchar"},
        integer: {name: "integer"},
        bigint: {name: "bigint"},
        float: {name: "double"},
        decimal: {name: "decimal"},
        datetime: {name: "timestamp"},
        timestamp: {name: "timestamp"},
        time: {name: "time"},
        date: {name: "date"},
        binary: {name: "varbinary"},
        boolean: {name: "boolean"},
        json: {name: "json"}
      }.freeze

      class << self
        def new_client(connection_parameters)
          Trino::Client.new(connection_parameters)
        end

        def dbconsole(config, options = {})
          # Trino doesn't have a traditional command-line client in Ruby
          # This could be extended to launch a web interface or CLI if available
          raise NotImplementedError, "dbconsole is not supported for Trino adapter"
        end
      end

      def initialize(connection, logger, connection_options, config)
        super(connection, logger, config)

        @config = config
        @connection_parameters = {
          server: "#{config[:host] || 'localhost'}:#{config[:port] || 8080}",
          catalog: config[:catalog] || config[:database],
          schema: config[:schema] || "default",
          user: config[:username] || ENV["USER"],
          ssl: config[:ssl] || false,
          http_proxy: config[:http_proxy],
          http_debug: config[:http_debug] || false
        }

        @connection_parameters[:password] = config[:password] if config[:password]
        @connection_parameters[:time_zone] = config[:time_zone] if config[:time_zone]
        @connection_parameters[:properties] = config[:properties] if config[:properties]

        @trino_client = self.class.new_client(@connection_parameters)
        @visitor = Arel::Visitors::ToSql.new(self)
      end

      # Returns the human-readable name of the adapter
      def adapter_name
        ADAPTER_NAME
      end

      # Does this adapter support migrations?
      def supports_migrations?
        false # Trino is typically read-only for analytical workloads
      end

      # Does this adapter support primary key?
      def supports_primary_key?
        false # Trino doesn't enforce primary keys
      end

      # Does this adapter support DDL transactions?
      def supports_ddl_transactions?
        false
      end

      # Does this adapter support bulk alter?
      def supports_bulk_alter?
        false
      end

      # Does this adapter support savepoints?
      def supports_savepoints?
        false
      end

      # Does this adapter support transaction isolation?
      def supports_transaction_isolation?
        false
      end

      # Does this adapter support indexes?
      def supports_indexes?
        false
      end

      # Does this adapter support explain?
      def supports_explain?
        true
      end

      # Does this adapter support views?
      def supports_views?
        true
      end

      # Does this adapter support materialized views?
      def supports_materialized_views?
        true
      end

      # Does this adapter support comments?
      def supports_comments?
        true
      end

      # Does this adapter support common table expressions?
      def supports_common_table_expressions?
        true
      end

      # Does this adapter support optimizer hints?
      def supports_optimizer_hints?
        false
      end

      # Does this adapter support insert returning?
      def supports_insert_returning?
        false
      end

      # CONNECTION MANAGEMENT ==========================================

      def active?
        return false unless @trino_client
        # Test connection with a simple query
        @trino_client.run("SELECT 1")
        true
      rescue
        false
      end

      def reconnect!
        disconnect!
        @trino_client = self.class.new_client(@connection_parameters)
      end

      def disconnect!
        @trino_client = nil
      end

      def reset!
        reconnect!
      end

      # DATABASE STATEMENTS ============================================

      def execute(sql, name = nil)
        log(sql, name) do
          result = @trino_client.run(sql)
          # Return a Result-like object
          TrinoResult.new(result[0], result[1])
        end
      end

      def exec_query(sql, name = "SQL", binds = [], prepare: false)
        log(sql, name) do
          columns, rows = @trino_client.run(sql)

          # Convert to ActiveRecord::Result
          column_names = columns.map(&:name)
          column_types = columns.map { |col| type_map.lookup(col.type) }

          ActiveRecord::Result.new(column_names, rows, column_types)
        end
      end

      def exec_delete(sql, name = nil, binds = [])
        execute(sql, name)
        0 # Trino doesn't return affected row count easily
      end

      alias exec_update exec_delete

      def select_all(arel, name = nil, binds = [], preparable: nil)
        arel = arel_from_relation(arel)
        sql = to_sql(arel, binds)

        if prepared_statements
          cache = @statements[sql_key(sql)]
          unless cache
            cache = @statements[sql_key(sql)] = {stmt: sql}
          end
        end

        exec_query(sql, name, binds, prepare: prepared_statements)
      end

      def select_value(arel, name = nil, binds = [])
        single_value_from_rows(select_rows(arel, name, binds))
      end

      def select_values(arel, name = nil)
        select_rows(arel, name).map(&:first)
      end

      def select_rows(arel, name = nil, binds = [])
        sql = to_sql(arel, binds)
        exec_query(sql, name, binds).rows
      end

      # SCHEMA STATEMENTS ==============================================

      def tables(name = nil)
        sql = "SHOW TABLES"
        sql += " FROM #{@connection_parameters[:schema]}" if @connection_parameters[:schema]

        result = exec_query(sql, name)
        result.rows.map(&:first)
      end

      def table_exists?(table_name)
        tables.include?(table_name.to_s)
      end

      def views
        sql = "SELECT table_name FROM information_schema.views WHERE table_schema = '#{@connection_parameters[:schema]}'"
        exec_query(sql).rows.map(&:first)
      end

      def view_exists?(view_name)
        views.include?(view_name.to_s)
      end

      def columns(table_name)
        sql = "DESCRIBE #{quote_table_name(table_name)}"
        result = exec_query(sql)

        result.rows.map do |row|
          column_name = row[0]
          sql_type = row[1]

          TrinoColumn.new(column_name, nil, sql_type_metadata(sql_type), sql_type)
        end
      end

      def column_definitions(table_name)
        columns(table_name)
      end

      def primary_key(table_name)
        nil # Trino doesn't have primary keys
      end

      def indexes(table_name)
        [] # Trino doesn't have traditional indexes
      end

      # QUOTING ========================================================

      def quote_table_name(name)
        quote_column_name(name)
      end

      def quote_column_name(name)
        "\"#{name.to_s.gsub('"', '""')}\""
      end

      def quote(value)
        case value
        when String
          "'#{value.gsub("'", "''")}'"
        when true
          "true"
        when false
          "false"
        when nil
          "NULL"
        when Numeric
          value.to_s
        when Date
          "DATE '#{value.strftime("%Y-%m-%d")}'"
        when Time, DateTime
          "TIMESTAMP '#{value.strftime("%Y-%m-%d %H:%M:%S.%6N")}'"
        else
          super
        end
      end

      def quoted_true
        "true"
      end

      def quoted_false
        "false"
      end

      def unquoted_true
        true
      end

      def unquoted_false
        false
      end

      # TYPE MAPPING ===================================================

      def native_database_types
        NATIVE_DATABASE_TYPES
      end

      def type_to_sql(type, limit: nil, precision: nil, scale: nil, **)
        case type.to_s
        when "integer"
          "integer"
        when "bigint"
          "bigint"
        when "float", "double"
          "double"
        when "decimal"
          if precision && scale
            "decimal(#{precision},#{scale})"
          elsif precision
            "decimal(#{precision})"
          else
            "decimal"
          end
        when "string", "text"
          if limit
            "varchar(#{limit})"
          else
            "varchar"
          end
        when "binary"
          "varbinary"
        when "boolean"
          "boolean"
        when "date"
          "date"
        when "time"
          "time"
        when "datetime", "timestamp"
          "timestamp"
        when "json"
          "json"
        else
          type.to_s
        end
      end

      private

      def sql_type_metadata(sql_type)
        SqlTypeMetadata.new(
          sql_type: sql_type,
          type: lookup_cast_type(sql_type)
        )
      end

      def lookup_cast_type(sql_type)
        case sql_type.downcase
        when /^varchar/, /^char/
          :string
        when "integer", "int"
          :integer
        when "bigint"
          :bigint
        when "double", "real"
          :float
        when /^decimal/
          :decimal
        when "boolean"
          :boolean
        when "date"
          :date
        when "time"
          :time
        when "timestamp"
          :datetime
        when "varbinary"
          :binary
        when "json"
          :json
        else
          :string
        end
      end

      def arel_from_relation(relation)
        if relation.is_a?(Arel::SelectManager)
          relation
        else
          relation.arel
        end
      end

      def sql_key(sql)
        "#{schema_cache.connection_pool.schema_reflection.database_version.to_s}-#{sql}"
      end
    end

    # Custom column class for Trino
    class TrinoColumn < ConnectionAdapters::Column
      def initialize(name, default, sql_type_metadata = nil, type = nil, **args)
        super(name, default, sql_type_metadata, true, **args) # Trino columns are nullable by default
        @sql_type = type
      end
    end

    # Custom result class for Trino
    class TrinoResult
      attr_reader :columns, :rows

      def initialize(columns, rows)
        @columns = columns
        @rows = rows
      end

      def each
        @rows.each { |row| yield row }
      end

      def to_a
        @rows
      end

      def length
        @rows.length
      end

      alias size length
    end
  end
end
