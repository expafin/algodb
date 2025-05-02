#!/bin/bash
#
# AlgoXL - Environment Manager
# -------------------------
# Manage environment variables for AlgoXL

# Default environment file location
DEFAULT_ENV_FILE="/opt/.env"

# Function to load environment variables from file
load_env() {
    local env_file="${1:-$DEFAULT_ENV_FILE}"
    
    if [ ! -f "$env_file" ]; then
        echo "Warning: Environment file not found at $env_file"
        return 1
    fi
    
    # Load variables from the environment file
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ $line = \#* ]] && continue
        [[ -z $line ]] && continue
        
        # Parse and export the variable
        if [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes if present
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            
            # Export the variable
            export "$name"="$value"
        fi
    done < "$env_file"
    
    return 0
}

# Function to get a variable from the environment file
get_env_var() {
    local name="$1"
    local default="$2"
    local env_file="${3:-$DEFAULT_ENV_FILE}"
    
    if [ ! -f "$env_file" ]; then
        echo "$default"
        return 1
    fi
    
    # Extract the variable value from the environment file
    local value=$(grep -E "^$name=" "$env_file" | cut -d'=' -f2- | sed 's/^"//;s/"$//;s/^'\''//;s/'\''$//')
    
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
    
    return 0
}

# Function to set a variable in the environment file
set_env_var() {
    local name="$1"
    local value="$2"
    local env_file="${3:-$DEFAULT_ENV_FILE}"
    
    # Create directory if it doesn't exist
    local env_dir=$(dirname "$env_file")
    if [ ! -d "$env_dir" ]; then
        mkdir -p "$env_dir"
    fi
    
    # Create the file if it doesn't exist
    if [ ! -f "$env_file" ]; then
        echo "# AlgoXL Environment Configuration" > "$env_file"
        echo "# Created on $(date '+%Y-%m-%d')" >> "$env_file"
        echo >> "$env_file"
    fi
    
    # Check if the variable already exists
    if grep -qE "^$name=" "$env_file"; then
        # Update existing variable
        sed -i "s|^$name=.*|$name=$value|" "$env_file"
    else
        # Add new variable
        echo "$name=$value" >> "$env_file"
    fi
    
    # Export the variable in the current shell
    export "$name"="$value"
    
    return 0
}

# Function to remove a variable from the environment file
remove_env_var() {
    local name="$1"
    local env_file="${2:-$DEFAULT_ENV_FILE}"
    
    if [ ! -f "$env_file" ]; then
        return 1
    fi
    
    # Remove the variable from the environment file
    sed -i "/^$name=/d" "$env_file"
    
    # Unset the variable in the current shell
    unset "$name"
    
    return 0
}

# Function to check if a variable exists in the environment file
has_env_var() {
    local name="$1"
    local env_file="${2:-$DEFAULT_ENV_FILE}"
    
    if [ ! -f "$env_file" ]; then
        return 1
    fi
    
    if grep -qE "^$name=" "$env_file"; then
        return 0
    else
        return 1
    fi
}

# Function to add a comment to the environment file
add_env_comment() {
    local comment="$1"
    local env_file="${2:-$DEFAULT_ENV_FILE}"
    
    # Create directory if it doesn't exist
    local env_dir=$(dirname "$env_file")
    if [ ! -d "$env_dir" ]; then
        mkdir -p "$env_dir"
    fi
    
    # Create the file if it doesn't exist
    if [ ! -f "$env_file" ]; then
        echo "# AlgoXL Environment Configuration" > "$env_file"
        echo "# Created on $(date '+%Y-%m-%d')" >> "$env_file"
        echo >> "$env_file"
    fi
    
    # Add the comment
    echo >> "$env_file"
    echo "# $comment" >> "$env_file"
    
    return 0
}

# Function to backup the environment file
backup_env_file() {
    local env_file="${1:-$DEFAULT_ENV_FILE}"
    local backup_dir="/var/backups/algoxl"
    
    # Create backup directory if it doesn't exist
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir"
    fi
    
    # Skip if file doesn't exist
    if [ ! -f "$env_file" ]; then
        return 1
    fi
    
    # Create backup with timestamp
    local backup_file="$backup_dir/$(basename "$env_file").$(date +%Y%m%d%H%M%S).bak"
    cp "$env_file" "$backup_file"
    
    # Return success
    echo "Backed up $env_file to $backup_file"
    return 0
}

# Export functions
export -f load_env
export -f get_env_var
export -f set_env_var
export -f remove_env_var
export -f has_env_var
export -f add_env_comment
export -f backup_env_file

# Load environment variables when script is sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # Only load when sourced, not when executed directly
    if [ -f "$DEFAULT_ENV_FILE" ]; then
        load_env "$DEFAULT_ENV_FILE"
    fi
fi