#!/usr/bin/env bash
#
# Deletes everything that ./scripts/create-infrastructure.sh created,
# including the automatic scaling that you add to the service in the
# tutorial.
#
# It keeps the parameters /notes-grafana/OTEL_EXPORTER_OTLP_ENDPOINT and
# /notes-grafana/OTEL_EXPORTER_OTLP_HEADERS, which you created yourself, so
# that you can run the create script again without making them again. They
# cost nothing. Delete them in Parameter Store when you no longer need them.
#
# It is safe to run more than once, and skips anything that doesn't exist.
#
#   ./scripts/destroy-infrastructure.sh

set -euo pipefail

export AWS_REGION=eu-west-1

# Print output straight to the terminal, instead of opening it in a pager
# that waits for you to press q
export AWS_PAGER=""

NAME=notes-grafana
PARAMETER_PREFIX=/notes-grafana
LOG_GROUP_NAME=/ecs/$NAME

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME=$NAME-$ACCOUNT_ID

# -- The database. Deleting it takes several minutes, so start it first and
# wait for it later.

if aws rds describe-db-instances --db-instance-identifier "$NAME-db" > /dev/null 2>&1; then
  echo "Deleting database $NAME-db"

  # A database that's still being created can't be deleted yet
  DB_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$NAME-db" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  if [ "$DB_STATUS" = "creating" ]; then
    echo "Waiting for the database to finish being created first"
    aws rds wait db-instance-available --db-instance-identifier "$NAME-db"
  fi

  if [ "$DB_STATUS" != "deleting" ]; then
    aws rds delete-db-instance \
      --db-instance-identifier "$NAME-db" \
      --skip-final-snapshot \
      --delete-automated-backups \
      > /dev/null
  fi
fi

# -- Automatic scaling. Removing the service from automatic scaling also
# deletes its scaling policies, and the CloudWatch alarms that the policies
# created. It's removed first, so that it can't start new tasks while the
# service is being deleted.

SCALABLE_TARGETS=$(aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs \
  --resource-ids "service/$NAME/$NAME" \
  --query 'length(ScalableTargets)' \
  --output text)

if [ "$SCALABLE_TARGETS" != "0" ]; then
  echo "Removing automatic scaling from service $NAME"
  aws application-autoscaling deregister-scalable-target \
    --service-namespace ecs \
    --resource-id "service/$NAME/$NAME" \
    --scalable-dimension ecs:service:DesiredCount
fi

# -- The service and cluster. Deleting a service with --force stops its
# tasks, and a cluster can't be deleted while it still has services.

CLUSTER_STATUS=$(aws ecs describe-clusters \
  --clusters "$NAME" \
  --query 'clusters[0].status' \
  --output text)

if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
  SERVICE_ARNS=$(aws ecs list-services \
    --cluster "$NAME" \
    --query 'serviceArns' \
    --output text)

  if [ -n "$SERVICE_ARNS" ]; then
    for service in $SERVICE_ARNS; do
      echo "Deleting service ${service##*/}"
      aws ecs delete-service \
        --cluster "$NAME" \
        --service "$service" \
        --force \
        > /dev/null
    done

    echo "Waiting for the service's tasks to stop"
    # $SERVICE_ARNS is left unquoted so that each ARN is a separate argument
    # shellcheck disable=SC2086
    aws ecs wait services-inactive --cluster "$NAME" --services $SERVICE_ARNS
  fi

  echo "Deleting cluster $NAME"
  aws ecs delete-cluster --cluster "$NAME" > /dev/null
fi

# -- Task definitions. A revision has to be deregistered before it can be
# deleted.

for revision in $(aws ecs list-task-definitions \
  --family-prefix "$NAME" \
  --status ACTIVE \
  --query 'taskDefinitionArns' \
  --output text); do
  echo "Deregistering task definition ${revision##*/}"
  aws ecs deregister-task-definition --task-definition "$revision" > /dev/null
done

