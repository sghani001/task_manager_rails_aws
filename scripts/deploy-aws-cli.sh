#!/usr/bin/env bash
# ============================================================
# Part B — AWS CLI IaC: Task Manager (RDS + EC2)
# ============================================================
# Idempotent — safe to re-run. Skips existing resources.
# Usage: bash scripts/deploy-aws-cli.sh
# ============================================================

set -euo pipefail

export AWS_REGION=us-east-1

# ---- Inputs ----
read -rsp "DB_PASSWORD (for taskadmin + task_manager roles): " DB_PASSWORD
echo
read -sp "RAILS_MASTER_KEY: " RAILS_MASTER_KEY
echo

echo ""
echo "===== B1. Variables set ====="
echo "Region: $AWS_REGION"

# ============================================================
# B2. Security Groups
# ============================================================
echo "===== B2. Creating security groups ====="

VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
echo "VPC: $VPC_ID"

web_sg_exists=$(aws ec2 describe-security-groups --group-names web-sg --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
if [ -z "$web_sg_exists" ]; then
  WEB_SG_ID=$(aws ec2 create-security-group \
    --group-name web-sg \
    --description "Task manager web" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)
  echo "web-sg created: $WEB_SG_ID"
  aws ec2 authorize-security-group-ingress --group-id "$WEB_SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0
  aws ec2 authorize-security-group-ingress --group-id "$WEB_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0
else
  WEB_SG_ID=$web_sg_exists
  echo "web-sg exists: $WEB_SG_ID"
fi

db_sg_exists=$(aws ec2 describe-security-groups --group-names db-sg --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
if [ -z "$db_sg_exists" ]; then
  DB_SG_ID=$(aws ec2 create-security-group \
    --group-name db-sg \
    --description "Task manager db" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)
  echo "db-sg created: $DB_SG_ID"
  aws ec2 authorize-security-group-ingress --group-id "$DB_SG_ID" --protocol tcp --port 5432 --source-group "$WEB_SG_ID"
else
  DB_SG_ID=$db_sg_exists
  echo "db-sg exists: $DB_SG_ID"
fi

# ============================================================
# B3. RDS PostgreSQL
# ============================================================
echo "===== B3. Creating RDS ====="

db_exists=$(aws rds describe-db-instances --db-instance-identifier task-manager-db --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null || echo "")

if [ -z "$db_exists" ]; then
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query 'Subnets[].SubnetId' --output text)

  sn_group_exists=$(aws rds describe-db-subnet-groups --db-subnet-group-name task-manager-subnet-group --query 'DBSubnetGroups[0].DBSubnetGroupName' --output text 2>/dev/null || echo "")
  if [ -z "$sn_group_exists" ]; then
    aws rds create-db-subnet-group \
      --db-subnet-group-name task-manager-subnet-group \
      --db-subnet-group-description "Task manager subnets" \
      --subnet-ids $SUBNET_IDS > /dev/null
    echo "DB subnet group created."
  else
    echo "DB subnet group exists."
  fi

  aws rds create-db-instance \
    --db-instance-identifier task-manager-db \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --master-username taskadmin \
    --master-user-password "$DB_PASSWORD" \
    --allocated-storage 20 \
    --db-name task_manager_production \
    --vpc-security-group-ids "$DB_SG_ID" \
    --db-subnet-group-name task-manager-subnet-group \
    --no-multi-az \
    --no-publicly-accessible \
    --backup-retention-period 0 > /dev/null
  echo "RDS creation initiated."

  echo "Waiting for RDS to become available (5-10 min)..."
  aws rds wait db-instance-available --db-instance-identifier task-manager-db
else
  echo "RDS instance task-manager-db already exists."
  echo "Waiting for it to be available..."
  aws rds wait db-instance-available --db-instance-identifier task-manager-db
fi

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier task-manager-db \
  --query 'DBInstances[0].Endpoint.Address' --output text)
echo "RDS endpoint: $DB_ENDPOINT"

# ============================================================
# B4. EC2 Instance
# ============================================================
echo "===== B4. Creating EC2 instance ====="

echo "Checking key pair..."
key_exists=$(aws ec2 describe-key-pairs --key-names task-manager-key-cli --query 'KeyPairs[0].KeyName' --output text 2>/dev/null || echo "")
if [ -z "$key_exists" ]; then
  KEY_NAME=task-manager-key-cli
  aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > ~/.ssh/$KEY_NAME.pem
  chmod 400 ~/.ssh/$KEY_NAME.pem
  echo "Key pair created and saved to ~/.ssh/$KEY_NAME.pem"
  ssh-keygen -y -f ~/.ssh/$KEY_NAME.pem > /dev/null && echo "Key verified OK"
else
  KEY_NAME=task-manager-key-cli
  if [ ! -f ~/.ssh/$KEY_NAME.pem ]; then
    echo "ERROR: Key pair '$KEY_NAME' exists in AWS but ~/.ssh/$KEY_NAME.pem is missing."
    echo "Recreate it from AWS Console or delete the key pair, then re-run."
    exit 1
  fi
  echo "Key pair exists. Using ~/.ssh/$KEY_NAME.pem"
fi

echo "Checking for existing EC2 instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=task-manager-web" "Name=instance-state-name,Values=running,pending" \
  --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")

if [ -z "$INSTANCE_ID" ]; then
  AMI_ID=$(aws ec2 describe-images --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
  echo "AMI: $AMI_ID"

  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  UD_FILE="$SCRIPT_DIR/.user-data.sh"
  sed "s|__DB_PASSWORD__|$DB_PASSWORD|g; s|__DB_ENDPOINT__|$DB_ENDPOINT|g; s|__RAILS_MASTER_KEY__|$RAILS_MASTER_KEY|g" \
    "$SCRIPT_DIR/user-data.sh.template" > "$UD_FILE"
  UD_B64=$(base64 -w0 "$UD_FILE")
  rm -f "$UD_FILE"

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --key-name "$KEY_NAME" \
    --security-group-ids "$WEB_SG_ID" \
    --user-data "$UD_B64" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=task-manager-web}]' \
    --query 'Instances[0].InstanceId' --output text)
  echo "Instance launched: $INSTANCE_ID"

  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
else
  echo "EC2 instance already running: $INSTANCE_ID"
fi

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo ""
echo "=============================================="
echo "DEPLOYMENT READY"
echo "=============================================="
echo "RDS endpoint: $DB_ENDPOINT"
echo "EC2 public IP: $PUBLIC_IP"
echo "App: http://$PUBLIC_IP/"
echo ""
echo "SSH: ssh -i ~/.ssh/$KEY_NAME.pem ec2-user@$PUBLIC_IP"
echo "Deploy log: sudo cat /var/log/task-manager-deploy.log"
echo "Teardown:  bash scripts/teardown-aws-cli.sh"
echo "=============================================="
