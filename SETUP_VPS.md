# VPS Setup Guide

A comprehensive guide to setting up a secure, production-ready VPS for deploying containerized applications with GitHub Actions integration.

---

## Table of Contents

1. [What You'll Achieve](#what-youll-achieve)
2. [Prerequisites](#prerequisites)
3. [Create Your VPS](#1-create-your-vps)
4. [Initial Server Setup](#2-initial-server-setup)
5. [Install Docker](#3-install-docker)
6. [Create a Deploy User](#4-create-a-deploy-user)
7. [Harden SSH Security](#5-harden-ssh-security)
8. [Install Fail2ban](#6-install-fail2ban-intrusion-prevention)
9. [Configure the Firewall](#7-configure-the-firewall)
10. [Enable Automatic Security Updates](#8-enable-automatic-security-updates)
11. [Set Up Rootless Docker](#9-set-up-rootless-docker)
12. [Troubleshooting](#troubleshooting)
13. [Commands Reference](#commands-reference)

---

## What You'll Achieve

By the end of this guide, you'll have:

- A hardened Ubuntu server with security best practices
- SSH access restricted to key-based authentication only
- A dedicated non-root user for deployments (used by GitHub Actions)
- Automatic protection against brute-force attacks
- A properly configured firewall
- Automatic security updates
- Rootless Docker for running containers without elevated privileges

**Time required**: ~30-45 minutes

---

## Prerequisites

Before you start, make sure you have:

- A terminal with SSH client (macOS/Linux have this built-in, Windows users can use WSL or Git Bash)
- An account with a VPS provider (this guide uses [Hetzner](https://www.hetzner.com/), but works with any provider)
- Basic familiarity with the command line

---

## 1. Create Your VPS

### Generate an SSH Key (Local Machine)

First, create an SSH key pair on your local machine. This key will be used for initial root access.

```bash
ssh-keygen -t ed25519 -C "your-email@example.com" -f ~/.ssh/your-vps-root
```

**Why ed25519?** It's the modern standard — shorter keys, faster operations, and stronger security than RSA.

### Create the VPS

1. Log into your VPS provider (e.g., Hetzner)
2. Create a new server with these specs:
   - **OS**: Ubuntu 24.04 LTS
   - **Plan**: Hetzner CX22 or similar (2 vCPU, 4GB RAM is plenty for most apps)
   - **SSH Key**: Paste your public key (`~/.ssh/your-vps-root.pub`)

**Why Ubuntu 24.04 LTS?** 
- "LTS" means Long Term Support — 5 years of security updates
- Ubuntu has excellent documentation and community support
- Most tutorials and Docker images assume Ubuntu/Debian

### First Login

```bash
ssh root@YOUR_SERVER_IP -i ~/.ssh/your-vps-root
```

You're now connected as root. Let's lock things down.

---

## 2. Initial Server Setup

### Update System Packages

First things first — update everything:

```bash
sudo apt update && sudo apt upgrade -y
```

**Why?** Your VPS image might be weeks or months old. This ensures you have the latest security patches before we do anything else. The `-y` flag auto-confirms the upgrade.

---

## 3. Install Docker

Install Docker using the official convenience script:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
```

**Why the official script?** 
- Always installs the latest stable version
- Handles all the repository setup automatically
- More reliable than distro packages (which are often outdated)

**What do those flags mean?**
- `-f` — Fail silently on HTTP errors
- `-s` — Silent mode (no progress bar)
- `-S` — Show errors if `-s` is used
- `-L` — Follow redirects

---

## 4. Create a Deploy User

Never run applications as root. We'll create a dedicated user for deployments.

### Create the User

```bash
adduser deploy
```

You'll be prompted to set a password — write it down somewhere safe. You'll need it for `sudo` commands.

### Grant sudo Privileges

```bash
usermod -aG sudo deploy
```

**Why a separate user?**
- **Principle of least privilege**: If someone compromises your app, they don't automatically get root access
- **Audit trail**: Easier to track who did what
- **GitHub Actions**: Your CI/CD will use this user to deploy — you don't want your pipeline running as root

### Set Up SSH Access for Deploy User

Now generate a *second* SSH key on your local machine for the deploy user:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/your-vps-deploy
```

**Why a separate key?** This key will be stored in GitHub Actions secrets. If it's ever compromised, you can revoke it without losing your own access.

On the server, set up the deploy user's SSH directory:

```bash
mkdir -p /home/deploy/.ssh
nano /home/deploy/.ssh/authorized_keys
```

Paste your new public key (`~/.ssh/your-vps-deploy.pub`) and save.

Set the correct permissions:

```bash
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

**Why these permissions?** SSH is paranoid by design — it refuses to work if the permissions are too open. `700` means only the owner can access the directory, `600` means only the owner can read the file.

---

## 5. Harden SSH Security

Now let's make SSH bulletproof.

### Edit SSH Configuration

```bash
nano /etc/ssh/sshd_config
```

Find and update these settings (some may already exist, others you'll need to add):

```ini
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
```

**What each setting does:**

| Setting | Value | Why |
|---------|-------|-----|
| `PermitRootLogin` | `no` | Root is the most targeted account. Disable it entirely. |
| `PubkeyAuthentication` | `yes` | Allow SSH key authentication (the secure way). |
| `PasswordAuthentication` | `no` | Passwords can be brute-forced. Keys cannot. |
| `PermitEmptyPasswords` | `no` | Just in case someone creates a user without a password. |
| `MaxAuthTries` | `3` | Lock out after 3 failed attempts per connection. |

### Test the Configuration

Before applying, always test:

```bash
sudo sshd -t
```

If it returns nothing, the config is valid. If you see errors, fix them before proceeding.

### Apply Changes

```bash
sudo systemctl reload ssh
```

### Change the SSH Port

The default SSH port (22) gets hammered by automated scanners. Changing it reduces noise dramatically.

Edit the SSH socket configuration:

```bash
sudo nano /etc/systemd/system/sockets.target.wants/ssh.socket
```

Find the `[Socket]` section and change:

```ini
[Socket]
ListenStream=0.0.0.0:2222
ListenStream=[::]:2222
```

**Why two ListenStream entries?** The first (`0.0.0.0:2222`) binds to all IPv4 addresses, the second (`[::]:2222`) binds to all IPv6 addresses. You need both for full connectivity.

Apply the changes:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
```

**Important**: Don't close your current session yet! Open a new terminal and test the connection first.

### Update Your Local SSH Config

On your local machine, create a convenient alias in `~/.ssh/config`:

```
Host toite
  HostName YOUR_SERVER_IP
  User deploy
  Port 2222
  IdentityFile ~/.ssh/your-vps-deploy
```

Now you can connect with just:

```bash
ssh deploy@toite
```

---

## 6. Install Fail2ban (Intrusion Prevention)

Fail2ban monitors log files and automatically bans IPs that show malicious signs (like too many failed login attempts).

### Install

```bash
sudo apt install fail2ban -y
```

### Configure

Create a local configuration file (never edit the original):

```bash
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local
```

Find and update these settings (they exist in the file — search for them):

```ini
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = 2222
logpath = %(sshd_log)s
backend = %(sshd_backend)s
```

**What these mean:**

| Setting | Value | Meaning |
|---------|-------|---------|
| `bantime` | `1h` | Banned IPs stay blocked for 1 hour |
| `findtime` | `10m` | Look at the last 10 minutes of attempts |
| `maxretry` | `5` | Ban after 5 failed attempts within findtime |
| `port` | `2222` | Must match your SSH port! |

### Apply and Verify

```bash
sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

You should see something like:

```
Status for the jail: sshd
|- Filter
|  |- Currently failed: 0
|  |- Total failed: 0
|  `- File list: /var/log/auth.log
`- Actions
   |- Currently banned: 0
   |- Total banned: 0
   `- Banned IP list:
```

---

## 7. Configure the Firewall

Ubuntu comes with UFW (Uncomplicated Firewall). Let's set it up to only allow what we need.

### Set Default Policies

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

**Why?** 
- **Deny incoming by default**: Nothing gets in unless explicitly allowed
- **Allow outgoing by default**: Your server can reach the internet (for updates, API calls, etc.)

### Allow Required Ports

```bash
sudo ufw allow 2222/tcp  # SSH (your custom port)
sudo ufw allow http      # Port 80 - web traffic
sudo ufw allow https     # Port 443 - secure web traffic
```

### Enable the Firewall

```bash
sudo ufw enable
```

You'll see: `Firewall is active and enabled on system startup`

**Don't panic** if your connection stays open — that's good! It means you allowed your SSH port correctly.

### Verify

```bash
sudo ufw status
```

---

## 8. Enable Automatic Security Updates

Security patches should be applied automatically — you don't want to manually update every time there's a vulnerability.

### Install

```bash
sudo apt install unattended-upgrades -y
```

### Configure

```bash
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

Select **Yes** when prompted.

### Verify

```bash
cat /etc/apt/apt.conf.d/20auto-upgrades
```

Should output:

```
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

**What this does:**
- `Update-Package-Lists "1"` — Check for updates daily
- `Unattended-Upgrade "1"` — Install security updates automatically

---

## 9. Set Up Rootless Docker

By default, Docker runs as root. This means if a container is compromised, the attacker has root access. Rootless Docker fixes this.

### Install Dependencies and Set Up

```bash
sudo apt-get install -y uidmap
dockerd-rootless-setuptool.sh install
```

### Configure Environment Variables

After the install script finishes, it will output something like this:

```
[INFO] Make sure the following environment variable(s) are set (or add them to ~/.bashrc):
export PATH=/usr/bin:$PATH

[INFO] Some applications may require the following environment variable too:
export DOCKER_HOST=unix:///run/user/1000/docker.sock
```

**Copy the exact values from your output** and add them to your `~/.bashrc`:

```bash
nano ~/.bashrc
```

Add the lines at the end (use the values from *your* script output):

```bash
export PATH=/usr/bin:$PATH
export DOCKER_HOST=unix:///run/user/1000/docker.sock
```

Then reload:

```bash
source ~/.bashrc
```

**Why?** The rootless Docker daemon uses a different socket path than the regular Docker. The user ID (`1000`) may vary depending on your system, so always use the values from the script output.


### Enable on Startup

```bash
sudo loginctl enable-linger $UID
```

**What's "linger"?** Normally, user services stop when you log out. This keeps your Docker containers running even when you're not connected.

### Allow Unprivileged Port Binding

By default, Linux only allows root to bind to ports below 1024. Since we want our rootless containers to serve HTTP (80) and HTTPS (443):

```bash
sudo nano /etc/sysctl.conf
```

Add this line:

```
net.ipv4.ip_unprivileged_port_start=0
```

Apply:

```bash
sudo sysctl -p
```

---

## You're Done!

Your VPS is now:

- Accessible only via SSH keys (no passwords)
- Protected by a firewall that only allows necessary traffic
- Automatically banning suspicious IPs
- Automatically installing security updates
- Running Docker without root privileges

### Next Steps

- Store the deploy user's SSH private key in your GitHub repository secrets
- Set up your GitHub Actions workflow to deploy using this user

---

## Troubleshooting

### Locked out of SSH?

If you can't connect via SSH:
1. Use your VPS provider's web console (most have one)
2. Check `/var/log/auth.log` for errors
3. Verify your SSH key is in the correct `authorized_keys` file
4. Make sure UFW allows your SSH port

### Fail2ban banned your IP?

```bash
sudo fail2ban-client set sshd unbanip YOUR_IP_ADDRESS
```

### Docker commands not working?

Make sure `DOCKER_HOST` is set:

```bash
echo $DOCKER_HOST
```

Should output: `unix:///run/user/1000/docker.sock`

### Rootless Docker setup fails?

If `dockerd-rootless-setuptool.sh install` fails or behaves unexpectedly, try re-running the Docker installation script first:

```bash
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
```

Then run the rootless setup again:

```bash
dockerd-rootless-setuptool.sh install
```

This often resolves missing dependencies or incomplete installations.

---

## Commands Reference

A condensed cheat sheet with all commands for quick copy-paste.

### Initial Setup
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh
```

### Create Deploy User
```bash
adduser deploy
usermod -aG sudo deploy
```

### SSH Keys Setup
```bash
# On local machine - generate keys
ssh-keygen -t ed25519 -C "root-access" -f ~/.ssh/toite-root
ssh-keygen -t ed25519 -C "deploy-access" -f ~/.ssh/toite-deploy-user

# On server - setup deploy user SSH
mkdir -p /home/deploy/.ssh
nano /home/deploy/.ssh/authorized_keys  # paste deploy public key
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

### SSH Hardening
```bash
# Edit /etc/ssh/sshd_config
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3

# Test and apply
sudo sshd -t
sudo systemctl reload ssh
```

### Change SSH Port
```bash
sudo nano /etc/systemd/system/sockets.target.wants/ssh.socket
# Change to:
# [Socket]
# ListenStream=0.0.0.0:2222
# ListenStream=[::]:2222

sudo systemctl daemon-reload
sudo systemctl restart ssh.socket
```

### Local SSH Config (~/.ssh/config)
```
Host toite
  HostName YOUR_SERVER_IP
  User deploy
  Port 2222
  IdentityFile ~/.ssh/toite-deploy-user
```

### Fail2ban
```bash
sudo apt install fail2ban -y
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local

# Update these values:
# [DEFAULT]
# bantime = 1h
# findtime = 10m
# maxretry = 5
# [sshd]
# enabled = true
# port = 2222

sudo systemctl restart fail2ban
sudo fail2ban-client status sshd
```

### Firewall (UFW)
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp
sudo ufw allow http
sudo ufw allow https
sudo ufw enable
```

### Automatic Security Updates
```bash
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure --priority=low unattended-upgrades
cat /etc/apt/apt.conf.d/20auto-upgrades
# Should show:
# APT::Periodic::Update-Package-Lists "1";
# APT::Periodic::Unattended-Upgrade "1";
```

### Rootless Docker
```bash
sudo apt-get install -y uidmap
dockerd-rootless-setuptool.sh install
sudo loginctl enable-linger $UID

# Add to ~/.bashrc - use values from script output above!
# export PATH=/usr/bin:$PATH
# export DOCKER_HOST=unix:///run/user/1000/docker.sock
source ~/.bashrc

# Allow unprivileged ports - add to /etc/sysctl.conf:
# net.ipv4.ip_unprivileged_port_start=0
sudo sysctl -p
```

