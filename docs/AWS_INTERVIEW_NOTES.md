# AWS Interview Study Notes
### Grounded in a real project: React + .NET API + PostgreSQL, deployed by CI/CD to AWS

> How to use: read section 0 until you can say it without notes. Everything else
> hangs off that story. Interviewers trust answers anchored in a real deploy.

---

## 0. My 30-second project story (memorize this)

> "I built a full web application — React frontend, .NET 8 API, PostgreSQL — and
> deployed it to AWS entirely through a CI/CD pipeline I wrote. GitHub Actions
> builds and tests every push; frontend changes publish to **S3** and serve
> worldwide through **CloudFront**; backend changes build a **Docker** image,
> push it to **ECR**, and roll it out on **Elastic Beanstalk**, which runs it on
> an **EC2** instance. GitHub authenticates to AWS with **OIDC** — no stored
> keys. One HTTPS domain serves everything: CloudFront routes `/api/*` to the
> API and everything else to the website. I also added JWT auth with rate
> limiting, Swagger docs, and I managed costs with budgets — the whole stack
> ran on the AWS free plan."

Every interview answer below is a variation of this story.

---

## 1. COMPUTE — when to use what (the classic question)

| Service | What it really is | Use when | Cost shape |
|---|---|---|---|
| **EC2** | A raw virtual machine you fully control | You need OS access, specific software, long-running steady workloads | Pay per second while running, even idle |
| **ECS (with EC2)** | Docker container orchestrator on YOUR EC2 fleet | Many containers, already have EC2s, want control + density | Pay for the EC2s |
| **ECS (with Fargate)** | Containers WITHOUT managing servers | Containers, but don't want to patch/size servers | Pay per task (vCPU+RAM used) |
| **EKS** | Managed **Kubernetes** | Large orgs, multi-cloud portability, complex orchestration, K8s skills on team | Pay for workers + ~$73/mo control plane |
| **Lambda** | Run a function, AWS runs everything; scales to zero | Event-driven, spiky/short tasks (<15 min), APIs with low traffic | Pay per request + duration; free tier generous |
| **Elastic Beanstalk** | Managed platform that assembles EC2+LB+scaling for you | Classic apps, fast setup, want managed but not locked out | Free service; pay the EC2s underneath |

**The one-liner hierarchy:** EC2 = you manage everything → Fargate = you manage containers → Lambda = you manage code → Beanstalk = AWS assembles, you still see the parts.

**How I answer "why Beanstalk for your project?":**
> "It gave me a managed runtime — health checks, one-command version deploys,
> rollback — without the setup cost of ECS. The tradeoff: a small always-on EC2
> cost (~$10/mo on t3.micro). If traffic were spiky or tiny, I'd rebuild the API
> as Lambda + API Gateway to scale to zero; if the org standardized on
> Kubernetes, the same Docker image would run unchanged on EKS. That's the point
> of containerizing: the compute choice stays swappable."

**Bonus credibility points:** "App Runner also existed for simple containers, but AWS placed it in maintenance mode, so I wouldn't start new work on it."

---

## 2. SERVICES I ACTUALLY USED — what, when, what I did

### S3 (Simple Storage Service)
- **What:** object storage — files ("objects") in buckets, infinite scale, 11-nines durability.
- **Analogy:** a giant hard drive you access by URL.
- **When:** static files, backups, uploads, data lakes — anything you read whole.
- **My use:** hosts my React build. Private bucket; only CloudFront may read it (Origin Access Control). Hashed JS/CSS cached 1 year; `index.html` never cached.
- **Q: S3 vs EBS vs EFS?** S3 = files over HTTP, separate from servers. EBS = a disk attached to ONE EC2. EFS = network disk shared by MANY EC2s.

### CloudFront (CDN)
- **What:** Amazon's edge network — caches content in 100s of cities close to users; TLS termination.
- **Analogy:** a worldwide chain of local shop fronts in front of one warehouse.
- **When:** any public site/app; static + accelerated dynamic (API pass-through).
- **My use:** ONE HTTPS domain. `/*` → S3 (the site), `/api/*` → my API origin. Cache invalidation after each frontend deploy.
- **Q: What happens on deploy then?** "Immutable hashed filenames mean browsers can cache assets forever; I only invalidate `index.html` paths in CloudFront."

### EC2 + EBS
- **What:** EC2 = the VM (CPU/RAM); EBS = its virtual hard disk, survives reboots independently.
- **My use:** t3.micro (2 vCPU burstable, 1 GB RAM) ran both my API and PostgreSQL containers. t3 "burstable" = cheap baseline CPU with burst ability — right size for a demo.
- **Q: What happens when the instance stops?** "EBS volume and its data persist; instance RAM is gone. I proved this the hard way — my DB lived in a Docker volume on EBS, so it survived redeploys but not environment termination."

### Elastic Beanstalk
- **What:** platform manager — provisions EC2 + security groups + health checks + deployment/rollback around your app. You own the resources, AWS turns the cranks.
- **My use:** single-instance environment, Docker Compose platform: my compose file ran TWO containers (API + PostgreSQL) on the one instance. Every deploy = new numbered application version → update-environment → health-checked rollout → one-click rollback.
- **Q: Beanstalk vs CloudFormation vs Terraform?** "Beanstalk = managed *runtime* for apps; CloudFormation/Terraform = IaC for *any* AWS resource. My bootstrap script was the IaC step; Beanstalk was the runtime layer."

