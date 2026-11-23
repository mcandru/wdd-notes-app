#!/usr/bin/env bash
#
# Deploys the notes app to ECS, with a MySQL database in RDS, and sends its
# logs, traces and metrics to Grafana Cloud. It creates:
#
#   - notes-grafana-alb-sg, notes-grafana-tasks-sg and notes-grafana-db-sg,
#     security groups that let the internet reach the load balancer, the load
#     balancer reach the tasks, and the tasks reach the database
#   - notes-grafana-db, a MySQL database in RDS, with its settings in the
#     parameter group notes-grafana-mysql, and its password in
#     Parameter Store as /notes-grafana/DB_PASSWORD
#   - notes-grafana-<account-id>, a private S3 bucket for the files attached
#     to notes
#   - notes-grafana-execution-role and notes-grafana-task-role, the IAM roles
#     for ECS and for the app
#   - /ecs/notes-grafana, a log group for the containers' output
#   - notes-grafana-alb, a load balancer, and notes-grafana-targets, its
#     target group
#   - notes-grafana, an ECS cluster, with the task definition notes-grafana
#     and a service that runs two copies of the app
#
# The tasks run the image ghcr.io/mcandru/wdd-notes-app:grafana-cloud, which
# is built from this branch. It also runs seed.js once in its own task, to
# create the notes table.
#
# Before you run it, create these two parameters in Parameter Store, with the
# values from your Grafana Cloud stack's OpenTelemetry page:
#
#   /notes-grafana/OTEL_EXPORTER_OTLP_ENDPOINT   String
#   /notes-grafana/OTEL_EXPORTER_OTLP_HEADERS    SecureString
#
# Run it from the root of the repository:
#
#   ./scripts/create-infrastructure.sh
#
# It takes about 15 minutes, most of it waiting for the database. Delete
# everything again with ./scripts/destroy-infrastructure.sh

set -euo pipefail

export AWS_REGION=eu-west-1

# Print output straight to the terminal, instead of opening it in a pager
# that waits for you to press q
export AWS_PAGER=""

NAME=notes-grafana
PARAMETER_PREFIX=/notes-grafana
APP_PORT=8000
DB_NAME=notes
DB_USER=notes_app
LOG_GROUP_NAME=/ecs/$NAME

# Every resource that can be tagged gets this tag, so that you can find them
# in the console
PROJECT_TAG=wdd-grafana

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME=$NAME-$ACCOUNT_ID

IMAGE=ghcr.io/mcandru/wdd-notes-app:grafana-cloud

stop() {
  echo "$1" >&2
  exit 1
}

# -- Checks, before anything is created

for parameter in OTEL_EXPORTER_OTLP_ENDPOINT OTEL_EXPORTER_OTLP_HEADERS; do
  if ! aws ssm get-parameter --name "$PARAMETER_PREFIX/$parameter" > /dev/null 2>&1; then
    stop "The parameter $PARAMETER_PREFIX/$parameter doesn't exist. Create it in
Parameter Store with the value from Grafana Cloud, and run this script again."
  fi
done

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

if [ "$VPC_ID" = "None" ]; then
  stop "This region has no default VPC. Create one in the VPC console with
Actions, Create default VPC, and run this script again."
fi

EXISTING_CLUSTER=$(aws ecs describe-clusters \
  --clusters "$NAME" \
  --query 'clusters[0].status' \
  --output text)

EXISTING_SG=$(aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$NAME-tasks-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

if [ "$EXISTING_CLUSTER" = "ACTIVE" ] || [ "$EXISTING_SG" != "None" ] \
  || aws rds describe-db-instances --db-instance-identifier "$NAME-db" > /dev/null 2>&1; then
  stop "Resources from an earlier run of this script still exist.
Run ./scripts/destroy-infrastructure.sh first, then run this script again."
fi

subnet_in_zone() {
  aws ec2 describe-subnets \
    --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="$1" \
    --query 'Subnets[0].SubnetId' \
    --output text
}

SUBNET_A=$(subnet_in_zone "${AWS_REGION}a")
SUBNET_B=$(subnet_in_zone "${AWS_REGION}b")

parameter_arn() {
  echo "arn:aws:ssm:$AWS_REGION:$ACCOUNT_ID:parameter$PARAMETER_PREFIX/$1"
}

# -- Security groups
#
# Each group only lets in traffic from the one before it, so the database
# can't be reached from the internet, only from the app's tasks.

create_security_group() {
  aws ec2 create-security-group \
    --group-name "$1" \
    --description "$2" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$PROJECT_TAG}]" \
    --query GroupId \
    --output text
}

echo "Creating security groups"

ALB_SG_ID=$(create_security_group "$NAME-alb-sg" "Notes app load balancer")
TASKS_SG_ID=$(create_security_group "$NAME-tasks-sg" "Notes app ECS tasks")
DB_SG_ID=$(create_security_group "$NAME-db-sg" "Notes app database")

aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  > /dev/null

