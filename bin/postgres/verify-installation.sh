#!/bin/bash
#
# AlgoDB - Installation Verification
# -------------------------------
# Script to verify PostgreSQL and TimescaleDB installation and configuration

# Exit on error
set -e

# Get the base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALGODB_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the required libraries
source "$ALGODB_HOME/lib/functions.sh"
source "$ALGODB_HOME/lib/env-manager.sh"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_color "red" "This script must be run as root. Use sudo or switch to root user."
    exit 1
fi

# Load environment variables
load_env

print_color "blue" "Verifying PostgreSQL and TimescaleDB installation..."

# Check PostgreSQL service status
print_color "blue" "Checking PostgreSQL service status..."
if systemctl is-active --quiet postgresql-${PG_VERSION}; then
    print_color "green" "PostgreSQL service is running."
else
    print_color "red" "PostgreSQL service is not running."
    systemctl status postgresql-${PG_VERSION}
    exit 1
fi

# Check PostgreSQL version
print_color "blue" "Checking PostgreSQL version..."
PG_VERSION_INSTALLED=$(sudo -u postgres psql -c "SELECT version();" -t | head -1)
print_color "green" "PostgreSQL version: $PG_VERSION_INSTALLED"

# Check TimescaleDB extension
print_color "blue" "Checking TimescaleDB extension..."
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';" | grep -q timescaledb; then
    TIMESCALEDB_VERSION=$(sudo -u postgres psql -d "$DB_NAME" -c "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';" -t | xargs)
    print_color "green" "TimescaleDB extension is installed (version: $TIMESCALEDB_VERSION)."
else
    print_color "red" "TimescaleDB extension is not installed in database '$DB_NAME'."
    exit 1
fi

# Check database connection
print_color "blue" "Checking database connection..."
if sudo -u postgres psql -d "$DB_NAME" -c "SELECT 1;" > /dev/null 2>&1; then
    print_color "green" "Successfully connected to database '$DB_NAME'."
else
    print_color "red" "Failed to connect to database '$DB_NAME'."
    exit 1
fi

# Check for hypertables
print_color "blue" "Checking for hypertables..."
HYPERTABLE_COUNT=$(sudo -u postgres psql -d "$DB_NAME" -c "SELECT count(*) FROM timescaledb_information.hypertables;" -t | xargs)
if [ "$HYPERTABLE_COUNT" -gt 0 ]; then
    print_color "green" "Found $HYPERTABLE_COUNT hypertables in database '$DB_NAME'."
    
    # List hypertables
    print_color "blue" "Listing hypertables:"
    sudo -u postgres psql -d "$DB_NAME" -c "SELECT hypertable_schema, hypertable_name, num_dimensions FROM timescaledb_information.hypertables;"
else
    print_color "yellow" "No hypertables found in database '$DB_NAME'."
    # This is not an error as the schema script may not have created any hypertables yet
fi

# Check PostgreSQL configuration
print_color "blue" "Checking PostgreSQL configuration for high-frequency trading optimization..."
CONFIG_FILE="/var/lib/pgsql/${PG_VERSION}/data/postgresql.conf"

# Check key parameters
SHARED_BUFFERS=$(sudo -u postgres psql -c "SHOW shared_buffers;" -t | xargs)
WORK_MEM=$(sudo -u postgres psql -c "SHOW work_mem;" -t | xargs)
MAX_PARALLEL_WORKERS=$(sudo -u postgres psql -c "SHOW max_parallel_workers;" -t | xargs)
RANDOM_PAGE_COST=$(sudo -u postgres psql -c "SHOW random_page_cost;" -t | xargs)

print_color "blue" "Current PostgreSQL configuration:"
echo "- shared_buffers = $SHARED_BUFFERS"
echo "- work_mem = $WORK_MEM"
echo "- max_parallel_workers = $MAX_PARALLEL_WORKERS"
echo "- random_page_cost = $RANDOM_PAGE_COST"

# Verify TimescaleDB configuration
TIMESCALEDB_MAX_BACKGROUND_WORKERS=$(sudo -u postgres psql -c "SHOW timescaledb.max_background_workers;" -t 2>/dev/null | xargs)
if [ -n "$TIMESCALEDB_MAX_BACKGROUND_WORKERS" ]; then
    print_color "green" "TimescaleDB is properly configured (max_background_workers = $TIMESCALEDB_MAX_BACKGROUND_WORKERS)."
else
    print_color "yellow" "TimescaleDB may not be properly configured. Check the postgresql.conf file."
fi

print_color "green" "PostgreSQL and TimescaleDB installation has been verified successfully."
set_env_var "INSTALLATION_VERIFIED" "true"
set_env_var "VERIFICATION_DATE" "$(date '+%Y-%m-%d')"