#!/bin/bash
# ============================================================
# EC2 user-data for Task Manager — Amazon Linux 2023 + RDS
# ============================================================
# Paste this entire script into the EC2 "User data" box
# under Advanced details when launching the instance.
#
# Prerequisites:
#   - RDS PostgreSQL already created and in "Available" state
#   - web-sg allows HTTP (80) and SSH (22) from 0.0.0.0/0
#   - db-sg allows PostgreSQL (5432) from web-sg
#
# Fill in the 4 placeholders below before launching.
# ============================================================

set -x
exec > >(tee /var/log/task-manager-deploy.log)
exec 2>&1

# ---- FILL THESE IN ----
RAILS_MASTER_KEY="b810523f70a77df261697136e2c0c922"
DB_PASSWORD="admin123"
RDS_ENDPOINT="task-manager-db.cadse68kcrrx.us-east-1.rds.amazonaws.com"
# -----------------------

echo "===== TASK MANAGER DEPLOYMENT START ====="

dnf update -y
dnf install -y docker git postgresql15
systemctl enable docker
systemctl start docker

# Create the task_manager role in RDS for Solid Cache/Queue/Cable
PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -U taskadmin -d postgres -c "
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'task_manager') THEN
      CREATE ROLE task_manager LOGIN PASSWORD '$DB_PASSWORD';
    END IF;
  END
  \$\$;
  ALTER ROLE task_manager CREATEDB;
"

# Verify the role can connect
PGPASSWORD="$DB_PASSWORD" psql -h "$RDS_ENDPOINT" -U task_manager -d postgres -c "SELECT 1;" || {
  echo "FATAL: task_manager role authentication failed" >&2
  exit 1
}

# Clone and build
git clone https://github.com/sghani001/task_manager_rails_aws.git /opt/task_manager
cd /opt/task_manager
docker build -t task_manager .

# Run the container
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

echo "===== DEPLOYMENT COMPLETE ====="
echo "Check: docker logs -f task_manager"
echo "App at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/"
