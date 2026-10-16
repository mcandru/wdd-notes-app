#!/usr/bin/env bash
#
# Runs once, on the instance, the first time it boots.
#
# create-infrastructure.sh launches the first instance with this file. Paste
# the same file into User data to launch a replacement in the console. It has
# nothing in it that is specific to your account, because it works out the
# registry address and reads the settings when it runs.

set -e

REGION=eu-west-1

dnf install -y docker
systemctl enable --now docker

# The registry address has the account number in it. The instance asks AWS
# which account it belongs to, using its role.
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="$ACCOUNT.dkr.ecr.$REGION.amazonaws.com"

# Every setting the app needs, out of Parameter Store and into a file that
# docker can read. The parameter names are the variable names, so stripping the
# path off the front and swapping the tab for an = is the whole conversion.
aws ssm get-parameters-by-path \
  --region $REGION \
  --path /notes-app-cloudfront/ \
  --query 'Parameters[].[Name,Value]' \
  --output text \
  | sed 's|^/notes-app-cloudfront/||' \
  | tr '\t' '=' > /etc/notes.env

chmod 600 /etc/notes.env

aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $REGISTRY

# -p 80:8000 publishes the container's port 8000 as port 80 on the machine.
docker run -d \
  --name notes \
  --restart unless-stopped \
  -p 80:8000 \
  --env-file /etc/notes.env \
  "$REGISTRY/notes-app-cloudfront:latest"
