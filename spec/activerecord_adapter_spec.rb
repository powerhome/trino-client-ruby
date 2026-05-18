require "spec_helper"
require "activerecord-trino-adapter"

RSpec.describe ActiveRecord::ConnectionAdapters::TrinoAdapter do
  let(:config) do
    {
      adapter: "trino",
      host: "localhost",
      port: 8080,
      catalog: "memory",
      schema: "default",
      username: "test"
    }
  end

  let(:mock_client) { double("Trino::Client") }
  let(:adapter) do
    allow(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).and_return(mock_client)
    ActiveRecord::Base.establish_connection(config).connection
  end

  describe "initialization" do
    it "creates a connection with correct parameters" do
      expect(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).with(
        hash_including(
          server: "localhost:8080",
          catalog: "memory",
          schema: "default",
          user: "test"
        )
      ).and_return(mock_client)

      ActiveRecord::Base.establish_connection(config)
    end

    it "uses default values for missing configuration" do
      minimal_config = {adapter: "trino"}
      expect(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).with(
        hash_including(
          server: "localhost:8080",
          schema: "default",
          ssl: false
        )
      ).and_return(mock_client)

      ActiveRecord::Base.establish_connection(minimal_config)
    end

    it "passes SSL configuration" do
      ssl_config = config.merge(ssl: true)
      expect(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).with(
        hash_including(ssl: true)
      ).and_return(mock_client)

      ActiveRecord::Base.establish_connection(ssl_config)
    end

    it "passes password when provided" do
      password_config = config.merge(password: "secret")
      expect(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).with(
        hash_including(password: "secret")
      ).and_return(mock_client)

      ActiveRecord::Base.establish_connection(password_config)
    end

    it "passes time zone configuration" do
      tz_config = config.merge(time_zone: "America/New_York")
      expect(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).with(
        hash_including(time_zone: "America/New_York")
      ).and_return(mock_client)

      ActiveRecord::Base.establish_connection(tz_config)
    end

    it "passes properties configuration" do
      props_config = config.merge(properties: {"query_max_execution_time" => "30m"})
      expect(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).with(
        hash_including(properties: {"query_max_execution_time" => "30m"})
      ).and_return(mock_client)

      ActiveRecord::Base.establish_connection(props_config)
    end
  end

  describe "#adapter_name" do
    it "returns Trino" do
      expect(adapter.adapter_name).to eq("Trino")
    end
  end

  describe "capability checks" do
    it "does not support migrations" do
      expect(adapter.supports_migrations?).to be false
    end

    it "does not support primary keys" do
      expect(adapter.supports_primary_key?).to be false
    end

    it "does not support DDL transactions" do
      expect(adapter.supports_ddl_transactions?).to be false
    end

    it "does not support bulk alter" do
      expect(adapter.supports_bulk_alter?).to be false
    end

    it "does not support savepoints" do
      expect(adapter.supports_savepoints?).to be false
    end

    it "does not support transaction isolation" do
      expect(adapter.supports_transaction_isolation?).to be false
    end

    it "does not support indexes" do
      expect(adapter.supports_indexes?).to be false
    end

    it "supports explain" do
      expect(adapter.supports_explain?).to be true
    end

    it "supports views" do
      expect(adapter.supports_views?).to be true
    end

    it "supports materialized views" do
      expect(adapter.supports_materialized_views?).to be true
    end

    it "supports comments" do
      expect(adapter.supports_comments?).to be true
    end

    it "supports common table expressions" do
      expect(adapter.supports_common_table_expressions?).to be true
    end

    it "does not support optimizer hints" do
      expect(adapter.supports_optimizer_hints?).to be false
    end

    it "does not support insert returning" do
      expect(adapter.supports_insert_returning?).to be false
    end
  end

  describe "#active?" do
    it "returns true when client can execute a query" do
      allow(mock_client).to receive(:run).with("SELECT 1").and_return([[], [[1]]])
      expect(adapter.active?).to be true
    end

    it "returns false when client raises an error" do
      allow(mock_client).to receive(:run).with("SELECT 1").and_raise(StandardError)
      expect(adapter.active?).to be false
    end

    it "returns false when client is nil" do
      adapter.disconnect!
      expect(adapter.active?).to be false
    end
  end

  describe "#disconnect!" do
    it "sets client to nil" do
      adapter.disconnect!
      expect(adapter.active?).to be false
    end
  end

  describe "#reconnect!" do
    it "disconnects and creates a new client" do
      expect(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).and_return(mock_client)
      adapter.reconnect!
    end
  end

  describe "#execute" do
    it "runs a query and returns TrinoResult" do
      columns = [
        double(name: "id", type: "integer"),
        double(name: "name", type: "varchar")
      ]
      rows = [[1, "Alice"], [2, "Bob"]]

      allow(mock_client).to receive(:run).with("SELECT * FROM users").and_return([columns, rows])

      result = adapter.execute("SELECT * FROM users")
      expect(result).to be_a(ActiveRecord::ConnectionAdapters::TrinoResult)
      expect(result.rows).to eq(rows)
    end
  end

  describe "#exec_query" do
    let(:columns) do
      [
        double(name: "id", type: "integer"),
        double(name: "name", type: "varchar"),
        double(name: "amount", type: "double")
      ]
    end

    let(:rows) do
      [[1, "Alice", 100.50], [2, "Bob", 200.75]]
    end

    it "returns an ActiveRecord::Result with columns and rows" do
      allow(mock_client).to receive(:run).with("SELECT * FROM users").and_return([columns, rows])

      result = adapter.exec_query("SELECT * FROM users")
      expect(result).to be_a(ActiveRecord::Result)
      expect(result.columns).to eq(["id", "name", "amount"])
      expect(result.rows).to eq(rows)
    end

    it "maps column types correctly" do
      allow(mock_client).to receive(:run).and_return([columns, rows])

      result = adapter.exec_query("SELECT * FROM users")
      column_types = result.column_types

      expect(column_types["id"]).to eq(:integer)
      expect(column_types["name"]).to eq(:string)
      expect(column_types["amount"]).to eq(:float)
    end

    it "handles empty result sets" do
      allow(mock_client).to receive(:run).and_return([columns, []])

      result = adapter.exec_query("SELECT * FROM users WHERE 1=0")
      expect(result.rows).to be_empty
      expect(result.columns).to eq(["id", "name", "amount"])
    end

    it "handles queries with no columns" do
      allow(mock_client).to receive(:run).and_return([[], []])

      result = adapter.exec_query("CREATE TABLE test (id int)")
      expect(result.rows).to be_empty
      expect(result.columns).to be_empty
    end
  end

  describe "#exec_delete" do
    it "executes delete and returns 0" do
      allow(mock_client).to receive(:run).with("DELETE FROM users WHERE id = 1").and_return([[], []])

      affected = adapter.exec_delete("DELETE FROM users WHERE id = 1")
      expect(affected).to eq(0)
    end
  end

  describe "#exec_update" do
    it "executes update and returns 0" do
      allow(mock_client).to receive(:run).with("UPDATE users SET name = 'Test'").and_return([[], []])

      affected = adapter.exec_update("UPDATE users SET name = 'Test'")
      expect(affected).to eq(0)
    end
  end

  describe "#select_all" do
    it "converts Arel to SQL and executes query" do
      columns = [double(name: "id", type: "integer")]
      rows = [[1], [2]]

      allow(mock_client).to receive(:run).and_return([columns, rows])

      result = adapter.select_all("SELECT * FROM users")
      expect(result).to be_a(ActiveRecord::Result)
      expect(result.rows).to eq(rows)
    end
  end

  describe "#select_value" do
    it "returns a single value from first row" do
      columns = [double(name: "count", type: "integer")]
      rows = [[42]]

      allow(mock_client).to receive(:run).and_return([columns, rows])

      value = adapter.select_value("SELECT COUNT(*) FROM users")
      expect(value).to eq(42)
    end

    it "returns nil for empty result" do
      columns = [double(name: "count", type: "integer")]
      rows = []

      allow(mock_client).to receive(:run).and_return([columns, rows])

      value = adapter.select_value("SELECT COUNT(*) FROM users WHERE 1=0")
      expect(value).to be_nil
    end
  end

  describe "#select_values" do
    it "returns array of first column values" do
      columns = [double(name: "name", type: "varchar")]
      rows = [["Alice"], ["Bob"], ["Charlie"]]

      allow(mock_client).to receive(:run).and_return([columns, rows])

      values = adapter.select_values("SELECT name FROM users")
      expect(values).to eq(["Alice", "Bob", "Charlie"])
    end
  end

  describe "#select_rows" do
    it "returns array of row arrays" do
      columns = [
        double(name: "id", type: "integer"),
        double(name: "name", type: "varchar")
      ]
      rows = [[1, "Alice"], [2, "Bob"]]

      allow(mock_client).to receive(:run).and_return([columns, rows])

      result_rows = adapter.select_rows("SELECT id, name FROM users")
      expect(result_rows).to eq(rows)
    end
  end

  describe "schema introspection" do
    describe "#tables" do
      it "returns list of table names" do
        columns = [double(name: "Table", type: "varchar")]
        rows = [["users"], ["orders"], ["products"]]

        allow(mock_client).to receive(:run).with("SHOW TABLES FROM default").and_return([columns, rows])

        tables = adapter.tables
        expect(tables).to eq(["users", "orders", "products"])
      end

      it "executes SHOW TABLES without schema when not configured" do
        no_schema_config = config.merge(schema: nil)
        allow(ActiveRecord::ConnectionAdapters::TrinoAdapter).to receive(:new_client).and_return(mock_client)
        adapter = ActiveRecord::Base.establish_connection(no_schema_config).connection

        columns = [double(name: "Table", type: "varchar")]
        rows = [["users"]]

        allow(mock_client).to receive(:run).with("SHOW TABLES").and_return([columns, rows])

        tables = adapter.tables
        expect(tables).to eq(["users"])
      end
    end

    describe "#table_exists?" do
      it "returns true when table exists" do
        columns = [double(name: "Table", type: "varchar")]
        rows = [["users"], ["orders"]]

        allow(mock_client).to receive(:run).and_return([columns, rows])

        expect(adapter.table_exists?("users")).to be true
      end

      it "returns false when table does not exist" do
        columns = [double(name: "Table", type: "varchar")]
        rows = [["users"], ["orders"]]

        allow(mock_client).to receive(:run).and_return([columns, rows])

        expect(adapter.table_exists?("products")).to be false
      end
    end

    describe "#columns" do
      it "returns column definitions for a table" do
        columns = [
          double(name: "Column", type: "varchar"),
          double(name: "Type", type: "varchar")
        ]
        rows = [
          ["id", "integer"],
          ["name", "varchar(255)"],
          ["created_at", "timestamp"]
        ]

        allow(mock_client).to receive(:run).with('DESCRIBE "users"').and_return([columns, rows])

        cols = adapter.columns("users")
        expect(cols.length).to eq(3)
        expect(cols[0].name).to eq("id")
        expect(cols[0].sql_type).to eq("integer")
        expect(cols[1].name).to eq("name")
        expect(cols[1].sql_type).to eq("varchar(255)")
        expect(cols[2].name).to eq("created_at")
        expect(cols[2].sql_type).to eq("timestamp")
      end

      it "marks all columns as nullable" do
        columns = [
          double(name: "Column", type: "varchar"),
          double(name: "Type", type: "varchar")
        ]
        rows = [["id", "integer"]]

        allow(mock_client).to receive(:run).and_return([columns, rows])

        cols = adapter.columns("users")
        expect(cols[0].null).to be true
      end
    end

    describe "#views" do
      it "returns list of view names" do
        columns = [double(name: "table_name", type: "varchar")]
        rows = [["user_summary"], ["sales_report"]]

        allow(mock_client).to receive(:run).with(
          "SELECT table_name FROM information_schema.views WHERE table_schema = 'default'"
        ).and_return([columns, rows])

        views = adapter.views
        expect(views).to eq(["user_summary", "sales_report"])
      end
    end

    describe "#view_exists?" do
      it "returns true when view exists" do
        columns = [double(name: "table_name", type: "varchar")]
        rows = [["user_summary"]]

        allow(mock_client).to receive(:run).and_return([columns, rows])

        expect(adapter.view_exists?("user_summary")).to be true
      end

      it "returns false when view does not exist" do
        columns = [double(name: "table_name", type: "varchar")]
        rows = [["user_summary"]]

        allow(mock_client).to receive(:run).and_return([columns, rows])

        expect(adapter.view_exists?("other_view")).to be false
      end
    end

    describe "#primary_key" do
      it "always returns nil" do
        expect(adapter.primary_key("users")).to be_nil
      end
    end

    describe "#indexes" do
      it "always returns empty array" do
        expect(adapter.indexes("users")).to eq([])
      end
    end
  end

  describe "quoting" do
    describe "#quote" do
      it "quotes strings with single quotes" do
        expect(adapter.quote("hello")).to eq("'hello'")
      end

      it "escapes single quotes in strings" do
        expect(adapter.quote("it's")).to eq("'it''s'")
      end

      it "quotes true as true" do
        expect(adapter.quote(true)).to eq("true")
      end

      it "quotes false as false" do
        expect(adapter.quote(false)).to eq("false")
      end

      it "quotes nil as NULL" do
        expect(adapter.quote(nil)).to eq("NULL")
      end

      it "quotes integers as strings" do
        expect(adapter.quote(42)).to eq("42")
      end

      it "quotes floats as strings" do
        expect(adapter.quote(3.14)).to eq("3.14")
      end

      it "quotes dates with DATE prefix" do
        date = Date.new(2024, 1, 15)
        expect(adapter.quote(date)).to eq("DATE '2024-01-15'")
      end

      it "quotes times with TIMESTAMP prefix" do
        time = Time.new(2024, 1, 15, 10, 30, 45)
        quoted = adapter.quote(time)
        expect(quoted).to start_with("TIMESTAMP '2024-01-15 10:30:45")
      end

      it "quotes DateTime with TIMESTAMP prefix" do
        datetime = DateTime.new(2024, 1, 15, 10, 30, 45)
        quoted = adapter.quote(datetime)
        expect(quoted).to start_with("TIMESTAMP '2024-01-15 10:30:45")
      end
    end

    describe "#quote_table_name" do
      it "quotes table names with double quotes" do
        expect(adapter.quote_table_name("users")).to eq('"users"')
      end

      it "escapes double quotes in table names" do
        expect(adapter.quote_table_name('my"table')).to eq('"my""table"')
      end

      it "handles symbols" do
        expect(adapter.quote_table_name(:users)).to eq('"users"')
      end
    end

    describe "#quote_column_name" do
      it "quotes column names with double quotes" do
        expect(adapter.quote_column_name("user_id")).to eq('"user_id"')
      end

      it "escapes double quotes in column names" do
        expect(adapter.quote_column_name('my"column')).to eq('"my""column"')
      end

      it "handles symbols" do
        expect(adapter.quote_column_name(:user_id)).to eq('"user_id"')
      end
    end

    describe "#quoted_true" do
      it "returns true" do
        expect(adapter.quoted_true).to eq("true")
      end
    end

    describe "#quoted_false" do
      it "returns false" do
        expect(adapter.quoted_false).to eq("false")
      end
    end

    describe "#unquoted_true" do
      it "returns boolean true" do
        expect(adapter.unquoted_true).to eq(true)
      end
    end

    describe "#unquoted_false" do
      it "returns boolean false" do
        expect(adapter.unquoted_false).to eq(false)
      end
    end
  end

  describe "type mapping" do
    describe "#native_database_types" do
      it "includes standard types" do
        types = adapter.native_database_types
        expect(types[:string]).to eq({name: "varchar"})
        expect(types[:integer]).to eq({name: "integer"})
        expect(types[:bigint]).to eq({name: "bigint"})
        expect(types[:float]).to eq({name: "double"})
        expect(types[:decimal]).to eq({name: "decimal"})
        expect(types[:datetime]).to eq({name: "timestamp"})
        expect(types[:timestamp]).to eq({name: "timestamp"})
        expect(types[:time]).to eq({name: "time"})
        expect(types[:date]).to eq({name: "date"})
        expect(types[:binary]).to eq({name: "varbinary"})
        expect(types[:boolean]).to eq({name: "boolean"})
        expect(types[:json]).to eq({name: "json"})
      end
    end

    describe "#type_to_sql" do
      it "converts integer type" do
        expect(adapter.type_to_sql(:integer)).to eq("integer")
      end

      it "converts bigint type" do
        expect(adapter.type_to_sql(:bigint)).to eq("bigint")
      end

      it "converts float type" do
        expect(adapter.type_to_sql(:float)).to eq("double")
      end

      it "converts double type" do
        expect(adapter.type_to_sql(:double)).to eq("double")
      end

      it "converts decimal without precision" do
        expect(adapter.type_to_sql(:decimal)).to eq("decimal")
      end

      it "converts decimal with precision" do
        expect(adapter.type_to_sql(:decimal, precision: 10)).to eq("decimal(10)")
      end

      it "converts decimal with precision and scale" do
        expect(adapter.type_to_sql(:decimal, precision: 10, scale: 2)).to eq("decimal(10,2)")
      end

      it "converts string without limit" do
        expect(adapter.type_to_sql(:string)).to eq("varchar")
      end

      it "converts string with limit" do
        expect(adapter.type_to_sql(:string, limit: 255)).to eq("varchar(255)")
      end

      it "converts text type" do
        expect(adapter.type_to_sql(:text)).to eq("varchar")
      end

      it "converts binary type" do
        expect(adapter.type_to_sql(:binary)).to eq("varbinary")
      end

      it "converts boolean type" do
        expect(adapter.type_to_sql(:boolean)).to eq("boolean")
      end

      it "converts date type" do
        expect(adapter.type_to_sql(:date)).to eq("date")
      end

      it "converts time type" do
        expect(adapter.type_to_sql(:time)).to eq("time")
      end

      it "converts datetime type" do
        expect(adapter.type_to_sql(:datetime)).to eq("timestamp")
      end

      it "converts timestamp type" do
        expect(adapter.type_to_sql(:timestamp)).to eq("timestamp")
      end

      it "converts json type" do
        expect(adapter.type_to_sql(:json)).to eq("json")
      end

      it "passes through unknown types" do
        expect(adapter.type_to_sql(:custom_type)).to eq("custom_type")
      end
    end

    describe "type lookup" do
      it "maps varchar to string" do
        expect(adapter.send(:lookup_cast_type, "varchar")).to eq(:string)
      end

      it "maps varchar(255) to string" do
        expect(adapter.send(:lookup_cast_type, "varchar(255)")).to eq(:string)
      end

      it "maps char to string" do
        expect(adapter.send(:lookup_cast_type, "char")).to eq(:string)
      end

      it "maps integer to integer" do
        expect(adapter.send(:lookup_cast_type, "integer")).to eq(:integer)
      end

      it "maps int to integer" do
        expect(adapter.send(:lookup_cast_type, "int")).to eq(:integer)
      end

      it "maps bigint to bigint" do
        expect(adapter.send(:lookup_cast_type, "bigint")).to eq(:bigint)
      end

      it "maps double to float" do
        expect(adapter.send(:lookup_cast_type, "double")).to eq(:float)
      end

      it "maps real to float" do
        expect(adapter.send(:lookup_cast_type, "real")).to eq(:float)
      end

      it "maps decimal to decimal" do
        expect(adapter.send(:lookup_cast_type, "decimal")).to eq(:decimal)
      end

      it "maps decimal(10,2) to decimal" do
        expect(adapter.send(:lookup_cast_type, "decimal(10,2)")).to eq(:decimal)
      end

      it "maps boolean to boolean" do
        expect(adapter.send(:lookup_cast_type, "boolean")).to eq(:boolean)
      end

      it "maps date to date" do
        expect(adapter.send(:lookup_cast_type, "date")).to eq(:date)
      end

      it "maps time to time" do
        expect(adapter.send(:lookup_cast_type, "time")).to eq(:time)
      end

      it "maps timestamp to datetime" do
        expect(adapter.send(:lookup_cast_type, "timestamp")).to eq(:datetime)
      end

      it "maps varbinary to binary" do
        expect(adapter.send(:lookup_cast_type, "varbinary")).to eq(:binary)
      end

      it "maps json to json" do
        expect(adapter.send(:lookup_cast_type, "json")).to eq(:json)
      end

      it "maps unknown types to string" do
        expect(adapter.send(:lookup_cast_type, "unknown_type")).to eq(:string)
      end

      it "handles case insensitive type names" do
        expect(adapter.send(:lookup_cast_type, "INTEGER")).to eq(:integer)
        expect(adapter.send(:lookup_cast_type, "VARCHAR")).to eq(:string)
        expect(adapter.send(:lookup_cast_type, "BOOLEAN")).to eq(:boolean)
      end
    end
  end

  describe "TrinoColumn" do
    it "creates a column with name and type" do
      metadata = ActiveRecord::ConnectionAdapters::SqlTypeMetadata.new(
        sql_type: "varchar",
        type: :string
      )
      column = ActiveRecord::ConnectionAdapters::TrinoColumn.new("name", nil, metadata, "varchar")

      expect(column.name).to eq("name")
      expect(column.sql_type).to eq("varchar")
      expect(column.null).to be true
    end

    it "marks columns as nullable by default" do
      metadata = ActiveRecord::ConnectionAdapters::SqlTypeMetadata.new(
        sql_type: "integer",
        type: :integer
      )
      column = ActiveRecord::ConnectionAdapters::TrinoColumn.new("id", nil, metadata, "integer")

      expect(column.null).to be true
    end
  end

  describe "TrinoResult" do
    it "stores columns and rows" do
      columns = [double(name: "id"), double(name: "name")]
      rows = [[1, "Alice"], [2, "Bob"]]

      result = ActiveRecord::ConnectionAdapters::TrinoResult.new(columns, rows)

      expect(result.columns).to eq(columns)
      expect(result.rows).to eq(rows)
    end

    it "provides each iterator" do
      columns = []
      rows = [[1, "Alice"], [2, "Bob"]]

      result = ActiveRecord::ConnectionAdapters::TrinoResult.new(columns, rows)

      iterated = []
      result.each { |row| iterated << row }

      expect(iterated).to eq(rows)
    end

    it "converts to array" do
      columns = []
      rows = [[1, "Alice"], [2, "Bob"]]

      result = ActiveRecord::ConnectionAdapters::TrinoResult.new(columns, rows)

      expect(result.to_a).to eq(rows)
    end

    it "returns length" do
      columns = []
      rows = [[1, "Alice"], [2, "Bob"]]

      result = ActiveRecord::ConnectionAdapters::TrinoResult.new(columns, rows)

      expect(result.length).to eq(2)
      expect(result.size).to eq(2)
    end
  end
end
