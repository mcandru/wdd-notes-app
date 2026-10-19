#!/usr/bin/env bash
#
# Runs the notes app on an EC2 instance with a CloudFront distribution in front
# of it, so that the domain names tutorial has something to point a name at.
#
#   ./create-infrastructure.sh
#

set -euo pipefail

REGION="eu-west-1"
NAME="notes-app-domain"

# The IDs of two policies that AWS manages. They're the same in every account.
CACHING_DISABLED="4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
ALL_VIEWER_EXCEPT_HOST="b689b0a8-53d0-40ab-baf2-68738e2966ac"

# user-data.sh is next to this script. It is found from where the script is
# rather than from wherever you ran it.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$SCRIPT_DIR/user-data.sh" ]; then
  echo "There is no user-data.sh in $SCRIPT_DIR." >&2
  echo "This script has to be next to user-data.sh." >&2
  exit 1
fi

echo "Creating infrastructure in $REGION"
echo

# ---------------------------------------------------------------------------
# 1. The security group
#
# HTTP is only allowed in from the addresses CloudFront connects from. AWS
# keeps that list up to date as a managed prefix list. Session Manager doesn't
# use SSH, so port 80 is the only port the instance needs open.
# ---------------------------------------------------------------------------

VPC_ID=$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)

if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
  echo "There is no default VPC in $REGION." >&2
  echo "Create one in the console under VPC, Your VPCs, Actions, Create default VPC," >&2
  echo "then run this script again." >&2
  exit 1
fi

SG_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=group-name,Values=$NAME-sg" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "Security group $NAME-sg already exists ($SG_ID)"
else
  echo "Creating security group $NAME-sg"

  SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$NAME-sg" \
    --description "Notes app behind CloudFront: HTTP in from CloudFront only" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

  PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
    --region "$REGION" \
    --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing" \
    --query 'PrefixLists[0].PrefixListId' \
    --output text)

  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --ip-permissions "IpProtocol=tcp,FromPort=80,ToPort=80,PrefixListIds=[{PrefixListId=$PREFIX_LIST_ID}]" \
    >/dev/null
fi

# ---------------------------------------------------------------------------
# 2. The IAM role
#
# The instance only needs Session Manager, so you can open a shell on it if
# the app doesn't start. It doesn't need to log in anywhere to pull a public
# image.
# ---------------------------------------------------------------------------

if aws iam get-role --role-name "$NAME-role" >/dev/null 2>&1; then
  echo "Role $NAME-role already exists"
else
  echo "Creating role $NAME-role"

  aws iam create-role \
    --role-name "$NAME-role" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "Service": "ec2.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }]
    }' >/dev/null
fi

aws iam attach-role-policy \
  --role-name "$NAME-role" \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# An EC2 instance is given an instance profile, which holds exactly one role.

PROFILE_CREATED=no

if aws iam get-instance-profile --instance-profile-name "$NAME-role" >/dev/null 2>&1; then
  echo "Instance profile $NAME-role already exists"
else
  echo "Creating instance profile $NAME-role"
  aws iam create-instance-profile --instance-profile-name "$NAME-role" >/dev/null
  PROFILE_CREATED=yes
fi

aws iam add-role-to-instance-profile \
  --instance-profile-name "$NAME-role" \
  --role-name "$NAME-role" >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# 3. The instance
#
# Amazon Linux 2023 on a t3.micro, in the default VPC, with the user data
# from user-data.sh. AWS publishes the ID of the newest Amazon Linux image in
# Parameter Store, so the script asks for it rather than naming one that goes
# out of date.
# ---------------------------------------------------------------------------

INSTANCE_ID=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$NAME" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
  echo "Instance $NAME already exists ($INSTANCE_ID)"
else
  AMI_ID=$(aws ssm get-parameter \
    --region "$REGION" \
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query 'Parameter.Value' \
    --output text)

  # A new instance profile takes a few seconds to become usable, and launching
  # with it before then fails with "Invalid IAM Instance Profile". Trying again
  # every few seconds is how AWS's own tools deal with that.

  if [ "$PROFILE_CREATED" = yes ]; then
    echo "Waiting for the instance profile to be ready"
    sleep 10
  fi

  echo "Launching instance $NAME"

  for attempt in 1 2 3 4 5 6; do
    if OUTPUT=$(aws ec2 run-instances \
      --region "$REGION" \
      --image-id "$AMI_ID" \
      --instance-type t3.micro \
      --security-group-ids "$SG_ID" \
      --iam-instance-profile "Name=$NAME-role" \
      --user-data "file://$SCRIPT_DIR/user-data.sh" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
      --query 'Instances[0].InstanceId' \
      --output text 2>&1); then
      INSTANCE_ID="$OUTPUT"
      break
    fi

    if [ "$attempt" = 6 ]; then
      echo "Could not launch the instance. AWS said:" >&2
      echo "  $OUTPUT" >&2
      exit 1
    fi

    sleep 5
  done
fi

echo "Waiting for $INSTANCE_ID to start"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

# ---------------------------------------------------------------------------
# 4. The Elastic IP
#
# CloudFront finds the instance by its public DNS name, and that name has the
# instance's address in it. An Elastic IP keeps the address, and so the name,
# the same until it is released.
# ---------------------------------------------------------------------------

