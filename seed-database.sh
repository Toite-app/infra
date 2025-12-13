#!/bin/bash
set -e

# Load environment
source .env

# 1. Pull seeder image
docker pull toite/seeder:latest

# 2. Stop services and remove volumes (preserve letsencrypt)
docker compose down
docker volume rm -f toite_postgres-data toite_mongo-data toite_redis-data

# 3. Start postgres and wait for healthy status
docker compose up -d --wait postgres

# 4. Run seeder
docker run --rm --network toite_internal \
  -e POSTGRESQL_URL="postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/toite" \
  toite/seeder:latest

# 5. Start all services
docker compose up -d
