#!/usr/bin/env bash
#
# Creates everything the notes app needs before the database tutorial starts.
#
#   ./create-infrastructure.sh [bucket-name]
#
# It makes:
#
#   notes-app-uploads-<account>  an S3 bucket for uploaded files
#   notes-app-db-role            an IAM role, so Session Manager can reach the
#                                instance and the app can read and write the
#                                bucket
#   notes-app-db-sg              a security group allowing HTTP in, and nothing
#                                else
#   notes-app-db                 a t3.micro running the app on port 80
#
# Pass the name of the bucket you made in the S3 tutorial if you still have it,
# and the script uses that one instead of creating another.
#
# It deliberately does NOT create the database, and it does not put DB_HOST or
# any of the other database settings in .env. Creating the database and
# connecting the app to it is the tutorial.
#
# Run it again and you get a second instance, which is what the last part of
# the tutorial asks for. Everything else is reused rather than duplicated.

set -euo pipefail

REGION="eu-west-1"
NAME="notes-app-db"
REPO="https://github.com/mcandru/wdd-notes-app.git"
BRANCH="database"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${1:-notes-app-uploads-$ACCOUNT_ID}"

echo "Creating infrastructure in $REGION"
echo

# ---------------------------------------------------------------------------
# 1. The bucket
#
# Uploaded files go here. Bucket names have to be unique across every AWS
# account in the world, so the default name has your account number on the end.
#
# The public access block is on, which is also the default for a new bucket.
# The app reads and writes these files with the credentials of the role below,
# and browsers download them through presigned links, so nothing here needs the
# bucket to be public.
# ---------------------------------------------------------------------------

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "Bucket $BUCKET already exists"
else
  echo "Creating bucket $BUCKET"

  if ! aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null 2>&1; then
    echo "Could not create the bucket $BUCKET." >&2
    echo "The name is probably taken by another AWS account. Run the script again" >&2
    echo "with a name of your own, for example:" >&2
    echo "  ./create-infrastructure.sh notes-app-uploads-yourname" >&2
    exit 1
  fi

  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

# ---------------------------------------------------------------------------
# 2. The IAM role
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

# The S3 permission, which is what you added by hand in the previous tutorial.
# The resource ends in /* because PutObject and GetObject act on objects, and
# IAM treats a bucket and the objects inside it as separate resources.
#
# Nothing here grants any database permission, because RDS checks a MySQL
# username and password rather than an IAM identity.

echo "Granting $NAME-role read and write access to $BUCKET"

aws iam put-role-policy \
  --role-name "$NAME-role" \
  --policy-name NotesAppUploads \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"ReadWriteUploads\",
      \"Effect\": \"Allow\",
      \"Action\": [\"s3:PutObject\", \"s3:GetObject\"],
      \"Resource\": \"arn:aws:s3:::$BUCKET/*\"
    }]
  }"

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
# 3. The security group
#
# Port 80 from anywhere, and nothing else. No SSH, because Session Manager
# does not need an open port.
#
# In the tutorial you make a second security group for the database, and its
# inbound rule names this group as the source. Every instance this script
# launches is a member of it, so a replacement instance can reach the database
# without anybody editing a rule.
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
# 4. The machine image
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
# 5. The boot script
#
# Everything the instance does to itself on first boot. The .env it writes has
# the S3 settings in it and no database settings, so the app starts, serves the
# page, and fails on every query. Filling in the missing settings is the
# tutorial.
# ---------------------------------------------------------------------------

USER_DATA=$(mktemp)
trap 'rm -f "$USER_DATA" "$USER_DATA.template"' EXIT

cat > "$USER_DATA.template" <<'TEMPLATE'
#!/usr/bin/env bash
set -e

# mariadb105 is the MySQL client. Amazon Linux 2023 has no package of its own
# called mysql, and the MariaDB client speaks the same protocol.
dnf install -y nodejs22 git mariadb105

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
  cat > .env <<ENV
PORT=80
S3_BUCKET=__BUCKET__
AWS_REGION=__REGION__
ENV

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
    -e "s|__BUCKET__|$BUCKET|" \
    -e "s|__REGION__|$REGION|" \
    "$USER_DATA.template" > "$USER_DATA"

# ---------------------------------------------------------------------------
# 6. Launch it
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
  Security   $NAME-sg ($SG_ID)
  Bucket     $BUCKET

The machine is running, but it is still installing the app. Give it three or
four minutes, then open that address.

  Shell      aws ssm start-session --target $INSTANCE_ID

There is no database yet, so the app will serve the page and fail on every
query. The tutorial creates the database and connects the app to it.

SUMMARY
