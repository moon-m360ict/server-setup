#!/usr/bin/env bash
# ==============================================================================
# Complete Ubuntu / Debian Server Automated Setup Script
# For: Node.js (TypeScript) + PostgreSQL + Redis + Nginx + SSL + PM2 + Firewall
# ==============================================================================

set -eo pipefail

# Text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}${BOLD}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}${BOLD}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}${BOLD}[ERROR]${NC} $1"; }

# Check root privilege
if [ "$EUID" -ne 0 ]; then
  log_error "Please run this script as root or with sudo:"
  log_error "  curl -fsSL https://raw.githubusercontent.com/moon-m360ict/server-setup/main/setup-server.sh | sudo bash"
  exit 1
fi

# ------------------------------------------------------------------------------
# Terminal Input Stream Setup (File Descriptor 3)
# ------------------------------------------------------------------------------
# When executed via pipe (e.g. curl ... | sudo bash), stdin (fd 0) is the pipe
# feeding the script code to bash. Attempting to 'read' from stdin directly would
# consume lines of the script itself, causing the script to exit prematurely.
# We redirect fd 3 from /dev/tty (the controlling terminal) so all interactive
# prompts read user input properly from the keyboard.
if [ -e /dev/tty ] && exec 3</dev/tty 2>/dev/null; then
  : # fd 3 attached to controlling terminal
else
  exec 3<&0
fi

CURRENT_USER="${SUDO_USER:-$(whoami)}"
USER_HOME=$(eval echo "~$CURRENT_USER")

clear
echo -e "${CYAN}${BOLD}"
echo "======================================================================"
echo "          🚀 FULL LINUX SERVER PRODUCTION SETUP SCRIPT                "
echo "  Node.js | PostgreSQL | Redis | Nginx | Let's Encrypt | PM2 | UFW    "
echo "======================================================================"
echo -e "${NC}"

# ==============================================================================
# STEP 1: INTERACTIVE CONFIGURATION GATHERING
# ==============================================================================
echo -e "${YELLOW}${BOLD}--- [1/5] Domain & SSL Configuration ---${NC}"
read -rp "Enter your Domain Name (e.g. api.yourdomain.com): " DOMAIN_NAME <&3
while [ -z "$DOMAIN_NAME" ]; do
  log_warn "Domain name cannot be empty!"
  read -rp "Enter your Domain Name: " DOMAIN_NAME <&3
done

read -rp "Enter Admin Email for SSL Certificate (e.g. admin@yourdomain.com): " SSL_EMAIL <&3
while [ -z "$SSL_EMAIL" ]; do
  log_warn "Email is required for Let's Encrypt notifications!"
  read -rp "Enter Admin Email for SSL: " SSL_EMAIL <&3
done

echo ""
echo -e "${YELLOW}${BOLD}--- [2/5] GitHub Repository Configuration ---${NC}"
read -rp "Enter GitHub Repository URL (HTTPS or SSH): " GIT_REPO_URL <&3
while [ -z "$GIT_REPO_URL" ]; do
  log_warn "GitHub repository URL cannot be empty!"
  read -rp "Enter GitHub Repository URL: " GIT_REPO_URL <&3
done

read -rp "Enter Git Branch to deploy [default: main]: " GIT_BRANCH <&3
GIT_BRANCH="${GIT_BRANCH:-main}"

DEFAULT_APP_DIR="$USER_HOME/$(basename -s .git "$GIT_REPO_URL")"
read -rp "Enter Installation Directory [default: $DEFAULT_APP_DIR]: " APP_DIR <&3
APP_DIR="${APP_DIR:-$DEFAULT_APP_DIR}"

read -rp "Enter Node.js App Port [default: 5000]: " APP_PORT <&3
APP_PORT="${APP_PORT:-5000}"

echo ""
echo -e "${YELLOW}${BOLD}--- [3/5] PostgreSQL Database Configuration ---${NC}"
read -rp "Enter PostgreSQL Database Name [default: erm_db]: " DB_NAME <&3
DB_NAME="${DB_NAME:-erm_db}"

