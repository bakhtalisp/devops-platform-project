# Postmortem Report: DevOps Platform Project

## Incident 1: Worker Service OOMKilled

### Timeline
- **02:22:37** Memory stress injected inside the worker-service pod (simulating a memory leak) via a `python3` script allocating unbounded memory.
- **02:46:35** Pod exceeded its 128Mi memory limit. Kubernetes killed the container with signal SIGKILL (exit code 137).
- Pod automatically restarted by Kubernetes (RestartPolicy: Always). Service resumed normal operation within seconds.

### Detection
- `kubectl describe pod` showed `Last State: Terminated, Reason: OOMKilled`.
- In a real environment, this would show up as a memory usage spike approaching the limit line in Grafana, followed by a pod restart count increase, and could trigger an Alertmanager rule such as `container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.9`.

### Root Cause
Worker-service was given a memory limit of 128Mi. The simulated workload (memory leak pattern) exceeded this limit, causing Kubernetes' OOM killer to terminate the container to protect the node from memory exhaustion.

### Fix
No code fix was required for the underlying app: the simulated stress was intentional. In a real leak scenario, the fix would be identifying and patching the memory leak in application code.

### Prevention
- Set memory **requests** close to real average usage and **limits** with reasonable headroom, not guessed values.
- Add a Grafana alert for pods nearing their memory limit *before* they get OOMKilled, so the team gets a warning instead of finding out via a crash.
- Use `kubectl top pods` regularly during load testing to validate real memory needs before production.

---

## Incident 2: Bad Deploy Green Version Health Check Failing

### Timeline
- Green version of `api-service` (`v2` image) was deployed with a broken `/health` endpoint intentionally returning HTTP 500 (simulating a bad code deploy).
- Kubernetes readinessProbe detected the failing health check within the configured probe interval.
- New green pod was marked `0/1 Not Ready` and was **never added** to the Service endpoint list.
- Old, healthy green pod continued serving all traffic with zero downtime; zero bad requests reached users.

### Detection
- `kubectl get pods` showed the new pod stuck at `0/1 Ready`, unlike normal pods which show `1/1`.
- In production, this maps to a Grafana panel showing pod readiness count dropping, and an Alertmanager rule like `kube_pod_status_ready == 0` for longer than a threshold (e.g., 2 minutes) would page the on-call engineer.

### Root Cause
A code change to the `/health` endpoint (simulating a bad deploy) caused it to return HTTP 500 instead of 200. The Kubernetes readinessProbe, configured to hit `/health`, correctly identified the pod as not ready to serve traffic.

### Fix
Reverted the `/health` endpoint to return `{"status": "healthy"}, 200`. Rebuilt and reloaded the image, then restarted the deployment. The new pod passed readiness checks and rejoined the Service.

### Prevention
- This incident demonstrates why **readinessProbes are mandatory** for every deployment; they are the last line of defense against bad deploys reaching real users.
- Add a CI step (already have Trivy scan in GitHub Actions M6) that runs a smoke test hitting `/health` before an image is even pushed, catching this earlier than production.
- Blue-green strategy (built in M7) meant this bad deploy caused **zero user-facing impact**; the old version kept serving throughout. This is the core value of blue-green over a rolling update, where a bad pod might briefly receive live traffic.

---

## General Learnings (both incidents)

1. GitOps (ArgoCD) with `selfHeal: true` will revert any manual
