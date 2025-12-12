#!/bin/bash
set -e

# SSL cert generator for postgres container
OUT_DIR="/certs"
EXPIRE_DAYS=365

ca_key="$OUT_DIR/ca.key"
ca_crt="$OUT_DIR/ca.crt"
srv_key="$OUT_DIR/server.key"
srv_crt="$OUT_DIR/server.crt"

fix_perms() {
    chown 999:999 "$ca_key" "$ca_crt" "$srv_key" "$srv_crt" 2>/dev/null || true
    chmod 600 "$ca_key" "$srv_key"
    chmod 644 "$ca_crt" "$srv_crt"
}

gen_ca() {
    openssl genrsa -out "$ca_key" 4096 2>/dev/null
    openssl req -new -x509 -days "$EXPIRE_DAYS" -nodes \
        -key "$ca_key" -out "$ca_crt" \
        -subj "/CN=Toite CA/O=Toite/C=EE" 2>/dev/null
}

gen_server() {
    local csr="$OUT_DIR/server.csr"
    openssl genrsa -out "$srv_key" 4096 2>/dev/null
    openssl req -new -key "$srv_key" -out "$csr" \
        -subj "/CN=toite-postgres/O=Toite/C=EE" 2>/dev/null
    openssl x509 -req -days "$EXPIRE_DAYS" \
        -in "$csr" -CA "$ca_crt" -CAkey "$ca_key" \
        -CAcreateserial -out "$srv_crt" 2>/dev/null
    rm -f "$csr" "$OUT_DIR/ca.srl"
}

main() {
    # skip if already generated
    if [ -f "$srv_key" ] && [ -f "$srv_crt" ] && [ -f "$ca_crt" ]; then
        fix_perms
        echo "Certs exist: $OUT_DIR"
        exit 0
    fi

    mkdir -p "$OUT_DIR"
    echo "Generating SSL certs..."
    gen_ca
    gen_server
    fix_perms
    echo "Certs ready: $OUT_DIR"
}

main
