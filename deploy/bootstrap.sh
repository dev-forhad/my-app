#!/usr/bin/env bash
# =============================================================================
# my-app — ONE-TIME AWS bootstrap (run this from the repo root, in Git Bash)
#
#   AWS_REGION=us-east-1 GITHUB_REPO=<your-github-username>/<repo> \
#     bash deploy/bootstrap.sh
#
# Creates every AWS resource this project needs (all free-tier friendly):
#   1. S3 bucket            — hosts the React build (served via CloudFront)
#   2. ECR repository       — stores the API Docker images
#   3. GitHub OIDC provider + IAM role — lets GitHub Actions deploy WITHOUT
#      any stored AWS keys (short-lived tokens, scoped to your main branch)
#   4. Elastic Beanstalk roles + application + environment
#                            — runs the .NET API + PostgreSQL containers
#                              on a single t3.micro instance (no load balancer)
#   5. CloudFront           — one HTTPS domain: /* -> React, /api/* -> API
#
# Safe to re-run: existing resources are detected and skipped.
# =============================================================================
set -euo pipefail

# ---- Configuration ----------------------------------------------------------
AWS_REGION="${AWS_REGION:-us-east-1}"
GITHUB_REPO="${GITHUB_REPO:?Set GITHUB_REPO like GITHUB_REPO=yourname/your-repo}"
APP_NAME="${APP_NAME:-my-app}"
# Read a bounded chunk of randomness first, then filter — piping tr directly
# off /dev/urandom leaves it writing forever and dying by SIGPIPE under pipefail.
DB_PASSWORD="${DB_PASSWORD:-$(head -c 96 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 24)}"

EB_APP="$APP_NAME-api"
EB_ENV="$APP_NAME-api-env"
CNAME_PREFIX="$APP_NAME-api"
ECR_REPO="$APP_NAME/api"
DEPLOY_ROLE="$APP_NAME-github-deploy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The AWS CLI on Windows cannot read Git Bash paths like /c/Users/... in
# file:// arguments — convert once to C:/Users/... (mixed) form. On real
# Linux/Mac cygpath doesn't exist and the path is already correct.
SCRIPT_DIR_WIN="$(cygpath -m "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR")"

step() { echo; echo "==> $*"; }

# Zip helper that works on Git Bash/Windows (no zip binary) by borrowing a
# tiny Alpine container from your Docker Desktop.
winpath() { (cd "$1" && pwd -W 2>/dev/null) || (cd "$1" && pwd); }
make_zip() { # make_zip <src-dir> <out-file>
  local src="$1" out="$2" outdir
  outdir="$(dirname "$out")"
  rm -f "$out"
  if command -v zip >/dev/null 2>&1; then
    (cd "$src" && zip -qr "$out" .)
  elif command -v docker >/dev/null 2>&1; then
    echo "    (zipping via Docker alpine image)"
    docker run --rm \
      -v "$(winpath "$src"):/src" \
      -v "$(winpath "$outdir"):/out" \
      alpine:3.20 sh -c "apk add -q zip >/dev/null && cd /src && zip -qr \"/out/$(basename "$out")\" ."
  else
    echo "::error:: no zip tool and Docker not running"; exit 1
  fi
}

# ---- Preflight --------------------------------------------------------------
step "Checking AWS credentials"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "Account: $ACCOUNT   Region: $AWS_REGION"

WEB_BUCKET="$APP_NAME-static-$ACCOUNT"
EB_BUCKET="elasticbeanstalk-$AWS_REGION-$ACCOUNT"

# ---- 1. S3 static-site bucket ------------------------------------------------
step "1/7 S3 bucket for the React build: $WEB_BUCKET"
if ! aws s3api head-bucket --bucket "$WEB_BUCKET" 2>/dev/null; then
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$WEB_BUCKET" >/dev/null
  else
    aws s3api create-bucket --bucket "$WEB_BUCKET" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
  echo "    created"
else
  echo "    already exists"
