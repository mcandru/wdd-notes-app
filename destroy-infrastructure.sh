#!/usr/bin/env bash
#
# Deletes everything from the load balancing tutorial:
#
#   - the load balancer notes-alb and the target group notes-targets
#   - every instance in the security group notes-instances-sg, including any
#     you launched yourself
#   - the security groups notes-instances-sg and notes-alb-sg
#   - the role notes-instance-role
#
# It is safe to run more than once, and skips anything that doesn't exist.
#
#   ./destroy-infrastructure.sh

set -euo pipefail

export AWS_REGION=eu-west-1

ALB_NAME=notes-alb
TARGET_GROUP_NAME=notes-targets
SG_NAME=notes-instances-sg
ALB_SG_NAME=notes-alb-sg
ROLE_NAME=notes-instance-role

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

security_group_id() {
  aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$1" \
    --query 'SecurityGroups[0].GroupId' \
    --output text
}

# The load balancer goes first, because the target group can't be deleted
# while a load balancer is using it.

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

if [ "$TARGET_GROUP_ARN" != "None" ]; then
  echo "Deleting target group $TARGET_GROUP_NAME"
  aws elbv2 delete-target-group --target-group-arn "$TARGET_GROUP_ARN"
fi

# Instances. A security group can't be deleted while an instance uses it.

SG_ID=$(security_group_id "$SG_NAME")

if [ "$SG_ID" != "None" ]; then
  INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters Name=instance.group-id,Values="$SG_ID" \
      Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

  if [ -n "$INSTANCE_IDS" ]; then
    echo "Terminating instances: $INSTANCE_IDS"
    # $INSTANCE_IDS is left unquoted so that each ID is a separate argument
    # shellcheck disable=SC2086
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS > /dev/null
    # shellcheck disable=SC2086
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
  fi
fi

# Security groups. After a load balancer is deleted, its network interfaces
# take a few minutes to go away, and its security group can't be deleted until
# they have. So keep trying for up to five minutes.

delete_security_group() {
  local name=$1
  local id
  id=$(security_group_id "$name")

  if [ "$id" = "None" ]; then
    return 0
  fi

  echo "Deleting security group $name"

  for _ in $(seq 30); do
    if aws ec2 delete-security-group --group-id "$id" 2> /dev/null; then
      return 0
    fi

    sleep 10
  done

  # One last try, this time showing the error
  aws ec2 delete-security-group --group-id "$id"
}

# The instances' group goes first, because its inbound rule refers to the
# load balancer's group.
delete_security_group "$SG_NAME"
delete_security_group "$ALB_SG_NAME"

# The role. Its instance profile and policy have to be removed before the role
# itself can be deleted.

if aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
  echo "Deleting role $ROLE_NAME"

  if aws iam get-instance-profile --instance-profile-name "$ROLE_NAME" > /dev/null 2>&1; then
    aws iam remove-role-from-instance-profile \
      --instance-profile-name "$ROLE_NAME" \
      --role-name "$ROLE_NAME" 2> /dev/null || true
    aws iam delete-instance-profile --instance-profile-name "$ROLE_NAME"
  fi

  aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2> /dev/null || true
  aws iam delete-role --role-name "$ROLE_NAME"
fi

echo "Done."
