#!/bin/bash
# Simulates OOMKill by dropping memory limit and request below actual usage
NAMESPACE="dev"
DEPLOYMENT="worker-service"

echo "=== Injecting failure: forcing OOMKill on $DEPLOYMENT ==="
kubectl -n $NAMESPACE patch deployment $DEPLOYMENT --type='json' \
  -p='[
    {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"5Mi"},
    {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"10Mi"}
  ]'

echo "Watch pods restart with OOMKilled status:"
echo "kubectl -n $NAMESPACE get pods -w"
