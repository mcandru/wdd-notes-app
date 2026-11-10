#!/usr/bin/env bash
#
# Creates the resources that the ECS tutorial needs before you start:
#
#   - notes-tasks-sg, a security group for the tasks that allows HTTP on
#     port 8000 from anywhere
#   - notes-ecs-<account-id>, a private S3 bucket for the files attached to
#     notes
#   - /notes-ecs/MAX_NOTE_LENGTH and /notes-ecs/S3_BUCKET, values in Parameter
#     Store that the task definition passes to the app
#
# You create the cluster, task definition and service yourself in the
# tutorial. The load balancer comes later, from ./create-load-balancer.sh.
#
# Run it from the root of the repository:
#
#   ./scripts/create-infrastructure.sh
#
# Delete everything again with ./scripts/destroy-infrastructure.sh

set -euo pipefail

export AWS_REGION=eu-west-1

# Print output straight to the terminal, instead of opening it in a pager
# that waits for you to press q
export AWS_PAGER=""

SG_NAME=notes-tasks-sg
APP_PORT=8000
PARAMETER_NAME=/notes-ecs/MAX_NOTE_LENGTH
PARAMETER_VALUE=100
BUCKET_PARAMETER_NAME=/notes-ecs/S3_BUCKET

# Every resource gets this tag, so that you can find them in the console
PROJECT_TAG=wdd-ecs

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

if [ "$VPC_ID" = "None" ]; then
  echo "This region has no default VPC. Create one in the VPC console with"
  echo "Actions, Create default VPC, and run this script again."
  exit 1
fi

# Bucket names are shared by every AWS account, so the account ID makes this
# one unique
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME=notes-ecs-$ACCOUNT_ID

# Stop if a previous run left resources behind

EXISTING_SG=$(aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

if [ "$EXISTING_SG" != "None" ]; then
  echo "$SG_NAME already exists, so this script has been run before."
  echo "Run ./scripts/destroy-infrastructure.sh first, then run this script again."
  exit 1
fi

if aws s3api head-bucket --bucket "$BUCKET_NAME" > /dev/null 2>&1; then
  echo "$BUCKET_NAME already exists, so this script has been run before."
  echo "Run ./scripts/destroy-infrastructure.sh first, then run this script again."
  exit 1
fi

# Security group for the tasks. On Fargate, each task gets its own network
# interface, and the security group is attached to that interface.

echo "Creating security group $SG_NAME"

SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "Notes app ECS tasks" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$PROJECT_TAG}]" \
  --query GroupId \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port "$APP_PORT" \
  --cidr 0.0.0.0/0 \
  > /dev/null

# The bucket for files attached to notes. New buckets block all public
# access, so the files can only be reached through the app's download links.
# Outside us-east-1, create-bucket needs the region in
# --create-bucket-configuration as well as in AWS_REGION.

echo "Creating bucket $BUCKET_NAME"

aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" \
  > /dev/null

aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging "TagSet=[{Key=Project,Value=$PROJECT_TAG}]"

# The app's settings in Parameter Store. --overwrite means a second run
# replaces the value instead of failing.

echo "Creating parameter $PARAMETER_NAME"

aws ssm put-parameter \
  --name "$PARAMETER_NAME" \
  --type String \
  --value "$PARAMETER_VALUE" \
  --overwrite \
  > /dev/null

echo "Creating parameter $BUCKET_PARAMETER_NAME"

aws ssm put-parameter \
  --name "$BUCKET_PARAMETER_NAME" \
  --type String \
  --value "$BUCKET_NAME" \
  --overwrite \
  > /dev/null

PARAMETER_ARN=$(aws ssm get-parameter \
  --name "$PARAMETER_NAME" \
  --query Parameter.ARN \
  --output text)

BUCKET_PARAMETER_ARN=$(aws ssm get-parameter \
  --name "$BUCKET_PARAMETER_NAME" \
  --query Parameter.ARN \
  --output text)

echo
echo "Done. You'll need these in the tutorial:"
echo
echo "  Security group:          $SG_NAME ($SG_ID)"
echo "  Bucket:                  $BUCKET_NAME"
echo "  MAX_NOTE_LENGTH ARN:     $PARAMETER_ARN"
echo "  S3_BUCKET ARN:           $BUCKET_PARAMETER_ARN"