fi
# Private bucket: nobody reads it directly, only through CloudFront.
aws s3api put-public-access-block --bucket "$WEB_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ---- 2. ECR repository --------------------------------------------------------
step "2/7 ECR repository for API images: $ECR_REPO"
if ! aws ecr describe-repositories --repository-names "$ECR_REPO" >/dev/null 2>&1; then
  aws ecr create-repository --repository-name "$ECR_REPO" >/dev/null
  echo "    created"
else
  echo "    already exists"
fi

# ---- 3. GitHub OIDC + deploy role ---------------------------------------------
step "3/7 GitHub OIDC provider + deploy role (no stored AWS keys)"
OIDC_ARN="arn:aws:iam::$ACCOUNT:oidc-provider/token.actions.githubusercontent.com"
if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  # GitHub rotates certificates; compute thumbprints from the live chain.
  # A stale hard-coded thumbprint makes STS reject every token with a generic
  # "Not authorized to perform sts:AssumeRoleWithWebIdentity".
  echo | openssl s_client -connect token.actions.githubusercontent.com:443 \
    -servername token.actions.githubusercontent.com -showcerts 2>/dev/null \
    | awk '/BEGIN CERT/{n++; f=".ghcert" n ".pem"} /BEGIN CERT/,/END CERT/{print > f}'
  THUMBS=""
  for c in .ghcert*.pem; do
    [ -e "$c" ] || continue
    T=$(openssl x509 -in "$c" -noout -fingerprint -sha1 2>/dev/null | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')
    [ -n "$T" ] && THUMBS="$THUMBS $T"
    rm -f "$c"
  done
  THUMBS="${THUMBS# } 6938fd4d98bab03faadb97b34396831e3780aea1"
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list $THUMBS >/dev/null
  echo "    OIDC provider created (thumbprints: $THUMBS)"
else
  echo "    OIDC provider already exists"
fi

cat > "$SCRIPT_DIR/.gha-trust.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Federated": "$OIDC_ARN" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GITHUB_REPO:*"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": { "Federated": "$OIDC_ARN" },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO%%/*}@*/${GITHUB_REPO##*/}@*:*"
        }
      }
    }
  ]
}
EOF