### ECR (Elastic Container Registry)
- **What:** private Docker image storage; Beanstalk/ECR pull from it.
- **My use:** every deploy builds one image tagged with the git SHA — immutable artifacts. Rolled back by re-deploying the previous tag.

### IAM + OIDC (the security story — strong interview material)
- **What:** IAM = identity (users/roles) + permissions (policies). Roles = assumable identities with *no long-term keys*.
- **My use:** GitHub Actions assumes an IAM **role** via **OIDC**: GitHub presents a short-lived signed token saying "I'm repo X on branch main"; AWS verifies and grants scoped permissions. Zero stored secrets.
- **Q: user vs role?** "User = permanent identity with keys; role = temporary credentials via assume. Automation should always use roles."
- **Q: least privilege?** "My deploy role could push to exactly one ECR repo, write two S3 buckets, and touch one Beanstalk app — nothing else. It got expanded only when real deploy errors proved each permission necessary."

### Billing/Budgets
- **My use:** free-plan credits, $1 budget alarm, cost ~$0.30/day for one t3.micro, terminate = ~$0/day. "I treat cloud cost as a design constraint: right-size instances, scale to zero where possible, alarm before spend."

---

## 3. STORAGE & DATABASES — quick map

| Need | Service | One line |
|---|---|---|
| Files, static site, backups | **S3** | objects via HTTP, infinite |
| Disk for one server | **EBS** | block device for EC2 |
| Shared disk for many servers | **EFS** | NFS mount, pay per GB |
| Relational DB (SQL) | **RDS** (Postgres/MySQL/...) | managed SQL: backups, patches, HA option |
| Serverless SQL, simple access | **Aurora Serverless / DynamoDB** | Dynamo = NoSQL key-value at any scale, millisecond latency |
| Caching / sessions | **ElastiCache (Redis)** | in-memory, microsecond reads |

**My line:** "I ran PostgreSQL in a container for the demo because cost was zero; for real data I'd move to RDS PostgreSQL — same engine, managed backups and patching — and the app only needs a connection-string change."

---

## 4. NETWORKING — five bullets that cover 80% of questions

1. **VPC** = your private network in AWS; subnets split it: **public** (internet-routable) vs **private** (DBs live here).
2. **Internet Gateway** connects the VPC to the internet; **NAT Gateway** lets private subnets call out without being reachable.
3. **Security Groups** = stateful firewall per instance (allow rules only). **NACLs** = stateless subnet filter. "I used SGs: port 80/443 open, everything else closed."
4. **ALB** (Application Load Balancer) = HTTP-level traffic splitter across targets; needed for multi-instance and blue/green. My demo was single-instance, so none — one of the ways I kept cost near zero.
5. **Route 53** = DNS; points a real domain at CloudFront/ALB with health checks.

---

## 5. MY ACTUAL ARCHITECTURE (draw this)

```
                    git push
                       │
                GitHub Actions (CI: build+test ──▶ CD: deploy)
                 │                    │
       client/** changed      server/** changed
                 │                    │
        npm run build          docker build ──▶ ECR (image: git-sha)
                 │                    │
        aws s3 sync            Beanstalk app version ──▶ update-environment
                 │                    │
                 ▼                    ▼
   ┌──────────────────────── CLOUDFRONT (one HTTPS domain) ───────────────────┐
   │   /*  ──▶ S3 bucket (React build, OAC private)                           │
   │   /api/* ──▶ Elastic Beanstalk EC2 (t3.micro)                            │
   │                 ├─ container: .NET 8 API  (JWT auth, rate limits)        │
   │                 └─ container: PostgreSQL 16                              │
   └───────────────────────────────────────────────────────────────────────────┘
```

**Talking points per arrow:** tests gate deploys · immutable artifacts · path-based deploy triggers · private S3 behind OAC · one domain, no CORS.

---

## 6. WHITEBOARD DESIGN — "TaskFlow", a modern task-manager SaaS

*The question: "Design a simple modern app on AWS." Draw one of these two.*

### Option A — Serverless (cheap, minimal ops) ← lead with this

```
User ──▶ Route53 ──▶ CloudFront ──┬──▶ S3 (React SPA)
                                  └──▶ /api/* ──▶ API Gateway
                                                    │  (JWT check via Cognito)
                                                    ▼
                                              Lambda (API logic)
                                                │        │
                                    DynamoDB (tasks)   SQS (email queue)
                                                          │
                                                    Lambda (worker) ──▶ SES (email)
Observability: CloudWatch logs + alarms.  IaC: SAM/Terraform.  CI/CD: GitHub Actions.
```

