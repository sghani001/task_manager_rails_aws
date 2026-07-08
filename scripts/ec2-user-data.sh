#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# EC2 user-data script for the Task Manager Rails app
# ------------------------------------------------------------
# Usage:
#   1. Launch an Ubuntu 22.04/24.04 EC2 instance.
#   2. Paste this script into User data.
#   3. Pass these values as instance tags or environment variables
#      before the script runs, or edit the defaults below.
# ------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

APP_NAME="task_manager"
APP_DIR="/var/www/${APP_NAME}"
APP_REPO="${APP_REPO:-https://github.com/your-org/task_manager.git}"
APP_BRANCH="${APP_BRANCH:-main}"
DB_NAME="${DB_NAME:-task_manager_production}"
DB_USER="${DB_USER:-task_manager}"
DB_PASSWORD="${DB_PASSWORD:-TaskManager123!}"
RAILS_ENV="${RAILS_ENV:-production}"
RAILS_MASTER_KEY="${RAILS_MASTER_KEY:-}"
SECRET_KEY_BASE="${SECRET_KEY_BASE:-}"
MISSION_CONTROL_USERNAME="${MISSION_CONTROL_USERNAME:-admin}"
MISSION_CONTROL_PASSWORD="${MISSION_CONTROL_PASSWORD:-admin123}"

if [[ -z "$RAILS_MASTER_KEY" ]]; then
  echo "RAILS_MASTER_KEY is required. Pass it as an environment variable or edit the script defaults." >&2
  exit 1
fi

if [[ -z "$SECRET_KEY_BASE" ]]; then
  echo "SECRET_KEY_BASE is required. Pass it as an environment variable or edit the script defaults." >&2
  exit 1
fi

# ------------------------------------------------------------
# 1) Base system packages
# ------------------------------------------------------------
apt-get update
apt-get install -y \
  curl git wget gnupg ca-certificates lsb-release \
  build-essential libssl-dev zlib1g-dev libreadline-dev \
  libyaml-dev libffi-dev libgdbm-dev libncurses5-dev \
  libxml2-dev libxslt1-dev libcurl4-openssl-dev \
  libpq-dev libsqlite3-dev pkg-config \
  postgresql postgresql-contrib nginx \
  libvips libvips-tools

# ------------------------------------------------------------
# 2) Install Node.js (useful for tooling and future assets)
# ------------------------------------------------------------
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
npm install -g yarn

# ------------------------------------------------------------
# 3) Install Ruby 3.3.11 with rbenv
# ------------------------------------------------------------
if [[ ! -d /root/.rbenv ]]; then
  git clone https://github.com/rbenv/rbenv.git /root/.rbenv
  cd /root/.rbenv && src/configure && make -C src
fi

if [[ ! -d /root/.rbenv/plugins/ruby-build ]]; then
  git clone https://github.com/rbenv/ruby-build.git /root/.rbenv/plugins/ruby-build
fi

cat >> /root/.bashrc <<'EOF'
export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"
EOF
export PATH="/root/.rbenv/bin:$PATH"
eval "$(rbenv init - bash)"

export RBENV_ROOT="/root/.rbenv"
export PATH="$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH"

rbenv install -s 3.3.11
rbenv global 3.3.11
ruby -v
gem install bundler -v 2.5.23 --no-document

# ------------------------------------------------------------
# 4) PostgreSQL setup
# ------------------------------------------------------------
service postgresql start
systemctl enable postgresql

su postgres -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'\" | grep -q 1 || createuser --superuser ${DB_USER}" >/dev/null 2>&1 || true
su postgres -c "psql -c \"ALTER USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';\"" >/dev/null 2>&1 || true
su postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\" | grep -q 1 || createdb -O ${DB_USER} ${DB_NAME}" >/dev/null 2>&1 || true

# ------------------------------------------------------------
# 5) Deploy the app
# ------------------------------------------------------------
mkdir -p "$APP_DIR"
cd "$APP_DIR"
if [[ ! -d .git ]]; then
  git clone "$APP_REPO" .
fi

git fetch origin "$APP_BRANCH" || true
git checkout "$APP_BRANCH" || true
git pull origin "$APP_BRANCH" || true

mkdir -p config
printf '%s
' "$RAILS_MASTER_KEY" > config/master.key

cat > .env <<EOF
RAILS_ENV=${RAILS_ENV}
RAILS_LOG_TO_STDOUT=1
DATABASE_URL=postgresql://${DB_USER}:${DB_PASSWORD}@127.0.0.1:5432/${DB_NAME}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
MISSION_CONTROL_USERNAME=${MISSION_CONTROL_USERNAME}
MISSION_CONTROL_PASSWORD=${MISSION_CONTROL_PASSWORD}
EOF

bundle config set --local path vendor/bundle
bundle config set --local without 'development test'
bundle install
bundle exec rails db:prepare
bundle exec rails assets:precompile

# ------------------------------------------------------------
# 6) Create a systemd service for Puma
# ------------------------------------------------------------
cat > /etc/systemd/system/task_manager.service <<EOF
[Unit]
Description=Task Manager Puma
After=network.target postgresql.service

[Service]
WorkingDirectory=${APP_DIR}
Environment=RAILS_ENV=production
EnvironmentFile=${APP_DIR}/.env
ExecStart=/root/.rbenv/shims/bundle exec puma -C ${APP_DIR}/config/puma.rb
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable task_manager
systemctl start task_manager

# ------------------------------------------------------------
# 7) Nginx reverse proxy
# ------------------------------------------------------------
cat > /etc/nginx/sites-available/task_manager <<EOF
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  server_name _;

  client_max_body_size 20M;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Real-IP \$remote_addr;
  }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/task_manager /etc/nginx/sites-enabled/task_manager
nginx -t
systemctl enable nginx
systemctl restart nginx

# ------------------------------------------------------------
# 8) Final status
# ------------------------------------------------------------
echo "Deployment setup complete."
echo "App directory: ${APP_DIR}"
echo "Service status:"
systemctl status task_manager --no-pager || true
