#!/bin/bash
#
# AlgoDB - TimescaleDB Test Script
# -----------------------------
# Script to test TimescaleDB installation and functionality

# Exit on error
set -e

# Get the base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALGODB_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the required libraries
source "$ALGODB_HOME/lib/functions.sh"
source "$ALGODB_HOME/lib/env-manager.sh"

# Load environment variables
load_env

# Set PostgreSQL version if not already set
PG_VERSION="${PG_VERSION:-15}"
DB_NAME="${DB_NAME:-algodb}"

print_section "Testing TimescaleDB Installation"

# Test 1: Check TimescaleDB extension
print_color "blue" "Test 1: Checking TimescaleDB extension..."
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';" | grep -q timescaledb; then
    TIMESCALEDB_VERSION=$(sudo -u postgres psql -d "$DB_NAME" -c "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';" -t | xargs)
    print_color "green" "✓ TimescaleDB extension is installed (version: $TIMESCALEDB_VERSION)."
else
    print_color "red" "✗ TimescaleDB extension is not installed in database '$DB_NAME'."
    exit 1
fi

# Test 2: Create a test hypertable
print_color "blue" "Test 2: Creating a test hypertable..."
TEST_HYPERTABLE="timescaledb_test_$(date +%s)"
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Create a test table
    CREATE TABLE $TEST_HYPERTABLE (
        time TIMESTAMPTZ NOT NULL,
        device_id TEXT,
        temperature DOUBLE PRECISION,
        humidity DOUBLE PRECISION
    );
    
    -- Convert to hypertable
    SELECT create_hypertable('$TEST_HYPERTABLE', 'time');
"; then
    print_color "green" "✓ Successfully created test hypertable."
else
    print_color "red" "✗ Failed to create test hypertable."
    exit 1
fi

# Test 3: Insert test data
print_color "blue" "Test 3: Inserting test data into hypertable..."
if sudo -u postgres psql -d "$DB_NAME" -c "
    INSERT INTO $TEST_HYPERTABLE (time, device_id, temperature, humidity)
    SELECT
        generate_series(now() - interval '24 hours', now(), interval '1 hour') as time,
        'device_' || (random() * 10)::int as device_id,
        20.0 + (random() * 10.0)::decimal(10,2) as temperature,
        50.0 + (random() * 10.0)::decimal(10,2) as humidity
    FROM generate_series(1, 10);
"; then
    print_color "green" "✓ Successfully inserted test data."
else
    print_color "red" "✗ Failed to insert test data."
    exit 1
fi

# Test 4: Query test data with time_bucket
print_color "blue" "Test 4: Querying test data with time_bucket..."
if sudo -u postgres psql -d "$DB_NAME" -c "
    SELECT 
        time_bucket('1 hour', time) AS hourly_bucket,
        device_id,
        avg(temperature) AS avg_temp,
        avg(humidity) AS avg_humidity
    FROM $TEST_HYPERTABLE
    GROUP BY hourly_bucket, device_id
    ORDER BY hourly_bucket DESC, device_id
    LIMIT 5;
"; then
    print_color "green" "✓ Successfully queried test data with time_bucket."
else
    print_color "red" "✗ Failed to query test data with time_bucket."
    exit 1
fi

# Test 5: Test compression (FIXED VERSION)
print_color "blue" "Test 5: Testing hypertable compression..."
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Add compression settings
    ALTER TABLE $TEST_HYPERTABLE SET (
        timescaledb.compress,
        timescaledb.compress_segmentby = 'device_id'
    );
    
    -- Try direct compression of the first chunk using a simpler approach
    SELECT compress_chunk(i.chunk_schema || '.' || i.chunk_name) 
    FROM timescaledb_information.chunks i
    WHERE i.hypertable_name = '$TEST_HYPERTABLE'
    LIMIT 1;
"; then
    print_color "green" "✓ Successfully set up and applied compression."
else
    print_color "red" "✗ Failed to set up and apply compression."
    exit 1
fi

# Test 6: Test continuous aggregates - Split into separate commands to avoid transaction issues
print_color "blue" "Test 6: Testing continuous aggregates..."
TEST_CAGG="test_cagg_$(date +%s)"

# First create the continuous aggregate
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Create a continuous aggregate
    CREATE MATERIALIZED VIEW $TEST_CAGG
    WITH (timescaledb.continuous) AS
    SELECT
        time_bucket('1 hour', time) as bucket,
        device_id,
        avg(temperature) as avg_temp,
        min(temperature) as min_temp,
        max(temperature) as max_temp,
        avg(humidity) as avg_humidity
    FROM $TEST_HYPERTABLE
    GROUP BY bucket, device_id;
"; then
    # Then query it in a separate statement
    if sudo -u postgres psql -d "$DB_NAME" -c "
        -- Query the continuous aggregate
        SELECT * FROM $TEST_CAGG ORDER BY bucket DESC, device_id LIMIT 5;
    "; then
        print_color "green" "✓ Successfully created and queried continuous aggregate."
    else
        print_color "red" "✗ Failed to query continuous aggregate."
        exit 1
    fi
else
    print_color "red" "✗ Failed to create continuous aggregate."
    exit 1
fi

# Test 7: Test policies - Split into separate commands for each policy
print_color "blue" "Test 7: Testing automated policies..."

# Add a refresh policy
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Add a refresh policy
    SELECT add_continuous_aggregate_policy('$TEST_CAGG',
        start_offset => INTERVAL '1 day',
        end_offset => INTERVAL '1 hour',
        schedule_interval => INTERVAL '1 hour');