aws ec2 authorize-security-group-ingress \
  --group-id "$TASKS_SG_ID" \
  --protocol tcp \
  --port "$APP_PORT" \
  --source-group "$ALB_SG_ID" \
  > /dev/null

aws ec2 authorize-security-group-ingress \
  --group-id "$DB_SG_ID" \
  --protocol tcp \
  --port 3306 \
  --source-group "$TASKS_SG_ID" \
  > /dev/null

# -- The database
#
# Created first, because it takes the longest. The script carries on with
# everything else and waits for it near the end.
#
# The password is random, and only kept in Parameter Store. It's hex, because
# RDS doesn't allow some symbols in passwords.

echo "Creating the database password in Parameter Store"

DB_PASSWORD=$(openssl rand -hex 16)

aws ssm put-parameter \
  --name "$PARAMETER_PREFIX/DB_PASSWORD" \
  --type SecureString \
  --value "$DB_PASSWORD" \
  --overwrite \
  > /dev/null

# MySQL's settings. RDS for MySQL 8.4 only accepts connections encrypted with
# TLS by default, and the app connects without it, so turn that off.

echo "Creating parameter group $NAME-mysql"

aws rds create-db-parameter-group \
  --db-parameter-group-name "$NAME-mysql" \
  --db-parameter-group-family mysql8.4 \
  --description "Notes app MySQL settings" \
  --tags Key=Project,Value="$PROJECT_TAG" \
  > /dev/null

aws rds modify-db-parameter-group \
  --db-parameter-group-name "$NAME-mysql" \
  --parameters ParameterName=require_secure_transport,ParameterValue=0,ApplyMethod=immediate \
  > /dev/null

# --backup-retention-period 0 turns off automatic backups, which makes the
# database quicker to create and delete. A real database would keep them.

echo "Creating database $NAME-db"

aws rds create-db-instance \
  --db-instance-identifier "$NAME-db" \
  --engine mysql \
  --engine-version 8.4 \
  --db-parameter-group-name "$NAME-mysql" \
  --db-instance-class db.t4g.micro \
  --allocated-storage 20 \
  --storage-type gp3 \
  --storage-encrypted \
  --db-name "$DB_NAME" \
  --master-username "$DB_USER" \
  --master-user-password "$DB_PASSWORD" \
  --vpc-security-group-ids "$DB_SG_ID" \
  --no-publicly-accessible \
  --backup-retention-period 0 \
  --tags Key=Project,Value="$PROJECT_TAG" \
  > /dev/null

# -- The bucket for files attached to notes. New buckets block all public
# access, so the files can only be reached through the app's download links.

echo "Creating bucket $BUCKET_NAME"

aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" \
  > /dev/null

aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging "TagSet=[{Key=Project,Value=$PROJECT_TAG}]"

# -- IAM roles
#
# The execution role is what ECS uses to start a task: to pull the image,
# read the secrets from Parameter Store and write to the log group. The task
# role is what the app itself uses, to read and write the bucket.

ECS_TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ecs-tasks.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}'

echo "Creating role $NAME-execution-role"

EXECUTION_ROLE_ARN=$(aws iam create-role \
  --role-name "$NAME-execution-role" \
  --assume-role-policy-document "$ECS_TRUST_POLICY" \
  --tags Key=Project,Value="$PROJECT_TAG" \
  --query Role.Arn \
  --output text)

aws iam attach-role-policy \
  --role-name "$NAME-execution-role" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

aws iam put-role-policy \
  --role-name "$NAME-execution-role" \
  --policy-name ReadAppSecrets \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": \"ssm:GetParameters\",
      \"Resource\": \"arn:aws:ssm:$AWS_REGION:$ACCOUNT_ID:parameter$PARAMETER_PREFIX/*\"
    }]
  }"

echo "Creating role $NAME-task-role"

TASK_ROLE_ARN=$(aws iam create-role \
  --role-name "$NAME-task-role" \
  --assume-role-policy-document "$ECS_TRUST_POLICY" \
  --tags Key=Project,Value="$PROJECT_TAG" \
  --query Role.Arn \
  --output text)

aws iam put-role-policy \
  --role-name "$NAME-task-role" \
  --policy-name ReadWriteUploads \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"s3:PutObject\", \"s3:GetObject\"],
      \"Resource\": \"arn:aws:s3:::$BUCKET_NAME/*\"
    }]
  }"

# -- Logs. ECS sends everything the containers print here, as well as the
# app sending its logs to Grafana Cloud.

echo "Creating log group $LOG_GROUP_NAME"

aws logs create-log-group --log-group-name "$LOG_GROUP_NAME"
aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME" --retention-in-days 7

# -- The load balancer

echo "Creating load balancer $NAME-alb"

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "$NAME-alb" \
  --type application \
  --scheme internet-facing \
  --subnets "$SUBNET_A" "$SUBNET_B" \
  --security-groups "$ALB_SG_ID" \
  --tags Key=Project,Value="$PROJECT_TAG" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# Fargate tasks have their own IP addresses, so the target type is ip. The
