#!/usr/bin/env bash
# ============================================================
# Part B — Teardown: destroys everything created by deploy-aws-cli.sh
# ============================================================
# Usage: bash scripts/teardown-aws-cli.sh
# ============================================================

set -euo pipefail

export AWS_REGION=us-east-1

echo "===== Terminating EC2 instance ====="
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=task-manager-web" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ -n "$INSTANCE_ID" ]; then
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" > /dev/null
  echo "Terminating $INSTANCE_ID..."
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
  echo "Terminated."
else
  echo "No running instance found."
fi

echo "===== Deleting RDS ====="
aws rds delete-db-instance --db-instance-identifier task-manager-db --skip-final-snapshot > /dev/null 2>&1 || echo "RDS not found or already deleting"
echo "Waiting for RDS deletion..."
aws rds wait db-instance-deleted --db-instance-identifier task-manager-db 2>/dev/null || echo "RDS gone."

echo "===== Deleting DB subnet group ====="
aws rds delete-db-subnet-group --db-subnet-group-name task-manager-subnet-group 2>/dev/null || true

echo "===== Deleting security groups ====="
aws ec2 delete-security-group --group-name db-sg 2>/dev/null || echo "db-sg gone"
aws ec2 delete-security-group --group-name web-sg 2>/dev/null || echo "web-sg gone"

echo "===== Deleting key pair ====="
aws ec2 delete-key-pair --key-name task-manager-key-cli 2>/dev/null || true
rm -f ~/.ssh/task-manager-key-cli.pem

rm -f scripts/.user-data.sh /tmp/task-manager-user-data.sh

echo ""
echo "=============================================="
echo "TEARDOWN COMPLETE"
echo "=============================================="
echo "Verify with:"
echo "  aws ec2 describe-instances --filters \"Name=tag:Name,Values=task-manager-web\""
echo "  aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'"
echo "  aws ec2 describe-security-groups --filters \"Name=group-name,Values=web-sg,db-sg\""
echo "=============================================="
