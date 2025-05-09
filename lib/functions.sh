#!/bin/bash
#
# AlgoDB - Shared Functions
# -----------------------
# Common utility functions for AlgoDB scripts

# Function to print a section header
print_section() {
    echo
    echo "====================================================================="
    echo "  $1"
    echo "====================================================================="
    echo
}

# Function to print colored text
print_color() {
    local color=$1
    local text=$2
    
    case $color in
        "red")    echo -e "\e[31m$text\e[0m" ;;
        "green")  echo -e "\e[32m$text\e[0m" ;;
        "yellow") echo -e "\e[33m$text\e[0m" ;;
        "blue")   echo -e "\e[34m$text\e[0m" ;;
        "purple") echo -e "\e[35m$text\e[0m" ;;
        "cyan")   echo -e "\e[36m$text\e[0m" ;;
        *) echo "$text" ;;
    esac
}

# Function to check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Function to check if a service is running
service_running() {
    systemctl is-active --quiet "$1"
}

# Function to check if a service is enabled
service_enabled() {
    systemctl is-enabled --quiet "$1"
}

# Function to verify if a package is installed
package_installed() {
    rpm -q "$1" &>/dev/null
}

# Function to prompt user for confirmation
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    local options="y/N"
    if [ "$default" = "y" ]; then
        options="Y/n"
    fi
    
    read -p "$prompt [$options]: " response
    
    if [ -z "$response" ]; then
        response=$default
    fi
    
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to prompt for a value with a default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local variable_name="$3"
    
    read -p "$prompt [$default]: " input
    input=${input:-$default}
    
    # Export the variable
    export "$variable_name"="$input"
    
    # Return the value
    echo "$input"
}

# Function to generate a random password
generate_password() {
    local length=${1:-16}
    tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c $length
}

# Function to log a message to file
log_message() {
    local level="$1"
    local message="$2"
    local log_file="${3:-/var/log/algodb.log}"
    
    # Create log directory if it doesn't exist
    local log_dir=$(dirname "$log_file")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
    fi
    
    # Get timestamp
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # Print to console if not suppressed
    if [ "${QUIET}" != "true" ]; then
        case "$level" in
            ERROR)   print_color "red" "[$level] $message" ;;
            WARNING) print_color "yellow" "[$level] $message" ;;
            INFO)    print_color "green" "[$level] $message" ;;
            DEBUG)   print_color "blue" "[$level] $message" ;;
            *)       echo "[$level] $message" ;;
        esac
    fi
}

# Function to backup a file before modifying it
backup_file() {
    local file="$1"
    local backup_dir="${2:-/var/backups/algodb}"
    
    # Create backup directory if it doesn't exist
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi
    
    # Skip if file doesn't exist
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    # Create backup with timestamp
    local backup_file="$backup_dir/$(basename "$file").$(date +%Y%m%d%H%M%S).bak"
    cp "$file" "$backup_file"
    
    # Return success
    log_message "INFO" "Backed up $file to $backup_file"
    return 0
}

# Function to restore a file from backup
restore_file() {
    local file="$1"
    local backup_dir="${2:-/var/backups/algodb}"
    
    # Find the most recent backup
    local backup_file=$(ls -t "$backup_dir/$(basename "$file")".*.bak 2>/dev/null | head -1)
    
    # Check if backup exists
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log_message "ERROR" "No backup found for $file"
        return 1
    fi
    
    # Restore from backup
    cp "$backup_file" "$file"
    
    # Return success
    log_message "INFO" "Restored $file from $backup_file"
    return 0
}

# Function to get PostgreSQL version
get_postgresql_version() {
    if command_exists psql; then
        psql --version | grep -oP '(?<=psql \(PostgreSQL\) )[0-9\.]+'
    elif package_installed postgresql-server; then
        rpm -q postgresql-server | grep -oP '(?<=postgresql-server-)[0-9\.]+'
    else
        echo "unknown"
    fi
}

# Function to get TimescaleDB version
get_timescaledb_version() {
    if [ -n "$1" ]; then
        # Use provided database name
        sudo -u postgres psql -d "$1" -c "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';" -t 2>/dev/null | xargs
    else
        # Try with postgres database
        sudo -u postgres psql -d postgres -c "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';" -t 2>/dev/null | xargs
    fi
}

# Function to check if PostgreSQL is configured for high-frequency trading
check_hft_configuration() {
    local config_file="/var/lib/pgsql/$1/data/postgresql.conf"
    
    # Check if file exists
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Check for key HFT configuration parameters
    if grep -q "timescaledb" "$config_file" && 
       grep -q "random_page_cost = 1.1" "$config_file" && 
       grep -q "effective_io_concurrency = 200" "$config_file"; then
        return 0
    else
        return 1
    fi
}

# Function to get system information
get_system_info() {
    # Return system information as a formatted string
    echo "$(hostname) - $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2) - $(nproc) cores - $(free -h | awk '/^Mem:/ {print $2}') RAM"
}

# Export functions
export -f print_section
export -f print_color
export -f command_exists
export -f service_running
export -f service_enabled
export -f package_installed
export -f confirm
export -f prompt_with_default
export -f generate_password
export -f log_message
export -f backup_file
export -f restore_file
export -f get_postgresql_version
export -f get_timescaledb_version
export -f check_hft_configuration
export -f get_system_info