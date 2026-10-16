#!/usr/bin/env bash
#
# Builds the notes app, pushes it to a private registry, and runs it on an EC2
# instance, so that the CloudFront tutorial has something to put HTTPS in front
# of.

set -euo pipefail

REGION="eu-west-1"
NAME="notes-app-cloudfront"
PARAM_PATH="/notes-app-cloudfront"

# The Dockerfile and user-data.sh are both next to this script, at the top of
# the repository. They are found from where the script is rather than from
# wherever you ran it.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

if [ ! -f "$SCRIPT_DIR/Dockerfile" ] || [ ! -f "$SCRIPT_DIR/user-data.sh" ]; then
  echo "There is no Dockerfile or user-data.sh in $SCRIPT_DIR." >&2
  echo "This script has to be at the top of the notes app repository." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker isn't running. Start Docker Desktop and run this script again." >&2
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${1:-$NAME-uploads-$ACCOUNT_ID}"
REGISTRY="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
IMAGE="$REGISTRY/$NAME:latest"

echo "Creating infrastructure in $REGION"
echo

# ---------------------------------------------------------------------------
# 1. The bucket
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
    echo "  ./create-infrastructure.sh notes-app-cloudfront-uploads-yourname" >&2
    exit 1
  fi

  aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
fi

# ---------------------------------------------------------------------------
# 2. The repository and the image
# ---------------------------------------------------------------------------

if aws ecr describe-repositories --region "$REGION" --repository-names "$NAME" >/dev/null 2>&1; then
  echo "Repository $NAME already exists"
else
  echo "Creating repository $NAME"

  aws ecr create-repository \
    --region "$REGION" \
    --repository-name "$NAME" >/dev/null
fi

echo "Building the image, which can take a few minutes"

docker build \
  --platform linux/amd64 \
  --target production \
  -t "$IMAGE" \
  "$SCRIPT_DIR"

echo "Pushing the image to $REGISTRY"

aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY" >/dev/null

docker push "$IMAGE"

# ---------------------------------------------------------------------------
# 3. The settings
# ---------------------------------------------------------------------------

echo "Storing the settings under $PARAM_PATH/"

aws ssm put-parameter \
  --region "$REGION" \
  --name "$PARAM_PATH/S3_BUCKET" \
  --type String \
  --value "$BUCKET" \
  --overwrite >/dev/null

aws ssm put-parameter \
  --region "$REGION" \
  --name "$PARAM_PATH/AWS_REGION" \
  --type String \
  --value "$REGION" \
  --overwrite >/dev/null

# ---------------------------------------------------------------------------
# 4. The security group
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
  SG_EXISTED=yes
else
  echo "Creating security group $NAME-sg"

  SG_ID=$(aws ec2 create-security-group \
    --region "$REGION" \
    --group-name "$NAME-sg" \
    --description "Notes app behind CloudFront: HTTP in" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' \
    --output text)
  SG_EXISTED=no
fi

# The rule is only added to a new group. If the group already exists you may
# have replaced this rule with the CloudFront one, and adding it back would
# open the instance to everyone again.

if [ "$SG_EXISTED" = no ]; then
  aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null
fi

# ---------------------------------------------------------------------------
# 5. The IAM role
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
# repository. The three actions that read an image are limited to this one.

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
        \"Resource\": \"arn:aws:ecr:$REGION:$ACCOUNT_ID:repository/$NAME\"
      }
    ]
  }"

# Neither setting is a SecureString, so no kms:Decrypt is needed.

aws iam put-role-policy \
  --role-name "$NAME-role" \
  --policy-name NotesAppConfiguration \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Sid\": \"ReadTheSettings\",
      \"Effect\": \"Allow\",
      \"Action\": [
        \"ssm:GetParameter\",
        \"ssm:GetParameters\",
        \"ssm:GetParametersByPath\"
      ],
      \"Resource\": [
        \"arn:aws:ssm:$REGION:$ACCOUNT_ID:parameter$PARAM_PATH\",
        \"arn:aws:ssm:$REGION:$ACCOUNT_ID:parameter$PARAM_PATH/*\"
      ]
    }]
  }"

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
# 6. The instance
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

PUBLIC_DNS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicDnsName' \
  --output text)

# The instance is running before its user data has finished installing Docker
# and starting the app, which takes another minute or two. Checking here means
# the summary only says the app is up when it is.

echo "Waiting for the app to answer on http://$PUBLIC_DNS"

APP_UP=no
for _ in $(seq 1 36); do
  if curl -fs -o /dev/null --max-time 5 "http://$PUBLIC_DNS/api/notes"; then
    APP_UP=yes
    break
  fi
  sleep 5
done

if [ "$APP_UP" = yes ]; then
  STATUS_LINE="The app is running at http://$PUBLIC_DNS"
else
  STATUS_LINE="The app has not answered yet. If you have already locked the
security group down to CloudFront, that is expected. Otherwise open a
shell with Session Manager and run: sudo cat /var/log/cloud-init-output.log"
fi

cat <<SUMMARY

Done.

  Bucket     $BUCKET
  Image      $IMAGE
  Settings   $PARAM_PATH/S3_BUCKET, $PARAM_PATH/AWS_REGION
  Security   $NAME-sg ($SG_ID)
  Role       $NAME-role
  Instance   $NAME ($INSTANCE_ID)

$STATUS_LINE

There is no Elastic IP and no CloudFront distribution. Making those two is
the tutorial.

SUMMARY