ALLOCATION_ID=$(aws ec2 describe-addresses \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$NAME" \
  --query 'Addresses[0].AllocationId' \
  --output text)

if [ -n "$ALLOCATION_ID" ] && [ "$ALLOCATION_ID" != "None" ]; then
  echo "Elastic IP $NAME already exists ($ALLOCATION_ID)"
else
  echo "Allocating an Elastic IP"

  ALLOCATION_ID=$(aws ec2 allocate-address \
    --region "$REGION" \
    --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$NAME}]" \
    --query 'AllocationId' \
    --output text)
fi

echo "Attaching the Elastic IP to $INSTANCE_ID"

aws ec2 associate-address \
  --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --allocation-id "$ALLOCATION_ID" \
  --allow-reassociation >/dev/null

ELASTIC_IP=$(aws ec2 describe-addresses \
  --region "$REGION" \
  --allocation-ids "$ALLOCATION_ID" \
  --query 'Addresses[0].PublicIp' \
  --output text)

# The instance's public DNS name can take a few seconds to change over to the
# Elastic IP's name, and the distribution needs the new one.

for _ in $(seq 1 12); do
  CURRENT_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  [ "$CURRENT_IP" = "$ELASTIC_IP" ] && break
  sleep 5
done

PUBLIC_DNS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicDnsName' \
  --output text)

# ---------------------------------------------------------------------------
# 5. The distribution
#
# The settings are the ones the CloudFront tutorial chooses in the console.
# HTTP is redirected to HTTPS, every method is allowed, nothing is cached, and
# every header except Host is passed on to the instance.
#
# A distribution has no name, so the comment is how this script and the
# destroy script find it again.
# ---------------------------------------------------------------------------

DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='$NAME'].Id | [0]" \
  --output text)

if [ -n "$DIST_ID" ] && [ "$DIST_ID" != "None" ]; then
  echo "Distribution $NAME already exists ($DIST_ID)"
else
  echo "Creating a CloudFront distribution in front of $PUBLIC_DNS"

  DIST_ID=$(aws cloudfront create-distribution \
    --query 'Distribution.Id' \
    --output text \
    --distribution-config "{
      \"CallerReference\": \"$NAME-$(date +%s)\",
      \"Comment\": \"$NAME\",
      \"Enabled\": true,
      \"IsIPV6Enabled\": true,
      \"HttpVersion\": \"http2\",
      \"Origins\": {
        \"Quantity\": 1,
        \"Items\": [{
          \"Id\": \"$NAME-instance\",
          \"DomainName\": \"$PUBLIC_DNS\",
          \"CustomOriginConfig\": {
            \"HTTPPort\": 80,
            \"HTTPSPort\": 443,
            \"OriginProtocolPolicy\": \"http-only\",
            \"OriginSslProtocols\": { \"Quantity\": 1, \"Items\": [\"TLSv1.2\"] }
          }
        }]
      },
      \"DefaultCacheBehavior\": {
        \"TargetOriginId\": \"$NAME-instance\",
        \"ViewerProtocolPolicy\": \"redirect-to-https\",
        \"AllowedMethods\": {
          \"Quantity\": 7,
          \"Items\": [\"GET\", \"HEAD\", \"OPTIONS\", \"PUT\", \"POST\", \"PATCH\", \"DELETE\"],
          \"CachedMethods\": { \"Quantity\": 2, \"Items\": [\"GET\", \"HEAD\"] }
        },
        \"CachePolicyId\": \"$CACHING_DISABLED\",
        \"OriginRequestPolicyId\": \"$ALL_VIEWER_EXCEPT_HOST\"
      }
    }")
fi

DIST_DOMAIN=$(aws cloudfront get-distribution \
  --id "$DIST_ID" \
  --query 'Distribution.DomainName' \
  --output text)

echo "Waiting for $DIST_ID to deploy, which usually takes five to ten minutes"
aws cloudfront wait distribution-deployed --id "$DIST_ID"

# The security group only lets CloudFront in, so the app can only be checked
# through the distribution. The instance may still be installing Docker and
# starting the app, which takes a minute or two after it boots.

echo "Waiting for the app to answer on https://$DIST_DOMAIN"

APP_UP=no
for _ in $(seq 1 36); do
  if curl -fs -o /dev/null --max-time 10 "https://$DIST_DOMAIN/api/notes"; then
    APP_UP=yes
    break
  fi
  sleep 5
done

if [ "$APP_UP" = yes ]; then
  STATUS_LINE="The app is running at https://$DIST_DOMAIN"
else
  STATUS_LINE="The app has not answered yet. Wait a minute and open
https://$DIST_DOMAIN in your browser. If it still fails, open a shell
with Session Manager and run: sudo cat /var/log/cloud-init-output.log"
fi

cat <<SUMMARY

Done.

  Security       $NAME-sg ($SG_ID), HTTP from CloudFront only
  Role           $NAME-role
  Instance       $NAME ($INSTANCE_ID)
  Elastic IP     $ELASTIC_IP ($ALLOCATION_ID)
  Distribution   $DIST_ID ($DIST_DOMAIN)

$STATUS_LINE

SUMMARY
