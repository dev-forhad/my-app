# my-app — React + .NET on AWS with Git-driven CI/CD

A complete, **free-tier-only** setup for learning the modern web app lifecycle:

```
 you ──git push──▶ GitHub ──▶ GitHub Actions (CI/CD)
                                  │  PR: build + test both apps (merge blocked on failure)
                                  │  push to main: deploy
                                  ├─ client/** changed ──▶ React build ─▶ S3 ─▶ CloudFront invalidate
                                  └─ server/** changed ──▶ Docker build ─▶ ECR ─▶ Elastic Beanstalk

 CloudFront (one HTTPS domain, free 1 TB/month):
   /*      → S3 (React build, hashed assets cached 1 year)
   /api/*  → Elastic Beanstalk (.NET API + PostgreSQL containers, t3.micro)
```

| Cost item | Price |
|---|---|
| CloudFront (always-free 1 TB/mo) | $0 |
| GitHub Actions (public repo: unlimited) | $0 |
| S3 + ECR (a few MB) | <$1 |
| Elastic Beanstalk t3.micro instance | ~$8–12/mo, paid from your **$100–200 free credits** |
| PostgreSQL (container on the same instance) | $0 extra |

> You created your AWS account after July 2025, so "free tier" means **credits**: AWS
> gave you $100–200 valid 6 months. The ~$10/mo instance drains credits slowly —
> you will not spend real money unless credits run out. Set the billing alarm below.

## Repo layout

```
client/                     React app (Vite)          ← replace with your real app later
server/                     .NET 8 Web API + xUnit tests  ← replace with your real app later
  Dockerfile                multi-stage build → tiny Alpine runtime image
docker-compose.dev.yml      local dev: PostgreSQL only
deploy/
  bootstrap.sh              ONE-TIME AWS setup (run locally, safe to re-run)
  docker-compose.prod.yml   what runs on the EC2 instance (API + PostgreSQL)
  ebextensions/             per-deploy hook (ECR login on the instance)
  cloudfront-template.json  the CDN configuration
.github/workflows/
  ci.yml                    build + test on every PR and push to main
  deploy-frontend.yml       client/** on main → S3 + CloudFront
  deploy-backend.yml        server/** or deploy/** on main → ECR + Beanstalk
```

## Step 0 — Run it locally (5 minutes)

```bash
docker compose -f docker-compose.dev.yml up -d     # PostgreSQL on :5432

cd server && dotnet run                             # API on http://localhost:8080
cd client && npm install && npm run dev             # UI on http://localhost:5173
```

The Vite dev server proxies `/api/*` to the API, mirroring the production
same-domain setup. Run tests: `cd server && dotnet test`.

## Step 1 — Push to GitHub

Create an empty repo on github.com (Public recommended: free unlimited Actions
minutes), then from this directory:

```bash
git init -b main
git add .
git commit -m "react + .net with ci/cd"
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```

Nothing deploys yet — the deploy workflows pause until Step 4 configures AWS.

## Step 2 — Connect AWS (one time)

```bash
aws configure        # access key + secret from your AWS IAM console, region e.g. us-east-1

cd <repo root>
AWS_REGION=us-east-1 GITHUB_REPO=<you>/<repo> bash deploy/bootstrap.sh
```

`bootstrap.sh` creates everything (S3 bucket, ECR repo, OIDC trust + deploy role,
Beanstalk app + environment with PostgreSQL, CloudFront) and is safe to re-run.
At the end it prints **your site URL** and a list of GitHub variables.

## Step 3 — Add the GitHub variables

Repo → **Settings → Secrets and variables → Actions → Variables tab** → add each
name/value pair printed by bootstrap (`AWS_ROLE_ARN`, `S3_BUCKET`,
`CLOUDFRONT_DISTRIBUTION_ID`, `AWS_REGION`, `ECR_REPOSITORY`, `EB_APPLICATION`,
`EB_ENVIRONMENT`).

This is what lets GitHub Actions deploy via a **short-lived OIDC token** — no AWS
keys are ever stored in GitHub.

## Step 4 — First deploy

```bash
git commit --allow-empty -m "first deploy" && git push
```

