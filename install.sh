#!/bin/bash
#
# AlgoXL - High-Frequency Trading Database Installation
# ----------------------------------------------------
# Main installation script for PostgreSQL with TimescaleDB
# optimized for high-frequency trading workloads

# Exit on error
set -e

# Get the base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ALGOXL_HOME="$SCRIPT_DIR"

# Source the bootstrap and functions
source "$ALGOXL_HOME/lib/functions.sh"

# Welcome message
print_section "AlgoXL - High-Frequency Trading Database Installation"
print_color "blue" "This script will install and configure PostgreSQL with TimescaleDB"
print_color "blue" "optimized for high-frequency trading on your server."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_color "red" "This script must be run as root. Use sudo or switch to root user."
    exit 1
fi

# Install required packages first
print_section "Installing Required Packages"
dnf install -y curl git bc

# Initialize bootstrap environment and run system check
source "$ALGOXL_HOME/lib/bootstrap.sh"
source "$ALGOXL_HOME/lib/env-manager.sh"

# Run initialize function which includes check_system
initialize

# Ask if the user wants to uninstall existing PostgreSQL
if confirm "Do you want to uninstall any existing PostgreSQL installations before proceeding?" "n"; then
    bash "$ALGOXL_HOME/bin/postgres/uninstall-postgres.sh"
fi

# Ask for PostgreSQL version
print_section "PostgreSQL Version Selection"
print_color "blue" "Available PostgreSQL versions:"
print_color "blue" "12 - PostgreSQL 12 (Older but stable)"
print_color "blue" "13 - PostgreSQL 13 (Older but stable)"
print_color "blue" "14 - PostgreSQL 14 (Stable)"
print_color "blue" "15 - PostgreSQL 15 (Recommended)"
print_color "blue" "16 - PostgreSQL 16 (Recent)"
print_color "blue" "17 - PostgreSQL 17 (Latest)"

# Prompt for version
DEFAULT_PG_VERSION="15"
read -p "Which PostgreSQL version do you want to install? [$DEFAULT_PG_VERSION]: " PG_VERSION
PG_VERSION=${PG_VERSION:-$DEFAULT_PG_VERSION}

# Using indicated version as is (no validation)
print_color "green" "Selected PostgreSQL version: $PG_VERSION"

# Set environment variable for PostgreSQL version
set_env_var "PG_VERSION" "$PG_VERSION"

# Install PostgreSQL
print_section "Installing PostgreSQL $PG_VERSION"
bash "$ALGOXL_HOME/bin/postgres/install-postgres.sh"

# Install and configure TimescaleDB (modified script now handles configuration and restart)
print_section "Installing and Configuring TimescaleDB"
bash "$ALGOXL_HOME/bin/postgres/install-timescaledb.sh"

# Verify PostgreSQL is running with TimescaleDB loaded
print_section "Verifying PostgreSQL Configuration"
PG_SERVICE=$(get_env_var "PG_SERVICE" "postgresql-${PG_VERSION}")
if ! systemctl is-active --quiet "$PG_SERVICE"; then
    print_color "red" "PostgreSQL service is not running. Attempting to start..."
    systemctl start "$PG_SERVICE"
    sleep 5
fi

# Double-check shared_preload_libraries configuration
PG_DATA_DIR=$(get_env_var "PG_DATA_DIR")
if [ -f "$PG_DATA_DIR/postgresql.conf" ]; then
    if ! grep -q "^shared_preload_libraries.*timescaledb" "$PG_DATA_DIR/postgresql.conf"; then
        print_color "red" "TimescaleDB is not configured in shared_preload_libraries. Adding it now..."
        echo "shared_preload_libraries = 'timescaledb'" >> "$PG_DATA_DIR/postgresql.conf"
        systemctl restart "$PG_SERVICE"
        sleep 10
    fi
fi
# Setup database schema
print_section "Setting Up Database Schema"
print_color "blue" "Enter the database name (leave empty for default: algoxl):"
read -p "Database name: " DB_NAME
DB_NAME=${DB_NAME:-algoxl}

print_color "blue" "Enter the database user (leave empty for default: algoxl_user):"
read -p "Database user: " DB_USER
DB_USER=${DB_USER:-algoxl_user}

print_color "blue" "Enter the database password (leave empty for auto-generated):"
read -s -p "Database password: " DB_PASSWORD
echo
DB_PASSWORD=${DB_PASSWORD:-$(tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 16 || echo 'AlgoXL2023!')}

# Export database variables
export DB_NAME
export DB_USER
export DB_PASSWORD

# Run setup schema script
bash "$ALGOXL_HOME/bin/postgres/setup-schema.sh"

# Verify installation
print_section "Verifying Installation"
bash "$ALGOXL_HOME/bin/postgres/verify-installation.sh"

# Run tests
print_section "Running Tests"
print_color "blue" "Running PostgreSQL tests..."
bash "$ALGOXL_HOME/tests/postgres/test-postgres.sh"

print_color "blue" "Running TimescaleDB tests..."
bash "$ALGOXL_HOME/tests/postgres/test-timescaledb.sh"

print_color "blue" "Running performance tests..."
bash "$ALGOXL_HOME/tests/postgres/test-performance.sh"

# Installation complete
print_section "Installation Complete"
print_color "green" "AlgoXL - High-Frequency Trading Database has been successfully installed!"
print_color "green" "PostgreSQL $PG_VERSION with TimescaleDB is now running and optimized for trading workloads."

# Display connection information
DB_NAME=$(get_env_var "DB_NAME")
DB_USER=$(get_env_var "DB_USER")
DB_PASSWORD=$(get_env_var "DB_PASSWORD")

print_color "blue" "Connection Information:"
print_color "blue" "Database: $DB_NAME"
print_color "blue" "User: $DB_USER"
print_color "blue" "Password: $DB_PASSWORD"
print_color "blue" "Connection string: postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME"

print_color "blue" "For quick reference, check: $ALGOXL_HOME/docs/postgres/quick-reference.md"