cat > "$SCRIPT_DIR/.gha-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcrAuth",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "EcrPush",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload",
        "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
        "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "arn:aws:ecr:$AWS_REGION:$ACCOUNT:repository/$ECR_REPO"
    },
    {
      "Sid": "ElasticBeanstalkDeploy",
      "Effect": "Allow",
      "Action": "elasticbeanstalk:*",
      "Resource": "*"
    },
    {
      "Sid": "S3ArtifactsAndStaticSite",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
                 "s3:CreateBucket", "s3:GetBucketLocation",
                 "s3:GetObjectAcl", "s3:PutObjectAcl"],
      "Resource": [
        "arn:aws:s3:::$EB_BUCKET",
        "arn:aws:s3:::$EB_BUCKET/*",
        "arn:aws:s3:::$WEB_BUCKET",
        "arn:aws:s3:::$WEB_BUCKET/*"
      ]
    },
    {
      "Sid": "InvalidateCloudFront",
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "arn:aws:cloudfront::$ACCOUNT:distribution/*"
    },
    {
      "Sid": "PassElasticBeanstalkRoles",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": [
        "arn:aws:iam::$ACCOUNT:role/aws-elasticbeanstalk-ec2-role",
        "arn:aws:iam::$ACCOUNT:role/aws-elasticbeanstalk-service-role"
      ],
      "Condition": {
        "StringEquals": { "iam:PassedToService": "elasticbeanstalk.amazonaws.com" }
      }
    },
    {
      "Sid": "ElasticBeanstalkSupportingServices",
      "Effect": "Allow",
      "Action": [
        "cloudformation:*", "autoscaling:*", "ec2:Describe*",
        "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
        "elasticloadbalancing:*", "cloudwatch:*", "sns:*", "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

if aws iam get-role --role-name "$DEPLOY_ROLE" >/dev/null 2>&1; then
  echo "    deploy role exists — updating trust + policy"
  aws iam update-assume-role-policy --role-name "$DEPLOY_ROLE" \
    --policy-document "file://$SCRIPT_DIR_WIN/.gha-trust.json"
else
  aws iam create-role --role-name "$DEPLOY_ROLE" \
    --assume-role-policy-document "file://$SCRIPT_DIR_WIN/.gha-trust.json" >/dev/null
fi
aws iam put-role-policy --role-name "$DEPLOY_ROLE" \
  --policy-name deploy --policy-document "file://$SCRIPT_DIR_WIN/.gha-policy.json"
rm -f "$SCRIPT_DIR/.gha-trust.json" "$SCRIPT_DIR/.gha-policy.json"
echo "    deploy role ready: $DEPLOY_ROLE"

# ---- 4. Elastic Beanstalk IAM roles --------------------------------------------
step "4/7 Elastic Beanstalk IAM roles (instance + service)"

EC2_ROLE="aws-elasticbeanstalk-ec2-role"
if ! aws iam get-role --role-name "$EC2_ROLE" >/dev/null 2>&1; then
  cat > "$SCRIPT_DIR/.eb-ec2-trust.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{ "Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com" }, "Action": "sts:AssumeRole" }]
}
EOF
  aws iam create-role --role-name "$EC2_ROLE" \
    --assume-role-policy-document file://$SCRIPT_DIR_WIN/.eb-ec2-trust.json >/dev/null
  rm -f "$SCRIPT_DIR/.eb-ec2-trust.json"
  echo "    instance role created"
else
  echo "    instance role already exists"
fi
for policy in AWSElasticBeanstalkWebTier AWSElasticBeanstalkWorkerTier AmazonEC2ContainerRegistryReadOnly; do
  aws iam attach-role-policy --role-name "$EC2_ROLE" \
    --policy-arn "arn:aws:iam::aws:policy/$policy" 2>/dev/null || true
done
# EB reads deployment artifacts from its S3 bucket using legacy ACL calls;
# the managed policies alone can miss s3:GetObjectAcl on that bucket.
cat > "$SCRIPT_DIR/.eb-instance-s3.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "EBArtifactBucketRead",
    "Effect": "Allow",
    "Action": ["s3:ListBucket", "s3:GetObject", "s3:GetObjectAcl", "s3:GetObjectVersion"],
    "Resource": [
      "arn:aws:s3:::elasticbeanstalk-$AWS_REGION-*",
      "arn:aws:s3:::elasticbeanstalk-$AWS_REGION-*/*"
    ]
  }]
}
EOF
aws iam put-role-policy --role-name "$EC2_ROLE" --policy-name eb-artifact-bucket \
  --policy-document "file://$SCRIPT_DIR_WIN/.eb-instance-s3.json" >/dev/null
rm -f "$SCRIPT_DIR/.eb-instance-s3.json"
if ! aws iam get-instance-profile --instance-profile-name "$EC2_ROLE" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$EC2_ROLE" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$EC2_ROLE" \
    --role-name "$EC2_ROLE" || true
  echo "    instance profile created (waiting for IAM propagation...)"
  sleep 15
else
  aws iam add-role-to-instance-profile --instance-profile-name "$EC2_ROLE" \
    --role-name "$EC2_ROLE" 2>/dev/null || true
fi

SERVICE_ROLE="aws-elasticbeanstalk-service-role"
if ! aws iam get-role --role-name "$SERVICE_ROLE" >/dev/null 2>&1; then
  cat > "$SCRIPT_DIR/.eb-svc-trust.json" <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{ "Effect": "Allow", "Principal": { "Service": "elasticbeanstalk.amazonaws.com" }, "Action": "sts:AssumeRole" }]
}
EOF
  aws iam create-role --role-name "$SERVICE_ROLE" \
    --assume-role-policy-document file://$SCRIPT_DIR_WIN/.eb-svc-trust.json >/dev/null
  rm -f "$SCRIPT_DIR/.eb-svc-trust.json"
  for policy in service-role/AWSElasticBeanstalkEnhancedHealth service-role/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy; do
    aws iam attach-role-policy --role-name "$SERVICE_ROLE" \
      --policy-arn "arn:aws:iam::aws:policy/$policy" 2>/dev/null || true
  done
  echo "    service role created"
