# DevOps Platform Engineering — GitOps, Blue-Green Deployments & Automated Incident Recovery

**A self-healing, GitOps-driven Kubernetes deployment platform — built solo, end-to-end, and stress-tested through deliberate failure injection with full incident postmortems.**

`Kubernetes` · `ArgoCD` · `Terraform` · `Docker` · `Prometheus` · `Grafana` · `GitHub Actions` · `Trivy` · `GitOps`

🔗 **Repo:** [github.com/bakhtalisp/devops-platform-project](https://github.com/bakhtalisp/devops-platform-project)

---

## Overview

This project implements a production-style GitOps deployment pipeline on Kubernetes — covering CI/CD, blue-green traffic switching, GitOps-based self-healing via ArgoCD, autoscaling, full observability, and Infrastructure as Code — then validates every safety mechanism by deliberately breaking the system and documenting the recovery.

## Key Highlights

- Built and deployed a complete GitOps pipeline using **ArgoCD** with `selfHeal` and auto-prune enabled, enforcing Git as the single source of truth for cluster state.
- Implemented **blue-green deployments** with manual traffic-switch rollback via Service selector changes, backed by Kubernetes readiness probes as an automated safety net.
- Configured **Horizontal Pod Autoscaler (HPA)** for automatic pod scaling based on CPU/memory utilization.
- Designed and provisioned AWS infrastructure (VPC, EC2, S3) using modular **Terraform**, following full apply → verify → destroy discipline to prove IaC competency without incurring ongoing cost.
- Built a full observability stack (**Prometheus, Grafana, Alertmanager**) with custom alerting rules.
- Validated system resilience by injecting two real failure scenarios (OOM crash, failed health check) and authored formal incident postmortems — root cause, timeline, fix, and prevention.
- Automated CI pipeline (**GitHub Actions**) running unit tests and **Trivy** container vulnerability scanning on every push.

---

## Architecture

```
devops-platform-project/
├── docs/                       # requirements, postmortem, architecture + proof screenshots
├── terraform/
│   ├── modules/                # vpc, ec2, s3, security-group
│   └── environments/dev/       # environment-specific config, state
├── k8s/
│   ├── base/                   # deployments, services, network policies
│   └── overlays/dev/           # kustomize overlay tracked by ArgoCD
├── argocd/application.yaml     # GitOps sync definition (selfHeal + auto-prune)
├── .github/workflows/ci.yml    # CI: pytest + Trivy container vulnerability scan
├── monitoring/                 # Prometheus, Grafana, Alertmanager config + custom alert rules
├── scripts/failure-injection/  # chaos scripts used to trigger both incidents below
└── services/
    ├── api-service/            # Flask app, blue + green variants
    └── worker-service/         # background worker, target of OOM incident
```

**Explicit deploy-order dependency:** `worker-service` uses an `initContainer` that runs a port-check (`nc`) against `api-service` before starting, preventing the worker from crash-looping on cold starts before its dependency is reachable.

---

## GitOps — ArgoCD Self-Healing

Deployed ArgoCD with an `Application` manifest (`selfHeal: true`, auto-prune) tracking `k8s/overlays/dev` as the single source of truth.

**Verified in a live drift test:**
- Manually scaled replicas from 1 → 3 directly on the cluster via `kubectl`.
- ArgoCD detected the drift against the Git-declared state and auto-reverted it within its sync interval — with zero manual intervention.
- Confirms Git is enforced as the actual source of truth, not just a dashboard label — any out-of-band change is automatically corrected.

## Blue-Green Deployment

- Ran two parallel Deployments (`api-service` v1 "blue", `api-service-green` v2 "green") behind a single Service, with the Service's label selector controlling live traffic.
- Executed a controlled blue → green traffic switch and a green → blue rollback, both applied through Git commits — never direct cluster changes — to keep ArgoCD's sync guarantees intact.
- Combined with readiness-probe protection, this provides two independent layers of deploy safety: automatic (probe-based) and manual (traffic-switch rollback).

## Incident Response & Postmortems

Stress-tested the platform's safety mechanisms with two deliberate failure injections:

**Incident 1 — OOM Crash (`worker-service`)**
- Injected an unbounded memory-allocation script directly into a running pod.
- Pod hit its 128Mi memory limit → `SIGKILL` → exited with code 137 (OOMKilled).
- Kubernetes' restart policy auto-recovered the pod with zero manual intervention.
- Full root cause and prevention write-up: [`docs/postmortem.md`](docs/postmortem.md)

**Incident 2 — Bad Deploy Caught Before Reaching Users**
- Modified the `/health` endpoint on the green deployment to return HTTP 500 and rolled it out.
- Kubernetes' readiness probe marked the new pod `0/1 NotReady`, keeping it out of the Service's traffic-serving endpoints.
- The existing healthy pod served 100% of traffic throughout — zero downtime, zero manual intervention.

Screenshots: [`failure-1-oom-killed.png`](docs/screenshots/failure-1-oom-killed.png) · [`failure-2-bad-deploy-not-ready.png`](docs/screenshots/failure-2-bad-deploy-not-ready.png)

---

## CI/CD Pipeline

- **GitHub Actions** runs on every push: `pytest` for unit tests, then **Trivy** for container image vulnerability scanning, with the action pinned to a fixed reference for supply-chain stability.
- **ArgoCD** automatically syncs merged changes to the cluster — no manual `kubectl apply` in the deployment path.

## Monitoring & Observability

- **Prometheus** scrapes cluster and application metrics; **Grafana** dashboards visualize them; **Alertmanager** fires on custom rules (`monitoring/custom-alert-rules.yaml`).
- This stack surfaced both incidents above, mirroring how an on-call engineer would first detect a production issue.

## Infrastructure as Code (Terraform)

- Provisioned AWS VPC, EC2, and S3 using modular Terraform (`terraform/modules/`), applied against a live AWS account, verified, then destroyed — a full apply/destroy discipline proving working IaC without ongoing cost.
- Used **Kind** (Kubernetes-in-Docker) for the Kubernetes layer, giving an identical `kubectl`/API surface to a managed cluster — every manifest and ArgoCD config here is portable to a live EKS environment unchanged.
- Screenshots: [`terraform-apply-output.png`](docs/screenshots/terraform-apply-output.png) · [`ec2-console.png`](docs/screenshots/ec2-console.png) · [`s3-console.png`](docs/screenshots/s3-console.png) · [`terraform-destroy-output.png`](docs/screenshots/terraform-destroy-output.png)

---

## What's Next

- Load-test HPA behavior under sustained traffic to validate real-world scaling thresholds.
- Add canary (percentage-based) traffic shifting on top of the current blue-green switch.
- Deploy the same manifests against a live EKS cluster to benchmark against Kind.