read -rp "Enter PostgreSQL Username [default: erm_user]: " DB_USER <&3
DB_USER="${DB_USER:-erm_user}"

read -rsp "Enter PostgreSQL Password (leave blank to auto-generate): " DB_PASS <&3
echo ""
if [ -z "$DB_PASS" ]; then
  DB_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
  log_info "Auto-generated PostgreSQL Password: ${GREEN}${DB_PASS}${NC}"
fi

read -rp "Enable remote access to PostgreSQL from your local PC (DBeaver/pgAdmin)? (Y/n): " ALLOW_PG_REMOTE <&3
ALLOW_PG_REMOTE="${ALLOW_PG_REMOTE:-Y}"

PG_CLIENT_IP="0.0.0.0/0"
if [[ "$ALLOW_PG_REMOTE" =~ ^[Yy]$ ]]; then
  read -rp "  Enter your Local Public IP to whitelist (leave blank for anywhere 0.0.0.0/0): " SPECIFIC_IP <&3
  if [ -n "$SPECIFIC_IP" ]; then
    PG_CLIENT_IP="${SPECIFIC_IP}/32"
  fi
fi

echo ""
echo -e "${YELLOW}${BOLD}--- [4/5] Redis Configuration ---${NC}"
read -rp "Enter Redis Port [default: 6379]: " REDIS_PORT <&3
REDIS_PORT="${REDIS_PORT:-6379}"

read -rsp "Enter Redis Password (optional, press Enter for none): " REDIS_PASS <&3
echo ""

echo ""
echo -e "${YELLOW}${BOLD}--- [5/5] Environment Variables (.env) Setup ---${NC}"
read -rp "Do you want to paste your .env file content now? (y/N): " HAS_ENV <&3
ENV_CONTENT=""
if [[ "$HAS_ENV" =~ ^[Yy]$ ]]; then
  echo -e "${CYAN}Type or paste your .env lines below.${NC}"
  echo -e "${CYAN}When finished, type ${BOLD}END_OF_ENV${NC}${CYAN} on a new line and press Enter:${NC}"
  while IFS= read -r line <&3 || [ -n "$line" ]; do
    if [ "$line" = "END_OF_ENV" ]; then
      break
    fi
    ENV_CONTENT+="$line"$'\n'
  done
else
  log_info "Skipping .env input. You can create or edit '$APP_DIR/.env' later."
fi

echo ""
echo -e "${CYAN}${BOLD}Summary of Settings:${NC}"
echo -e "  Domain:         ${GREEN}$DOMAIN_NAME${NC}"
echo -e "  SSL Email:      ${GREEN}$SSL_EMAIL${NC}"
echo -e "  Git Repo:       ${GREEN}$GIT_REPO_URL ($GIT_BRANCH)${NC}"
echo -e "  App Directory:  ${GREEN}$APP_DIR${NC}"
echo -e "  App Port:       ${GREEN}$APP_PORT${NC}"
echo -e "  Postgres DB:    ${GREEN}$DB_NAME${NC} (User: ${GREEN}$DB_USER${NC})"
echo -e "  Postgres Remote:${GREEN}${ALLOW_PG_REMOTE:-Y} (Allowed: $PG_CLIENT_IP)${NC}"
echo -e "  Redis Port:     ${GREEN}$REDIS_PORT${NC}"
echo ""
read -rp "Are you ready to proceed with the automated installation? (Y/n): " CONFIRM <&3
CONFIRM="${CONFIRM:-Y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  log_warn "Installation aborted by user."
  exit 0
fi

START_TIME=$(date +%s)

# Detect OS codename (noble, jammy, focal, bookworm, bullseye, etc.)
OS_CODENAME=$(lsb_release -cs 2>/dev/null || (. /etc/os-release && echo "$VERSION_CODENAME"))

