#!/usr/bin/env bash
# Run once after first boot of a VM installed from autoinstall.yaml, as the
# opsadmin admin user (uses sudo internally where needed). Installs kubectl,
# k3d, and the GitHub Actions runner, then hands off to the existing
# scripts/bootstrap-runner-kubeconfig.sh for the deploy-only kubeconfig.
#
# Network-touching steps (package/binary downloads) live here rather than in
# autoinstall's late-commands, which run inside an install-time chroot where
# snapd/dbus aren't reliably usable and a failed step is harder to retry.
#
# Usage: bash bootstrap-post-install.sh <github-runner-registration-token>
set -euo pipefail

k3d_version="v5.7.4"
runner_version="2.336.0"
runner_user="releasewardrunner"
cluster="releaseward"
repo_url="${RELEASEWARD_REPO_URL:?Set RELEASEWARD_REPO_URL to this repository https clone URL}"
registration_token="${1:?Pass the GitHub self-hosted runner registration token as the first argument}"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this as opsadmin (it sudos internally), not as root." >&2
  exit 1
fi

echo "== ufw: allow SSH only =="
sudo ufw allow OpenSSH
sudo ufw --force enable

echo "== kubectl (snap) =="
sudo snap install kubectl --classic

echo "== k3d ${k3d_version}, checksum-verified against the release's own SHA256SUMS =="
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "${tmp_dir}"' EXIT
chmod 711 "${tmp_dir}"
curl -fsSL -o "${tmp_dir}/k3d" \
  "https://github.com/k3d-io/k3d/releases/download/${k3d_version}/k3d-linux-amd64"
curl -fsSL -o "${tmp_dir}/checksums.txt" \
  "https://github.com/k3d-io/k3d/releases/download/${k3d_version}/checksums.txt"
expected="$(grep 'k3d-linux-amd64$' "${tmp_dir}/checksums.txt" | awk '{print $1}')"
actual="$(sha256sum "${tmp_dir}/k3d" | awk '{print $1}')"
if [[ -z "${expected}" || "${expected}" != "${actual}" ]]; then
  echo "k3d checksum mismatch: expected ${expected:-<none>}, got ${actual}" >&2
  exit 1
fi
sudo install -m 0755 "${tmp_dir}/k3d" /usr/local/bin/k3d

echo "== k3d cluster '${cluster}' =="
if ! k3d cluster get "${cluster}" >/dev/null 2>&1; then
  k3d cluster create "${cluster}" --port '8080:80@loadbalancer' --wait
fi
mkdir -p ~/.kube
k3d kubeconfig get "${cluster}" > ~/.kube/config
chmod 600 ~/.kube/config

echo "== repo checkout (manifests only) =="
if [[ ! -d ~/releaseward ]]; then
  git clone --depth 1 "${repo_url}" ~/releaseward
fi
kubectl apply -f ~/releaseward/k8s/namespace.yaml
kubectl apply -f ~/releaseward/k8s/runner-rbac.yaml
kubectl apply -f ~/releaseward/k8s/service.yaml -f ~/releaseward/k8s/ingress.yaml

echo "== GitHub Actions runner ${runner_version}, checksum from the release download page =="
runner_tarball="actions-runner-linux-x64-${runner_version}.tar.gz"
sudo -u "${runner_user}" mkdir -p "/home/${runner_user}/actions-runner"
curl -fsSL -o "${tmp_dir}/${runner_tarball}" \
  "https://github.com/actions/runner/releases/download/v${runner_version}/${runner_tarball}"
echo "Verify this against the sha256 shown on the runner's GitHub release page" \
  "for v${runner_version} before continuing:"
sha256sum "${tmp_dir}/${runner_tarball}"
read -r -p "Checksum matches the release page? [y/N] " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Aborting — checksum not confirmed." >&2
  exit 1
fi
sudo -u "${runner_user}" tar xzf "${tmp_dir}/${runner_tarball}" \
  -C "/home/${runner_user}/actions-runner"

sudo -u "${runner_user}" \
  "/home/${runner_user}/actions-runner/config.sh" \
  --unattended \
  --url "${repo_url}" \
  --token "${registration_token}" \
  --name "releaseward-hyperv-deploy" \
  --labels "releaseward-deploy" \
  --work "_work"

sudo "/home/${runner_user}/actions-runner/svc.sh" install "${runner_user}"
sudo "/home/${runner_user}/actions-runner/svc.sh" start

echo "== Deploy-only kubeconfig for ${runner_user} =="
sudo KUBECONFIG=~/.kube/config bash ~/releaseward/scripts/bootstrap-runner-kubeconfig.sh \
  "${runner_user}" "${USER}" 168h

echo "Done. Runner is registered as a systemd service (releaseward-deploy label)"
echo "and will survive reboots without a foreground terminal. Rotate its"
echo "kubeconfig by rerunning scripts/bootstrap-runner-kubeconfig.sh every 7 days."