else
  echo "    service role already exists"
fi

# ---- 5. Elastic Beanstalk application + environment -----------------------------
step "5/7 Elastic Beanstalk application + environment ($EB_ENV, t3.micro, single instance)"

# NOTE: with `--output text`, a missing value prints the literal string "None" —
# so never use grep-based emptiness checks; count results instead.
APP_COUNT=$(aws elasticbeanstalk describe-applications \
  --application-names "$EB_APP" --query "length(Applications)" --output text 2>/dev/null)
if [ "$APP_COUNT" = "0" ]; then
  aws elasticbeanstalk create-application --application-name "$EB_APP" >/dev/null
  echo "    application created"
else
  echo "    application already exists"
fi

ENV_STATUS=$(aws elasticbeanstalk describe-environments --environment-names "$EB_ENV" \
  --query "Environments[0].Status" --output text 2>/dev/null)

# Only skip creation for a live/starting environment. NOTE: a failed creation
# ends in status "Terminated" — the name must be recreated from scratch.
case "$ENV_STATUS" in
  Ready|Launching|Updating)
    echo "    environment already exists (status: $ENV_STATUS) — skipping creation"
    ;;
  *)
  echo "    picking the latest 'Amazon Linux 2023 + Docker' platform..."
  SOLUTION_STACK=$(aws elasticbeanstalk list-available-solution-stacks \
    --query "SolutionStacks[?starts_with(@, '64bit Amazon Linux 2023') && contains(@, 'running Docker')] | [0]" \
    --output text)
  if [ "$SOLUTION_STACK" = "None" ]; then
    echo "::error:: No AL2023 Docker solution stack found"; exit 1
  fi
  echo "    platform: $SOLUTION_STACK"

  # Initial bundle: a placeholder web container + the real PostgreSQL container.
  # The first CI deploy replaces the placeholder with the real API image.
  BUNDLE="$SCRIPT_DIR/.initial-bundle"
  rm -rf "$BUNDLE"; mkdir -p "$BUNDLE/.ebextensions"
  cp "$SCRIPT_DIR/ebextensions/01-ecr-login.config" "$BUNDLE/.ebextensions/"
  cat > "$BUNDLE/docker-compose.yml" <<EOF
services:
  api:
    image: nginx:alpine   # placeholder until the first CI deploy
    ports:
      - "80:80"
    restart: always
  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: \${DB_PASSWORD}
      POSTGRES_DB: appdb
    command: >
      postgres -c shared_buffers=128MB -c max_connections=25
               -c work_mem=4MB -c maintenance_work_mem=32MB -c jit=off
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d appdb"]
      interval: 5s
      timeout: 3s
      retries: 12
    restart: always
volumes:
  pgdata:
