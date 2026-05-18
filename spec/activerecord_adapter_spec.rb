require "spec_helper"
require "activerecord-trino-adapter"

# These tests require a running Trino server
# Set TRINO_SERVER environment variable to run these tests
# Example: TRINO_SERVER=localhost:8080 bundle exec rspec spec/activerecord_adapter_spec.rb

RSpec.describe ActiveRecord::ConnectionAdapters::TrinoAdapter do
  let(:config) do
    {
      adapter: "trino",
      host: ENV["TRINO_SERVER"]&.split(":")&.first || "localhost",
      port: ENV["TRINO_SERVER"]&.split(":")&.last&.to_i || 8080,
      catalog: "memory",
      schema: "default",
      username: "test"
    }
  end

  before(:all) do
    unless ENV["TRINO_SERVER"]
      skip "Set TRINO_SERVER environment variable to run ActiveRecord adapter tests"
    end
  end

  describe "connection" do
    it "establishes a connection" do
      connection = ActiveRecord::Base.establish_connection(config).connection
      expect(connection).to be_active
    end

    it "returns the correct adapter name" do
      connection = ActiveRecord::Base.establish_connection(config).connection
      expect(connection.adapter_name).to eq("Trino")
    end
  end

  describe "querying" do
    before do
      ActiveRecord::Base.establish_connection(config)
    end

    it "executes a simple query" do
      result = ActiveRecord::Base.connection.execute("SELECT 1 as num")
      expect(result.rows.first).to eq([1])
    end

    it "retrieves tables" do
      tables = ActiveRecord::Base.connection.tables
      expect(tables).to be_an(Array)
    end

    it "executes query with exec_query" do
      result = ActiveRecord::Base.connection.exec_query("SELECT 1 as num, 'test' as str")
      expect(result.columns).to eq(["num", "str"])
      expect(result.rows.first).to eq([1, "test"])
    end

    it "handles multiple rows" do
      sql = "SELECT * FROM (VALUES (1, 'a'), (2, 'b'), (3, 'c')) AS t(num, letter)"
      result = ActiveRecord::Base.connection.exec_query(sql)
      expect(result.rows.length).to eq(3)
      expect(result.rows).to eq([[1, "a"], [2, "b"], [3, "c"]])
    end
  end

  describe "type mapping" do
    before do
      ActiveRecord::Base.establish_connection(config)
    end

    it "maps string types correctly" do
      result = ActiveRecord::Base.connection.exec_query("SELECT 'hello' as str")
      expect(result.rows.first.first).to be_a(String)
    end

    it "maps integer types correctly" do
      result = ActiveRecord::Base.connection.exec_query("SELECT 123 as num")
      expect(result.rows.first.first).to be_a(Integer)
    end

    it "maps boolean types correctly" do
      result = ActiveRecord::Base.connection.exec_query("SELECT true as bool_val")
      expect(result.rows.first.first).to be_in([true, false])
    end
  end

  describe "quoting" do
    before do
      ActiveRecord::Base.establish_connection(config)
      @connection = ActiveRecord::Base.connection
    end

    it "quotes strings correctly" do
      expect(@connection.quote("test")).to eq("'test'")
    end

    it "quotes strings with single quotes correctly" do
      expect(@connection.quote("it's")).to eq("'it''s'")
    end

    it "quotes table names correctly" do
      expect(@connection.quote_table_name("my_table")).to eq('"my_table"')
    end

    it "quotes column names correctly" do
      expect(@connection.quote_column_name("my_column")).to eq('"my_column"')
    end

    it "quotes dates correctly" do
      date = Date.new(2024, 1, 15)
      expect(@connection.quote(date)).to eq("DATE '2024-01-15'")
    end

    it "quotes timestamps correctly" do
      time = Time.new(2024, 1, 15, 10, 30, 45)
      quoted = @connection.quote(time)
      expect(quoted).to start_with("TIMESTAMP '2024-01-15 10:30:45")
    end

    it "quotes booleans correctly" do
      expect(@connection.quote(true)).to eq("true")
      expect(@connection.quote(false)).to eq("false")
    end

    it "quotes nil correctly" do
      expect(@connection.quote(nil)).to eq("NULL")
    end

    it "quotes numbers correctly" do
      expect(@connection.quote(42)).to eq("42")
      expect(@connection.quote(3.14)).to eq("3.14")
    end
  end

  describe "capabilities" do
    before do
      ActiveRecord::Base.establish_connection(config)
      @connection = ActiveRecord::Base.connection
    end

    it "indicates no support for migrations" do
      expect(@connection.supports_migrations?).to be false
    end

    it "indicates no support for primary keys" do
      expect(@connection.supports_primary_key?).to be false
    end

    it "indicates support for views" do
      expect(@connection.supports_views?).to be true
    end

    it "indicates support for common table expressions" do
      expect(@connection.supports_common_table_expressions?).to be true
    end

    it "indicates support for explain" do
      expect(@connection.supports_explain?).to be true
    end
  end
end
