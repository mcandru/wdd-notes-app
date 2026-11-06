#!/usr/bin/env bash
#
# Launches one more instance running the notes app, set up the same way as the
# two that create-infrastructure.sh makes. Give it the name the app should show:
#
#   ./add-instance.sh instance-3
#
# It does not register the instance with a target group. That part is up to you.
#
# Run ./create-infrastructure.sh before this, because the new instance uses the
# security group and role that script creates.

set -euo pipefail

export AWS_REGION=eu-west-1

# Print output straight to the terminal, instead of opening it in a pager
# that waits for you to press q
export AWS_PAGER=""

IMAGE=ghcr.io/mcandru/wdd-notes-app:load-balancing
INSTANCE_TYPE=t3.micro
SG_NAME=notes-instances-sg
ROLE_NAME=notes-instance-role
PROJECT_TAG=wdd-load-balancing

if [ $# -ne 1 ]; then
  echo "Give the new instance a name, for example:"
  echo "  ./add-instance.sh instance-3"
  exit 1
fi

NAME=$1

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

if [ "$SG_ID" = "None" ]; then
  echo "$SG_NAME doesn't exist. Run ./create-infrastructure.sh first."
  exit 1
fi

# The new instance goes in eu-west-1a. The load balancer only sends traffic to
# the Availability Zones it was created in, which are 1a and 1b.
SUBNET=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="${AWS_REGION}a" \
  --query 'Subnets[0].SubnetId' \
  --output text)

AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value \
  --output text)

# The same boot script as the other instances, with this instance's name
USER_DATA=$(cat <<EOF
#!/bin/bash
dnf install -y docker
systemctl enable --now docker
docker run -d \\
  --name notes \\
  --restart unless-stopped \\
  -p 80:8000 \\
  -e INSTANCE_NAME=$NAME \\
  $IMAGE
EOF
)

echo "Launching notes-$NAME in ${AWS_REGION}a"

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name="$ROLE_NAME" \
  --user-data "$USER_DATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=notes-$NAME},{Key=Project,Value=$PROJECT_TAG}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Waiting for it to be running"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

echo
echo "Done. notes-$NAME is $INSTANCE_ID."
echo "It isn't registered with a target group, so the load balancer doesn't"
echo "know it exists yet."
