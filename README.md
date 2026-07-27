# releaseward

A self-hosted, AI-assisted CI/CD release pipeline — built hands-on to learn GitHub Actions, self-hosted Kubernetes, and Claude-driven pipeline automation.

## Status

Walking skeleton in progress. The GitHub-hosted path now runs lint/tests, two-pass filesystem security scanning, a hardened Docker build, and two-pass image scanning. Successful `master` pushes publish an immutable commit-SHA image to GHCR; protected deployment from WSL to k3d is the next increment. See `PROJECT_BRIEF.md` for the brief, `ARCHITECTURE.md` for the current design, and `TASKS.md` for verified progress.

![ReleaseWard hybrid CI/CD pipeline and trust boundaries](docs/releaseward-hybrid-pipeline.svg)

## Pipeline behavior

| Event | Execution environment | Result |
|---|---|---|
| Pull request | Disposable GitHub-hosted Ubuntu runner | Lint, tests, filesystem scan, image build, and image scan. No publish and no access to local k3d. |
| Feature-branch push | Disposable GitHub-hosted Ubuntu runner | Same build-and-verify path; no publish. |
| Push to `master` | Disposable GitHub-hosted Ubuntu runner | Runs every gate, then publishes `ghcr.io/<owner>/<repo>:<commit-sha>` and records the registry digest. |
| Trusted deployment *(next task)* | Deployment-only self-hosted runner in WSL Ubuntu | Pulls the verified image, deploys to k3d, and runs rollout/health smoke tests. Pull-request code will not run here. |

Changes use short-lived `feature/*` or `fix/*` branches and a pull request into protected `master`. The runner boundary and rejected alternatives are recorded in `DECISIONS.md`.

## Setup

Prerequisites: WSL2 with an Ubuntu distro, Docker Engine and Node.js installed inside it (not Docker Desktop — see `DECISIONS.md` for why), plus k3d and kubectl for the `k8s/` manifests.

**Important, two WSL2 environment fixes required before running k3d:**
1. Set `vmIdleTimeout=-1` under `[wsl2]` in `%UserProfile%\.wslconfig`, then run `wsl --shutdown` once. Without this, WSL2's default idle-timeout tears down the whole VM (and every container in it) after a period of inactivity.
2. Set Docker's cgroup driver to `cgroupfs` instead of the default `systemd` — create `/etc/docker/daemon.json` inside the WSL distro with `{"exec-opts": ["native.cgroupdriver=cgroupfs"]}`, then `systemctl restart docker`. Without this, the k3d server container crash-loops intermittently (`unable to apply cgroup configuration` / `error creating systemd unit`) — a known fragile interaction between Docker's systemd cgroup driver and nested WSL2 containers.

See `DECISIONS.md` for the full troubleshooting story on both.

```bash
cd app
npm ci
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
- `.github/workflows/ci.yml` — hosted CI, security gates, image build, and master-only GHCR publishing
- `docs/releaseward-hybrid-pipeline.svg` — current pipeline and runner trust-boundary diagram
- `CHEATSHEET.md` — WSL/Docker/k3d/kubectl commands for poking around by hand
- `KNOWN_ISSUES.md` — ongoing environment risks that aren't fully resolved yet (start here if something breaks that isn't in `DECISIONS.md`)
- `PROJECT_BRIEF.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TASKS.md` — living project state (see each file's own header for how it's used)
