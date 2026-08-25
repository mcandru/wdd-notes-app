#!/usr/bin/env bash
#
# Creates everything the notes app needs before the container tutorial starts,
# apart from the registry, the password, and the instance.
#
#   ./create-infrastructure.sh [bucket-name]
#
# It makes:
#
#   notes-app-uploads-<account>   an S3 bucket for uploaded files
#   notes-app-containers-sg       a security group allowing HTTP in
#   notes-db-sg                   a security group allowing MySQL in, but only
#                                 from notes-app-containers-sg
#   notes-db                      a MySQL database on RDS
#   notes-app-containers-role     an IAM role, so the instance can open a
#                                 Session Manager shell, use the bucket, pull
#                                 an image, and read the database password
#
# All of that is scenery from earlier tutorials. It deliberately does NOT
# create the ECR repository, does NOT put the database password into Parameter
# Store, and does NOT launch an instance. Those three are the tutorial.
#
# The role is given permission to pull from a repository and to read a
# parameter that do not exist yet. A policy can name a resource before the
# resource is made.
#
# The database is created without waiting for it. It takes several minutes,
# which is roughly how long building and pushing the image takes.
#
# Safe to run again if it fails part way through.

set -euo pipefail

REGION="eu-west-1"
NAME="notes-app-containers"
REPO_NAME="notes-app"
DB_ID="notes-db"
DB_SG_NAME="notes-db-sg"
DB_USER="admin"
DB_NAME="notes"
PARAM_NAME="/notes-app/db-password"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${1:-notes-app-uploads-$ACCOUNT_ID}"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"

echo "Creating infrastructure in $REGION"
echo

# ---------------------------------------------------------------------------
# 1. The bucket
#
# Uploaded files go here, exactly as they did in the S3 tutorial. Bucket names
# have to be unique across every AWS account in the world, so the default name
# has your account number on the end.
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
# 2. The database password
#
# Generated here and printed at the end. It is not stored anywhere, because
# putting it somewhere the instance can read it safely is part of the tutorial.
#
# RDS rejects several punctuation characters in a master password, so this is
# letters and digits only.
# ---------------------------------------------------------------------------

DB_PASSWORD=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)
DB_EXISTED=no

# ---------------------------------------------------------------------------
# 3. The security groups
#
# Two of them. One for the instance, allowing HTTP from anywhere. One for the
# database, allowing MySQL from the first group and from nowhere else.
#
# The database rule names a security group rather than an address, so it keeps
# working when the instance is replaced and gets a new IP.
# ---------------------------------------------------------------------------

VPC_ID=$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)

find_sg() {
  aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=group-name,Values=$1" "Name=vpc-id,Values=$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || true
}

APP_SG_ID=$(find_sg "$NAME-sg")

if [ -n "$APP_SG_ID" ] && [ "$APP_SG_ID" != "None" ]; then
  echo "Security group $NAME-sg already exists ($APP_SG_ID)"
else
  echo "Creating security group $NAME-sg"

  APP_SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$NAME-sg" \
    --description "Notes app: HTTP in, nothing else" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$APP_SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
fi

DB_SG_ID=$(find_sg "$DB_SG_NAME")

if [ -n "$DB_SG_ID" ] && [ "$DB_SG_ID" != "None" ]; then
  echo "Security group $DB_SG_NAME already exists ($DB_SG_ID)"
else
  echo "Creating security group $DB_SG_NAME"

  DB_SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$DB_SG_NAME" \
    --description "Allows the notes app to reach the database" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)

  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$DB_SG_ID" \
    --protocol tcp --port 3306 --source-group "$APP_SG_ID" >/dev/null
fi

# ---------------------------------------------------------------------------
# 4. The database
#
# The same settings you chose by hand in the RDS tutorial. It is not public,
# so nothing outside the VPC can reach it, including your own laptop.
#
# There is no wait here. Creating it takes several minutes and nothing needs it
# until the instance is launched.
# ---------------------------------------------------------------------------

if aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
  echo "Database $DB_ID already exists"
  DB_EXISTED=yes
