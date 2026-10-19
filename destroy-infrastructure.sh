#!/usr/bin/env bash
#
# Deletes everything create-infrastructure.sh made.
#
#   ./destroy-infrastructure.sh [-y]
#

set -euo pipefail

REGION="eu-west-1"
NAME="notes-app-domain"

SKIP_CONFIRM=no

for arg in "$@"; do
  case "$arg" in
    -y|--yes) SKIP_CONFIRM=yes ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "This deletes the domain names tutorial's infrastructure, from account $ACCOUNT_ID:"
echo
echo "  The CloudFront distribution $NAME"
echo "  Every instance named $NAME or in $NAME-sg, in $REGION"
echo "  The Elastic IP $NAME"
echo "  The security group and the role"
echo
echo "Your hosted zone and your certificate are not deleted."
echo

if [ "$SKIP_CONFIRM" != yes ]; then
  read -r -p "Type yes to continue: " REPLY
  if [ "$REPLY" != "yes" ]; then
    echo "Nothing was deleted."
    exit 0
  fi
  echo
fi

# ---------------------------------------------------------------------------
# 1. The distribution
#
# A distribution has to be disabled, and the change fully deployed, before it
# can be deleted. Each change has to quote the ETag from the step before it,
# which is how CloudFront stops two changes overwriting each other.
# ---------------------------------------------------------------------------

DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='$NAME'].Id | [0]" \
  --output text)

if [ -n "$DIST_ID" ] && [ "$DIST_ID" != "None" ]; then
  DIST_ENABLED=$(aws cloudfront get-distribution \
    --id "$DIST_ID" \
    --query 'Distribution.DistributionConfig.Enabled' \
    --output text)

  if [ "$DIST_ENABLED" = "True" ]; then
    echo "Disabling distribution $DIST_ID"

    CONFIG_FILE=$(mktemp)
    ETAG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query ETag --output text)
    aws cloudfront get-distribution-config \
      --id "$DIST_ID" \
      --query DistributionConfig \
      --output json > "$CONFIG_FILE"

    # Only the top level "Enabled" is indented by exactly four spaces. The
    # nested ones, such as the logging setting, are indented further.
    sed -i.bak 's/^    "Enabled": true/    "Enabled": false/' "$CONFIG_FILE"

    aws cloudfront update-distribution \
      --id "$DIST_ID" \
      --if-match "$ETAG" \
      --distribution-config "file://$CONFIG_FILE" >/dev/null

    rm -f "$CONFIG_FILE" "$CONFIG_FILE.bak"
  fi

  echo "Waiting for $DIST_ID to finish disabling, which can take ten to fifteen minutes"
  aws cloudfront wait distribution-deployed --id "$DIST_ID"

  echo "Deleting distribution $DIST_ID"
  ETAG=$(aws cloudfront get-distribution --id "$DIST_ID" --query ETag --output text)
  aws cloudfront delete-distribution --id "$DIST_ID" --if-match "$ETAG"
else
  echo "Distribution $NAME is already gone"
fi

# ---------------------------------------------------------------------------
# 2. The instances
#
# Found by name and by security group. A replacement launched in the console
# is in the group even if it was given a different name, and the group can't
# be deleted while any instance is still using it.
# ---------------------------------------------------------------------------

SG_ID=$(aws ec2 describe-security-groups \
  --region "$REGION" \
  --filters "Name=group-name,Values=$NAME-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null || true)

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

  echo "Waiting for the instances to terminate"
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $INSTANCE_IDS
else
  echo "No instances to terminate"
fi

# ---------------------------------------------------------------------------
# 3. The Elastic IP
#
# Terminating the instance detached it, and an address that isn't attached to
# anything is still charged.
# ---------------------------------------------------------------------------

ALLOCATION_IDS=$(aws ec2 describe-addresses \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$NAME" \
  --query 'Addresses[].AllocationId' \
  --output text)

if [ -n "$ALLOCATION_IDS" ] && [ "$ALLOCATION_IDS" != "None" ]; then
  for allocation in $ALLOCATION_IDS; do
    echo "Releasing Elastic IP $allocation"
    aws ec2 release-address --region "$REGION" --allocation-id "$allocation"
  done
else
  echo "Elastic IP $NAME is already gone"
fi

# ---------------------------------------------------------------------------
# 4. The security group
# ---------------------------------------------------------------------------

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
  echo "Deleting security group $NAME-sg ($SG_ID)"
  aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" >/dev/null
else
  echo "Security group $NAME-sg is already gone"
fi

# ---------------------------------------------------------------------------
# 5. The role and its instance profile
#
# A role can't be deleted while anything is still attached to it, so its
# policy comes off first and the profile it sits in goes with it.
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

  for arn in $(aws iam list-attached-role-policies --role-name "$NAME-role" --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name "$NAME-role" --policy-arn "$arn"
  done

  aws iam delete-role --role-name "$NAME-role" >/dev/null
else
  echo "Role $NAME-role is already gone"
fi

cat <<SUMMARY

Done. Everything the script created has been deleted.

Your hosted zone is still there. Delete your certificate in Certificate
Manager, in us-east-1, now that the distribution that used it is gone.

SUMMARY
