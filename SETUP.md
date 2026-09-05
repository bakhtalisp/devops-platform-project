# SETUP.md: Run `devops-platform-project` Locally

> Note: tool versions below are **recommended minimums**, not a record of exactly what
> was used originally (that detail wasn't preserved). File paths follow the documented
> repo structure: adjust if your actual filenames differ slightly.

---

## 1. Prerequisites (Tools & Minimum Versions)

| Tool | Minimum Version | Why |
|---|---|---|
| Docker Engine / Docker Desktop | 24.0+ | Builds images, backs Kind nodes |
| kubectl | 1.28+ | Cluster interaction |
| kind | 0.20+ | Local Kubernetes cluster |
| Helm | 3.13+ | Monitoring stack install |
| Terraform | 1.6+ | AWS demo only (provider pinned to `6.62.0` in existing lockfile) |
| ArgoCD CLI | 2.9+ | GitOps sync (optional UI/kubectl also work) |
| AWS CLI | v2 | Only needed for the optional Terraform demo |
| Git | any recent | Clone + commit (ArgoCD source of truth) |

Check versions:
```bash
docker --version
kubectl version --client
kind --version
helm version
terraform --version
argocd version --client
```

---

## 2. Clone the Repo

```bash
git clone https://github.com/bakhtalisp/devops-platform-project.git
cd devops-platform-project
```

---

## 3. Create the Kind Cluster

`kind-config.yaml` (2-node cluster with port mappings, since Kind doesn't expose
ports externally by default):

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: devops-platform
nodes:
  - role: control-plane
  - role: worker
```

```bash
kind create cluster --name devops-platform --config kind-config.yaml
kubectl cluster-info --context kind-devops-platform
kubectl get nodes
```

---

## 4. Namespaces + Network Policies

```bash
kubectl create namespace dev
kubectl create namespace prod
kubectl create namespace monitoring
kubectl create namespace argocd

kubectl apply -f k8s/base/ -n dev
kubectl apply -f k8s/base/ -n prod
```

---

## 5. Secrets (set up BEFORE deploying)

**Grafana admin password:**
```bash
kubectl create secret generic grafana-admin-secret \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<your-password> \
  -n monitoring
```

**AWS credentials (only if running the optional Terraform demo):**
```bash
export AWS_ACCESS_KEY_ID=<your-key>
export AWS_SECRET_ACCESS_KEY=<your-secret>
export AWS_SESSION_TOKEN=<if-using-temporary-borrowed-credentials>
export AWS_DEFAULT_REGION=us-east-1
```
Never commit these. `.gitignore` already covers `*.secret.yaml` and `.env`.

---

## 6. Deploy the Microservices (Kustomize)

```bash
kubectl apply -k k8s/overlays/dev
kubectl get pods -n dev -w
```
Watch for `worker-service`; its initContainer does an `nc` port check against
`api-service`, so it will stay `Init` until `api-service` is `Running`. This is
expected (deploy-order dependency), not a failure.

---

## 7. Install ArgoCD

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-server
```

Get the initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Port-forward and log in (see port table below):
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080 --username admin --password <password> --insecure
```

---

## 8. Apply the ArgoCD Application + Sync

```bash
kubectl apply -f argocd/application.yaml -n argocd
argocd app sync devops-platform
argocd app get devops-platform
```

`selfHeal: true` + auto-prune means ArgoCD will now auto-correct any drift.
**Important:** any `kubectl edit`/`scale` done manually will be reverted unless
it's committed to Git first Git is the source of truth.

---

## 9. Verify Blue-Green Setup

```bash
kubectl get deployments -n dev -l app=api-service
kubectl get svc api-service -n dev -o yaml | grep -A3 selector
```
To switch live traffic from blue → green: change the `version` label in the Service
selector in the manifest, commit, push; ArgoCD picks it up automatically.

---

## 10. Install Monitoring Stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f monitoring/values.yaml

kubectl apply -f monitoring/prometheus-rules/api-service-alerts.yaml -n monitoring
kubectl get svc -n monitoring   # confirm actual service names before port-forwarding
```

---

## 11. Ports & Local Access

Kind clusters aren't reachable externally by default; everything below uses
`kubectl port-forward`. Given the two-terminal-tab / limited RAM constraint,
run these in the background with `&`:

| Service | Namespace | Command | Local URL |
|---|---|---|---|
| ArgoCD UI | argocd | `kubectl port-forward svc/argocd-server -n argocd 8080:443 &` | https://localhost:8080 |
| Grafana | monitoring | `kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80 &` | http://localhost:3000 |
| Prometheus | monitoring | `kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090 &` | http://localhost:9090 |
| Alertmanager | monitoring | `kubectl port-forward svc/kube-prometheus-stack-alertmanager -n monitoring 9093:9093 &` | http://localhost:9093 |
| api-service | dev | `kubectl port-forward svc/api-service -n dev 5000:5000 &` | http://localhost:5000 |

Grafana login: `admin` / the password you set in `grafana-admin-secret`.

---

## 12. Prerequisite Env Vars / Config Files Summary

| Item | Type | Notes |
|---|---|---|
| kubeconfig | auto-managed | `kind create cluster` sets context `kind-devops-platform` automatically |
| `grafana-admin-secret` | K8s Secret | Must be created manually before Helm install (Step 5) not in Git |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` | shell env vars | Only for optional Terraform demo, temporary, never persisted |
| `terraform.tfvars` (if present) | file | Keep out of Git if it holds anything sensitive |
| `.env` / `*.secret.yaml` | files | Already `.gitignore`-excluded |

---

## 13. Optional: AWS Terraform Demo (apply → screenshot → destroy)

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
# take your screenshot here (console + terraform output)
terraform destroy
cd -
```
Note: EKS demo is intentionally skipped (provider version lock conflict: 
constraint `~>5.0` vs. `6.62.0` already locked). VPC/EC2/S3 module is the
proof point; Kind replaces EKS as the actual cluster layer.

---

## 14. Cleanup

```bash
kind delete cluster --name devops-platform
```

## Troubleshooting

- **ArgoCD keeps undoing my change** → you edited live cluster state without
  committing to Git. Commit + push first, then let ArgoCD sync.
- **worker-service stuck in Init** → check that `api-service` is `Running` first;
  the initContainer port-check depends on it.
- **Port-forward dies when you switch terminal tabs** → always background it
  with `&` given the 2-tab WSL constraint; check with `jobs` and `kill %<n>` when done.
