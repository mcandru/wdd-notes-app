#!/usr/bin/env bash
#
# Deletes everything the container tutorial made, including the three things
# create-infrastructure.sh deliberately left for you to make yourself.
#
#   ./destroy-infrastructure.sh [bucket-name] [-y]
#
# It deletes:
#
#   notes-app-containers          any instance tagged with that name
#   notes-db                      the database, with no final snapshot
#   notes-app                     the ECR repository and every image in it
#   notes-app-uploads-<account>   the bucket, and everything in it
#   /notes-app/*                  every parameter under that path
#   notes-db-sg                   the database security group
#   notes-app-containers-sg       the instance security group
#   notes-app-containers-role     the role, its policies, and its profile
#
# Nothing here can be undone, so it asks before it starts. Pass -y to skip the
# question.
#
# The order is forced by what depends on what. The instance has to go before
# the security group it uses and before the role it holds. The database has to
# go before the security group it uses. Deleting either one takes a while, so
# both are started first, the quick deletions happen while they run, and the
# script waits for them at the end.
#
# Safe to run again. Anything already gone is reported and skipped.

set -euo pipefail

REGION="eu-west-1"
NAME="notes-app-containers"
REPO_NAME="notes-app"
DB_ID="notes-db"
DB_SG_NAME="notes-db-sg"
PARAM_PATH="/notes-app/"

SKIP_CONFIRM=no
BUCKET_ARG=""

for arg in "$@"; do
  case "$arg" in
    -y|--yes) SKIP_CONFIRM=yes ;;
    *) BUCKET_ARG="$arg" ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${BUCKET_ARG:-notes-app-uploads-$ACCOUNT_ID}"

echo "This deletes the notes app infrastructure in $REGION, from account $ACCOUNT_ID:"
echo
echo "  The database $DB_ID and its backups"
echo "  Any instance named $NAME"
echo "  The repository $REPO_NAME and every image in it"
echo "  The bucket $BUCKET and everything in it"
echo "  Every parameter under $PARAM_PATH"
echo "  The security groups and the role"
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

# ---------------------------------------------------------------------------
# 1. Start the two slow deletions
#
# Neither of these waits. Terminating an instance takes about a minute and
# deleting a database takes several, so they run while the rest of the script
# works through the quick ones.
# ---------------------------------------------------------------------------

INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=$NAME" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
  echo "Terminating instance $INSTANCE_IDS"
  # shellcheck disable=SC2086
  aws ec2 terminate-instances --region "$REGION" --instance-ids $INSTANCE_IDS >/dev/null
else
  echo "No instance named $NAME is running"
fi

# A database that is already deleting cannot be deleted again, which is what
# the `|| true` covers.

if aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
  echo "Deleting database $DB_ID"

  aws rds delete-db-instance \
    --region "$REGION" \
    --db-instance-identifier "$DB_ID" \
    --skip-final-snapshot \
    --delete-automated-backups >/dev/null 2>&1 || true
else
  echo "Database $DB_ID is already gone"
fi

# ---------------------------------------------------------------------------
# 2. The repository
#
# --force is what allows a repository that still has images in it to go.
# ---------------------------------------------------------------------------

if aws ecr describe-repositories --region "$REGION" --repository-names "$REPO_NAME" >/dev/null 2>&1; then
  echo "Deleting repository $REPO_NAME and its images"
  aws ecr delete-repository --region "$REGION" --repository-name "$REPO_NAME" --force >/dev/null
else
  echo "Repository $REPO_NAME is already gone"
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
# 4. The parameters
#
# Asking for the names rather than listing them means the script keeps working
# if the set of parameters changes.
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
# 5. Wait for the two slow ones
#
# The security groups and the role cannot go until these have finished.
# ---------------------------------------------------------------------------

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
  echo "Waiting for the instance to terminate"
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $INSTANCE_IDS
fi

if aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$DB_ID" >/dev/null 2>&1; then
  echo "Waiting for the database to delete, which takes several minutes"
  aws rds wait db-instance-deleted --region "$REGION" --db-instance-identifier "$DB_ID"
fi

# ---------------------------------------------------------------------------
# 6. The security groups
#
# notes-db-sg goes first, because its rule names notes-app-containers-sg and a
# group cannot be deleted while another group's rule points at it.
# ---------------------------------------------------------------------------

delete_sg() {
  local sg_id
  sg_id=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=group-name,Values=$1" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || true)

  if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
    echo "Deleting security group $1 ($sg_id)"
    aws ec2 delete-security-group --region "$REGION" --group-id "$sg_id" >/dev/null
  else
    echo "Security group $1 is already gone"
  fi
}

delete_sg "$DB_SG_NAME"
delete_sg "$NAME-sg"

# ---------------------------------------------------------------------------
# 7. The role and its instance profile
#
# A role cannot be deleted while anything is still attached to it, so its
# policies come off first and the profile it sits in goes with it. The policy
# names are read back rather than listed here, so renaming one does not leave
# a role behind that will not delete.
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

cat <<SUMMARY

Done. Everything the tutorial created has been deleted.

Your local images are still on your machine. Clear them out with:

  docker system prune -a

SUMMARY
