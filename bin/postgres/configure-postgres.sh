#!/bin/bash
#
# AlgoXL - PostgreSQL Configuration
# ------------------------------
# Script to configure PostgreSQL for high-frequency trading

# Exit on error
set -e

# Get the base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALGOXL_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source the required libraries
source "$ALGOXL_HOME/lib/functions.sh"
source "$ALGOXL_HOME/lib/env-manager.sh"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_color "red" "This script must be run as root. Use sudo or switch to root user."
    exit 1
fi

# Load environment variables
load_env

print_color "blue" "Configuring PostgreSQL $PG_VERSION for high-frequency trading..."

# Get service name from environment or detect it
PG_SERVICE=$(get_env_var "PG_SERVICE" "postgresql-${PG_VERSION}")
if [ -z "$PG_SERVICE" ] || ! systemctl list-unit-files | grep -q "$PG_SERVICE"; then
    print_color "yellow" "Attempting to detect PostgreSQL service name..."
    if systemctl list-unit-files | grep -q "postgresql-${PG_VERSION}.service"; then
        PG_SERVICE="postgresql-${PG_VERSION}"
    elif systemctl list-unit-files | grep -q "postgresql.service"; then
        PG_SERVICE="postgresql"
    else
        PG_SERVICE=$(systemctl list-unit-files | grep -i postgresql | head -1 | awk '{print $1}' | sed 's/\.service$//')
        
        if [ -z "$PG_SERVICE" ]; then
            print_color "red" "Could not determine PostgreSQL service name. Using default: postgresql-${PG_VERSION}"
            PG_SERVICE="postgresql-${PG_VERSION}"
        fi
    fi
    set_env_var "PG_SERVICE" "$PG_SERVICE"
fi

print_color "blue" "Using PostgreSQL service: $PG_SERVICE"

# Get data directory from environment or detect it
PG_DATA_DIR=$(get_env_var "PG_DATA_DIR" "/var/lib/pgsql/${PG_VERSION}/data")
if [ ! -d "$PG_DATA_DIR" ]; then
    print_color "yellow" "Data directory $PG_DATA_DIR not found. Attempting to detect..."
    if [ -d "/var/lib/pgsql/${PG_VERSION}/data" ]; then
        PG_DATA_DIR="/var/lib/pgsql/${PG_VERSION}/data"
    elif [ -d "/var/lib/postgresql/${PG_VERSION}/data" ]; then
        PG_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/data"
    else
        # Try to find data directory
        POSTGRES_USER=$(id -u postgres 2>/dev/null || echo "postgres")
        PG_DATA_DIR=$(find /var/lib -name "postgresql.conf" -type f 2>/dev/null | grep -v backup | head -1 | xargs dirname 2>/dev/null)
        
        if [ -z "$PG_DATA_DIR" ]; then
            print_color "red" "Could not determine PostgreSQL data directory."
            exit 1
        fi
    fi
    set_env_var "PG_DATA_DIR" "$PG_DATA_DIR"
fi

print_color "blue" "Using PostgreSQL data directory: $PG_DATA_DIR"

# Detect hardware specifications
CPU_CORES=$(nproc)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))

print_color "blue" "Detected hardware: $CPU_CORES cores, ${TOTAL_MEM_GB}GB RAM"

# Calculate optimal PostgreSQL settings
SHARED_BUFFERS="$((TOTAL_MEM_MB / 4))MB"
EFFECTIVE_CACHE_SIZE="$((TOTAL_MEM_MB * 3 / 4))MB"
WORK_MEM="$((128 * CPU_CORES))MB"
MAINTENANCE_WORK_MEM="$((512 * (CPU_CORES / 2)))MB"
MAX_PARALLEL_WORKERS="$CPU_CORES"
MAX_PARALLEL_WORKERS_PER_GATHER="$((CPU_CORES / 2))"
MAX_CONNECTIONS=200
WAL_BUFFERS="16MB"
RANDOM_PAGE_COST="1.1"
EFFECTIVE_IO_CONCURRENCY=200
CHECKPOINT_TIMEOUT="15min"
CHECKPOINT_COMPLETION_TARGET="0.9"

# Save settings to environment
set_env_var "PG_SHARED_BUFFERS" "$SHARED_BUFFERS"
set_env_var "PG_EFFECTIVE_CACHE_SIZE" "$EFFECTIVE_CACHE_SIZE"
set_env_var "PG_WORK_MEM" "$WORK_MEM"
set_env_var "PG_MAINTENANCE_WORK_MEM" "$MAINTENANCE_WORK_MEM"
set_env_var "PG_MAX_PARALLEL_WORKERS" "$MAX_PARALLEL_WORKERS"
set_env_var "PG_MAX_CONNECTIONS" "$MAX_CONNECTIONS"
set_env_var "PG_WAL_BUFFERS" "$WAL_BUFFERS"
set_env_var "PG_RANDOM_PAGE_COST" "$RANDOM_PAGE_COST"
set_env_var "PG_EFFECTIVE_IO_CONCURRENCY" "$EFFECTIVE_IO_CONCURRENCY"
set_env_var "PG_CHECKPOINT_TIMEOUT" "$CHECKPOINT_TIMEOUT"
set_env_var "PG_CHECKPOINT_COMPLETION_TARGET" "$CHECKPOINT_COMPLETION_TARGET"