for revision in $(aws ecs list-task-definitions \
  --family-prefix "$NAME" \
  --status INACTIVE \
  --query 'taskDefinitionArns' \
  --output text); do
  echo "Deleting task definition ${revision##*/}"
  aws ecs delete-task-definitions --task-definitions "$revision" > /dev/null || true
done

# -- The load balancer goes before the target group, because the target group
# can't be deleted while a load balancer is using it.

ALB_ARN=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?LoadBalancerName=='$NAME-alb'] | [0].LoadBalancerArn" \
  --output text)

if [ "$ALB_ARN" != "None" ]; then
  echo "Deleting load balancer $NAME-alb"
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
fi

TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?TargetGroupName=='$NAME-targets'] | [0].TargetGroupArn" \
  --output text)

# AWS reports the load balancer as deleted shortly before it releases the
# target group, so the first attempts can fail with ResourceInUse. Keep trying
# for up to a minute.

if [ "$TARGET_GROUP_ARN" != "None" ]; then
  echo "Deleting target group $NAME-targets"

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

# -- The bucket. S3 won't delete a bucket that still has files in it, so empty
# it first.

if aws s3api head-bucket --bucket "$BUCKET_NAME" > /dev/null 2>&1; then
  echo "Emptying bucket $BUCKET_NAME"
  aws s3 rm "s3://$BUCKET_NAME" --recursive > /dev/null

  echo "Deleting bucket $BUCKET_NAME"
  aws s3api delete-bucket --bucket "$BUCKET_NAME"
fi

# -- IAM roles. A role's policies have to be removed before the role can be
# deleted.

delete_role() {
  local role=$1

  if ! aws iam get-role --role-name "$role" > /dev/null 2>&1; then
    return 0
  fi

  echo "Deleting role $role"

  for policy in $(aws iam list-attached-role-policies \
    --role-name "$role" \
    --query 'AttachedPolicies[].PolicyArn' \
    --output text); do
    aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
  done

  for policy in $(aws iam list-role-policies \
    --role-name "$role" \
    --query 'PolicyNames' \
    --output text); do
    aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
  done

  aws iam delete-role --role-name "$role"
}

delete_role "$NAME-execution-role"
delete_role "$NAME-task-role"

# -- The database password and the log group

if aws ssm get-parameter --name "$PARAMETER_PREFIX/DB_PASSWORD" > /dev/null 2>&1; then
  echo "Deleting parameter $PARAMETER_PREFIX/DB_PASSWORD"
  aws ssm delete-parameter --name "$PARAMETER_PREFIX/DB_PASSWORD"
fi

LOG_GROUP_EXISTS=$(aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP_NAME" \
  --query "logGroups[?logGroupName=='$LOG_GROUP_NAME'] | length(@)" \
  --output text)

if [ "$LOG_GROUP_EXISTS" != "0" ]; then
  echo "Deleting log group $LOG_GROUP_NAME"
  aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME"
fi

# -- Wait for the database to go, and then delete its parameter group and
# the security groups, which can't be deleted while the database uses them

if aws rds describe-db-instances --db-instance-identifier "$NAME-db" > /dev/null 2>&1; then
  echo "Waiting for the database to be deleted. This takes 5 to 10 minutes."
  aws rds wait db-instance-deleted --db-instance-identifier "$NAME-db"
fi

if aws rds describe-db-parameter-groups --db-parameter-group-name "$NAME-mysql" > /dev/null 2>&1; then
  echo "Deleting parameter group $NAME-mysql"
  aws rds delete-db-parameter-group --db-parameter-group-name "$NAME-mysql"
fi

# Stopped tasks and a deleted load balancer leave network interfaces behind
# for a few minutes, and a security group can't be deleted until they've
# gone. So keep trying for up to five minutes.

delete_security_group() {
  local name=$1
  local id
  id=$(aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$name" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

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

# Each group's inbound rule names the group before it, so delete them from
# the database back to the load balancer
delete_security_group "$NAME-db-sg"
delete_security_group "$NAME-tasks-sg"
delete_security_group "$NAME-alb-sg"

echo "Done."
