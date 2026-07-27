#!/usr/bin/env bash

set -euo pipefail

cluster="releaseward"
runner_user="releasewardrunner"
runner_home="/home/${runner_user}"

if [[ "${USER}" == "${runner_user}" ]]; then
  echo "Start this script as your normal WSL user so it can check Docker and k3d." >&2
  exit 1
fi

docker info >/dev/null

if ! k3d cluster get "${cluster}" >/dev/null 2>&1; then
  echo "k3d cluster ${cluster} does not exist." >&2
  exit 1
fi

if ! kubectl get nodes --request-timeout=10s >/dev/null 2>&1; then
  echo "Starting k3d cluster ${cluster}..."
  k3d cluster start "${cluster}"
fi

kubectl wait \
  --for=condition=Ready \
  nodes \
  --all \
  --timeout=60s >/dev/null

echo "Starting the deployment-only runner in the foreground."
echo "Keep this terminal open; Ctrl+C takes the runner offline."
exec sudo --set-home --user "${runner_user}" \
  "${runner_home}/actions-runner/run.sh"