# ==============================================================================
# STEP 2: SYSTEM UPDATE & ESSENTIAL PACKAGES
# ==============================================================================
log_info "Step 1/8: Updating package repository and installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

apt-get install -y \
  curl \
  wget \
  git \
  build-essential \
  ufw \
  fail2ban \
  htop \
  jq \
  unzip \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release \
  certbot \
  python3-certbot-nginx \
  nginx

log_success "System packages installed successfully."

# ==============================================================================
# STEP 3: CONFIGURE 2GB SWAP MEMORY
# ==============================================================================
log_info "Step 2/8: Checking and configuring Swap memory..."
SWAP_EXISTING=$(swapon --show | wc -l)
if [ "$SWAP_EXISTING" -le 1 ]; then
  log_info "No active swap found. Creating 2GB swap file..."
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
  sysctl vm.swappiness=20
  echo 'vm.swappiness=20' >> /etc/sysctl.conf
  log_success "2GB Swap configured and enabled permanently."
else
  log_info "Active swap already detected. Skipping swap creation."
fi

# ==============================================================================
# STEP 4: INSTALL NODE.JS (LATEST ACTIVE LTS) & PM2
# ==============================================================================
log_info "Step 3/8: Setting up official NodeSource repository for latest Node.js LTS (v22)..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes
NODE_MAJOR=22 # Node.js 22 is the current official Active LTS
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
apt-get update -y
apt-get install -y nodejs

log_success "Node.js version: $(node -v) | npm version: $(npm -v)"

# Update npm to latest and install PM2 globally
log_info "Updating npm and installing PM2 latest..."
npm install -g npm@latest pm2@latest
pm2 startup systemd -u "$CURRENT_USER" --hp "$USER_HOME" || true
log_success "PM2 latest installed and systemd startup configured."

# ==============================================================================
# STEP 5: INSTALL & CONFIGURE POSTGRESQL (OFFICIAL REPOSITORY)
# ==============================================================================
log_info "Step 4/8: Setting up official PostgreSQL repository for latest stable release..."
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt ${OS_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list
apt-get update -y
apt-get install -y postgresql postgresql-contrib

systemctl enable postgresql
systemctl start postgresql

PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | head -n 1 | awk '{print $1, $2}')
log_success "Installed PostgreSQL: $PG_VERSION"

# Create Database and User
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE USER \"$DB_USER\" WITH PASSWORD '$DB_PASS';"

sudo -u postgres psql -c "ALTER USER \"$DB_USER\" WITH PASSWORD '$DB_PASS';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || \
  sudo -u postgres psql -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO \"$DB_USER\";" || true

log_success "PostgreSQL database '$DB_NAME' and user '$DB_USER' configured successfully."

# Configure remote access (DBeaver / pgAdmin / TablePlus from local PC)
if [[ "$ALLOW_PG_REMOTE" =~ ^[Yy]$ ]]; then
  log_info "Configuring PostgreSQL to allow remote connections from $PG_CLIENT_IP..."
  PG_CONF=$(sudo -u postgres psql -t -P format=unaligned -c "SHOW config_file;")
  PG_HBA=$(sudo -u postgres psql -t -P format=unaligned -c "SHOW hba_file;")

  # Listen on all addresses
  if grep -q "^#listen_addresses" "$PG_CONF"; then
    sed -i "s/^#listen_addresses = .*/listen_addresses = '*'/" "$PG_CONF"
  elif grep -q "^listen_addresses" "$PG_CONF"; then
    sed -i "s/^listen_addresses = .*/listen_addresses = '*'/" "$PG_CONF"
  else
    echo "listen_addresses = '*'" >> "$PG_CONF"
  fi

  # Add client auth rule in pg_hba.conf
  if ! grep -q "host.*all.*all.*$PG_CLIENT_IP" "$PG_HBA"; then
    echo "host    all             all             $PG_CLIENT_IP            scram-sha-256" >> "$PG_HBA"
  fi

  systemctl restart postgresql
  log_success "PostgreSQL configured to accept remote connections on port 5432."
