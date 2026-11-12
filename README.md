# Linux Production Server Setup Script

Automated VPS setup script for Node.js (22 LTS), PostgreSQL (16/17), Redis (7.2+), Nginx Reverse Proxy with SSL (Certbot), PM2 Process Manager, and Firewall (UFW).

## Quick Run

Run this command directly in your server terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/moon-m360ict/server-setup/main/setup-server.sh | sudo bash
```

Alternatively, you can run:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/moon-m360ict/server-setup/main/setup-server.sh)"
```

Or download and inspect first:

```bash
wget -qO setup-server.sh https://raw.githubusercontent.com/moon-m360ict/server-setup/main/setup-server.sh
sudo bash setup-server.sh
```

---

## Interactive Prompts

When you run the script, it will interactively ask for:

1. **Domain & SSL**:
   - Domain name (e.g. `api.yourdomain.com`)
   - Admin email for automated Let's Encrypt SSL issuance and renewal
2. **Repository Configuration**:
   - Git repository URL (HTTPS or SSH)
   - Git branch (default: `main`)
   - Installation directory (default: `~/repo-name`)
   - Node.js app port (default: `5000`)
3. **PostgreSQL Database**:
   - Database name (default: `erm_db`)
   - Database user (default: `erm_user`)
   - Password (leave blank to auto-generate a secure random 16-character password)
   - Remote access toggle (DBeaver / pgAdmin / TablePlus) with optional IP whitelist
4. **Redis Cache**:
   - Redis port (default: `6379`)
   - Optional Redis password
5. **Environment Variables (.env)**:
   - Automatically generates core system variables (`PORT`, `NODE_ENV="PROD"`, `DB_HOST="localhost"`, `DB_PORT=5432`, `DB_NAME`, `DB_USER`, `DB_PASS`, `REDIS_HOST="127.0.0.1"`, `REDIS_PORT="6379"`).
   - Allows pasting any additional custom environment variables (e.g. `JWT_SECRET`, API keys) which are appended to the `.env` file.
6. **Confirmation**:
   - Review the summary of settings before the automated installation begins.

---

## What Gets Installed & Configured

- **OS Optimizations**: 2GB Swap memory (`/swapfile`), system package updates.
- **Node.js**: Official NodeSource repository, Node.js 22 (LTS) & npm.
- **Process Manager**: PM2 globally installed, systemd service enabled for auto-restart on boot.
- **Database**: PostgreSQL 16/17 official PGDG repository, automated user & DB creation, pg_hba.conf configured.
- **Cache**: Redis official repository with systemd supervision.
- **Web Server**: Nginx reverse proxy with gzip, security headers, file upload limits, and WebSocket support.
- **SSL**: Automated Certbot issuance with systemd renewal timer.
- **Security**: UFW firewall (SSH, HTTP, HTTPS, optional remote Postgres) & Fail2ban brute-force protection.
- **Error Rollback & Cleanup Trap**: If any step fails or you cancel with `Ctrl+C`, the script lists all resources created so far and prompts you to safely clean them up (removes created DB, Nginx config, App dir, PM2 process, Swapfile) to keep your server clean.
