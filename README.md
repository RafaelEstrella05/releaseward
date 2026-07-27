# releaseward

A self-hosted, AI-assisted CI/CD release pipeline — built hands-on to learn GitHub Actions, self-hosted Kubernetes, and Claude-driven pipeline automation.

## Status

Walking skeleton in progress. The hosted path runs lint/tests, two-pass filesystem security scanning, a hardened Docker build, and two-pass image scanning. A successful `master` push publishes an immutable commit-SHA image to GHCR, passes its registry digest to a deployment-only WSL runner, and deploys that exact digest to the `releaseward-dev` namespace in k3d. This full chain has been verified end to end through a real Actions-triggered run on `master` (all four jobs — lint-and-test, filesystem-security, image-build, deploy-development — passing), not just a manual local exercise. Remaining v1 work: the AI release-summary stage, Jira/Confluence tracking, and a final README pass. See `PROJECT_BRIEF.md` for the brief, `ARCHITECTURE.md` for the current design, and `TASKS.md` for verified progress.

![ReleaseWard hybrid CI/CD pipeline and trust boundaries](docs/releaseward-hybrid-pipeline.svg)

## Pipeline behavior

| Event | Execution environment | Result |
|---|---|---|
| Pull request | Disposable GitHub-hosted Ubuntu runner | Lint, tests, filesystem scan, image build, and image scan. No publish and no access to local k3d. |
| Feature-branch push | Disposable GitHub-hosted Ubuntu runner | Same build-and-verify path; no publish. |
| Push to `master` | Hosted runner, then deployment-only WSL runner | Hosted CI runs every gate and publishes `ghcr.io/<owner>/<repo>:<commit-sha>`. The WSL job receives the returned digest, applies only trusted manifests to `releaseward-dev`, and runs rollout plus ingress health checks. |

Changes use short-lived `feature/*` or `fix/*` branches and a pull request into protected `master`. The runner boundary and rejected alternatives are recorded in `DECISIONS.md`.

## Setup

Prerequisites: WSL2 with an Ubuntu distro, Docker Engine and Node.js installed inside it (not Docker Desktop — see `DECISIONS.md` for why), plus k3d and kubectl for the `k8s/` manifests.

**Important, two WSL2 environment fixes required before running k3d:**
1. Set `vmIdleTimeout=-1` under `[wsl2]` in `%UserProfile%\.wslconfig`, then run `wsl --shutdown` once. Without this, WSL2's default idle-timeout tears down the whole VM (and every container in it) after a period of inactivity.
2. Set Docker's cgroup driver to `cgroupfs` instead of the default `systemd` — create `/etc/docker/daemon.json` inside the WSL distro with `{"exec-opts": ["native.cgroupdriver=cgroupfs"]}`, then `systemctl restart docker`. Without this, the k3d server container crash-loops intermittently (`unable to apply cgroup configuration` / `error creating systemd unit`) — a known fragile interaction between Docker's systemd cgroup driver and nested WSL2 containers.

See `DECISIONS.md` for the full troubleshooting story on both.

### Deployment-runner bootstrap

The runner is a separate WSL account named `releasewardrunner`. It is not in the `docker` group and its Kubernetes identity is limited to Deployments in `releaseward-dev`. Service and Ingress changes remain administrator-only bootstrap operations.

On this workstation, the dedicated account and checksum-verified GitHub Actions runner v2.336.0 are already installed under `/home/releasewardrunner/actions-runner`. On a clean machine, create the account first and use the current Linux/x64 download plus checksum commands shown by GitHub's **New self-hosted runner** page.

From the repository root in WSL, bootstrap the namespace and Role with your normal cluster-admin user:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/runner-rbac.yaml
kubectl apply -f k8s/service.yaml -f k8s/ingress.yaml
sudo bash scripts/bootstrap-runner-kubeconfig.sh \
  releasewardrunner "$USER" 168h
```

The last command creates a seven-day credential. Rerun it to rotate the credential before it expires.

In GitHub, open **Settings -> Actions -> Runners -> New self-hosted runner**, select Linux/x64, and use the displayed one-hour registration token from the dedicated account:

```bash
sudo --set-home --user releasewardrunner bash
cd ~/actions-runner
read -rsp 'One-hour registration token: ' RUNNER_TOKEN
echo
./config.sh \
  --url https://github.com/rafaelestrella05/releaseward \
  --token "$RUNNER_TOKEN" \
  --name releaseward-wsl-deploy \
  --labels releaseward-deploy \
  --work _work \
  --unattended
unset RUNNER_TOKEN
exit
```

Do not paste that token into a document, commit, issue, or chat. Start the runner from your normal WSL account and keep that terminal open:

```bash
bash scripts/start-local-runner.sh
```

The foreground process keeps the WSL distribution active. `Ctrl+C` takes the deployment runner offline. The workflow never schedules pull-request jobs on it and k3d pulls the public GHCR image directly by digest, so the runner account does not need Docker-socket access.

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
- `k8s/` — the development namespace, namespace-scoped runner RBAC, and application manifests
- `.github/workflows/ci.yml` — hosted CI/security/build/publish jobs plus the trusted development deployment job
- `scripts/` — limited runner-kubeconfig bootstrap and foreground runner startup helpers
- `docs/releaseward-hybrid-pipeline.svg` — current pipeline and runner trust-boundary diagram
- `CHEATSHEET.md` — WSL/Docker/k3d/kubectl commands for poking around by hand
- `KNOWN_ISSUES.md` — ongoing environment risks that aren't fully resolved yet (start here if something breaks that isn't in `DECISIONS.md`)
- `PROJECT_BRIEF.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TASKS.md` — living project state (see each file's own header for how it's used)
