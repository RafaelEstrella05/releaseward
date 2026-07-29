# Known issues

A living list of things to remember and watch out for — distinct from `DECISIONS.md` (a historical log of what was decided and why). This file is about **ongoing risks that haven't been fully eliminated**, so they don't get forgotten once the moment's troubleshooting is over.

---

## k3d server node has residual cgroup fragility inside WSL2 (not fully eliminated)

**Status**: Open / accepted risk, not fully fixed.

**Symptom**: `k3d-releaseward-server-0` occasionally exits with code 128. Two distinct error signatures seen so far:
1. `unable to apply cgroup configuration: ... error creating systemd unit ... got 'failed'` — happened every ~6 minutes before the fix below.
2. `unable to apply cgroup configuration: failed to write ...: device or resource busy` — still happens occasionally *after* the fix below, but much more rarely (~an hour+ between occurrences instead of ~6 minutes).

**Root cause**: Running k3d (Docker running a full Kubernetes node nested inside a container, which itself runs its own nested containerd for pods) inside WSL2 is a Docker-in-Docker setup with an extra layer of cgroup management compared to a normal (non-nested) Docker or Kubernetes install. That extra nesting appears to have some inherent fragility in how WSL2's cgroup v2 hierarchy handles it, that switching Docker's cgroup driver from `systemd` to `cgroupfs` (see `DECISIONS.md`, 2026-07-16) substantially improved but did not fully eliminate.

**Current mitigation — this is why it's an "accept and move on," not a blocker**: both layers of Kubernetes/Docker self-healing already recover from this automatically, with no manual intervention required in most cases:
- Docker's restart policy brings the container back on its own.
- If it doesn't come back on its own, `docker start k3d-releaseward-server-0` does it manually (see `CHEATSHEET.md`).
- Once the node's back, Kubernetes' Deployment controller reschedules the app's pod automatically.

**Why this matters now**: the deployment-only GitHub Actions runner depends on this WSL2 environment. The runner job fails closed if the Kubernetes API or rollout is unavailable. If crashes recur frequently enough to disrupt it, investigate the "device or resource busy" error, try `kind`, or move the runner and cluster to a real Linux VM.

**Revisit when**: a real Actions-triggered deployment fails because the k3d node restarted, or crash frequency increases.

---

## WSL keeps the VM alive but stops the distribution without a foreground process (resolved — historical reference)

**Status**: Resolved by moving the deployment runner off WSL entirely.

**Symptom**: Docker and the k3d containers appear healthy during one WSL command, then `docker.service` is explicitly stopped as soon as the final `wsl.exe` process exits. The WSL kernel boot ID remains unchanged, so this is not the whole WSL2 VM rebooting.

**Root cause**: `vmIdleTimeout=-1` keeps the shared WSL2 virtual machine alive; it does not guarantee that an individual distribution remains active when no Windows-side WSL process is attached. Systemd services alone did not keep this Ubuntu distribution running in the observed setup.

**Former mitigation (WSL runner, decommissioned 2026-07-28)**: ran a foreground `scripts/start-local-runner.sh` in a dedicated WSL terminal to keep the distribution active; the script has since been deleted along with the rest of the WSL runner setup.

**Resolution**: the deployment runner moved to a disposable Hyper-V Ubuntu Server VM (`infra/hyperv-runner/`), where the GitHub Actions runner runs as a real systemd service and survives without any foreground terminal — exactly the "always-on Linux VM" option this issue's original "Revisit when" pointed at. Confirmed via a real `deploy-development` job round-tripping successfully on 2026-07-29 (see `DECISIONS.md`).

---

## Native npm clean installs can fail in the OneDrive-backed checkout

**Status**: Open / mitigated environment constraint.

**Symptom**: Native Windows `npm ci` may fail with `EPERM` while trying to remove an existing package directory under `app/node_modules`. The observed failure involved `acorn-jsx`; the parent OneDrive tree had inherited deny-delete ACL behavior and package directories appeared as reparse-point/placeholders.

**Impact**: This can leave the ignored local `node_modules` directory partially removed. It does not indicate a broken lockfile or application: the same checkout passed `npm ci`, lint, and all seven tests in an isolated non-OneDrive directory, and the Docker build passed in WSL.

**Current mitigation**:

- Treat the disposable GitHub-hosted Ubuntu runner and WSL/Docker build as authoritative.
- Prefer `npm ci` in a non-OneDrive working copy when a truly clean native install is needed.
- Do not weaken CI to `npm install` or suppress a failed test because of this Windows filesystem behavior.
- If the local dependency tree is interrupted, restore it from a clean install and rerun `npm run lint` plus `npm test`.

**Revisit when**: Native Windows dependency work becomes frequent enough to justify moving the active checkout outside OneDrive. The repository itself can remain backed up remotely through Git; it does not need OneDrive synchronization as a second source-control mechanism.