| Component | Service | Why in one line |
|---|---|---|
| DNS | Route 53 | domain + health checks |
| Front door | CloudFront | HTTPS, caching, global edge |
| UI hosting | S3 | static SPA, cheapest possible |
| API entry | API Gateway | auth, throttling, no servers |
| Auth | Cognito | managed sign-up/login, JWT out of the box |
| Logic | Lambda | scales to zero; perfect for spiky task APIs |
| Data | DynamoDB | single-table tasks; millisecond, any scale |
| Async work | SQS + Lambda | retries built in; UI never waits on email |
| Email | SES | cheap transactional mail |

**Say:** "Everything scales to zero, so idle cost ≈ $0 — right for unknown or spiky traffic. The tradeoff is cold starts and Dynamo's access patterns."

### Option B — Containerized (my project's pattern, grown up)

```
User ──▶ Route53 ──▶ CloudFront/ALB ──▶ ECS Fargate (API containers, auto-scaled)
                                          │              │
                                    RDS PostgreSQL    ElastiCache Redis
                                          │
                                    S3 (file uploads)
CI/CD: GitHub Actions ──▶ ECR ──▶ ECS rolling deploy.  Secrets: SSM/Secrets Manager.
```

**Say:** "When the team and traffic grow, Fargate gives long-running processes and full container control without server management. Same Docker image from my portfolio project would deploy here unchanged."

**The killer closing line:** "Both designs share the same shape — edge/CDN, stateless API, managed data, async workers, IaC, CI/CD. Choosing between them is a cost-and-team decision, not a rewrite."

---

## 7. RAPID-FIRE Q&A (practice out loud)

1. **S3 durability vs availability?** 11 nines durability (replicated); availability ~99.99% — durability is about not *losing* data, availability about always *reaching* it.
2. **CloudFront invalidation?** Purges edge cache; I invalidate index.html after deploys; hashed assets never need it.
3. **What is a security group?** Stateful per-instance firewall; allow-list only; traffic replies auto-allowed.
4. **Public vs private subnet?** Public has a route to an Internet Gateway; private doesn't — databases belong there.
5. **IAM role vs user?** Role = temporary credentials via assume; user = permanent keys. Automation → roles, always.
6. **How does your CI/CD authenticate to AWS?** OIDC — GitHub presents a short-lived signed token; my IAM role trusts only `repo:me/repo:*`. No stored secrets.
7. **How do you roll back a bad deploy?** Immutable versions: Beanstalk redeploys the previous ECR-tagged version in one click; frontend = revert commit and pipeline republishes.
8. **Horizontal vs vertical scaling?** Vertical = bigger box (limits, downtime); horizontal = more boxes (needs stateless design + ALB). My app is 12-factor stateless — sessions in JWT, data in Postgres — so it can scale horizontally unchanged.
9. **What is a cold start?** Lambda's first-request init delay; mitigations: provisioned concurrency, lighter runtimes. Long-running or latency-critical → containers instead.
10. **How did you keep costs near zero?** Free-plan credits, one burstable micro instance, no load balancer, scale-to-zero option documented, $1 budget alarm, and I terminated everything when the test ended — verified zero running billables.
11. **Monolith vs microservices?** Start modular-monolith; split when teams/scale demand it. My API is one deployable with clean module boundaries — containers make future splits cheap.
12. **Where do secrets live?** Not in git. Demo: EB environment properties + generated keys, injected at deploy. Production-grade: AWS Secrets Manager/SSM with rotation.
13. **What's CDN caching strategy for a SPA?** Hashed immutable assets = cache forever; entry HTML = no-cache; invalidate edge on deploy.
14. **API security layers you implemented?** JWT authn, role authorization, per-IP rate limiting (5 login/min → 429), input validation, HTTPS everywhere, private DB not internet-exposed.
15. **What broke and how did you debug it?** Best story: AWS rejected GitHub's OIDC tokens with a generic "not authorized." Everything looked correct — I pulled GitHub's live certificate chain and found AWS's stored thumbprint was stale after GitHub rotated certs. Taught me: read the actual bytes (CloudTrail, logs, tokens), never debug from assumptions.

---

## 8. GLOSSARY — one-liners

- **Region/AZ:** geographic cluster / independent datacenter inside it. Multi-AZ = high availability.
- **ARN:** Amazon Resource Name — global unique ID for any resource (`arn:aws:s3:::bucket`).
- **IaC:** infrastructure as code — my `bootstrap.sh` (scripted) → CloudFormation/Terraform (declarative).
- **AMI:** server image (snapshot of a configured machine). **Snapshot:** EBS disk backup.
- **ALB/NLB:** layer-7 / layer-4 load balancers.
- **API Gateway:** managed HTTP front door with auth/throttling — Lambda's usual partner.
- **Cognito:** managed user sign-up/sign-in, issues JWTs.
- **CloudWatch:** logs + metrics + alarms. **CloudTrail:** who-did-what audit log (the tool that caught my OIDC bug).
- **SSM:** systems manager — run commands/patch without SSH; also stores secrets (Parameter Store).
- **SES/SNS/SQS:** send email / push notifications / message queues.
- **OAC:** Origin Access Control — lets CloudFront, and only CloudFront, read a private S3 bucket.

---

*Written after building, deploying, securing, cost-managing, and cleanly tearing down this exact stack: Oct 25–28, 2026.*
