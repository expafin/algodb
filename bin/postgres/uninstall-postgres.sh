#!/bin/bash
#
# AlgoXL - PostgreSQL Uninstallation
# -------------------------------
# Script to uninstall PostgreSQL and clean up data directories

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

print_section "Uninstalling PostgreSQL Installation"

# Stop all PostgreSQL services
print_color "blue" "Stopping PostgreSQL services..."
systemctl stop postgresql* 2>/dev/null || true

# List installed PostgreSQL packages
PG_PACKAGES=$(rpm -qa | grep postgresql)

if [ -n "$PG_PACKAGES" ]; then
    print_color "blue" "Found existing PostgreSQL packages:"
    echo "$PG_PACKAGES"
    
    print_color "blue" "Uninstalling PostgreSQL packages..."
    dnf remove -y postgresql* 2>/dev/null
else
    print_color "blue" "No PostgreSQL packages found."
fi

# Find and remove PostgreSQL data directories
PG_DATA_DIRS=$(find /var/lib -name "pgsql" -type d 2>/dev/null)
if [ -n "$PG_DATA_DIRS" ]; then
    print_color "yellow" "WARNING: The following PostgreSQL data directories will be removed:"
    echo "$PG_DATA_DIRS"
    
    if confirm "Do you want to remove these directories and ALL DATA inside them?" "n"; then
        print_color "blue" "Removing PostgreSQL data directories..."
        rm -rf $PG_DATA_DIRS
        print_color "green" "PostgreSQL data directories have been removed."
    else
        print_color "yellow" "Data directories will not be removed."
    fi
fi

# Remove TimescaleDB repository
if [ -f /etc/yum.repos.d/timescale_timescaledb.repo ]; then
    print_color "blue" "Removing TimescaleDB repository files..."
    rm -f /etc/yum.repos.d/timescale_timescaledb.repo
fi

# Remove PostgreSQL repo files
if [ -f /etc/yum.repos.d/pgdg-redhat-all.repo ]; then
    print_color "blue" "Removing PostgreSQL repository files..."
    rm -f /etc/yum.repos.d/pgdg*.repo
fi

# Update environment variables
if has_env_var "PG_INSTALLED"; then
    remove_env_var "PG_INSTALLED"
fi
if has_env_var "TIMESCALEDB_INSTALLED"; then
    remove_env_var "TIMESCALEDB_INSTALLED"
fi

print_color "green" "PostgreSQL uninstallation completed successfully."