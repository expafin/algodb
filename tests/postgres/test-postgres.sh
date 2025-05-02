#!/bin/bash
#
# AlgoXL - PostgreSQL Test Script
# ----------------------------
# Script to test PostgreSQL installation and functionality

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

print_section "Testing PostgreSQL Installation"

# Test 1: Check PostgreSQL service status
print_color "blue" "Test 1: Checking PostgreSQL service status..."
if systemctl is-active --quiet postgresql-${PG_VERSION}; then
    print_color "green" "✓ PostgreSQL service is running."
else
    print_color "red" "✗ PostgreSQL service is not running."
    systemctl status postgresql-${PG_VERSION}
    exit 1
fi

# Test 2: Check PostgreSQL version
print_color "blue" "Test 2: Checking PostgreSQL version..."
PG_VERSION_INSTALLED=$(sudo -u postgres psql -c "SELECT version();" -t | head -1)
print_color "green" "✓ PostgreSQL version: $PG_VERSION_INSTALLED"

# Test 3: Check connection to database
print_color "blue" "Test 3: Checking connection to database $DB_NAME..."
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    print_color "green" "✓ Successfully connected to database $DB_NAME."
else
    print_color "red" "✗ Failed to connect to database $DB_NAME."
    exit 1
fi

# Test 4: Create a test table
print_color "blue" "Test 4: Creating a test table..."
TEST_TABLE="pg_test_$(date +%s)"
if sudo -u postgres psql -d "$DB_NAME" -c "
    CREATE TABLE $TEST_TABLE (
        id SERIAL PRIMARY KEY,
        name TEXT,
        value NUMERIC,
        created_at TIMESTAMPTZ DEFAULT now()
    );
"; then
    print_color "green" "✓ Successfully created test table."
else
    print_color "red" "✗ Failed to create test table."
    exit 1
fi

# Test 5: Insert test data
print_color "blue" "Test 5: Inserting test data..."
if sudo -u postgres psql -d "$DB_NAME" -c "
    INSERT INTO $TEST_TABLE (name, value) VALUES
    ('test1', 1.1),
    ('test2', 2.2),
    ('test3', 3.3);
"; then
    print_color "green" "✓ Successfully inserted test data."
else
    print_color "red" "✗ Failed to insert test data."
    exit 1
fi

# Test 6: Query test data
print_color "blue" "Test 6: Querying test data..."
QUERY_RESULT=$(sudo -u postgres psql -d "$DB_NAME" -c "SELECT COUNT(*) FROM $TEST_TABLE;" -t | xargs)
if [ "$QUERY_RESULT" -eq 3 ]; then
    print_color "green" "✓ Successfully queried test data."
else
    print_color "red" "✗ Query returned unexpected result: $QUERY_RESULT"
    exit 1
fi

# Test 7: Clean up test table
print_color "blue" "Test 7: Cleaning up test table..."
if sudo -u postgres psql -d "$DB_NAME" -c "DROP TABLE $TEST_TABLE;"; then
    print_color "green" "✓ Successfully cleaned up test table."
else
    print_color "red" "✗ Failed to clean up test table."
    exit 1
fi

# Test 8: Check database configuration
print_color "blue" "Test 8: Checking database configuration..."
SHARED_BUFFERS=$(sudo -u postgres psql -c "SHOW shared_buffers;" -t | xargs)
WORK_MEM=$(sudo -u postgres psql -c "SHOW work_mem;" -t | xargs)
MAX_PARALLEL_WORKERS=$(sudo -u postgres psql -c "SHOW max_parallel_workers;" -t | xargs)

print_color "blue" "Current PostgreSQL configuration:"
echo "- shared_buffers = $SHARED_BUFFERS"
echo "- work_mem = $WORK_MEM"
echo "- max_parallel_workers = $MAX_PARALLEL_WORKERS"

# Test 9: Check database users
print_color "blue" "Test 9: Checking database users..."
DB_USERS=$(sudo -u postgres psql -c "SELECT rolname FROM pg_roles WHERE rolcanlogin;" -t)
print_color "green" "✓ Database users:"
echo "$DB_USERS"

print_section "PostgreSQL Tests Summary"
print_color "green" "✓ All PostgreSQL tests completed successfully."
set_env_var "PG_TESTS_PASSED" "true"