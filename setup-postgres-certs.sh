#!/bin/bash

# PostgreSQL SSL Certificate Generator (Container Version)
# Generates CA and server certificates for PostgreSQL SSL connections
# Runs as postgres user (UID 999) - no root required
# Idempotent: skips generation if certificates already exist

set -e

CERTS_DIR="/certs"
VALIDITY_DAYS=1825  # 5 years

# CA files
CA_KEY="$CERTS_DIR/ca.key"
CA_CERT="$CERTS_DIR/ca.crt"

# Server files
SERVER_KEY="$CERTS_DIR/server.key"
SERVER_CERT="$CERTS_DIR/server.crt"
SERVER_CSR="$CERTS_DIR/server.csr"

echo "PostgreSQL SSL Certificate Generator"
echo "======================================"

# Check if certificates already exist
if [ -f "$SERVER_KEY" ] && [ -f "$SERVER_CERT" ] && [ -f "$CA_CERT" ]; then
    echo "Certificates already exist, ensuring proper permissions..."
    chown 999:999 "$CA_KEY" "$CA_CERT" "$SERVER_KEY" "$SERVER_CERT" 2>/dev/null || true
    chmod 600 "$CA_KEY" 2>/dev/null || true
    chmod 600 "$SERVER_KEY"
    chmod 644 "$CA_CERT"
    chmod 644 "$SERVER_CERT"
    echo "  CA cert:     $CA_CERT"
    echo "  Server cert: $SERVER_CERT"
    echo "  Server key:  $SERVER_KEY"
    echo "Permissions verified."
    exit 0
fi

echo "Generating SSL certificates..."

# Create certs directory if it doesn't exist
mkdir -p "$CERTS_DIR"

# Step 1: Generate CA private key
echo "Generating CA private key..."
openssl genrsa -out "$CA_KEY" 4096

# Step 2: Generate CA certificate
echo "Generating CA certificate..."
openssl req -new -x509 -days $VALIDITY_DAYS -nodes \
    -key "$CA_KEY" \
    -out "$CA_CERT" \
    -subj "/CN=Toite CA/O=Toite/C=EE"

# Step 3: Generate server private key
echo "Generating server private key..."
openssl genrsa -out "$SERVER_KEY" 4096

# Step 4: Generate server certificate signing request
echo "Generating server CSR..."
openssl req -new \
    -key "$SERVER_KEY" \
    -out "$SERVER_CSR" \
    -subj "/CN=toite-postgres/O=Toite/C=EE"

# Step 5: Sign server certificate with CA
echo "Signing server certificate with CA..."
openssl x509 -req -days $VALIDITY_DAYS \
    -in "$SERVER_CSR" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$SERVER_CERT"

# Step 6: Set proper ownership and permissions
# Owner: postgres user (UID 999)
# Keys: 600 (read/write for owner only)
# Certificates: 644 (readable by all)
echo "Setting ownership and permissions..."
chown 999:999 "$CA_KEY" "$CA_CERT" "$SERVER_KEY" "$SERVER_CERT"
chmod 600 "$CA_KEY"
chmod 600 "$SERVER_KEY"
chmod 644 "$CA_CERT"
chmod 644 "$SERVER_CERT"

# Clean up CSR (not needed after signing)
rm -f "$SERVER_CSR"
rm -f "$CERTS_DIR/ca.srl"

# Verify the certificates
echo ""
echo "Verifying certificates..."
echo "CA Certificate:"
openssl x509 -in "$CA_CERT" -noout -subject -dates
echo ""
echo "Server Certificate:"
openssl x509 -in "$SERVER_CERT" -noout -subject -dates

echo ""
echo "======================================"
echo "SSL certificates generated successfully!"
echo "  CA key:      $CA_KEY"
echo "  CA cert:     $CA_CERT"
echo "  Server key:  $SERVER_KEY"
echo "  Server cert: $SERVER_CERT"
echo "  Validity:    $VALIDITY_DAYS days (5 years)"
echo "======================================"

exit 0
