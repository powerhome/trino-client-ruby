# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
- `bundle exec rake spec` - Run all RSpec tests
- `bundle exec rspec spec/[filename]_spec.rb` - Run specific test file

### Building
- `bundle exec rake build` - Build the gem
- `bundle exec rake` - Default task (runs spec and build)

### Code Quality
- `bundle exec standardrb` - Run StandardRB linter (code style enforcement)
- `bundle exec standardrb --fix` - Auto-fix style issues

### Model Generation
- `bundle exec rake modelgen:latest` - Generate model files from latest Trino version
- `bundle exec rake modelgen:all` - Generate all model versions

## Architecture Overview

This is a Ruby client library for Trino (distributed SQL query engine). The architecture is layered:

### Core Components

1. **Client Layer** (`lib/trino/client/client.rb`):
   - `Trino::Client::Client` - Main API entry point
   - Provides `run()`, `run_with_names()`, `query()`, `kill()` methods
   - Handles synchronous and streaming query execution

2. **Query Layer** (`lib/trino/client/query.rb`):
   - `Query` class - Manages query execution lifecycle
   - Handles streaming results via `each_row`, `each_row_chunk`
   - Provides column metadata and result transformation

3. **Statement Client** (`lib/trino/client/statement_client.rb`):
   - `StatementClient` - Low-level HTTP communication with Trino
   - Manages query state machine (running, finished, failed, aborted)
   - Handles retries, timeouts, and error conditions
   - Supports both JSON and MessagePack response formats

4. **HTTP Layer** (`lib/trino/client/faraday_client.rb`):
   - Uses Faraday for HTTP requests with middleware for gzip and redirects
   - Handles authentication, SSL configuration, proxy settings

### Model System

- **Versioned Models** (`lib/trino/client/model_versions/`):
  - Generated from Trino source code for different Trino versions
  - Each version (351, 316, 303, etc.) has its own model definitions
  - Default is version 351

- **Model Generation** (`modelgen/`):
  - Automated model generation from Trino Java source
  - Downloads Trino source and extracts model definitions

### Key Features

- **Streaming Results**: Query results can be processed row-by-row without loading all data into memory
- **Timeout Control**: Supports both query-level and plan-level timeouts
- **Error Recovery**: Built-in retry logic for transient failures (502, 503, 504)
- **Multiple Result Formats**: Raw arrays, named hashes, or streaming iteration
- **ROW Type Support**: Can parse Trino ROW types into Ruby hashes via `transform_row`

### Testing

Tests are organized by component:
- `spec/client_spec.rb` - Client API tests
- `spec/statement_client_spec.rb` - Low-level protocol tests
- `spec/column_value_parser_spec.rb` - Data parsing tests
- `spec/tpch_query_spec.rb` - Integration tests with TPC-H queries
- `spec/activerecord_adapter_spec.rb` - ActiveRecord adapter tests (requires running Trino server)

## ActiveRecord Adapter

The library includes an optional ActiveRecord adapter in `lib/active_record/connection_adapters/trino_adapter.rb`.

### Architecture

The adapter extends `ActiveRecord::ConnectionAdapters::AbstractAdapter` and provides:

1. **Connection Management**:
   - Uses the existing `Trino::Client` for all communication
   - Connection parameters are mapped from ActiveRecord config to Trino client options
   - Supports reconnection and connection health checks

2. **Query Execution**:
   - `execute()` - Runs raw SQL and returns a TrinoResult
   - `exec_query()` - Returns ActiveRecord::Result with typed columns
   - `select_all()`, `select_value()`, `select_rows()` - Standard ActiveRecord query methods

3. **Schema Introspection**:
   - `tables()` - Lists tables using SHOW TABLES
   - `columns()` - Gets column definitions using DESCRIBE
   - `views()`, `view_exists?()` - View support via information_schema
   - Type mapping from Trino SQL types to ActiveRecord types

4. **Quoting and Type Mapping**:
   - Custom quoting for Trino SQL syntax (e.g., DATE '2024-01-01')
   - Type mapping between Trino types (varchar, bigint, double, etc.) and Ruby types
   - Proper escaping of identifiers and values

### Usage

To use the adapter:

```ruby
require 'activerecord-trino-adapter'

ActiveRecord::Base.establish_connection(
  adapter: 'trino',
  host: 'localhost',
  port: 8080,
  catalog: 'hive',
  schema: 'default',
  username: 'user'
)
```

### Limitations

- Read-only for most catalogs (Trino is primarily analytical)
- No transaction support
- No migration support
- No primary key enforcement
- No traditional indexes

### Testing the Adapter

Set `TRINO_SERVER` environment variable and run:
```bash
TRINO_SERVER=localhost:8080 bundle exec rspec spec/activerecord_adapter_spec.rb
```