Watch both deploy workflows in the **Actions** tab (~5–10 min for Beanstalk),
then open `https://<your-cloudfront-domain>` — the todo app is live, talking to
.NET + PostgreSQL through `/api/*`.

## Step 5 — Billing alarm (2 minutes, protects your credits)

AWS console → **Billing → Budgets → Create budget** → "Zero spend" budget →
alert at $5 to your email. Also glance at **Cost Explorer** weekly.

## The daily lifecycle (what you wanted to learn)

1. **Branch**: `git switch -c feature/dark-mode`
2. **Code + commit**, push, open a **pull request**
3. **CI gate**: `ci.yml` builds + tests client and server; a red X blocks merge
4. **Merge to main** → only the affected deploy workflow runs:
   - frontend changes → S3 sync + cache invalidation (~1 min)
   - backend changes → new ECR image (tagged with the git SHA) → Beanstalk
     rolling deploy with health checks (~5 min) → automatic smoke test
5. **Verify**: the workflow's smoke-test step hits the API; Beanstalk console
   shows health + logs (Request logs → Last 100 lines)

### Rollback drill (do it once, so you know it works)

- **Backend**: Beanstalk console → your environment → **Application versions**
  → pick the previous `v-<sha>` → **Deploy**. (Every deploy is an immutable
  ECR image + version — this is why we tag images with the git SHA.)
- **Frontend**: `git revert <commit> && git push` — the pipeline redeploys the
  old build (or re-run an old successful workflow from the Actions tab).
- **Database caveat**: PostgreSQL data lives on the instance's docker volume.
  It survives redeploys, but terminating/rebuilding the environment wipes it.
  Fine for a test app; see upgrade paths for real persistence.

## Swap in your real app

- **React**: delete `client/src` contents, drop yours in (Vite assumed; for CRA
  only `npm run build` output name matters). Keep API calls **relative**
  (`/api/...`) — CloudFront makes them work in production.
- **.NET**: drop your project files into `server/` (keep the multi-stage
  `Dockerfile`; if your entry project isn't `Api.csproj`, adjust the final
  `ENTRYPOINT ["dotnet", "<YourApp>.dll"]`). Wire your connection string from
  the `ConnectionStrings__DefaultConnection` env var — that's what compose sets.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Deploy workflow: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The OIDC trust is scoped to `repo:<you>/<repo>:ref:refs/heads/main`. Re-run bootstrap with the exact `GITHUB_REPO`, or check the variable values. |
| Beanstalk environment stuck `Degraded` / no containers | EB console → Logs → Last 100 lines. Usually ECR pull or a failing container; check the `/var/log/eb-activity.log` for compose errors. |
| `get-login-password` failures on the instance | The `.ebextensions/01-ecr-login.config` hook logs into ECR; verify `AmazonEC2ContainerRegistryReadOnly` is attached to `aws-elasticbeanstalk-ec2-role` (bootstrap does this). |
| API works direct (`elasticbeanstalk.com`) but not via CloudFront | Wait for the distribution to finish deploying; `/api/*` must route to the EB origin (check the distribution's behaviors). |
| CNAME already taken | Beanstalk names are region-unique; re-run bootstrap with `APP_NAME=something-else`. |
| Frontend updated but browser shows old page | The workflow invalidates CloudFront; if you bypassed CI, run `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"`. |

## Stopping all cost

Done learning for now? `aws elasticbeanstalk terminate-environment --environment-name my-app-api-env`
stops the only billed resource (~$0/day after that; S3/ECR/CloudFront pennies).
Recreate later by re-running bootstrap.

## Upgrade paths (when you outgrow this)

- **Real database**: RDS PostgreSQL (db.t4g.micro, ~$12/mo) or a free managed
  Postgres (Neon/Supabase) — point `ConnectionStrings__DefaultConnection` at it.
- **Staging environment**: clone the EB environment as `*-staging`, add a
  GitHub environment + workflow that deploys there first.
- **Infrastructure as code**: Terraform replaces `bootstrap.sh` (same resources,
  reviewable diffs).
- **Custom domain + HTTPS for the API**: Route 53 + ACM certificate on CloudFront.
- **Blue/green deploys**: Beanstalk supports them natively once you add a load
  balancer (~$16/mo).