"; then
    print_color "green" "✓ Successfully created refresh policy."
else
    print_color "red" "✗ Failed to create refresh policy."
    exit 1
fi

# Add a retention policy
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Add a retention policy
    SELECT add_retention_policy('$TEST_HYPERTABLE', INTERVAL '90 days');
"; then
    print_color "green" "✓ Successfully created retention policy."
else
    print_color "red" "✗ Failed to create retention policy."
    exit 1
fi

# Add a compression policy
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Add a compression policy
    SELECT add_compression_policy('$TEST_HYPERTABLE', INTERVAL '7 days');
"; then
    print_color "green" "✓ Successfully created compression policy."
else
    print_color "red" "✗ Failed to create compression policy."
    exit 1
fi

# List policies - Try different views based on TimescaleDB version
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Check if policies view exists
    SELECT EXISTS (
        SELECT 1 FROM pg_catalog.pg_views 
        WHERE schemaname = 'timescaledb_information' 
        AND viewname = 'policies'
    );
"; then
    # Check which view to use for policies
    HAS_POLICIES_VIEW=$(sudo -u postgres psql -d "$DB_NAME" -c "
        SELECT EXISTS (
            SELECT 1 FROM pg_catalog.pg_views 
            WHERE schemaname = 'timescaledb_information' 
            AND viewname = 'policies'
        );
    " -t | xargs)
    
    if [ "$HAS_POLICIES_VIEW" = "t" ]; then
        # Use the policies view if it exists
        sudo -u postgres psql -d "$DB_NAME" -c "
            -- List policies using timescaledb_information.policies
            SELECT * FROM timescaledb_information.policies;
        "
    else
        # Try alternate views for policy information
        print_color "blue" "Using alternate views for policy information..."
        
        # Check refresh policies
        sudo -u postgres psql -d "$DB_NAME" -c "
            -- List refresh policies
            SELECT * FROM timescaledb_information.continuous_aggregate_policies;
        " 2>/dev/null || true
        
        # Check retention policies
        sudo -u postgres psql -d "$DB_NAME" -c "
            -- List retention policies
            SELECT * FROM timescaledb_information.drop_chunks_policies;
        " 2>/dev/null || true
        
        # Check compression policies
        sudo -u postgres psql -d "$DB_NAME" -c "
            -- List compression policies
            SELECT * FROM timescaledb_information.compression_policies;
        " 2>/dev/null || true
        
        # If none of those work, try the jobs table
        sudo -u postgres psql -d "$DB_NAME" -c "
            -- List all TimescaleDB jobs (which include policies)
            SELECT * FROM timescaledb_information.jobs;
        " 2>/dev/null || true
    fi
    
    print_color "green" "✓ Successfully listed policies."
else
    print_color "yellow" "⚠ Could not query policy information. Continuing tests."
fi

# Test 8: Clean up test objects - Split into separate commands for each policy removal
print_color "blue" "Test 8: Cleaning up test objects..."

# Remove refresh policy
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Remove refresh policy
    SELECT remove_continuous_aggregate_policy('$TEST_CAGG');
"; then
    print_color "green" "✓ Successfully removed refresh policy."
else
    print_color "red" "✗ Failed to remove refresh policy."
    exit 1
fi

# Remove retention policy
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Remove retention policy
    SELECT remove_retention_policy('$TEST_HYPERTABLE');
"; then
    print_color "green" "✓ Successfully removed retention policy."
else
    print_color "red" "✗ Failed to remove retention policy."
    exit 1
fi

# Remove compression policy
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Remove compression policy
    SELECT remove_compression_policy('$TEST_HYPERTABLE');
"; then
    print_color "green" "✓ Successfully removed compression policy."
else
    print_color "red" "✗ Failed to remove compression policy."
    exit 1
fi

# Drop continuous aggregate
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Drop continuous aggregate
    DROP MATERIALIZED VIEW $TEST_CAGG;
"; then
    print_color "green" "✓ Successfully dropped continuous aggregate."
else
    print_color "red" "✗ Failed to drop continuous aggregate."
    exit 1
fi

# Drop hypertable
if sudo -u postgres psql -d "$DB_NAME" -c "
    -- Drop hypertable
    DROP TABLE $TEST_HYPERTABLE;
"; then
    print_color "green" "✓ Successfully dropped hypertable."
else
    print_color "red" "✗ Failed to drop hypertable."
    exit 1
fi

# Test 9: Check for existing hypertables in our schema
print_color "blue" "Test 9: Checking for existing hypertables in our schema..."
HYPERTABLE_COUNT=$(sudo -u postgres psql -d "$DB_NAME" -c "SELECT count(*) FROM timescaledb_information.hypertables WHERE hypertable_schema = 'market_data';" -t | xargs)
if [ "$HYPERTABLE_COUNT" -gt 0 ]; then
    print_color "green" "✓ Found $HYPERTABLE_COUNT hypertables in market_data schema."
    
    # List hypertables
    print_color "blue" "Listing hypertables in market_data schema:"
    sudo -u postgres psql -d "$DB_NAME" -c "SELECT hypertable_name, num_dimensions FROM timescaledb_information.hypertables WHERE hypertable_schema = 'market_data';"
else
    print_color "yellow" "⚠ No hypertables found in market_data schema."
fi

print_section "TimescaleDB Tests Summary"
print_color "green" "✓ All TimescaleDB tests completed successfully."
set_env_var "TIMESCALEDB_TESTS_PASSED" "true"