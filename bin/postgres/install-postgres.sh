#!/bin/bash
#
# AlgoDB - PostgreSQL Installation
# ------------------------------
# Script to install PostgreSQL on AlmaLinux 9.5

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

print_color "blue" "Installing PostgreSQL $PG_VERSION..."

# Remove existing repo if it exists to ensure clean installation
if rpm -q pgdg-redhat-repo &>/dev/null; then
    print_color "blue" "Removing existing PostgreSQL repository..."
    dnf remove -y pgdg-redhat-repo
fi

# Add PostgreSQL repository
print_color "blue" "Adding PostgreSQL repository..."
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-10-x86_64/pgdg-redhat-repo-latest.noarch.rpm

# Verify the repository is installed and enabled
if ! rpm -q pgdg-redhat-repo &>/dev/null; then
    print_color "red" "Failed to install PostgreSQL repository package."
    exit 1
fi

# Clean dnf cache to ensure we have the latest repository metadata
print_color "blue" "Cleaning DNF cache to refresh repository data..."
dnf clean all
dnf makecache

# Disable builtin PostgreSQL module (if it exists)
print_color "blue" "Disabling built-in PostgreSQL module..."
dnf -qy module disable postgresql 2>/dev/null || print_color "yellow" "No built-in PostgreSQL module found (this is normal for AlmaLinux 10)"

# Check for available PostgreSQL packages
print_color "blue" "Checking for available PostgreSQL packages..."
AVAILABLE_PACKAGES=$(dnf list available | grep -i "postgresql${PG_VERSION}" | grep -i server)

if [ -z "$AVAILABLE_PACKAGES" ]; then
    print_color "yellow" "PostgreSQL $PG_VERSION packages not found. Listing available PostgreSQL versions..."
    dnf list available | grep -i postgresql | grep -i server
    
    # Ask if the user wants to continue with a different version
    read -p "PostgreSQL $PG_VERSION not available. Enter a different version number or press Enter to abort: " NEW_VERSION
    
    if [ -z "$NEW_VERSION" ]; then
        print_color "red" "Installation aborted."
        exit 1
    else
        PG_VERSION="$NEW_VERSION"
        set_env_var "PG_VERSION" "$PG_VERSION"
        print_color "blue" "Proceeding with PostgreSQL $PG_VERSION installation..."
    fi
fi

# Directly use PG_VERSION for package names
POSTGRES_VERSION=$PG_VERSION

# Install PostgreSQL server and development packages
print_color "blue" "Installing PostgreSQL $POSTGRES_VERSION packages..."
dnf install -y postgresql${POSTGRES_VERSION}-server postgresql${POSTGRES_VERSION}-contrib postgresql${POSTGRES_VERSION}-devel

# Initialize PostgreSQL database
print_color "blue" "Initializing PostgreSQL database..."
SETUP_SCRIPT="/usr/pgsql-${POSTGRES_VERSION}/bin/postgresql-${POSTGRES_VERSION}-setup"

if [ -f "$SETUP_SCRIPT" ]; then
    if ! "$SETUP_SCRIPT" initdb; then
        print_color "red" "Failed to initialize PostgreSQL database."
        exit 1
    fi
else
    print_color "red" "PostgreSQL setup script not found at $SETUP_SCRIPT"
    print_color "yellow" "Attempting to find the setup script..."
    
    ALTERNATIVE_SCRIPT=$(find /usr -name "*postgresql*setup*" -type f | head -1)
    
    if [ -n "$ALTERNATIVE_SCRIPT" ]; then
        print_color "blue" "Found alternative setup script: $ALTERNATIVE_SCRIPT"
        if ! "$ALTERNATIVE_SCRIPT" initdb; then
            print_color "red" "Failed to initialize PostgreSQL database with alternative script."
            exit 1
        fi
    else
        print_color "red" "No PostgreSQL setup script found. Installation cannot continue."
        exit 1
    fi
fi

# Set environment variables
PG_DATA_DIR="/var/lib/pgsql/${POSTGRES_VERSION}/data"
if [ ! -d "$PG_DATA_DIR" ]; then
    # Try to find the data directory
    print_color "yellow" "Default data directory not found. Attempting to locate data directory..."
    POSSIBLE_DATA_DIR=$(find /var/lib/pgsql -name postgresql.conf -type f | xargs dirname | head -1)
    
    if [ -n "$POSSIBLE_DATA_DIR" ]; then
        PG_DATA_DIR="$POSSIBLE_DATA_DIR"
        print_color "blue" "Found data directory at: $PG_DATA_DIR"
    else
        print_color "red" "Could not locate PostgreSQL data directory."
        exit 1
    fi
fi

PG_SERVICE="postgresql-${POSTGRES_VERSION}"
if ! systemctl list-unit-files | grep -q "$PG_SERVICE"; then
    # Try to find the service name
    print_color "yellow" "Default service name not found. Attempting to locate service..."
    POSSIBLE_SERVICE=$(systemctl list-unit-files | grep -i postgresql | head -1 | awk '{print $1}' | sed 's/\.service$//')
    
    if [ -n "$POSSIBLE_SERVICE" ]; then
        PG_SERVICE="$POSSIBLE_SERVICE"
        print_color "blue" "Found service name: $PG_SERVICE"
    else
        print_color "red" "Could not locate PostgreSQL service."
        exit 1
    fi
fi

# Save to environment
set_env_var "PG_DATA_DIR" "$PG_DATA_DIR"
set_env_var "PG_SERVICE" "$PG_SERVICE"

# Start PostgreSQL service
print_color "blue" "Starting PostgreSQL service..."
systemctl enable $PG_SERVICE
systemctl start $PG_SERVICE

# Wait for PostgreSQL to start
sleep 5

# Check if PostgreSQL service is running
if ! systemctl is-active --quiet $PG_SERVICE; then
    print_color "red" "Failed to start PostgreSQL service."
    systemctl status $PG_SERVICE
    exit 1
fi

# Set environment variables
set_env_var "PG_INSTALLED" "true"
set_env_var "PG_INSTALL_DATE" "$(date '+%Y-%m-%d')"

print_color "green" "PostgreSQL $PG_VERSION has been successfully installed."