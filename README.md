# releaseward

A self-hosted, AI-assisted CI/CD release pipeline — built hands-on to learn GitHub Actions, self-hosted Kubernetes, and Claude-driven pipeline automation.

## Status

Early development, built iteratively via the `builder` workflow. See `PROJECT_BRIEF.md` for the full brief, `ARCHITECTURE.md` for the design, and `TASKS.md` for current progress.

## Setup

Prerequisites: WSL2 with an Ubuntu distro, Docker Engine and Node.js installed inside it (not Docker Desktop — see `DECISIONS.md` for why), plus k3d and kubectl for the `k8s/` manifests.

**Important, two WSL2 environment fixes required before running k3d:**
1. Set `vmIdleTimeout=-1` under `[wsl2]` in `%UserProfile%\.wslconfig`, then run `wsl --shutdown` once. Without this, WSL2's default idle-timeout tears down the whole VM (and every container in it) after a period of inactivity.
2. Set Docker's cgroup driver to `cgroupfs` instead of the default `systemd` — create `/etc/docker/daemon.json` inside the WSL distro with `{"exec-opts": ["native.cgroupdriver=cgroupfs"]}`, then `systemctl restart docker`. Without this, the k3d server container crash-loops intermittently (`unable to apply cgroup configuration` / `error creating systemd unit`) — a known fragile interaction between Docker's systemd cgroup driver and nested WSL2 containers.

See `DECISIONS.md` for the full troubleshooting story on both.

```bash
cd app
npm install
docker build -t releaseward-demo:dev .
```

## Usage

```bash
docker run -d --name releaseward-demo -p 3000:3000 releaseward-demo:dev

curl http://localhost:3000/livez
# {"status":"alive"}

curl http://localhost:3000/readyz
# {"status":"not ready"}   <- for ~2.5s while it "warms up", then:
# {"status":"ready"}

curl -X POST http://localhost:3000/classify \
  -H 'Content-Type: application/json' \
  -d '{"text":"Badge access denied at rear entrance, after hours, repeated attempts"}'
# {"category":"access_denied","confidence":0.25}
```

Or open `http://localhost:3000/` for a minimal form UI over the same endpoint.

See `app/SECURITY_FLAWS.md` for the two intentional, documented vulnerabilities the pipeline's Trivy stage is meant to catch.

See `CHEATSHEET.md` for the full set of WSL/Docker/k3d/kubectl commands to poke around by hand.

## Project layout

- `app/` — the Node + Express demo service (health endpoints, structured logging, the security-event classify feature, intentional Trivy fixtures)
- `k8s/` — Kubernetes manifests (Deployment, Service, Ingress) for deploying the demo service to k3d
- `CHEATSHEET.md` — WSL/Docker/k3d/kubectl commands for poking around by hand
- `KNOWN_ISSUES.md` — ongoing environment risks that aren't fully resolved yet (start here if something breaks that isn't in `DECISIONS.md`)
- `PROJECT_BRIEF.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TASKS.md` — living project state (see each file's own header for how it's used)
