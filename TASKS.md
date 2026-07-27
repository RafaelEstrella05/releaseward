# Tasks: releaseward

> Backlog of vertical-slice increments. Task #1 is always the walking skeleton. Each task needs a stated Purpose, agreed with the user, before it's added here (Stage 2).

## Format

```
### [ ] Task: [Short name]
- **Purpose**: [What problem this solves / how it serves PROJECT_BRIEF.md]
- **Status**: todo | in-progress | done
- **Notes**: [Filled in when done — what was learned or changed from plan]
```

---

<!-- Entries below this line. Mark done tasks with [x]. -->

### [x] Task: Demo service running locally in Docker
- **Purpose**: Establishes the artifact everything else in the pipeline operates on — nothing can be built, tested, scanned, or shipped until this exists. Node + Express, `readyz`/`livez` health endpoints, structured JSON logging with request IDs, one small feature endpoint, and 1-2 intentional documented security flaws for Trivy to catch later.
- **Status**: done
- **Notes**: Built and verified inside WSL Ubuntu (installed Docker Engine + Node.js natively there, no Docker Desktop — Docker Desktop wasn't installed on Windows, and native Linux install is a cleaner fit for the self-hosted-runner work coming up). Feature endpoint was first built as a generic record classifier (financial/personal/medical categories) then re-themed to a physical-security event triage domain (access-denied, after-hours, tailgating, device-offline, visitor) after review — good reminder to settle the demo's theme before writing the first version, not after. Verified: livez/readyz timing, classify endpoint across all 5 categories, 400 on missing input, structured JSON logs with request IDs and response times, `npm audit` already flags the intentional lodash CVE. Nothing committed to git yet — pending approval.

### [x] Task: k3d cluster up, service deployed manually
- **Purpose**: Learn raw Kubernetes manifests (Deployment, Service, Ingress) and probe semantics by hand, in WSL Ubuntu, before automating any of it via CI.
- **Status**: done
- **Notes**: Installed kubectl + k3d in WSL Ubuntu; cluster uses k3d's bundled Traefik as the ingress controller (no separate ingress-nginx install). Manifests live in `k8s/` (Deployment with liveness/readiness probes wired to `/livez`/`/readyz`, ClusterIP Service, host-based Ingress at `releaseward.localhost`). Local image needs `k3d image import releaseward-demo:dev -c releaseward` since k3d's containerd doesn't see the host Docker daemon's images automatically. Caught and fixed a deprecated `kubernetes.io/ingress.class` annotation in favor of `spec.ingressClassName` while building this.

  Hit two real environment bugs while building this, both in `DECISIONS.md`: (1) WSL2's default idle-timeout was tearing down the whole VM between commands, fixed via `vmIdleTimeout=-1` in `.wslconfig`; (2) even after that, the k3d server container kept crash-looping — first (wrongly) diagnosed as leftover corruption from the VM issue and "fixed" by recreating the cluster, but it recurred identically on a fresh, stable VM. Real cause: Docker's default `systemd` cgroup driver intermittently failed to create the container's cgroup scope via dbus in this nested WSL2 setup — fixed by switching Docker to `native.cgroupdriver=cgroupfs` in `/etc/docker/daemon.json` plus a matching `--kubelet-arg=cgroup-driver=cgroupfs` on the k3d server node. Verified stable for 8+ minutes (past the ~6 minute point where it crashed twice before) with `RestartCount=0`. Good lesson in not trusting the first plausible-looking diagnosis — re-tested against a counterexample instead of declaring victory early.

  Verified end-to-end through the real ingress (health checks + classify), not just port-forwarding to the pod directly.

### [x] Task: GitHub Actions CI — lint + unit test only
- **Purpose**: Smallest possible real Actions workflow (triggers, jobs, secrets) before layering anything else on top.
- **Status**: done
- **Notes**: Added `.github/workflows/ci.yml`: pushes and pull requests run `npm ci`, ESLint, and 7 classifier unit tests on a fresh GitHub-hosted Ubuntu runner with Node 20. Extracted the pure classification logic into `app/classifier.js` so unit tests can import it without starting the Express server; updated the Dockerfile and verified the Node 20 image still builds and starts. The first real Actions run (`95ae30f`, run 29853945890) passed every step in 13 seconds.

  Honest snags: ESLint correctly flagged the deliberately unused fake API key, so it received one documented line-level exception rather than weakening lint rules globally. Two initial tests failed because their input phrases did not match the test expectations; correcting the fixtures—not the working classifier—made all 7 pass. The first WSL push also stalled because WSL Git had no credential helper, fixed by configuring this repository to use the existing Windows Git Credential Manager.

### [x] Task: Trivy security gate in the workflow
- **Purpose**: Add the repo/filesystem scan and (once there's an image) the image scan, so the pipeline actually catches the demo service's intentional flaws — the JD-style security-scanning stage.
- **Status**: done
- **Notes**: Added a two-pass `filesystem-security` job after lint/test using Trivy Action v0.36.0 pinned to its full signed commit SHA. The evidence pass reports all `HIGH`/`CRITICAL` findings; the blocking pass suppresses only the exact intentional IDs in `.trivyignore` and fails on anything new. The real hosted run (`be435ec`, run 30175385058) passed both jobs and showed the expected four lodash findings plus one synthetic-secret finding. A local negative test without the allowlist returned exit code 1, proving the gate actually blocks.

  Honest snags: the original fake `sk-...` value was not detected by current Trivy, so it was replaced with a guaranteed synthetic `releaseward_demo_...` fixture and a project-specific rule rather than imitating a real provider credential. The first scan also exposed three unintentional `HIGH` Kubernetes hardening gaps; these were fixed with a numeric non-root UID, dropped capabilities, disabled privilege escalation, a read-only root filesystem, and the runtime-default seccomp profile. The March 2026 Trivy Actions supply-chain compromise changed the implementation from a version-tag reference to an immutable SHA pin. Image scanning remains for the next Docker build/publish task, when the workflow creates the image artifact.

### [x] Task: Docker build + push to ghcr.io in the workflow
- **Purpose**: Completes the "build and publish artifact" half of the pipeline, tagged by commit SHA.
- **Status**: done
- **Notes**: Added an `image-build` job after the filesystem security gate. GitHub-hosted Ubuntu now builds the Docker image with an immutable `ghcr.io/<owner>/<repo>:<commit-sha>` reference and OCI source/revision labels, then runs two Trivy image passes: full HIGH/CRITICAL evidence followed by a blocking pass that accepts only the exact intentional fixture IDs. Pull requests and feature-branch pushes build and scan but never log in or publish; a successful push to `master` publishes to GHCR and records the returned repository digest in the job summary. This keeps untrusted PR work away from the WSL/k3d machine and leaves the self-hosted runner for the later trusted deployment stage.

  The first strict image scan found real, unintentional HIGH findings in Alpine OpenSSL packages and npm's bundled tools. Those were fixed instead of allowlisted: the Dockerfile is now multi-stage, uses `npm ci --omit=dev`, upgrades the runtime Alpine packages, and removes npm/npx from the final image because the service does not need a package manager at runtime. The hardened image passed the blocking local Trivy scan, both health endpoints passed in the built container, workflow YAML parsed successfully, lint passed, and all seven unit tests passed.

  One local snag was environmental rather than a code failure: native Windows `npm ci` could not replace part of `node_modules` in the OneDrive-backed checkout because of inherited deny-delete/reparse-point behavior. A clean install, lint, and tests passed from an isolated non-OneDrive directory; the ignored dependency folder was restored afterward and lint/tests also passed from the project path with normal host permissions. The authoritative clean build remains the disposable Linux runner/container environment. See `DECISIONS.md` and `KNOWN_ISSUES.md`.

### [ ] Task: Self-hosted runner + automated deploy to k3d + health-check smoke test
- **Purpose**: Closes the loop on the core architectural insight — hosted runners can't reach local k8s, so a protected, deployment-only self-hosted runner (WSL Ubuntu) is required. It must consume the verified GHCR artifact from a trusted `master` run and must never execute pull-request code. This is the "does the pipeline actually ship it" moment.
- **Status**: in progress
- **Notes**: Added a `deploy-development` job that can run only after the hosted image job succeeds on a `master` push. It targets `[self-hosted, linux, x64, releaseward-deploy]`, validates the expected GHCR digest, applies a locally rendered digest-pinned Deployment, records the source revision/digest as annotations, waits for rollout, and checks `/livez` plus `/readyz` through the administrator-created ingress. Pull-request and feature-branch runs cannot schedule this job.

  Created `releaseward-dev` with restricted Pod Security labels and a namespace-only `releaseward-deployer` Role. The dedicated WSL account `releasewardrunner` is not in the Docker group and has a seven-day kubeconfig that can manage only Deployments in that namespace. Service and Ingress changes are one-time administrator operations because Trivy correctly identified runner authority over traffic-routing resources as HIGH risk. GHCR is public, so k3d pulls the digest directly; the runner does not need the Docker socket. The exact published digest `sha256:36c7cf...ffd6` was deployed through the restricted identity, rollout succeeded, and both ingress health checks returned the expected JSON.

  The checksum-verified runner v2.336.0 is now registered as `releaseward-wsl-deploy` with the `releaseward-deploy` label and confirmed online at `Listening for Jobs`. Remaining: merge this feature branch and capture one real Actions-triggered deployment. The foreground runner process intentionally keeps the WSL distribution alive; this corrects the earlier assumption that `vmIdleTimeout=-1` alone kept systemd services running between separate `wsl.exe` invocations.

### [ ] Task: AI-writable candidate branch + ephemeral test image lane
- **Purpose**: Let a bounded coding agent iterate autonomously without confusing an AI-produced candidate with a trusted release artifact. The agent may push only to `ai-test/**`; hosted CI publishes an immutable candidate image for automatic testing in k3d, while human review and trusted promotion remain mandatory before staging or production eligibility.
- **Status**: in-progress
- **Notes**: Candidate images use a distinct `ai-test-<commit-sha>` tag or package namespace, short retention, no deployment credentials, and GitHub-hosted runners only. The AI identity cannot modify protected workflow/policy paths, push to or merge `master`, approve its own PR, or access the WSL deployment runner. Automatic deployment targets a dedicated `releaseward-test` namespace. A candidate digest must not advance directly to staging/production merely because its tests passed; later work must define the reviewed provenance/promotion gate.

  The bot pushes from a dedicated Hyper-V VM (Ubuntu Desktop + VS Code), not WSL — WSL2 mounts the Windows host's drives and is reachable from Windows in the other direction too, so it isn't a clean boundary for code the AI agent writes and executes. The VM runs under a separate GitHub identity (`releaseward-ai-bot`, its own email, its own PAT scoped to `contents`/`pull-requests` on this repo only) with no shared clipboard/drives back to the host (Hyper-V Basic Session mode, Default Switch NAT networking). Enforcement of the `ai-test/**`-only push restriction and the other boundaries above still lives in GitHub branch rulesets/repo settings, not in the VM itself — the VM isolates blast radius on this machine; it isn't what stops the bot from pushing to `master`.

### [ ] Task: Claude Code Action release-summary stage
- **Purpose**: The AI-driven pipeline differentiator — Claude reads the completed run (logs, diff, commits) and posts a plain-English release summary as a PR/commit comment.
- **Status**: todo
- **Notes**:

### [ ] Task: Jira project + Confluence architecture page
- **Purpose**: Real hands-on reps on tools flagged as new, linked from the README as a referenceable artifact.
- **Status**: todo
- **Notes**:

### [ ] Task: README polish
- **Purpose**: Final legibility pass — a stranger should be able to run the whole thing locally in under 15 minutes from the README alone.
- **Status**: todo
- **Notes**:

### [ ] Task: Staging and production environments on isolated Hyper-V VMs
- **Purpose**: Real dev -> staging -> production promotion story, and moves deployment infrastructure off WSL2's shared-kernel/mounted-drive model onto genuinely isolated hosts. Staging and production each get their own headless Ubuntu Server VM (no GUI/VS Code needed — access is SSH/kubectl only, unlike the AI-agent's Ubuntu Desktop VM where interactive coding happens). Existing WSL-based dev k3d/runner setup is left as-is; this adds environments, it does not replace the working one.
- **Status**: todo
- **Notes**: Depends on defining the reviewed provenance/promotion gate flagged in the AI-writable candidate branch task — a candidate that passes ephemeral testing should not skip straight to staging/production without that gate existing first.
