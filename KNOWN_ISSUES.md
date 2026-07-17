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

**Why this matters more later**: this residual fragility is fine for casual local dev/testing, but it directly matters once the self-hosted GitHub Actions runner (a later task) depends on this same WSL2 environment staying up continuously to pick up CI jobs. If crashes recur frequently enough to disrupt that, this needs real follow-up then — options to consider at that point: investigating the "device or resource busy" error more specifically, trying `kind` instead of `k3d` (also nested, but a different implementation that might not share this exact fragility), or moving the self-hosted runner + cluster to a real Linux VM instead of WSL2 to remove the nesting entirely.

**Revisit when**: the self-hosted runner task (Task 6) is reached, or if crash frequency increases noticeably before then.
