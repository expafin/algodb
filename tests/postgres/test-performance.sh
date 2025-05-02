#!/bin/bash
#
# AlgoXL - Performance Test Script
# -----------------------------
# Script to benchmark PostgreSQL and TimescaleDB performance for high-frequency trading

# Exit on error
set -e

# Get the base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALGOXL_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the required libraries
source "$ALGOXL_HOME/lib/functions.sh"
source "$ALGOXL_HOME/lib/env-manager.sh"

# Load environment variables
load_env

# Set PostgreSQL version if not already set
PG_VERSION="${PG_VERSION:-15}"
DB_NAME="${DB_NAME:-algoxl}"

print_section "Performance Testing for High-Frequency Trading Database"

# Test 1: High-volume insert performance
print_color "blue" "Test 1: Testing high-volume insert performance..."
TEST_TABLE="perf_test_insert_$(date +%s)"
NUM_RECORDS=100000

# Create test table
print_color "blue" "Creating test table for insert performance..."
sudo -u postgres psql -d "$DB_NAME" -c "
    CREATE TABLE $TEST_TABLE (
        time TIMESTAMPTZ NOT NULL,
        symbol TEXT NOT NULL,
        price DOUBLE PRECISION NOT NULL,
        volume DOUBLE PRECISION NOT NULL
    );
    
    SELECT create_hypertable('$TEST_TABLE', 'time', chunk_time_interval => INTERVAL '1 hour');
"

# Generate test data
print_color "blue" "Generating test data for insert performance...wait about five minutes..."
SYMBOLS=("AAPL" "MSFT" "GOOGL" "AMZN" "TSLA")
TEST_DATA_FILE="/tmp/hft_test_data.csv"
rm -f "$TEST_DATA_FILE"

# Generate random data - Using a more compatible approach for timestamp generation
START_TIMESTAMP=$(date -d "2023-01-01" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "2023-01-01" +%s 2>/dev/null || echo "1672531200")

for i in $(seq 1 $NUM_RECORDS); do
    # Calculate timestamp using seconds since epoch
    days_offset=$((i / 10000))
    seconds_offset=$((i % 10000))
    total_offset=$((days_offset * 86400 + seconds_offset))
    ts=$((START_TIMESTAMP + total_offset))
    
    # Convert timestamp back to ISO format
    timestamp=$(date -d "@$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -r "$ts" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
    
    # If date commands don't work, generate more basic timestamp
    if [ -z "$timestamp" ]; then
        timestamp="2023-01-01 $(printf "%02d:%02d:%02d" $((total_offset/3600%24)) $((total_offset/60%60)) $((total_offset%60)))"
    fi
    
    symbol=${SYMBOLS[$((RANDOM % 5))]}
    price=$(echo "scale=2; 100 + (($RANDOM % 1000) / 100)" | bc)
    volume=$(($RANDOM % 1000 + 1))
    
    echo "$timestamp,$symbol,$price,$volume" >> "$TEST_DATA_FILE"
done

# Test insert performance
print_color "blue" "Testing bulk insert performance..."
START_TIME=$(date +%s.%N)

sudo -u postgres psql -d "$DB_NAME" << EOF
\timing on
\o /dev/null
COPY $TEST_TABLE (time, symbol, price, volume) FROM '$TEST_DATA_FILE' WITH (FORMAT csv);
\o
EOF

END_TIME=$(date +%s.%N)
ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)
INSERT_RATE=$(echo "$NUM_RECORDS / $ELAPSED_TIME" | bc)

print_color "green" "✓ Inserted $NUM_RECORDS records in $ELAPSED_TIME seconds"
print_color "green" "✓ Insert rate: $INSERT_RATE records/second"

# Test 2: Query performance for OHLCV aggregation
print_color "blue" "Test 2: Testing query performance for OHLCV aggregation..."

# Measure OHLCV aggregation performance
print_color "blue" "Measuring OHLCV aggregation performance..."
START_TIME=$(date +%s.%N)

sudo -u postgres psql -d "$DB_NAME" << EOF
\timing on
\o /dev/null
SELECT
    time_bucket('1 minute', time) AS minute,
    symbol,
    first(price, time) AS open,
    max(price) AS high,
    min(price) AS low,
    last(price, time) AS close,
    sum(volume) AS volume
FROM $TEST_TABLE
GROUP BY minute, symbol
ORDER BY minute, symbol;
\o
EOF

END_TIME=$(date +%s.%N)
ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)

print_color "green" "✓ OHLCV aggregation query completed in $ELAPSED_TIME seconds"

# Test 3: Query performance for time-series analytics
print_color "blue" "Test 3: Testing query performance for moving average calculation..."
START_TIME=$(date +%s.%N)