EOF
  make_zip "$BUNDLE" "$SCRIPT_DIR/.initial-bundle.zip"
  rm -rf "$BUNDLE"

  aws s3 mb "s3://$EB_BUCKET" --region "$AWS_REGION" 2>/dev/null || true
  # EB uploads artifacts with legacy ACL calls; buckets created since 2023
  # default to ACLs-off ownership, which makes provisioning fail with
  # "The bucket does not allow ACLs". BucketOwnerPreferred re-enables them
  # for owner-only grants while keeping the bucket private.
  aws s3api put-bucket-ownership-controls --bucket "$EB_BUCKET" \
    --ownership-controls "Rules=[{ObjectOwnership=BucketOwnerPreferred}]" 2>/dev/null || true
  aws s3 cp "$SCRIPT_DIR/.initial-bundle.zip" "s3://$EB_BUCKET/initial-$APP_NAME.zip" >/dev/null
  if ! aws elasticbeanstalk create-application-version \
    --application-name "$EB_APP" \
    --version-label v-bootstrap \
    --source-bundle "S3Bucket=$EB_BUCKET,S3Key=initial-$APP_NAME.zip" >/dev/null 2>&1; then
    aws elasticbeanstalk describe-application-versions \
      --application-name "$EB_APP" --version-labels v-bootstrap \
      --query "length(ApplicationVersions)" --output text 2>/dev/null | grep -q '^0$' \
      && { echo "::error:: could not create v-bootstrap application version"; exit 1; }
    echo "    v-bootstrap already exists"
  fi
  rm -f "$SCRIPT_DIR/.initial-bundle.zip"

  echo "    creating environment (takes ~5-10 minutes)..."
  aws elasticbeanstalk create-environment \
    --application-name "$EB_APP" \
    --environment-name "$EB_ENV" \
    --cname-prefix "$CNAME_PREFIX" \
    --solution-stack-name "$SOLUTION_STACK" \
    --version-label v-bootstrap \
    --option-settings \
      "Namespace=aws:autoscaling:launchconfiguration,OptionName=InstanceType,Value=t3.micro" \
      "Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=$EC2_ROLE" \
      "Namespace=aws:elasticbeanstalk:environment,OptionName=EnvironmentType,Value=SingleInstance" \
      "Namespace=aws:elasticbeanstalk:environment,OptionName=ServiceRole,Value=$SERVICE_ROLE" \
      "Namespace=aws:elasticbeanstalk:managedactions,OptionName=ManagedActionsEnabled,Value=false" \
      "Namespace=aws:elasticbeanstalk:healthreporting:system,OptionName=SystemType,Value=enhanced" \
      "Namespace=aws:elasticbeanstalk:application:environment,OptionName=DB_PASSWORD,Value=$DB_PASSWORD" \
    --tags "Key=app,Value=$APP_NAME" >/dev/null

  # Poll status every 20s (up to 15 min) — the built-in waiter gives up at ~7
  # minutes, which is shorter than a cold t3.micro launch can take.
  for i in $(seq 1 45); do
    ST=$(aws elasticbeanstalk describe-environments --environment-names "$EB_ENV" \
      --query "Environments[0].Status" --output text 2>/dev/null)
    [ "$ST" = "Ready" ] && break
    [ "$ST" = "Terminated" ] && break
    sleep 20
  done
  ST=$(aws elasticbeanstalk describe-environments --environment-names "$EB_ENV" \
    --query "Environments[0].Status" --output text 2>/dev/null)
  if [ "$ST" != "Ready" ]; then
    echo "::error:: environment ended in status '$ST' — check events:"
    aws elasticbeanstalk describe-events --environment-name "$EB_ENV" --max-records 5 \
      --query "Events[0:5].[EventDate, Severity, Message]" --output text
    exit 1
  fi
esac

EB_CNAME=$(aws elasticbeanstalk describe-environments --environment-names "$EB_ENV" \
  --query "Environments[0].CNAME" --output text)
EB_HEALTH=$(aws elasticbeanstalk describe-environments --environment-names "$EB_ENV" \
  --query "Environments[0].Health" --output text)
echo "    API URL: http://$EB_CNAME  (health: $EB_HEALTH)"

# ---- 6. CloudFront (S3 + API on one HTTPS domain) --------------------------------
step "6/7 CloudFront distribution (React on /*, API on /api/*)"

OAC_ID=$(aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='$APP_NAME-oac'].Id | [0]" --output text)
if [ "$OAC_ID" = "None" ]; then
  OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config \
    "Name=$APP_NAME-oac,Description=OAC for $WEB_BUCKET,SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
    --query "OriginAccessControl.Id" --output text)
  echo "    origin access control created"
else
  echo "    origin access control already exists"
fi

