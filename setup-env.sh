#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
EXAMPLE_ENV_FILE="$SCRIPT_DIR/.example.env"

# =============================================================================
# Argument Parsing
# =============================================================================

FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -f, --force    Skip confirmation prompt if .env exists"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Generator Functions
# =============================================================================

# Escape special characters for sed replacement string
# Characters: \ & | (backslash, ampersand, and our delimiter)
escape_sed_replacement() {
    local str="$1"
    str="${str//\\/\\\\}"  # Escape backslashes first
    str="${str//&/\\&}"    # Escape ampersands
    str="${str//|/\\|}"    # Escape the delimiter
    printf '%s' "$str"
}

# Generate a random password
# Usage: generate_password <length> [--symbols]
generate_password() {
    local length="${1:-24}"
    local use_symbols="${2:-}"
    local result
    
    if [[ "$use_symbols" == "--symbols" ]]; then
        # Include special symbols in the character set
        result=$(head -c 256 < /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9!@#$%^&*()_=+-' | head -c "$length")
    else
        # Alphanumeric only
        result=$(head -c 256 < /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c "$length")
    fi
    
    printf '%s' "$result"
}

# Generate a cryptographic secret (hex-encoded)
# Usage: generate_secret <bytes>
# Output will be 2x bytes in hex characters
generate_secret() {
    local bytes="${1:-64}"
    openssl rand -hex "$bytes"
}

# =============================================================================
# Main Script
# =============================================================================

echo "=== Toite Environment Setup ==="
echo

# Check if .example.env exists
if [[ ! -f "$EXAMPLE_ENV_FILE" ]]; then
    echo "Error: .example.env not found at $EXAMPLE_ENV_FILE"
    exit 1
fi

# Check if .env already exists
if [[ -f "$ENV_FILE" ]]; then
    if [[ "$FORCE" == true ]]; then
        echo "Warning: .env file already exists at $ENV_FILE (overwriting due to --force)"
    else
        echo "Warning: .env file already exists at $ENV_FILE"
        read -rp "Do you want to overwrite it? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi
    echo
fi

# Copy template
cp "$EXAMPLE_ENV_FILE" "$ENV_FILE"
echo "Created .env from .example.env"

# Generate passwords (24 chars, alphanumeric only)
MONGO_PASSWORD=$(generate_password 24)
POSTGRES_PASSWORD=$(generate_password 24)
REDIS_PASSWORD=$(generate_password 24)

# Generate admin password (24 chars, with symbols)
INITIAL_ADMIN_PASSWORD=$(generate_password 24)

# Generate secrets (64 bytes = 128 hex chars)
JWT_SECRET=$(generate_secret 64)
COOKIES_SECRET=$(generate_secret 64)
CSRF_SECRET=$(generate_secret 64)

# Detect Docker socket path for rootless Docker
DOCKER_SOCK="/run/user/$(id -u)/docker.sock"

echo "Generated random passwords and secrets"

# Escape special sed characters in password with symbols
INITIAL_ADMIN_PASSWORD_ESCAPED=$(escape_sed_replacement "$INITIAL_ADMIN_PASSWORD")

# Substitute values in .env file
# Using | as delimiter since passwords might contain special chars
sed -i.bak \
    -e "s|^MONGO_PASSWORD=.*|MONGO_PASSWORD=$MONGO_PASSWORD|" \
    -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" \
    -e "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD|" \
    -e "s|^INITIAL_ADMIN_PASSWORD=.*|INITIAL_ADMIN_PASSWORD=$INITIAL_ADMIN_PASSWORD_ESCAPED|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" \
    -e "s|^COOKIES_SECRET=.*|COOKIES_SECRET=$COOKIES_SECRET|" \
    -e "s|^CSRF_SECRET=.*|CSRF_SECRET=$CSRF_SECRET|" \
    -e "s|^DOCKER_SOCK=.*|DOCKER_SOCK=$DOCKER_SOCK|" \
    "$ENV_FILE"

# Remove backup file created by sed
rm -f "${ENV_FILE}.bak"

echo
echo "=== Setup Complete ==="
echo
echo "Generated values:"
echo "  - MONGO_PASSWORD:         (24 chars, alphanumeric)"
echo "  - POSTGRES_PASSWORD:      (24 chars, alphanumeric)"
echo "  - REDIS_PASSWORD:         (24 chars, alphanumeric)"
echo "  - INITIAL_ADMIN_PASSWORD: (24 chars, with symbols)"
echo "  - JWT_SECRET:             (128 hex chars)"
echo "  - COOKIES_SECRET:         (128 hex chars)"
echo "  - CSRF_SECRET:            (128 hex chars)"
echo "  - DOCKER_SOCK:            $DOCKER_SOCK"
echo
echo "Note: The following optional fields are left empty:"
echo "  - DADATA_API_TOKEN"
echo "  - GOOGLE_MAPS_API_KEY"
echo
echo "S3/MinIO settings use default values for local development."
echo
echo "Environment file created at: $ENV_FILE"

