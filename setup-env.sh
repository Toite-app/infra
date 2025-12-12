#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
EXAMPLE_ENV_FILE="$SCRIPT_DIR/.example.env"

# =============================================================================
# Generator Functions
# =============================================================================

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
    echo "Warning: .env file already exists at $ENV_FILE"
    read -rp "Do you want to overwrite it? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
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
INITIAL_ADMIN_PASSWORD=$(generate_password 24 --symbols)

# Generate secrets (64 bytes = 128 hex chars)
JWT_SECRET=$(generate_secret 64)
COOKIES_SECRET=$(generate_secret 64)
CSRF_SECRET=$(generate_secret 64)

echo "Generated random passwords and secrets"

# Substitute values in .env file
# Using | as delimiter since passwords might contain special chars
sed -i.bak \
    -e "s|^MONGO_PASSWORD=.*|MONGO_PASSWORD=$MONGO_PASSWORD|" \
    -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" \
    -e "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$REDIS_PASSWORD|" \
    -e "s|^INITIAL_ADMIN_PASSWORD=.*|INITIAL_ADMIN_PASSWORD=$INITIAL_ADMIN_PASSWORD|" \
    -e "s|^JWT_SECRET=.*|JWT_SECRET=$JWT_SECRET|" \
    -e "s|^COOKIES_SECRET=.*|COOKIES_SECRET=$COOKIES_SECRET|" \
    -e "s|^CSRF_SECRET=.*|CSRF_SECRET=$CSRF_SECRET|" \
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
echo
echo "Note: The following optional fields are left empty:"
echo "  - DADATA_API_TOKEN"
echo "  - GOOGLE_MAPS_API_KEY"
echo
echo "S3/MinIO settings use default values for local development."
echo
echo "Environment file created at: $ENV_FILE"