SSM_PARAM="/$APP_NAME/cloudfront-distribution-id"
# MSYS_NO_PATHCONV stops Git Bash rewriting the leading-slash SSM name into a
# Windows path when calling the native aws.exe.
DIST_ID=$(MSYS_NO_PATHCONV=1 aws ssm get-parameter --name "$SSM_PARAM" --query "Parameter.Value" --output text 2>/dev/null || echo None)
if [ "$DIST_ID" = "None" ]; then
  # Managed policy IDs differ per account — resolve by name, never hard-code.
  POL_CACHE=$(aws cloudfront list-cache-policies --type managed \
    --query "CachePolicyList.Items[?CachePolicy.CachePolicyConfig.Name=='Managed-CachingOptimized'].CachePolicy.Id" --output text)
  POL_NOCACHE=$(aws cloudfront list-cache-policies --type managed \
    --query "CachePolicyList.Items[?CachePolicy.CachePolicyConfig.Name=='Managed-CachingDisabled'].CachePolicy.Id" --output text)
  POL_ORQ=$(aws cloudfront list-origin-request-policies --type managed \
    --query "OriginRequestPolicyList.Items[?OriginRequestPolicy.OriginRequestPolicyConfig.Name=='Managed-AllViewerExceptHostHeader'].OriginRequestPolicy.Id" --output text)
  sed -e "s|__CALLER_REF__|$APP_NAME-$(date +%s)|" \
      -e "s|__WEB_BUCKET__|$WEB_BUCKET|" \
      -e "s|__REGION__|$AWS_REGION|" \
      -e "s|__EB_CNAME__|$EB_CNAME|" \
      -e "s|__OAC_ID__|$OAC_ID|" \
      -e "s|__POL_CACHE__|$POL_CACHE|" \
      -e "s|__POL_NOCACHE__|$POL_NOCACHE|" \
      -e "s|__POL_ORQ__|$POL_ORQ|" \
      "$SCRIPT_DIR/cloudfront-template.json" > "$SCRIPT_DIR/.cf-dist.json"
  DIST_ID=$(aws cloudfront create-distribution \
    --distribution-config "file://$SCRIPT_DIR_WIN/.cf-dist.json" \
    --query "Distribution.Id" --output text)
  rm -f "$SCRIPT_DIR/.cf-dist.json"
  MSYS_NO_PATHCONV=1 aws ssm put-parameter --name "$SSM_PARAM" --value "$DIST_ID" --type String >/dev/null
  echo "    distribution created: $DIST_ID (first deploy takes ~5-10 min)"
else
  echo "    distribution already exists: $DIST_ID"
fi

# Let CloudFront read the private S3 bucket (this is what makes the bucket
# "public to CloudFront only").
cat > "$SCRIPT_DIR/.bucket-policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontOACRead",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$WEB_BUCKET/*",
    "Condition": { "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT:distribution/$DIST_ID" } }
  }]
}
EOF
aws s3api put-bucket-policy --bucket "$WEB_BUCKET" \
  --policy "file://$SCRIPT_DIR_WIN/.bucket-policy.json"
rm -f "$SCRIPT_DIR/.bucket-policy.json"

CF_DOMAIN=$(aws cloudfront get-distribution --id "$DIST_ID" \
  --query "Distribution.DomainName" --output text)

# ---- 7. Done ----------------------------------------------------------------------
step "7/7 Done — summary"
cat <<EOF

    Your site (after first deploy):  https://$CF_DOMAIN
    API (direct):                    http://$EB_CNAME
    API via CloudFront:              https://$CF_DOMAIN/api/items

    NOW add these GitHub repository variables
    (repo -> Settings -> Secrets and variables -> Actions -> Variables tab):

      AWS_REGION                 = $AWS_REGION
      AWS_ROLE_ARN               = arn:aws:iam::$ACCOUNT:role/$DEPLOY_ROLE
      S3_BUCKET                  = $WEB_BUCKET
      CLOUDFRONT_DISTRIBUTION_ID = $DIST_ID
      ECR_REPOSITORY             = $ECR_REPO
      EB_APPLICATION             = $EB_APP
      EB_ENVIRONMENT             = $EB_ENV

    Then trigger the first deploy:
      git commit --allow-empty -m "first deploy" && git push

    Next: set a billing alarm (README, "Cost control").
EOF
