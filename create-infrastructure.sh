#!/usr/bin/env bash
#
# Creates two EC2 instances in the default VPC, one in eu-west-1a and one in
# eu-west-1b. Each one runs a copy of the notes app in Docker, with a different
# INSTANCE_NAME so that you can tell them apart.
#
# It also creates:
#   - notes-instances-sg, a security group that allows HTTP in from anywhere
#   - notes-instance-role, a role that lets you open a shell on the instances
#     with Session Manager
#
# Run it from the root of the repository:
#
#   ./create-infrastructure.sh
#
# Delete everything again with ./destroy-infrastructure.sh

set -euo pipefail

export AWS_REGION=eu-west-1

IMAGE=ghcr.io/mcandru/wdd-notes-app:load-balancing
INSTANCE_TYPE=t3.micro
SG_NAME=notes-instances-sg
ROLE_NAME=notes-instance-role

# Every resource gets this tag, so that you can find them in the console
PROJECT_TAG=wdd-load-balancing

# Find the default VPC and one subnet in each of two Availability Zones

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

if [ "$VPC_ID" = "None" ]; then
  echo "This region has no default VPC. Create one in the VPC console with"
  echo "Actions, Create default VPC, and run this script again."
  exit 1
fi

subnet_in_zone() {
  aws ec2 describe-subnets \
    --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="$1" \
    --query 'Subnets[0].SubnetId' \
    --output text
}

SUBNET_A=$(subnet_in_zone "${AWS_REGION}a")
SUBNET_B=$(subnet_in_zone "${AWS_REGION}b")

# Stop if a previous run left resources behind

EXISTING_SG=$(aws ec2 describe-security-groups \
  --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

if [ "$EXISTING_SG" != "None" ]; then
  echo "$SG_NAME already exists, so this script has been run before."
  echo "Run ./destroy-infrastructure.sh first, then run this script again."
  exit 1
fi

# The latest Amazon Linux 2023 image for x86. AWS publishes its ID in
# Parameter Store, so it never has to be looked up by hand.

AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value \
  --output text)

# Security group for the instances

echo "Creating security group $SG_NAME"

SG_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "Notes app instances" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$PROJECT_TAG}]" \
  --query GroupId \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  > /dev/null

# Role for the instances. Its only permission is the one Session Manager needs.

if aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1; then
  echo "Using the existing role $ROLE_NAME"
else
  echo "Creating role $ROLE_NAME"

  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Principal": { "Service": "ec2.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }]
    }' \
    > /dev/null

  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

  aws iam create-instance-profile \
    --instance-profile-name "$ROLE_NAME" \
    > /dev/null

  aws iam add-role-to-instance-profile \
    --instance-profile-name "$ROLE_NAME" \
    --role-name "$ROLE_NAME"
fi

# Launches one instance. $1 is the name the app shows, $2 is the subnet.

launch_instance() {
  local name=$1
  local subnet=$2

  # The boot script. It installs Docker and starts the app, passing the
  # instance's name in as an environment variable.
  local user_data
  user_data=$(cat <<EOF
#!/bin/bash
dnf install -y docker
systemctl enable --now docker
docker run -d \\
  --name notes \\
  --restart unless-stopped \\
  -p 80:8000 \\
  -e INSTANCE_NAME=$name \\
  $IMAGE
EOF
  )

  # A role that was created seconds ago can take a little while to reach EC2,
  # and until it does, run-instances fails with "Invalid IAM Instance Profile".
  # So try a few times before giving up.
  local error_file
  error_file=$(mktemp)

  for _ in 1 2 3 4 5 6; do
    if aws ec2 run-instances \
      --image-id "$AMI_ID" \
      --instance-type "$INSTANCE_TYPE" \
      --subnet-id "$subnet" \
      --security-group-ids "$SG_ID" \
      --iam-instance-profile Name="$ROLE_NAME" \
      --user-data "$user_data" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=notes-$name},{Key=Project,Value=$PROJECT_TAG}]" \
      --query 'Instances[0].InstanceId' \
      --output text 2> "$error_file"; then
      return 0
    fi

    sleep 5
  done

  cat "$error_file" >&2
  return 1
}

echo "Launching notes-instance-1 in ${AWS_REGION}a"
INSTANCE_1=$(launch_instance instance-1 "$SUBNET_A")

echo "Launching notes-instance-2 in ${AWS_REGION}b"
INSTANCE_2=$(launch_instance instance-2 "$SUBNET_B")

echo "Waiting for both instances to be running"
aws ec2 wait instance-running --instance-ids "$INSTANCE_1" "$INSTANCE_2"

aws ec2 describe-instances \
  --instance-ids "$INSTANCE_1" "$INSTANCE_2" \
  --query 'Reservations[].Instances[].{Name: Tags[?Key==`Name`] | [0].Value, Zone: Placement.AvailabilityZone, PublicIP: PublicIpAddress}' \
  --output table

echo
echo "Done. Each instance takes another minute or two to install Docker and"
echo "start the app. Then open http://<PublicIP> for each one in a browser."
