#!/bin/bash

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Load colors
source "${SCRIPT_DIR}/colors.sh"

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓${NC} $*"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ✗${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠${NC} $*"
}

info() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')] ℹ${NC} $*"
}

step() {
    echo ""
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${PURPLE}▶${NC} $*"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Load .env file
load_env() {
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        # Read .env file line by line
        while IFS= read -r line; do
            # Skip comments and empty lines
            if [ -z "$line" ] || [ "${line:0:1}" = "#" ]; then
                continue
            fi

            # Handle export prefix
            if echo "$line" | grep -q '^export[[:space:]]'; then
                line=$(echo "$line" | sed 's/^export[[:space:]]//')
            fi

            # Split key and value at first =
            if echo "$line" | grep -q '='; then
                key=$(echo "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')
                value=$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//')

                # Remove quotes from value if present
                value=$(echo "$value" | sed 's/^["'\'']\(.*\)["'\'']$/\1/')

                # Export the variable
                if [ -n "$key" ]; then
                    export "$key=$value"
                fi
            fi
        done < "${PROJECT_ROOT}/.env"
        return 0
    else
        error "File .env not found in ${PROJECT_ROOT}"
        return 1
    fi
}

# Retry command
retry() {
    local max_attempts="${1}"
    local delay="${2}"
    shift 2
    local command="$@"
    local attempt=1

    until [ $attempt -gt $max_attempts ]; do
        if eval "$command"; then
            return 0
        fi

        warning "Command failed. Attempt $attempt/$max_attempts. Retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
    done

    error "Command failed after $max_attempts attempts"
    return 1
}

# Check prerequisites
check_prerequisites() {
    local missing=()

    for cmd in "$@"; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required tools: ${missing[*]}"
        return 1
    fi

    return 0
}