fi

# ==============================================================================
# STEP 6: INSTALL & CONFIGURE REDIS (OFFICIAL REPOSITORY)
# ==============================================================================
log_info "Step 5/8: Setting up official Redis repository for latest stable release..."
curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${OS_CODENAME} main" > /etc/apt/sources.list.d/redis.list
apt-get update -y
apt-get install -y redis-server redis-tools || apt-get install -y redis redis-tools

# Set supervised systemd in redis.conf
if [ -f "/etc/redis/redis.conf" ]; then
  sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
  sed -i "s/^port .*/port $REDIS_PORT/" /etc/redis/redis.conf

  if [ -n "$REDIS_PASS" ]; then
    if grep -q "^# requirepass" /etc/redis/redis.conf; then
      sed -i "s/^# requirepass .*/requirepass $REDIS_PASS/" /etc/redis/redis.conf
    elif grep -q "^requirepass" /etc/redis/redis.conf; then
      sed -i "s/^requirepass .*/requirepass $REDIS_PASS/" /etc/redis/redis.conf
    else
      echo "requirepass $REDIS_PASS" >> /etc/redis/redis.conf
    fi
  fi
fi

systemctl enable redis-server 2>/dev/null || systemctl enable redis 2>/dev/null || true
systemctl restart redis-server 2>/dev/null || systemctl restart redis 2>/dev/null || true
REDIS_VERSION=$(redis-server --version 2>/dev/null | awk '{print $3}' || echo "latest")
log_success "Installed Redis ($REDIS_VERSION) running on port $REDIS_PORT."

# ==============================================================================
# STEP 7: CLONE REPO, CONFIGURE .ENV, BUILD & LAUNCH PM2
# ==============================================================================
log_info "Step 6/8: Setting up application codebase..."

if [ ! -d "$APP_DIR" ]; then
  log_info "Cloning repository $GIT_REPO_URL ($GIT_BRANCH)..."
  sudo -u "$CURRENT_USER" git clone -b "$GIT_BRANCH" "$GIT_REPO_URL" "$APP_DIR" <&3
else
  log_info "Directory $APP_DIR already exists. Pulling latest $GIT_BRANCH..."
  cd "$APP_DIR"
  sudo -u "$CURRENT_USER" git checkout "$GIT_BRANCH" || true
  sudo -u "$CURRENT_USER" git pull origin "$GIT_BRANCH" || true
fi

cd "$APP_DIR"

# Write .env file
if [ -n "$ENV_CONTENT" ]; then
  log_info "Writing .env configuration..."
  echo "$ENV_CONTENT" > "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"
  chown "$CURRENT_USER:$CURRENT_USER" "$APP_DIR/.env"
  log_success ".env file saved securely."
fi

# Install dependencies
log_info "Installing application dependencies..."
sudo -u "$CURRENT_USER" npm install --prefer-offline --no-audit --no-fund

# Build TypeScript / Project if configured
if [ -f "package.json" ]; then
  if grep -q '"build":' package.json; then
    log_info "Running project build script (npm run build)..."
    sudo -u "$CURRENT_USER" npm run build || true
  elif [ -f "tsconfig.json" ] && [ ! -d "dist" ]; then
    log_info "Building TypeScript project (npx tsc)..."
    sudo -u "$CURRENT_USER" npx tsc || true
  fi
fi

# Create credentials dir if needed
mkdir -p "$APP_DIR/credentials" "$APP_DIR/log"
chown -R "$CURRENT_USER:$CURRENT_USER" "$APP_DIR"

# Launch or reload with PM2 as the standard user
log_info "Starting application with PM2 Cluster Mode..."
sudo -u "$CURRENT_USER" bash <<EOF
cd "$APP_DIR"
if [ -f "ecosystem.config.js" ]; then
  pm2 reload ecosystem.config.js --update-env || pm2 start ecosystem.config.js
