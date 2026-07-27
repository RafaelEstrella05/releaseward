#!/usr/bin/env bash

set -euo pipefail

target_user="${1:-releasewardrunner}"
admin_user="${2:-${SUDO_USER:-}}"
token_duration="${3:-168h}"
namespace="releaseward-dev"
service_account="releaseward-deployer"
context_name="releaseward-development"

generate_config() {
  local runner_config="$1"
  local duration="$2"
  local server
  local ca_data
  local token
  local ca_file

  if [[ -z "${KUBECONFIG:-}" || ! -r "${KUBECONFIG}" ]]; then
    echo "KUBECONFIG must point to a readable cluster-admin kubeconfig." >&2
    exit 1
  fi

  server="$(
    kubectl config view --raw --minify \
      --output jsonpath='{.clusters[0].cluster.server}'
  )"
  ca_data="$(
    kubectl config view --raw --minify \
      --output jsonpath='{.clusters[0].cluster.certificate-authority-data}'
  )"

  if [[ -z "${server}" || -z "${ca_data}" ]]; then
    echo "The current kubeconfig must contain a server and embedded CA data." >&2
    exit 1
  fi

  ca_file="${runner_config}.ca"
  printf '%s' "${ca_data}" | base64 --decode > "${ca_file}"
  token="$(
    kubectl create token "${service_account}" \
      --namespace "${namespace}" \
      --duration "${duration}"
  )"

  kubectl config --kubeconfig "${runner_config}" set-cluster releaseward \
    --server "${server}" \
    --certificate-authority "${ca_file}" \
    --embed-certs=true >/dev/null
  kubectl config --kubeconfig "${runner_config}" set-credentials "${service_account}" \
    --token "${token}" >/dev/null
  kubectl config --kubeconfig "${runner_config}" set-context "${context_name}" \
    --cluster releaseward \
    --namespace "${namespace}" \
    --user "${service_account}" >/dev/null
  kubectl config --kubeconfig "${runner_config}" use-context "${context_name}" >/dev/null
  unset token
  rm -- "${ca_file}"
}

if [[ "${1:-}" == "--generate" ]]; then
  generate_config "$2" "$3"
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script as root and pass the cluster-admin WSL username." >&2
  exit 1
fi

if [[ -z "${admin_user}" ]]; then
  echo "Pass the cluster-admin WSL username as the second argument." >&2
  exit 1
fi

target_home="$(getent passwd "${target_user}" | cut -d: -f6)"
admin_home="$(getent passwd "${admin_user}" | cut -d: -f6)"
if [[ -z "${target_home}" ]]; then
  echo "Unknown runner account: ${target_user}" >&2
  exit 1
fi
if [[ -z "${admin_home}" ]]; then
  echo "Unknown cluster-admin account: ${admin_user}" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT
chown "${admin_user}:${admin_user}" "${work_dir}"

runner_config="${work_dir}/config"
runuser --user "${admin_user}" -- \
  env KUBECONFIG="${admin_home}/.kube/config" \
  bash "$0" --generate "${runner_config}" "${token_duration}"

install --directory --mode 700 --owner "${target_user}" --group "${target_user}" \
  "${target_home}/.kube"
install --mode 600 --owner "${target_user}" --group "${target_user}" \
  "${runner_config}" "${target_home}/.kube/config"

runuser --user "${target_user}" -- \
  kubectl auth can-i patch deployments.apps --namespace "${namespace}" |
  grep --fixed-strings --line-regexp yes >/dev/null

if runuser --user "${target_user}" -- \
  kubectl auth can-i get namespaces 2>/dev/null |
  grep --fixed-strings --line-regexp yes >/dev/null; then
  echo "Runner unexpectedly has cluster-scoped namespace read access." >&2
  exit 1
fi

for permission in \
  "patch services" \
  "patch ingresses.networking.k8s.io" \
  "get secrets"; do
  read -r verb resource <<< "${permission}"
  if runuser --user "${target_user}" -- \
    kubectl auth can-i "${verb}" "${resource}" --namespace "${namespace}" |
    grep --fixed-strings --line-regexp yes >/dev/null; then
    echo "Runner unexpectedly has ${verb} access to ${resource}." >&2
    exit 1
  fi
done

echo "Installed a ${token_duration} kubeconfig for ${target_user}."
echo "Access is limited to Deployments in ${namespace}."
