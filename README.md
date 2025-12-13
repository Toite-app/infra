# Toite Infrastructure

This repository contains the infrastructure configuration for deploying Toite applications. It includes Docker Compose setup, deployment scripts, and documentation for running the complete application stack on a VPS.

## Architecture Overview

![Architecture Overview](docs/overall.png)

The infrastructure follows a CI/CD pipeline where:

1. **CI/CD Pipelines** - GitHub Actions in the `backend` and `internal-frontend` repositories build and push Docker images to Docker Hub when changes are merged to main
2. **Docker Hub** - Acts as the central registry storing all application images
3. **Domain** - DNS A record points to the VPS (e.g., `demo.toite.ee`)
4. **VPS** - A single server runs all services via Docker Compose:
   - **Traefik** - Reverse proxy handling routing and TLS certificates
   - **PostgreSQL, Redis, MongoDB** - Data stores
   - **S3** - Object storage
   - **Backend Application** - API server
   - **Internal Frontend** - Admin/internal web application

## Getting Started

### 1. Set Up Your VPS

Follow the [VPS Setup Guide](SETUP_VPS.md) to provision and secure your server. This guide covers:

- Creating a hardened Ubuntu server with security best practices
- Setting up SSH key-based authentication
- Installing rootless Docker
- Configuring firewall and automatic security updates