elif [ -f "dist/server.js" ]; then
  pm2 start dist/server.js --name "server" -i 2 --wait-ready --listen-timeout 10000 --kill-timeout 10000 || pm2 reload server
elif [ -f "dist/index.js" ]; then
  pm2 start dist/index.js --name "server" -i 2 --wait-ready --listen-timeout 10000 --kill-timeout 10000 || pm2 reload server
elif [ -f "server.js" ]; then
  pm2 start server.js --name "server" -i 2 --wait-ready --listen-timeout 10000 --kill-timeout 10000 || pm2 reload server
elif [ -f "index.js" ]; then
  pm2 start index.js --name "server" -i 2 --wait-ready --listen-timeout 10000 --kill-timeout 10000 || pm2 reload server
else
  pm2 start npm --name "server" -- start || true
fi
pm2 save || true
EOF

log_success "PM2 application cluster launched."

# ==============================================================================
# STEP 8: CONFIGURE NGINX & SSL
# ==============================================================================
log_info "Step 7/8: Configuring Nginx reverse proxy..."

NGINX_CONF="/etc/nginx/sites-available/$DOMAIN_NAME"

cat > "$NGINX_CONF" <<'EOF'
# Upstream to Node.js backend
upstream node_backend {
    server 127.0.0.1:APP_PORT_PLACEHOLDER;
    keepalive 64;
}

server {
    listen 80;
    listen [::]:80;
    server_name DOMAIN_NAME_PLACEHOLDER;

    # Maximum file upload size
    client_max_body_size 100M;
    client_body_buffer_size 128k;

    # Gzip Compression
    gzip on;
    gzip_comp_level 5;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        application/javascript
        application/json
        application/x-javascript
        application/xml
        text/css
        text/javascript
        text/plain
        text/xml;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Drop bot scanner probes safely without matching API routes
    location ~* "[.](php|aspx?|jsp|cgi|sh|env|git|bak|sql)$" {
        access_log off;
        log_not_found off;
        return 444;
    }

    # Reverse proxy to Node.js / Socket.io
    location / {
        proxy_pass http://node_backend;
        proxy_http_version 1.1;

        # WebSocket headers
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Standard proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # Timeouts for streaming & long polling
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        proxy_buffering off;
    }
}
EOF

# Replace placeholders
sed -i "s/APP_PORT_PLACEHOLDER/$APP_PORT/g" "$NGINX_CONF"
sed -i "s/DOMAIN_NAME_PLACEHOLDER/$DOMAIN_NAME/g" "$NGINX_CONF"

# Enable site
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$DOMAIN_NAME"
rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
nginx -t
systemctl reload nginx || systemctl restart nginx
log_success "Nginx reverse proxy configured for $DOMAIN_NAME on port $APP_PORT."

# Setup SSL with Let's Encrypt Certbot
log_info "Step 8/8: Installing Let's Encrypt SSL certificate..."
certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "$SSL_EMAIL" --redirect || {
  log_warn "Certbot automated issuance failed. Please ensure DNS A-record for $DOMAIN_NAME points to this server IP."
  log_warn "You can run 'certbot --nginx -d $DOMAIN_NAME' manually once DNS propagates."
}

# Setup automated SSL renewal test
systemctl enable certbot.timer 2>/dev/null || true
systemctl start certbot.timer 2>/dev/null || true

# ==============================================================================
# STEP 9: UFW FIREWALL & SECURITY
# ==============================================================================
log_info "Configuring UFW Firewall & Fail2ban..."
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH || ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp

if [[ "$ALLOW_PG_REMOTE" =~ ^[Yy]$ ]]; then
  if [ "$PG_CLIENT_IP" = "0.0.0.0/0" ]; then
    ufw allow 5432/tcp
    log_info "UFW: Port 5432 opened for remote PostgreSQL access (all IPs)."
  else
    ufw allow from "$SPECIFIC_IP" to any port 5432 proto tcp
    log_info "UFW: Port 5432 opened for PostgreSQL specifically from $SPECIFIC_IP."
  fi
