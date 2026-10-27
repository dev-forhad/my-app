#!/usr/bin/env bash
# =============================================================================
# Reset the portfolio admin password (and optionally kill all admin sessions).
#
#   bash deploy/reset-admin-password.sh                  # generate a strong password
#   bash deploy/reset-admin-password.sh "MyNewPass123"   # set a specific one
#   bash deploy/reset-admin-password.sh --logout-all     # also rotate the JWT key,
#                                                        # invalidating every issued
#                                                        # token immediately
#
# Requires: aws CLI configured with access to the Elastic Beanstalk environment.
# The password is stored as an EB environment property — never in the repo.
# =============================================================================
set -euo pipefail

ENV_NAME="${EB_ENVIRONMENT:-my-app-api-env}"
LOGOUT_ALL=false
NEW_PASSWORD=""

for arg in "$@"; do
  case "$arg" in
    --logout-all) LOGOUT_ALL=true ;;
    *) NEW_PASSWORD="$arg" ;;
  esac
done

if [ -z "$NEW_PASSWORD" ]; then
  NEW_PASSWORD=$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 20)
  echo "Generated a new password."
fi

settings=(
  "Namespace=aws:elasticbeanstalk:application:environment,OptionName=ADMIN_PASSWORD,Value=$NEW_PASSWORD"
)

if [ "$LOGOUT_ALL" = "true" ]; then
  JWT_KEY=$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 64)
  settings+=("Namespace=aws:elasticbeanstalk:application:environment,OptionName=JWT_KEY,Value=$JWT_KEY")
  echo "Rotating the JWT key as well — all existing admin sessions become invalid."
fi

echo "Applying new credentials to environment '$ENV_NAME' (takes 1-3 minutes)..."
aws elasticbeanstalk update-environment \
  --environment-name "$ENV_NAME" \
  --option-settings "${settings[@]}" >/dev/null

for i in $(seq 1 20); do
  sleep 30
  STATUS=$(aws elasticbeanstalk describe-environments --environment-names "$ENV_NAME" \
    --query "Environments[0].Status" --output text 2>/dev/null)
  [ "$STATUS" = "Ready" ] && break
  echo "  [$((i * 30))s] $STATUS"
done

if [ "$STATUS" != "Ready" ]; then
  echo "WARNING: environment did not return to Ready — check the EB console."
  exit 1
fi

echo
echo "Done. New admin password: $NEW_PASSWORD"
echo "Store it safely (password manager). It lives as the ADMIN_PASSWORD"
echo "environment property in Elastic Beanstalk."