# Backup original configuration
CONFIG_FILE="$PG_DATA_DIR/postgresql.conf"
HBA_FILE="$PG_DATA_DIR/pg_hba.conf"

print_color "blue" "Backing up original configuration files..."
TIMESTAMP=$(date +%Y%m%d%H%M%S)
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.${TIMESTAMP}"
cp "$HBA_FILE" "${HBA_FILE}.backup.${TIMESTAMP}"

# Check if TimescaleDB is installed
TIMESCALEDB_INSTALLED=$(get_env_var "TIMESCALEDB_INSTALLED" "false")

# Apply new configuration from template
print_color "blue" "Applying optimized configuration for high-frequency trading..."

# Only include TimescaleDB in the configuration if it's installed
if [ "$TIMESCALEDB_INSTALLED" = "true" ]; then
    print_color "blue" "TimescaleDB is installed. Including TimescaleDB configuration."
    SHARED_PRELOAD_LIBRARIES="'timescaledb'"
    TIMESCALEDB_CONFIG="
# TimescaleDB Configuration
shared_preload_libraries = $SHARED_PRELOAD_LIBRARIES
timescaledb.max_background_workers = $MAX_PARALLEL_WORKERS_PER_GATHER
timescaledb.telemetry_level = 'off'"
else
    print_color "yellow" "TimescaleDB is not installed. Skipping TimescaleDB configuration."
    SHARED_PRELOAD_LIBRARIES="''"
    TIMESCALEDB_CONFIG=""
fi

# Generate the configuration file content
CONFIG_CONTENT=$(cat "$ALGOXL_HOME/templates/postgres/postgresql.conf.template" | \
    sed "s/{{PG_VERSION}}/$PG_VERSION/g" | \
    sed "s/{{CPU_CORES}}/$CPU_CORES/g" | \
    sed "s/{{TOTAL_MEM_GB}}/$TOTAL_MEM_GB/g" | \
    sed "s/{{SHARED_BUFFERS}}/$SHARED_BUFFERS/g" | \
    sed "s/{{EFFECTIVE_CACHE_SIZE}}/$EFFECTIVE_CACHE_SIZE/g" | \
    sed "s/{{WORK_MEM}}/$WORK_MEM/g" | \
    sed "s/{{MAINTENANCE_WORK_MEM}}/$MAINTENANCE_WORK_MEM/g" | \
    sed "s/{{MAX_PARALLEL_WORKERS}}/$MAX_PARALLEL_WORKERS/g" | \
    sed "s/{{MAX_PARALLEL_WORKERS_PER_GATHER}}/$MAX_PARALLEL_WORKERS_PER_GATHER/g" | \
    sed "s/{{MAX_CONNECTIONS}}/$MAX_CONNECTIONS/g" | \
    sed "s/{{WAL_BUFFERS}}/$WAL_BUFFERS/g" | \
    sed "s/{{RANDOM_PAGE_COST}}/$RANDOM_PAGE_COST/g" | \
    sed "s/{{EFFECTIVE_IO_CONCURRENCY}}/$EFFECTIVE_IO_CONCURRENCY/g" | \
    sed "s/{{CHECKPOINT_TIMEOUT}}/$CHECKPOINT_TIMEOUT/g" | \
    sed "s/{{CHECKPOINT_COMPLETION_TARGET}}/$CHECKPOINT_COMPLETION_TARGET/g" | \
    sed "s/{{GENERATION_DATE}}/$(date '+%Y-%m-%d %H:%M:%S')/g")

# Update the TimescaleDB configuration section
if [ "$TIMESCALEDB_INSTALLED" = "true" ]; then
    echo "$CONFIG_CONTENT" > "$CONFIG_FILE"
else
    # Remove the TimescaleDB section if TimescaleDB is not installed
    echo "$CONFIG_CONTENT" | grep -v "TimescaleDB Configuration" | grep -v "timescaledb" > "$CONFIG_FILE"
fi

# Apply pg_hba.conf from template
cat "$ALGOXL_HOME/templates/postgres/pg_hba.conf.template" > "$HBA_FILE"

# Set secure permissions on configuration files
chmod 600 "$CONFIG_FILE" "$HBA_FILE"
chown postgres:postgres "$CONFIG_FILE" "$HBA_FILE"

# Restart PostgreSQL to apply changes
print_color "blue" "Restarting PostgreSQL to apply changes..."
systemctl restart "$PG_SERVICE"

# Wait for PostgreSQL to restart
sleep 5

# Check if PostgreSQL service is running
if ! systemctl is-active --quiet "$PG_SERVICE"; then
    print_color "red" "Failed to restart PostgreSQL service after configuration changes."
    systemctl status "$PG_SERVICE"
    exit 1
fi

print_color "green" "PostgreSQL has been configured for high-frequency trading workloads."