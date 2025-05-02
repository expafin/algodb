#!/bin/bash
#
# AlgoXL - TimescaleDB Installation
# -------------------------------
# Script to install and configure TimescaleDB extension

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

print_color "blue" "Installing TimescaleDB for PostgreSQL $PG_VERSION..."

# Add TimescaleDB repository
print_color "blue" "Adding TimescaleDB repository..."
if ! rpm -q timescaledb-tools &>/dev/null; then
    cat > /etc/yum.repos.d/timescale_timescaledb.repo << EOF
[timescale_timescaledb]
name=timescale_timescaledb
baseurl=https://packagecloud.io/timescale/timescaledb/el/9/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/timescale/timescaledb/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF
fi

# Install TimescaleDB
print_color "blue" "Installing TimescaleDB package..."
dnf install -y timescaledb-2-postgresql-${PG_VERSION}

# IMPORTANT: Directly update the PostgreSQL configuration file
PG_DATA_DIR=$(get_env_var "PG_DATA_DIR" "/var/lib/pgsql/${PG_VERSION}/data")
if [ -z "$PG_DATA_DIR" ] || [ ! -d "$PG_DATA_DIR" ]; then
    # Try to find the data directory
    if [ -d "/var/lib/pgsql/${PG_VERSION}/data" ]; then
        PG_DATA_DIR="/var/lib/pgsql/${PG_VERSION}/data"
    elif [ -d "/var/lib/postgresql/${PG_VERSION}/data" ]; then
        PG_DATA_DIR="/var/lib/postgresql/${PG_VERSION}/data"
    else
        # Try to find data directory
        PG_DATA_DIR=$(find /var/lib -name "postgresql.conf" -type f 2>/dev/null | grep -v backup | head -1 | xargs dirname 2>/dev/null)
    fi
    
    if [ -z "$PG_DATA_DIR" ] || [ ! -d "$PG_DATA_DIR" ]; then
        print_color "red" "Could not determine PostgreSQL data directory."
        exit 1
    fi
    
    # Save to environment
    set_env_var "PG_DATA_DIR" "$PG_DATA_DIR"
fi

CONFIG_FILE="$PG_DATA_DIR/postgresql.conf"
print_color "blue" "Updating PostgreSQL configuration at $CONFIG_FILE..."

# Backup the original configuration file
TIMESTAMP=$(date +%Y%m%d%H%M%S)
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.${TIMESTAMP}"

# Check if shared_preload_libraries is already set
if grep -q "^shared_preload_libraries" "$CONFIG_FILE"; then
    # Append timescaledb if not already included
    if ! grep -q "timescaledb" "$CONFIG_FILE"; then
        sed -i "s/^shared_preload_libraries\s*=\s*'\([^']*\)'/shared_preload_libraries = '\1,timescaledb'/" "$CONFIG_FILE"
    fi
else
    # Add the parameter if it doesn't exist
    echo "# TimescaleDB Configuration" >> "$CONFIG_FILE"
    echo "shared_preload_libraries = 'timescaledb'" >> "$CONFIG_FILE"
    echo "timescaledb.max_background_workers = 8" >> "$CONFIG_FILE"
    echo "timescaledb.telemetry_level = 'off'" >> "$CONFIG_FILE"
fi

# Ensure proper permissions
chmod 600 "$CONFIG_FILE"
chown postgres:postgres "$CONFIG_FILE"

# Get PostgreSQL service name
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

# Restart PostgreSQL service to apply changes
print_color "blue" "Restarting PostgreSQL service ($PG_SERVICE) to apply TimescaleDB configuration..."
systemctl restart "$PG_SERVICE"

# Wait for PostgreSQL to restart
sleep 10

# Verify PostgreSQL service is running
if ! systemctl is-active --quiet "$PG_SERVICE"; then
    print_color "red" "Failed to restart PostgreSQL service after configuring TimescaleDB."
    systemctl status "$PG_SERVICE"
    exit 1
fi

# Check if TimescaleDB is properly loaded
if sudo -u postgres psql -c "SELECT 1 FROM pg_extension WHERE extname = 'timescaledb';" 2>/dev/null | grep -q 1; then
    print_color "green" "TimescaleDB is already enabled in the main database."
else
    print_color "blue" "TimescaleDB is properly installed but not yet enabled in any database."
fi

# Set environment variables
set_env_var "TIMESCALEDB_INSTALLED" "true"
set_env_var "TIMESCALEDB_INSTALL_DATE" "$(date '+%Y-%m-%d')"

print_color "green" "TimescaleDB has been successfully installed and configured."