else
  echo "Creating database $DB_ID, which takes several minutes"

  aws rds create-db-instance \
    --region "$REGION" \
    --db-instance-identifier "$DB_ID" \
    --db-instance-class db.t4g.micro \
    --engine mysql \
    --master-username "$DB_USER" \
    --master-user-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --allocated-storage 20 \
    --storage-type gp3 \
    --no-publicly-accessible \
    --vpc-security-group-ids "$DB_SG_ID" \
    --backup-retention-period 1 \
    --no-multi-az >/dev/null
fi

# ---------------------------------------------------------------------------
# 5. The IAM role
#
# Four separate permissions, each one scoped to the thing it needs:
#
#   Session Manager   so you can open a shell without SSH
#   S3                read and write the uploads bucket
#   ECR               pull this one repository
#   Parameter Store   read the database password and decrypt it
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

# GetAuthorizationToken is the login step and cannot be limited to one
# repository, because the token it returns is what identifies you to the
# registry. The three actions that read an image are limited to this repository.

echo "Granting $NAME-role permission to pull $REPO_NAME"

aws iam put-role-policy \
  --role-name "$NAME-role" \
  --policy-name NotesAppPullImage \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"LogIntoTheRegistry\",
        \"Effect\": \"Allow\",
        \"Action\": \"ecr:GetAuthorizationToken\",
        \"Resource\": \"*\"
      },
      {
        \"Sid\": \"PullThisRepository\",
        \"Effect\": \"Allow\",
        \"Action\": [
          \"ecr:BatchGetImage\",
          \"ecr:GetDownloadUrlForLayer\",
          \"ecr:BatchCheckLayerAvailability\"
        ],
        \"Resource\": \"arn:aws:ecr:$REGION:$ACCOUNT_ID:repository/$REPO_NAME\"
      }
    ]
  }"

# Reading a SecureString needs two permissions, because Parameter Store hands
# back an encrypted value and KMS is what decrypts it. The condition limits the
# decrypt permission to requests that came through Parameter Store.

echo "Granting $NAME-role permission to read $PARAM_NAME"

aws iam put-role-policy \
  --role-name "$NAME-role" \
  --policy-name NotesAppDatabasePassword \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"ReadThePassword\",
        \"Effect\": \"Allow\",
        \"Action\": \"ssm:GetParameter\",
        \"Resource\": \"arn:aws:ssm:$REGION:$ACCOUNT_ID:parameter$PARAM_NAME\"
      },
      {
        \"Sid\": \"DecryptIt\",
        \"Effect\": \"Allow\",
        \"Action\": \"kms:Decrypt\",
        \"Resource\": \"*\",
        \"Condition\": {
          \"StringEquals\": { \"kms:ViaService\": \"ssm.$REGION.amazonaws.com\" }
        }
      }
    ]
  }"

# An EC2 instance cannot be given a role directly. It is given an "instance
# profile", which is a container holding exactly one role.

if aws iam get-instance-profile --instance-profile-name "$NAME-role" >/dev/null 2>&1; then
  echo "Instance profile $NAME-role already exists"
else
  echo "Creating instance profile $NAME-role"

  aws iam create-instance-profile --instance-profile-name "$NAME-role" >/dev/null
  aws iam add-role-to-instance-profile \
    --instance-profile-name "$NAME-role" \
    --role-name "$NAME-role"
fi

if [ "$DB_EXISTED" = yes ]; then
  PASSWORD_LINE="Password   unchanged, use the one you saved when it was created"
else
  PASSWORD_LINE="Password   $DB_PASSWORD"
fi

cat <<SUMMARY

Done.

  Bucket     $BUCKET
  Database   $DB_ID (still creating)
  $PASSWORD_LINE
  Security   $NAME-sg ($APP_SG_ID), $DB_SG_NAME ($DB_SG_ID)
  Role       $NAME-role
  Registry   $REGISTRY

Keep that password. It is not stored anywhere yet, and this is the only time
it is printed.

There is no repository, no stored password, and no instance. Making those three
is the tutorial.

SUMMARY
