#!/bin/bash
# ============================================================
# Deploy latest code to EC2 — run this via SSH
# ============================================================
# Usage:
#   ssh -i ~/.ssh/key.pem ec2-user@<ip>
#   sudo bash scripts/deploy-ec2.sh
#
# Fill in the 3 placeholders before running.
# ============================================================

set -euo pipefail

RAILS_MASTER_KEY="b810523f70a77df261697136e2c0c922"
DB_PASSWORD="admin123"
RDS_ENDPOINT="task-manager-db.cadse68kcrrx.us-east-1.rds.amazonaws.com"

echo "===== PULLING LATEST CODE ====="
cd /opt/task_manager
git pull origin main

echo "===== REBUILDING DOCKER IMAGE ====="
docker build -t task_manager .

echo "===== REPLACING CONTAINER ====="
docker rm -f task_manager 2>/dev/null || true
docker run -d --name task_manager \
  -p 80:80 \
  -e RAILS_MASTER_KEY="$RAILS_MASTER_KEY" \
  -e DATABASE_URL="postgres://taskadmin:$DB_PASSWORD@$RDS_ENDPOINT:5432/task_manager_production?sslmode=require" \
  -e TASK_MANAGER_DATABASE_PASSWORD="$DB_PASSWORD" \
  -e DATABASE_HOST="$RDS_ENDPOINT" \
  -e MISSION_CONTROL_USERNAME=admin \
  -e MISSION_CONTROL_PASSWORD="$DB_PASSWORD" \
  -e PGSSLMODE=require \
  -e RAILS_LOG_LEVEL=info \
  --restart unless-stopped \
  task_manager

echo "===== DONE ====="
echo "Watch logs: docker logs -f task_manager"
