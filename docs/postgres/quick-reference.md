# AlgoXL - High-Frequency Trading Database Quick Reference

## Overview

AlgoXL is a high-performance PostgreSQL database with TimescaleDB extension, optimized for storing and querying OHLCV (Open, High, Low, Close, Volume) time-series data for high-frequency trading.

## Connection Information

- **Database Name**: algoxl
- **Host**: localhost
- **Port**: 5432
- **Main User**: algoxl_user
- **Connection String**: postgresql://algoxl_user:your_password@localhost:5432/algoxl

## Database Schema

### Main Tables

- **market_data.tick_data**: Raw price and volume data
  ```sql
  CREATE TABLE market_data.tick_data (
      time TIMESTAMPTZ NOT NULL,  -- Timestamp of the tick
      symbol VARCHAR(20) NOT NULL, -- Trading symbol
      price NUMERIC(16,6) NOT NULL, -- Price at this tick
      volume NUMERIC(20,2) NOT NULL, -- Volume at this tick
      bid NUMERIC(16,6),           -- Bid price (optional)
      ask NUMERIC(16,6),           -- Ask price (optional)
      source VARCHAR(20)           -- Data source
  );
  ```

- **market_data.ohlcv**: Aggregated candle data
  ```sql
  CREATE TABLE market_data.ohlcv (
      time TIMESTAMPTZ NOT NULL,   -- Start time of the candle
      symbol VARCHAR(20) NOT NULL,  -- Trading symbol
      interval VARCHAR(10) NOT NULL, -- Time interval (1m, 5m, 1h, etc.)
      open NUMERIC(16,6) NOT NULL,  -- Opening price
      high NUMERIC(16,6) NOT NULL,  -- Highest price
      low NUMERIC(16,6) NOT NULL,   -- Lowest price
      close NUMERIC(16,6) NOT NULL, -- Closing price
      volume NUMERIC(20,2) NOT NULL, -- Total volume
      trades INTEGER,               -- Number of trades
      vwap NUMERIC(16,6)            -- Volume-weighted average price
  );
  ```

### Continuous Aggregates

- **market_data.ohlcv_1min**: 1-minute OHLCV data
- **market_data.ohlcv_5min**: 5-minute OHLCV data

## Common Commands

### Connection

```bash
# Connect to database
psql -U algoxl_user -d algoxl

# Connect as postgres (admin)
sudo -u postgres psql -d algoxl
```

### Data Insertion

```sql
-- Insert tick data
INSERT INTO market_data.tick_data (time, symbol, price, volume, bid, ask)
VALUES (now(), 'AAPL', 185.45, 100, 185.44, 185.46);

-- Bulk insert from CSV
COPY market_data.tick_data (time, symbol, price, volume, bid, ask)
FROM '/path/to/data.csv' WITH (FORMAT csv, HEADER);
```

### Querying OHLCV Data

```sql
-- Get latest OHLCV data for a symbol
SELECT * FROM market_data.ohlcv
WHERE symbol = 'AAPL' AND interval = '5m'
ORDER BY time DESC
LIMIT 10;

-- Calculate VWAP
SELECT 
    symbol,
    SUM(close * volume) / NULLIF(SUM(volume), 0) AS vwap
FROM market_data.ohlcv
WHERE time > now() - interval '1 day'
GROUP BY symbol;
```

### TimescaleDB Functions

```sql
-- Create a time-bucketed query (downsampling)
SELECT
    time_bucket('1 hour', time) AS hour,
    symbol,
    first(open, time) AS open,
    max(high) AS high,
    min(low) AS low,
    last(close, time) AS close,
    sum(volume) AS volume
FROM market_data.ohlcv
WHERE time > now() - interval '7 days'
GROUP BY hour, symbol;

-- Refresh a continuous aggregate manually
CALL refresh_continuous_aggregate('market_data.ohlcv_1min', NULL, now());
```

## Maintenance Commands

```sql
-- Compress chunks older than 7 days
SELECT compress_chunk(chunk.schema_name || '.' || chunk.table_name)
FROM timescaledb_information.chunks chunk
WHERE hypertable_name = 'ohlcv'
AND range_end < now() - interval '7 days';

-- View compression status
SELECT
    hypertable_name,
    pg_size_pretty(before_compression_total_bytes) AS before_compression,
    pg_size_pretty(after_compression_total_bytes) AS after_compression,
    round(100 * (before_compression_total_bytes - after_compression_total_bytes) / 
        NULLIF(before_compression_total_bytes, 0)::numeric, 2) as compression_ratio
FROM timescaledb_information.compression_stats;

-- List hypertables
SELECT * FROM timescaledb_information.hypertables;

-- List chunks
SELECT * FROM timescaledb_information.chunks
ORDER BY range_end DESC;

-- List policies
SELECT * FROM timescaledb_information.policies;
```

## Performance Tuning

1. **Add Proper Indexes**
   ```sql
   -- Create index for symbol and time lookups
   CREATE INDEX ON market_data.ohlcv (symbol, interval, time DESC);
   ```

2. **Optimize Chunk Size**
   ```sql
   -- Set chunk interval
   SELECT set_chunk_time_interval('market_data.tick_data', INTERVAL '1 hour');
   SELECT set_chunk_time_interval('market_data.ohlcv', INTERVAL '1 day');
   ```

3. **Enable Compression**
   ```sql
   -- Set compression options
   ALTER TABLE market_data.ohlcv SET (
       timescaledb.compress,
       timescaledb.compress_segmentby = 'symbol,interval'
   );
   
   -- Add compression policy
   SELECT add_compression_policy('market_data.ohlcv', INTERVAL '7 days');
   ```

## Troubleshooting

1. **Check Server Status**
   ```bash
   systemctl status postgresql-15
   ```

2. **View PostgreSQL Logs**
   ```bash
   sudo tail -f /var/lib/pgsql/15/data/log/postgresql-*.log
   ```

3. **Check Database Size**
   ```sql
   SELECT pg_size_pretty(pg_database_size('algoxl')) AS db_size;
   ```

4. **Monitor Active Queries**
   ```sql
   SELECT pid, age(clock_timestamp(), query_start), usename, query
   FROM pg_stat_activity
   WHERE query != '<IDLE>' AND query NOT ILIKE '%pg_stat_activity%'
   ORDER BY query_start DESC;
   ```

5. **Cancel a Long-Running Query**
   ```sql
   SELECT pg_cancel_backend(pid);
   ```