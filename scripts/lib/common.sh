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
    command -v "$1" &> /dev/null
}

# Load .env file
load_env() {
    if [ -f "${PROJECT_ROOT}/.env" ]; then
        set -a
        source "${PROJECT_ROOT}/.env"
        set +a
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