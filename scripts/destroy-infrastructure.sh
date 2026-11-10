#!/usr/bin/env bash
#
# Deletes everything from the ECS tutorial:
#
#   - every service in the cluster notes-cluster, and then the cluster
#   - every revision of the task definition notes-task
#   - the load balancer notes-alb and the target group notes-targets
#   - the security groups notes-tasks-sg and notes-alb-sg
#   - the bucket notes-ecs-<account-id>, and every file in it
#   - the parameters /notes-ecs/MAX_NOTE_LENGTH and /notes-ecs/S3_BUCKET
#   - the log group /ecs/notes-task
#
# It doesn't delete the roles ecsTaskExecutionRole or notes-task-role. Other
# ECS work in your account can use ecsTaskExecutionRole, and you can delete
# notes-task-role yourself in the IAM console.
#
# It is safe to run more than once, and skips anything that doesn't exist.
#
#   ./scripts/destroy-infrastructure.sh

set -euo pipefail

export AWS_REGION=eu-west-1

# Print output straight to the terminal, instead of opening it in a pager
# that waits for you to press q
export AWS_PAGER=""

CLUSTER_NAME=notes-cluster
TASK_FAMILY=notes-task
ALB_NAME=notes-alb
TARGET_GROUP_NAME=notes-targets
SG_NAME=notes-tasks-sg
ALB_SG_NAME=notes-alb-sg
PARAMETER_NAME=/notes-ecs/MAX_NOTE_LENGTH
BUCKET_PARAMETER_NAME=/notes-ecs/S3_BUCKET
LOG_GROUP_NAME=/ecs/notes-task

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME=notes-ecs-$ACCOUNT_ID

security_group_id() {
  aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$1" \
    --query 'SecurityGroups[0].GroupId' \
    --output text
}

# Services first. Deleting a service with --force stops its tasks, and a
# cluster can't be deleted while it still has services.

CLUSTER_STATUS=$(aws ecs describe-clusters \
  --clusters "$CLUSTER_NAME" \
  --query 'clusters[0].status' \
  --output text)

if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
  SERVICE_ARNS=$(aws ecs list-services \
    --cluster "$CLUSTER_NAME" \
    --query 'serviceArns' \
    --output text)

  if [ -n "$SERVICE_ARNS" ]; then
    for service in $SERVICE_ARNS; do
      echo "Deleting service ${service##*/}"
      aws ecs delete-service \
        --cluster "$CLUSTER_NAME" \
        --service "$service" \
        --force \
        > /dev/null
    done

    echo "Waiting for the services' tasks to stop"
    # $SERVICE_ARNS is left unquoted so that each ARN is a separate argument
    # shellcheck disable=SC2086
    aws ecs wait services-inactive --cluster "$CLUSTER_NAME" --services $SERVICE_ARNS
  fi

  echo "Deleting cluster $CLUSTER_NAME"
  aws ecs delete-cluster --cluster "$CLUSTER_NAME" > /dev/null
fi

# Task definitions. A revision has to be deregistered before it can be
# deleted.

ACTIVE_REVISIONS=$(aws ecs list-task-definitions \
  --family-prefix "$TASK_FAMILY" \
  --status ACTIVE \
  --query 'taskDefinitionArns' \
  --output text)

for revision in $ACTIVE_REVISIONS; do
  echo "Deregistering task definition ${revision##*/}"
  aws ecs deregister-task-definition --task-definition "$revision" > /dev/null
done

INACTIVE_REVISIONS=$(aws ecs list-task-definitions \
  --family-prefix "$TASK_FAMILY" \
  --status INACTIVE \
  --query 'taskDefinitionArns' \
  --output text)

for revision in $INACTIVE_REVISIONS; do
  echo "Deleting task definition ${revision##*/}"
  aws ecs delete-task-definitions --task-definitions "$revision" > /dev/null || true
done

# The load balancer goes before the target group, because the target group
# can't be deleted while a load balancer is using it.

ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?LoadBalancerName=='$ALB_NAME'] | [0].LoadBalancerArn" \
  --output text)

if [ "$ALB_ARN" != "None" ]; then
  echo "Deleting load balancer $ALB_NAME"
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
fi

TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?TargetGroupName=='$TARGET_GROUP_NAME'] | [0].TargetGroupArn" \
  --output text)

# AWS reports the load balancer as deleted shortly before it releases the
# target group, so the first attempts can fail with ResourceInUse. Keep trying
# for up to a minute.

if [ "$TARGET_GROUP_ARN" != "None" ]; then
  echo "Deleting target group $TARGET_GROUP_NAME"

  for _ in $(seq 12); do
    if aws elbv2 delete-target-group --target-group-arn "$TARGET_GROUP_ARN" 2> /dev/null; then
      break
    fi

    sleep 5
  done

  # If it still exists, one last try that shows the error
  if aws elbv2 describe-target-groups --target-group-arns "$TARGET_GROUP_ARN" > /dev/null 2>&1; then
    aws elbv2 delete-target-group --target-group-arn "$TARGET_GROUP_ARN"
  fi
fi

# Security groups. Stopped tasks and a deleted load balancer leave network
# interfaces behind for a few minutes, and a security group can't be deleted
# until they've gone. So keep trying for up to five minutes.

delete_security_group() {
  local name=$1
  local id
  id=$(security_group_id "$name")

  if [ "$id" = "None" ]; then
    return 0
  fi

  echo "Deleting security group $name"

  for _ in $(seq 30); do
    if aws ec2 delete-security-group --group-id "$id" > /dev/null 2>&1; then
      return 0
    fi

    sleep 10
  done

  # One last try, this time showing the error
  aws ec2 delete-security-group --group-id "$id" > /dev/null
}

# The tasks' group goes first, because after the tutorial its inbound rule
# refers to the load balancer's group.
delete_security_group "$SG_NAME"
delete_security_group "$ALB_SG_NAME"

# The bucket. S3 won't delete a bucket that still has files in it, so empty
# it first.

if aws s3api head-bucket --bucket "$BUCKET_NAME" > /dev/null 2>&1; then
  echo "Emptying bucket $BUCKET_NAME"
  aws s3 rm "s3://$BUCKET_NAME" --recursive > /dev/null

  echo "Deleting bucket $BUCKET_NAME"
  aws s3api delete-bucket --bucket "$BUCKET_NAME"
fi

# The parameters and the log group

for name in "$PARAMETER_NAME" "$BUCKET_PARAMETER_NAME"; do
  if aws ssm get-parameter --name "$name" > /dev/null 2>&1; then
    echo "Deleting parameter $name"
    aws ssm delete-parameter --name "$name"
  fi
done

LOG_GROUP_EXISTS=$(aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP_NAME" \
  --query "logGroups[?logGroupName=='$LOG_GROUP_NAME'] | length(@)" \
  --output text)

if [ "$LOG_GROUP_EXISTS" != "0" ]; then
  echo "Deleting log group $LOG_GROUP_NAME"
  aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
fi

echo "Done."
