#!/bin/bash
#
# AlgoDB - Bootstrap Script
# -----------------------
# Initial bootstrap and environment setup for AlgoDB

# Exit on error
set -e

# Get the base directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALGODB_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"

# Define the environment file path
ENV_FILE="${ENV_FILE:-/opt/.env}"

# Source the shared functions
source "$ALGODB_HOME/lib/functions.sh"

# Create the environment file if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    print_color "blue" "Creating environment file at $ENV_FILE..."
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$ENV_FILE")"
    
    # Detect hardware specifications with fallback values
    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | sed 's/^[ \t]*//' || echo "Unknown CPU")
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 8388608) # Default to 8GB if detection fails
    TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
    TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))
    STORAGE_SIZE=$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "Unknown")
    
    # Create basic environment file
    cat > "$ENV_FILE" << EOF
# AlgoDB High-Frequency Trading Database Environment
# =================================================
# Created on $(date '+%Y-%m-%d %H:%M:%S')

# Base directories
ALGODB_HOME="$ALGODB_HOME"
PROJECT_BASE_DIR="/opt/algodb"

# Server information
HOSTNAME=$(hostname)
OS_VERSION=$(cat /etc/os-release 2>/dev/null | grep VERSION_ID | cut -d'"' -f2 || echo "Unknown")
INSTALLATION_DATE="$(date '+%Y-%m-%d')"

# Hardware detection
CPU_CORES=$CPU_CORES
CPU_MODEL="$CPU_MODEL"
TOTAL_MEM_KB=$TOTAL_MEM_KB
TOTAL_MEM_MB=$TOTAL_MEM_MB
TOTAL_MEM_GB=$TOTAL_MEM_GB
STORAGE_SIZE="$STORAGE_SIZE"

# Database settings
PG_VERSION="15"
DB_NAME="algodb"
DB_USER="algodb_user"
DB_PASSWORD="$(tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 16 2>/dev/null || echo 'AlgoDB2023!')"
EOF

    print_color "green" "Environment file created at $ENV_FILE"
fi

# Source the environment manager to load environment variables
source "$ALGODB_HOME/lib/env-manager.sh"
load_env

# Create required directories
check_directories() {
    print_color "blue" "Checking required directories..."
    
    # Create base project directory
    PROJECT_BASE_DIR="${PROJECT_BASE_DIR:-/opt/algodb}"
    if [ ! -d "$PROJECT_BASE_DIR" ]; then
        print_color "blue" "Creating project base directory at $PROJECT_BASE_DIR..."
        mkdir -p "$PROJECT_BASE_DIR"
    fi
    
    # Create subdirectories
    mkdir -p "$PROJECT_BASE_DIR/data"
    mkdir -p "$PROJECT_BASE_DIR/logs"
    mkdir -p "$PROJECT_BASE_DIR/backups"
    
    # Set proper permissions
    if [ "$(id -u)" -eq 0 ]; then
        chown -R postgres:postgres "$PROJECT_BASE_DIR" 2>/dev/null || true
        chmod -R 755 "$PROJECT_BASE_DIR"
    fi
    
    print_color "green" "Required directories are in place."
}

# Check system requirements
check_system() {
    print_color "blue" "Checking system requirements..."
    
    # Always re-detect hardware to ensure correct values
    CPU_CORES=$(nproc 2>/dev/null || echo 4)
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | sed 's/^[ \t]*//' || echo "Unknown CPU")
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 8388608)
    TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
    TOTAL_MEM_GB=$((TOTAL_MEM_MB / 1024))
    
    # Check OS
    if ! grep -q "AlmaLinux" /etc/os-release 2>/dev/null; then
        print_color "yellow" "Warning: This script is optimized for AlmaLinux. Detected OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")"
    fi
    
    # Check CPU and memory
    print_color "blue" "Detected hardware: $CPU_CORES cores, ${TOTAL_MEM_GB}GB RAM"
    if [ "$CPU_CORES" -lt 4 ]; then
        print_color "yellow" "Warning: Recommended minimum is 4 CPU cores. Detected: $CPU_CORES cores"
    fi
    
    if [ "$TOTAL_MEM_GB" -lt 8 ]; then
        print_color "yellow" "Warning: Recommended minimum is 8GB RAM. Detected: ${TOTAL_MEM_GB}GB RAM"
    fi
    
    # Check for required packages
    print_color "blue" "Checking for required packages..."
    MISSING_PACKAGES=()
    
    for pkg in dnf curl git bc; do
        if ! command -v $pkg &> /dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done
    
    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        print_color "yellow" "Missing required packages: ${MISSING_PACKAGES[*]}"
        if [ "$(id -u)" -eq 0 ]; then
            print_color "blue" "Installing missing packages..."
            dnf install -y ${MISSING_PACKAGES[*]}
        else
            print_color "red" "Please install missing packages: ${MISSING_PACKAGES[*]}"
            exit 1
        fi
    else
        print_color "green" "All required packages are installed."
    fi
    
    print_color "green" "System requirements check passed."
}

# Initialize everything
initialize() {
    check_directories
    check_system
    
    # Update environment with detected system information
    set_env_var "CPU_CORES" "$CPU_CORES"
    set_env_var "TOTAL_MEM_GB" "$TOTAL_MEM_GB"
    set_env_var "CPU_MODEL" "$CPU_MODEL"
    set_env_var "STORAGE_SIZE" "$(df -h / 2>/dev/null | awk 'NR==2 {print $2}' || echo "Unknown")"
    set_env_var "OS_VERSION" "$(cat /etc/os-release 2>/dev/null | grep VERSION_ID | cut -d'"' -f2 || echo "Unknown")"
    
    print_color "green" "Bootstrap completed successfully."
}

# Run initialization if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    initialize
fi