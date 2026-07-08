#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

APP_DIR="/opt/task_manager"
APP_REPO="${APP_REPO:-https://github.com/your-org/task_manager.git}"
APP_BRANCH="${APP_BRANCH:-main}"
RAILS_MASTER_KEY="${RAILS_MASTER_KEY:-}"
SECRET_KEY_BASE="${SECRET_KEY_BASE:-}"

if [[ -z "$RAILS_MASTER_KEY" || -z "$SECRET_KEY_BASE" ]]; then
  echo "RAILS_MASTER_KEY and SECRET_KEY_BASE are required." >&2
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu || true

mkdir -p "$APP_DIR"
cd "$APP_DIR"
if [ ! -d .git ]; then
  git clone "$APP_REPO" .
else
  git fetch origin "$APP_BRANCH" || true
  git checkout "$APP_BRANCH" || true
  git pull origin "$APP_BRANCH" || true
fi

mkdir -p .env
cat > .env <<EOF
RAILS_ENV=production
RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
SECRET_KEY_BASE=${SECRET_KEY_BASE}
POSTGRES_DB=task_manager_production
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
EOF

cat > docker-compose.yml <<'EOF2'
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_DB: task_manager_production
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  web:
    build:
      context: .
      dockerfile: Dockerfile
    environment:
      RAILS_ENV: production
      RAILS_MASTER_KEY: ${RAILS_MASTER_KEY}
      SECRET_KEY_BASE: ${SECRET_KEY_BASE}
      DATABASE_URL: postgresql://postgres:postgres@db:5432/task_manager_production
    ports:
      - "80:3000"
    depends_on:
      - db
    command: bash -lc "bundle exec rails db:prepare && bundle exec rails server -b 0.0.0.0"

volumes:
  postgres_data:
EOF2

cd "$APP_DIR"
docker compose up --build -d

echo "Docker deployment started."
echo "Open http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/"