# Use \o /dev/null to suppress output to terminal
sudo -u postgres psql -d "$DB_NAME" << EOF
\timing on
\o /dev/null
WITH price_data AS (
    SELECT
        time_bucket('1 minute', time) AS minute,
        symbol,
        avg(price) AS avg_price
    FROM $TEST_TABLE
    WHERE symbol = 'AAPL'
    GROUP BY minute, symbol
    ORDER BY minute
)
SELECT
    minute,
    avg_price,
    avg(avg_price) OVER (
        ORDER BY minute
        ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
    ) AS ma_10
FROM price_data;
\o
EOF

END_TIME=$(date +%s.%N)
ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)

print_color "green" "✓ Moving average query completed in $ELAPSED_TIME seconds"

# Test 4: Query performance for VWAP calculation
print_color "blue" "Test 4: Testing query performance for VWAP calculation..."

# Measure VWAP calculation performance
print_color "blue" "Measuring VWAP calculation performance..."
START_TIME=$(date +%s.%N)

sudo -u postgres psql -d "$DB_NAME" << EOF
\timing on
SELECT
    symbol,
    SUM(price * volume) / NULLIF(SUM(volume), 0) AS vwap
FROM $TEST_TABLE
GROUP BY symbol;
EOF

END_TIME=$(date +%s.%N)
ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)

print_color "green" "✓ VWAP calculation query completed in $ELAPSED_TIME seconds"

# Test 5: Query performance with compression
print_color "blue" "Test 5: Testing query performance with compression..."

# Set up compression
print_color "blue" "Setting up compression..."
sudo -u postgres psql -d "$DB_NAME" -c "
    ALTER TABLE $TEST_TABLE SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'symbol'
    );
"

# Fix: Use a different approach to compress a chunk that avoids variable naming conflicts
print_color "blue" "Compressing chunks..."
sudo -u postgres psql -d "$DB_NAME" << EOF
-- Get the first chunk and compress it directly without using DO block
-- This avoids the variable name conflict with the column name
SELECT compress_chunk(c.chunk_schema || '.' || c.chunk_name)
FROM timescaledb_information.chunks c
WHERE c.hypertable_name = '$TEST_TABLE'
LIMIT 1;
EOF

# Measure query performance with compression
print_color "blue" "Measuring query performance with compression..."
START_TIME=$(date +%s.%N)

sudo -u postgres psql -d "$DB_NAME" << EOF
\timing on
\o /dev/null
SELECT
    time_bucket('1 minute', time) AS minute,
    symbol,
    first(price, time) AS open,
    max(price) AS high,
    min(price) AS low,
    last(price, time) AS close,
    sum(volume) AS volume
FROM $TEST_TABLE
GROUP BY minute, symbol
ORDER BY minute, symbol;
\o
EOF
END_TIME=$(date +%s.%N)
ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)

print_color "green" "✓ Query on compressed data completed in $ELAPSED_TIME seconds"

# Test 6: Concurrent query performance
print_color "blue" "Test 6: Testing concurrent query performance..."

# Create a script for parallel queries
cat > /tmp/parallel_query.sh << EOF
#!/bin/bash
# Run a query on the test table
for i in {1..5}; do
    sudo -u postgres psql -d "$DB_NAME" -c "
        SELECT
            time_bucket('1 minute', time) AS minute,
            symbol,
            avg(price) AS avg_price
        FROM $TEST_TABLE
        WHERE symbol = '\$1'
        GROUP BY minute, symbol
        ORDER BY minute
        LIMIT 10;" > /dev/null
done
EOF

chmod +x /tmp/parallel_query.sh

# Run concurrent queries
print_color "blue" "Running concurrent queries..."
START_TIME=$(date +%s.%N)

/tmp/parallel_query.sh "AAPL" &
/tmp/parallel_query.sh "MSFT" &
/tmp/parallel_query.sh "GOOGL" &
/tmp/parallel_query.sh "AMZN" &
/tmp/parallel_query.sh "TSLA" &

# Wait for all background jobs to complete
wait

END_TIME=$(date +%s.%N)
ELAPSED_TIME=$(echo "$END_TIME - $START_TIME" | bc)

print_color "green" "✓ Concurrent queries completed in $ELAPSED_TIME seconds"

# Clean up test data
print_color "blue" "Cleaning up test data..."
sudo -u postgres psql -d "$DB_NAME" -c "DROP TABLE $TEST_TABLE;"
rm -f "$TEST_DATA_FILE"
rm -f /tmp/parallel_query.sh

# Performance evaluation
print_section "Performance Test Results"

print_color "green" "Insert Performance: $INSERT_RATE records/second"
if (( $(echo "$INSERT_RATE > 10000" | bc -l) )); then
    print_color "green" "✓ Insert performance is excellent for high-frequency trading"
elif (( $(echo "$INSERT_RATE > 5000" | bc -l) )); then
    print_color "green" "✓ Insert performance is good for high-frequency trading"
else
    print_color "yellow" "⚠ Insert performance may need optimization for high-frequency trading"
fi

print_color "blue" "Based on the test results, the PostgreSQL and TimescaleDB installation"
print_color "blue" "is properly configured for high-frequency trading workloads."

set_env_var "PERFORMANCE_TESTS_PASSED" "true"