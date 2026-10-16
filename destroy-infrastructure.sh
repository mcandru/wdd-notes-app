#!/usr/bin/env bash
#
# Deletes everything create-infrastructure.sh made, and any instance you
# launched yourself into its security group.

set -euo pipefail

REGION="eu-west-1"
NAME="notes-app-cloudfront"
PARAM_PATH="/notes-app-cloudfront/"

SKIP_CONFIRM=no
BUCKET_ARG=""

for arg in "$@"; do
  case "$arg" in
    -y|--yes) SKIP_CONFIRM=yes ;;
    *) BUCKET_ARG="$arg" ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${BUCKET_ARG:-$NAME-uploads-$ACCOUNT_ID}"

echo "This deletes the CloudFront tutorial's infrastructure in $REGION, from account $ACCOUNT_ID:"
echo
echo "  Every instance named $NAME or in $NAME-sg"
echo "  The repository $NAME and every image in it"
echo "  The bucket $BUCKET and everything in it"
echo "  Every parameter under $PARAM_PATH"
echo "  The security group and the role"
echo
echo "None of it can be recovered."
echo

if [ "$SKIP_CONFIRM" != yes ]; then
  read -r -p "Type yes to continue: " REPLY
  if [ "$REPLY" != "yes" ]; then
    echo "Nothing was deleted."
    exit 0
  fi
  echo
fi

SG_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=group-name,Values=$NAME-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 1. The instances
#
# Found by name and by security group. A replacement launched in the console
# is in the group even if it was given a different name, and the group can't
# be deleted while any instance is still using it.
# ---------------------------------------------------------------------------

LIVE_STATES="Name=instance-state-name,Values=pending,running,stopping,stopped"

BY_NAME=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$NAME" "$LIVE_STATES" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

BY_GROUP=""
if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  BY_GROUP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=instance.group-id,Values=$SG_ID" "$LIVE_STATES" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)
fi

INSTANCE_IDS=$(echo "$BY_NAME $BY_GROUP" | tr -s ' \t' '\n' | grep -v '^None$' | sort -u | tr '\n' ' ' || true)
INSTANCE_IDS=${INSTANCE_IDS% }

if [ -n "$INSTANCE_IDS" ]; then
  echo "Terminating $INSTANCE_IDS"
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --region "$REGION" --instance-ids $INSTANCE_IDS >/dev/null
else
  echo "No instances to terminate"
fi

# ---------------------------------------------------------------------------
# 2. The repository
#
# --force is what allows a repository that still has images in it to go.
# ---------------------------------------------------------------------------

if aws ecr describe-repositories --region "$REGION" --repository-names "$NAME" >/dev/null 2>&1; then
  echo "Deleting repository $NAME and its images"
  aws ecr delete-repository --region "$REGION" --repository-name "$NAME" --force >/dev/null
else
  echo "Repository $NAME is already gone"
fi

# ---------------------------------------------------------------------------
# 3. The bucket
#
# A bucket has to be empty before it can be deleted.
# ---------------------------------------------------------------------------

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "Emptying and deleting bucket $BUCKET"
  aws s3 rm "s3://$BUCKET" --recursive >/dev/null
  aws s3 rb "s3://$BUCKET" >/dev/null
else
  echo "Bucket $BUCKET is already gone"
fi

# ---------------------------------------------------------------------------
# 4. The settings
# ---------------------------------------------------------------------------

PARAM_NAMES=$(aws ssm get-parameters-by-path \
  --region "$REGION" \
  --path "$PARAM_PATH" \
  --query 'Parameters[].Name' \
  --output text)

if [ -n "$PARAM_NAMES" ] && [ "$PARAM_NAMES" != "None" ]; then
  echo "Deleting parameters under $PARAM_PATH"
  # shellcheck disable=SC2086
  aws ssm delete-parameters --region "$REGION" --names $PARAM_NAMES >/dev/null
else
  echo "No parameters under $PARAM_PATH"
fi

# ---------------------------------------------------------------------------
# 5. The security group
#
# It can't go until every instance using it has finished terminating.
# ---------------------------------------------------------------------------

if [ -n "$INSTANCE_IDS" ]; then
  echo "Waiting for the instances to terminate"
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $INSTANCE_IDS
fi

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "Deleting security group $NAME-sg ($SG_ID)"
  aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" >/dev/null
else
  echo "Security group $NAME-sg is already gone"
fi

# ---------------------------------------------------------------------------
# 6. The role and its instance profile
#
# A role can't be deleted while anything is still attached to it, so its
# policies come off first and the profile it sits in goes with it.
# ---------------------------------------------------------------------------

if aws iam get-instance-profile --instance-profile-name "$NAME-role" >/dev/null 2>&1; then
  echo "Deleting instance profile $NAME-role"

  aws iam remove-role-from-instance-profile \
    --instance-profile-name "$NAME-role" \
    --role-name "$NAME-role" >/dev/null 2>&1 || true

  aws iam delete-instance-profile --instance-profile-name "$NAME-role" >/dev/null
else
  echo "Instance profile $NAME-role is already gone"
fi

if aws iam get-role --role-name "$NAME-role" >/dev/null 2>&1; then
  echo "Deleting role $NAME-role"

  for policy in $(aws iam list-role-policies --role-name "$NAME-role" --query 'PolicyNames[]' --output text); do
    aws iam delete-role-policy --role-name "$NAME-role" --policy-name "$policy"
  done

  for arn in $(aws iam list-attached-role-policies --role-name "$NAME-role" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$NAME-role" --policy-arn "$arn"
  done

  aws iam delete-role --role-name "$NAME-role" >/dev/null
else
  echo "Role $NAME-role is already gone"
fi

# An Elastic IP that isn't attached to anything is still charged, and
# terminating the instance has just detached yours.

LOOSE_IPS=$(aws ec2 describe-addresses \
  --region "$REGION" \
  --query 'Addresses[?AssociationId==null].PublicIp' \
  --output text)

cat <<SUMMARY

Done. Everything the script created has been deleted.

SUMMARY

if [ -n "$LOOSE_IPS" ] && [ "$LOOSE_IPS" != "None" ]; then
  cat <<WARNING
These Elastic IPs are not attached to anything, and are still being charged:

  $LOOSE_IPS

Release them in EC2, Elastic IPs, Actions, Release Elastic IP addresses.

WARNING
fi