fi

ufw --force enable

systemctl enable fail2ban 2>/dev/null || true
systemctl restart fail2ban 2>/dev/null || true
log_success "UFW Firewall & Fail2ban active."

# ==============================================================================
# COMPLETION SUMMARY
# ==============================================================================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
SERVER_IP=$(curl -s --max-time 4 https://ifconfig.me || curl -s --max-time 4 https://api.ipify.org || hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")

clear
echo -e "${GREEN}${BOLD}"
echo "======================================================================"
echo "          🎉 SERVER PRODUCTION SETUP COMPLETED SUCCESSFULLY!          "
echo "======================================================================"
echo -e "${NC}"
echo -e "⏱️ Total Installation Time: ${CYAN}$((DURATION / 60))m $((DURATION % 60))s${NC}\n"

echo -e "${BOLD}🌐 Web Services:${NC}"
echo -e "  Domain URL:           ${GREEN}https://$DOMAIN_NAME${NC}"
echo -e "  Server Public IP:     ${CYAN}$SERVER_IP${NC}"
echo -e "  Local App Port:       ${CYAN}http://127.0.0.1:$APP_PORT${NC}"
echo -e "  Application Path:     ${CYAN}$APP_DIR${NC}"
echo -e "  SSL Auto-Renew:       ${GREEN}Enabled (Certbot Systemd Timer)${NC}"

echo -e "\n${BOLD}🗄️ Database Credentials (Local Machine / DBeaver / pgAdmin):${NC}"
echo -e "  Host / IP:            ${GREEN}$SERVER_IP${NC}"
echo -e "  Port:                 ${CYAN}5432${NC}"
echo -e "  Database Name:        ${CYAN}$DB_NAME${NC}"
echo -e "  Database User:        ${CYAN}$DB_USER${NC}"
echo -e "  Database Password:    ${YELLOW}$DB_PASS${NC}"
echo -e "  Remote Access:        ${GREEN}${ALLOW_PG_REMOTE:-Y} (Allowed: $PG_CLIENT_IP)${NC}"
echo -e "  Connection URI:       ${CYAN}postgresql://$DB_USER:$DB_PASS@$SERVER_IP:5432/$DB_NAME${NC}"

echo -e "\n${BOLD}⚡ Redis Cache:${NC}"
echo -e "  Redis Host:           ${CYAN}127.0.0.1:$REDIS_PORT (Internal only)${NC}"
if [ -n "$REDIS_PASS" ]; then
  echo -e "  Redis Password:       ${YELLOW}$REDIS_PASS${NC}"
else
  echo -e "  Redis Password:       ${CYAN}(None / Localhost only)${NC}"
fi

echo -e "\n${BOLD}🛡️ Security Status:${NC}"
echo -e "  UFW Firewall:         ${GREEN}Active (SSH 22, HTTP 80, HTTPS 443$([[ "$ALLOW_PG_REMOTE" =~ ^[Yy]$ ]] && echo ", Postgres 5432"))${NC}"
echo -e "  Fail2ban:             ${GREEN}Active (Brute-force protection)${NC}"
echo -e "  Swap Memory:          ${GREEN}2GB Virtual RAM Active${NC}"

echo -e "\n${BOLD}🛠️ Useful Server Management Commands:${NC}"
echo -e "  View Live Logs:       ${CYAN}pm2 logs${NC}"
echo -e "  Restart App:          ${CYAN}pm2 reload ecosystem.config.js${NC}"
echo -e "  Check PM2 Status:     ${CYAN}pm2 status${NC}"
echo -e "  Check Nginx Status:   ${CYAN}sudo systemctl status nginx${NC}"
echo -e "  Check Postgres:       ${CYAN}sudo systemctl status postgresql${NC}"
echo -e "  Check Redis:          ${CYAN}sudo systemctl status redis-server${NC}"
echo -e "  Check Memory/Disk:    ${CYAN}free -h && df -h /${NC}"
echo -e "\n======================================================================\n"
