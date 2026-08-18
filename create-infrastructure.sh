#!/usr/bin/env bash
#
# Creates the infrastructure for the notes app, running with files stored on
# the instance's own disk.
#
#   ./create-infrastructure.sh
#
# It makes:
#
#   notes-app-s3-role   an IAM role, so Session Manager can reach the instance
#   notes-app-s3-sg     a security group allowing HTTP in, and nothing else
#   notes-app-s3        a t3.micro running the app on port 80
#
# It deliberately does NOT give the role any S3 permission, and does not set
# S3_BUCKET. Adding those is what will be done in the tutorial.
#
# Safe to run again if it fails part way through.

set -euo pipefail

REGION="eu-west-1"
NAME="notes-app-s3"
REPO="https://github.com/mcandru/wdd-notes-app.git"
BRANCH="storing-files-s3"

echo "Creating infrastructure in $REGION"
echo

# ---------------------------------------------------------------------------
# 1. The IAM role
#
# The role lets the instance prove who it is to AWS. AmazonSSMManagedInstanceCore
# is what allows Session Manager to open a shell on it.
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

  aws iam attach-role-policy \
    --role-name "$NAME-role" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
fi

# An EC2 instance cannot be given a role directly. It is given an "instance
# profile", which is a container holding exactly one role. The console makes
# this for you silently. From the CLI you have to make it yourself, and
# forgetting to is the usual reason a scripted instance is unreachable.

if aws iam get-instance-profile --instance-profile-name "$NAME-role" >/dev/null 2>&1; then
  echo "Instance profile $NAME-role already exists"
else
  echo "Creating instance profile $NAME-role"

  aws iam create-instance-profile --instance-profile-name "$NAME-role" >/dev/null
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$NAME-role" \
    --role-name "$NAME-role"
fi

# ---------------------------------------------------------------------------
# 2. The security group
#
# Port 80 from anywhere, and nothing else. No SSH, because Session Manager
# does not need an open port.
# ---------------------------------------------------------------------------

SG_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=group-name,Values=$NAME-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "Security group $NAME-sg already exists ($SG_ID)"
else
  echo "Creating security group $NAME-sg"

  VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

  SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$NAME-sg" \
    --description "Notes app: HTTP in, nothing else" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
fi

# ---------------------------------------------------------------------------
# 3. The machine image
#
# Asking AWS for the current Amazon Linux 2023 image, rather than hardcoding an
# ID. Image IDs change whenever AWS publishes a new build, and they are
# different in every region.
# ---------------------------------------------------------------------------

AMI_ID=$(aws ssm get-parameters \
  --region "$REGION" \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' \
  --output text)

echo "Using image $AMI_ID"

# ---------------------------------------------------------------------------
# 4. The boot script
#
# Everything the instance does to itself on first boot. Note that it writes a
# .env with PORT only. There is no S3_BUCKET, so the app will store uploaded
# files on this machine's own disk.
# ---------------------------------------------------------------------------

USER_DATA=$(mktemp)
trap 'rm -f "$USER_DATA" "$USER_DATA.template"' EXIT

cat > "$USER_DATA.template" <<'TEMPLATE'
#!/usr/bin/env bash
set -e

dnf install -y nodejs22 git

# Let Node listen on port 80 without running the whole app as root
setcap 'cap_net_bind_service=+ep' "$(readlink -f "$(which node)")"

# Swap, so the frontend build cannot run out of memory on a t3.micro
dd if=/dev/zero of=/swapfile bs=1M count=1024
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# The app belongs to ec2-user, not to root
su - ec2-user -c '
  git clone __REPO__
  cd wdd-notes-app
  git checkout __BRANCH__

  cd backend
  npm install
  echo "PORT=80" > .env

  cd ../frontend
  npm install
  npm run build
'

cat > /etc/systemd/system/notes.service <<'EOF'
[Unit]
Description=Notes app
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user/wdd-notes-app/backend
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now notes
TEMPLATE

sed -e "s|__REPO__|$REPO|" \
    -e "s|__BRANCH__|$BRANCH|" \
    "$USER_DATA.template" > "$USER_DATA"

# ---------------------------------------------------------------------------
# 5. Launch it
#
# IAM is eventually consistent, so an instance profile created seconds ago may
# not be visible to EC2 yet. That is what the retry is for.
# ---------------------------------------------------------------------------

echo "Launching $NAME"

INSTANCE_ID=""

for attempt in 1 2 3 4 5 6; do
  if INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --iam-instance-profile "Name=$NAME-role" \
    --security-group-ids "$SG_ID" \
    --user-data "file://$USER_DATA" \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
    --query 'Instances[0].InstanceId' \
    --output text 2>/dev/null); then
    break
  fi

  echo "  the new role is not visible to EC2 yet, waiting (attempt $attempt)"
  sleep 10
  INSTANCE_ID=""
done

if [ -z "$INSTANCE_ID" ]; then
  echo "Could not launch the instance. Run the last command again by hand to see the error." >&2
  exit 1
fi

echo "Waiting for $INSTANCE_ID to start"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

cat <<SUMMARY

Done.

  Instance   $INSTANCE_ID
  Address    http://$PUBLIC_IP
  Security   $SG_ID

The machine is running, but it is still installing the app. Give it three or
four minutes, then open that address.

  Shell      aws ssm start-session --target $INSTANCE_ID

SUMMARY
