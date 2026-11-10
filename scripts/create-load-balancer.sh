#!/usr/bin/env bash
#
# Creates an Application Load Balancer for the ECS tasks:
#
#   - notes-alb-sg, a security group for the load balancer that allows HTTP
#     on port 80 from anywhere
#   - notes-alb, the load balancer, in eu-west-1a and eu-west-1b, with a
#     listener on port 80
#
# It doesn't create a target group. Until you create one in the tutorial and
# point the listener at it, the listener answers every request with a 503
# and a short message.
#
#   ./scripts/create-load-balancer.sh

set -euo pipefail

export AWS_REGION=eu-west-1

# Print output straight to the terminal, instead of opening it in a pager
# that waits for you to press q
export AWS_PAGER=""

ALB_NAME=notes-alb
ALB_SG_NAME=notes-alb-sg
PROJECT_TAG=wdd-ecs

VPC_ID=$(aws ec2 describe-vpcs \
  --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' \
  --output text)

subnet_in_zone() {
  aws ec2 describe-subnets \
    --filters Name=vpc-id,Values="$VPC_ID" Name=availability-zone,Values="$1" \
    --query 'Subnets[0].SubnetId' \
    --output text
}

SUBNET_A=$(subnet_in_zone "${AWS_REGION}a")
SUBNET_B=$(subnet_in_zone "${AWS_REGION}b")

# Stop if a previous run left resources behind

EXISTING_ALB=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?LoadBalancerName=='$ALB_NAME'] | [0].LoadBalancerArn" \
  --output text)

if [ "$EXISTING_ALB" != "None" ]; then
  echo "$ALB_NAME already exists, so this script has been run before."
  exit 1
fi

# Security group for the load balancer

echo "Creating security group $ALB_SG_NAME"

ALB_SG_ID=$(aws ec2 create-security-group \
  --group-name "$ALB_SG_NAME" \
  --description "Notes app load balancer" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$PROJECT_TAG}]" \
  --query GroupId \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  > /dev/null

# The load balancer and its listener

echo "Creating load balancer $ALB_NAME"

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "$ALB_NAME" \
  --type application \
  --scheme internet-facing \
  --subnets "$SUBNET_A" "$SUBNET_B" \
  --security-groups "$ALB_SG_ID" \
  --tags Key=Project,Value="$PROJECT_TAG" \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

# A listener needs a default action. With no target group to forward to yet,
# this one sends back a fixed response.

aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions '[{"Type":"fixed-response","FixedResponseConfig":{"StatusCode":"503","ContentType":"text/plain","MessageBody":"This listener has no target group yet"}}]' \
  > /dev/null

echo "Waiting for the load balancer to become active. This takes a few minutes."
aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo
echo "Done. You'll need these in the tutorial:"
echo
echo "  Load balancer DNS name: $ALB_DNS"
echo "  Security group:         $ALB_SG_NAME ($ALB_SG_ID)"
