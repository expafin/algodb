#!/bin/bash
#
# AlgoXL - Database Schema Setup
# ----------------------------
# Script to set up the database schema for high-frequency trading

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

# Make sure DB_NAME, DB_USER, and DB_PASSWORD are properly set
if [ -z "$DB_NAME" ]; then
    print_color "yellow" "DB_NAME not set. Using default: algoxl"
    DB_NAME="algoxl"
fi

if [ -z "$DB_USER" ]; then
    print_color "yellow" "DB_USER not set. Using default: algoxl_user"
    DB_USER="algoxl_user"
fi

if [ -z "$DB_PASSWORD" ]; then
    print_color "yellow" "DB_PASSWORD not set. Generating a secure password."
    DB_PASSWORD=$(generate_password 16)
fi

# Sanitize values to avoid potential command injection
DB_NAME=$(echo "$DB_NAME" | tr -dc 'a-zA-Z0-9_')
DB_USER=$(echo "$DB_USER" | tr -dc 'a-zA-Z0-9_')

# FIX: Properly handle password escaping for PostgreSQL
# Escape single quotes in the password by doubling them (PostgreSQL syntax)
PG_PASSWORD=$(echo "$DB_PASSWORD" | sed "s/'/''/g")

# Save database credentials to environment
# Use set_env_var instead of direct env export to ensure proper escaping
set_env_var "DB_NAME" "$DB_NAME"
set_env_var "DB_USER" "$DB_USER"
set_env_var "DB_PASSWORD" "$DB_PASSWORD"

print_color "blue" "Setting up database schema for high-frequency trading..."

# Create database user
print_color "blue" "Creating database user..."
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
    # FIX: Properly quote the password for PostgreSQL
    sudo -u postgres psql -c "CREATE USER \"$DB_USER\" WITH PASSWORD '$PG_PASSWORD';"
else
    # FIX: Properly quote the password for PostgreSQL
    sudo -u postgres psql -c "ALTER USER \"$DB_USER\" WITH PASSWORD '$PG_PASSWORD';"
fi

# Create database
print_color "blue" "Creating database..."
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
    sudo -u postgres psql -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"
else
    print_color "yellow" "Database '$DB_NAME' already exists."
fi

# Create TimescaleDB extension
print_color "blue" "Creating TimescaleDB extension in database..."
sudo -u postgres psql -d "$DB_NAME" -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

# Set up schema from template
print_color "blue" "Setting up schema from template..."
cat "$ALGOXL_HOME/templates/postgres/schema.sql.template" | \
    sed "s/{{DB_NAME}}/$DB_NAME/g" | \
    sed "s/{{DB_USER}}/$DB_USER/g" | \
    sudo -u postgres psql -d "$DB_NAME"

# Set up users from template
print_color "blue" "Setting up users and permissions..."
cat "$ALGOXL_HOME/templates/postgres/users.sql.template" | \
    sed "s/{{DB_NAME}}/$DB_NAME/g" | \
    sed "s/{{DB_USER}}/$DB_USER/g" | \
    sudo -u postgres psql -d "$DB_NAME"

print_color "green" "Database schema has been successfully set up."
print_color "blue" "Database: $DB_NAME"
print_color "blue" "User: $DB_USER"
print_color "blue" "Password: $DB_PASSWORD"
print_color "blue" "Connection string: postgresql://$DB_USER:$DB_PASSWORD@localhost:5432/$DB_NAME"