# health check asks for the home page, which doesn't need the database.

TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
  --name "$NAME-targets" \
  --protocol HTTP \
  --port "$APP_PORT" \
  --target-type ip \
  --vpc-id "$VPC_ID" \
  --health-check-path / \
  --tags Key=Project,Value="$PROJECT_TAG" \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
  > /dev/null

# -- Wait for the database, so its address can go in the task definition

echo "Waiting for the database to be ready. This takes 5 to 10 minutes."

aws rds wait db-instance-available --db-instance-identifier "$NAME-db"

DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "$NAME-db" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

# -- The task definition
#
# The settings that aren't secret are environment variables. The secrets come
# from Parameter Store, and ECS reads them with the execution role when it
# starts a task.

echo "Registering task definition $NAME"

TASK_DEFINITION=$(mktemp)
trap 'rm -f "$TASK_DEFINITION"' EXIT

cat > "$TASK_DEFINITION" <<JSON
{
  "family": "$NAME",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "$EXECUTION_ROLE_ARN",
  "taskRoleArn": "$TASK_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "$IMAGE",
      "essential": true,
      "portMappings": [{ "containerPort": $APP_PORT, "protocol": "tcp" }],
      "environment": [
        { "name": "PORT", "value": "$APP_PORT" },
        { "name": "DB_HOST", "value": "$DB_HOST" },
        { "name": "DB_PORT", "value": "3306" },
        { "name": "DB_USER", "value": "$DB_USER" },
        { "name": "DB_NAME", "value": "$DB_NAME" },
        { "name": "S3_BUCKET", "value": "$BUCKET_NAME" },
        { "name": "AWS_REGION", "value": "$AWS_REGION" }
      ],
      "secrets": [
        { "name": "DB_PASSWORD", "valueFrom": "$(parameter_arn DB_PASSWORD)" },
        { "name": "OTEL_EXPORTER_OTLP_ENDPOINT", "valueFrom": "$(parameter_arn OTEL_EXPORTER_OTLP_ENDPOINT)" },
        { "name": "OTEL_EXPORTER_OTLP_HEADERS", "valueFrom": "$(parameter_arn OTEL_EXPORTER_OTLP_HEADERS)" }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "$LOG_GROUP_NAME",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "app"
        }
      }
    }
  ]
}
JSON

TASK_DEFINITION_ARN=$(aws ecs register-task-definition \
  --cli-input-json "file://$TASK_DEFINITION" \
  --tags key=Project,value="$PROJECT_TAG" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "Creating cluster $NAME"

aws ecs create-cluster \
  --cluster-name "$NAME" \
  --tags key=Project,value="$PROJECT_TAG" \
  > /dev/null

NETWORK="awsvpcConfiguration={subnets=[$SUBNET_A,$SUBNET_B],securityGroups=[$TASKS_SG_ID],assignPublicIp=ENABLED}"

# -- Create the notes table
#
# Runs seed.js once, in a task of its own, with the same settings as the app.
# Setting OTEL_SDK_DISABLED stops it sending anything to Grafana Cloud, so it
# doesn't show up there as a copy of the app.

echo "Creating the notes table with seed.js"

SEED_TASK_ARN=$(aws ecs run-task \
  --cluster "$NAME" \
  --task-definition "$TASK_DEFINITION_ARN" \
  --launch-type FARGATE \
  --network-configuration "$NETWORK" \
  --overrides '{"containerOverrides":[{"name":"app","command":["node","seed.js"],"environment":[{"name":"OTEL_SDK_DISABLED","value":"true"}]}]}' \
  --query 'tasks[0].taskArn' \
  --output text)

aws ecs wait tasks-stopped --cluster "$NAME" --tasks "$SEED_TASK_ARN"

SEED_EXIT_CODE=$(aws ecs describe-tasks \
  --cluster "$NAME" \
  --tasks "$SEED_TASK_ARN" \
  --query 'tasks[0].containers[0].exitCode' \
  --output text)

if [ "$SEED_EXIT_CODE" != "0" ]; then
  stop "seed.js failed. Its output is in the log group $LOG_GROUP_NAME in CloudWatch.
Run ./scripts/destroy-infrastructure.sh, and then this script again."
fi

# -- The service, which keeps two copies of the app running behind the load
# balancer

echo "Creating service $NAME"

aws ecs create-service \
  --cluster "$NAME" \
  --service-name "$NAME" \
  --task-definition "$TASK_DEFINITION_ARN" \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "$NETWORK" \
  --load-balancers targetGroupArn="$TARGET_GROUP_ARN",containerName=app,containerPort="$APP_PORT" \
  --tags key=Project,value="$PROJECT_TAG" \
  > /dev/null

echo "Waiting for both copies of the app to start"

aws ecs wait services-stable --cluster "$NAME" --services "$NAME"

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo
echo "Done. The app is at:"
echo
echo "  http://$ALB_DNS"
