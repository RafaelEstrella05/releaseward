# Architecture: releaseward

> Filled in during Stage 1 (Walking-skeleton design). Update as the architecture evolves — this should reflect current reality, not just the original plan.

**Design walkthrough confirmed**: 2026-07-14 19:18, user-narrated end-to-end.

## Walking Skeleton

![ReleaseWard hybrid CI/CD pipeline and trust boundaries](docs/releaseward-hybrid-pipeline.svg)

```
git push / pull request
  -> disposable GitHub-hosted runner
  -> lint + unit tests (fail fast, cheapest checks)
  -> two-pass Trivy repository/filesystem gate
  -> multi-stage Docker image build, tagged by commit SHA
  -> two-pass Trivy final-image gate
  -> pull request / feature push: stop after verification
  -> master push: publish immutable image to ghcr.io and record its digest
  -> protected self-hosted runner (Hyper-V Ubuntu Server VM) receives that digest
  -> applies trusted manifests to the releaseward-dev namespace
  -> k3d pulls the public image directly by digest
  -> polls rollout, readyz/livez, and ingress smoke checks
  -> Claude Code Action later summarizes trusted pipeline evidence
```

This is the thinnest slice that touches every major component. The hosted build/publish path is implemented and verified: a real `master` push ran lint/test, the two-pass Trivy gates, and image build/publish end to end via GitHub Actions. The self-hosted deployment path was originally verified the same way on a WSL Ubuntu runner (not just a manual local exercise); that runner has since been decommissioned and replaced by a disposable Hyper-V Ubuntu Server VM (`infra/hyperv-runner/`) — registered and online, but not yet exercised by a real Actions-triggered deploy (see `TASKS.md`). AI summarization is planned later in `TASKS.md`. The split is also a security boundary: public pull-request code runs only on fresh hosted infrastructure with no route to the local cluster.

## Components

| Component | Responsibility | Notes |
|---|---|---|
| Demo service | Node + Express REST API with `readyz`/`livez` health endpoints, structured JSON logging (request IDs for traceability), plus a minimal feature (a security-event triage/classify endpoint + light front end, themed around physical-security operations — e.g. access-denied, after-hours entry, tailgating, device-offline, visitor check-in) | Deliberately minimal in scope — the pipeline is the star, not the app. Intentionally includes 1-2 documented security flaws (e.g., a vulnerable dependency version, a hardcoded secret) so the Trivy stage has something real to catch. Feature keeps evolving in small increments once the pipeline exists, to exercise it with real usage rather than staying static |
| GitHub Actions | Orchestrates the whole pipeline: triggers on push/PR, runs jobs in order, gates publishing/deployment on job success | Hosted jobs have explicit timeouts and job-scoped permissions |
| GitHub-hosted runner | Runs lint/test, filesystem scanning, Docker build, and image scanning in a fresh Ubuntu VM | Handles all pull-request code; cannot reach the local k3d network |
| Trivy | Security gate: scans repo/filesystem (deps, secrets, IaC/K8s manifests) and the built container image (vulnerabilities) | Single tool covering dependency scanning, secret detection, and vulnerability assessment |
| ghcr.io | Container registry — stores successful `master` images tagged by commit SHA and addressable by returned digest | Pull requests build and scan but do not authenticate or publish |
| Self-hosted GitHub Actions runner | The WSL runner (`releaseward-wsl-deploy`) has been decommissioned. `releaseward-hyperv-deploy`, on the disposable Hyper-V Ubuntu Server VM provisioned from `infra/hyperv-runner/`, is now the sole registered self-hosted runner (label `releaseward-deploy`) — registered/online as of 2026-07-28 but not yet exercised by a real `deploy-development` job | Dedicated Unix account, trusted `master` push only, no Docker group, seven-day Deployment-only kubeconfig. Cutover from WSL is done on the host side; the task in `TASKS.md` stays in-progress until a real deploy has round-tripped through it — see `DECISIONS.md` (2026-07-28) |
| k3d | Local development Kubernetes, now on the Hyper-V runner VM above (its bootstrap script creates the cluster); the former WSL k3d cluster is retired along with that runner | Runs the app in `releaseward-dev`; its container runtime pulls the public GHCR artifact directly by digest |
| Claude Code Action | Reads the completed pipeline run (logs, diff, commits) and posts a plain-English release summary on the PR/commit | Authenticated via OAuth token off the existing $20/mo Claude Pro subscription — no incremental API billing. Self-healing (auto-fix-and-commit on failure) is a possible later stretch task, not in v1 scope |
| GitHub branch ruleset (`Protect Master`) | Repository-level control forcing every change through the pipeline gates before it reaches `master` | Blocks branch deletion and force-pushes; requires a passing pull request with `lint-and-test`, `filesystem-security`, and `image-build` all green; no actor (including admins) can bypass it. Verified via the GitHub API 2026-07-28 — see DECISIONS.md |
| Jira | Tracks this build's own tasks as real tickets | Free tier |
| Confluence | Hosts one architecture/documentation page for the project | Free tier |

Not yet a pipeline component: the isolated Hyper-V VM (`infra/hyperv-codebot/`) where a bounded AI coding agent authors `ai-test/**` changes is real and running, but the lane around it (candidate-image publishing, automatic `releaseward-test` deployment, the promotion gate) is still paused/undesigned — see "AI-writable candidate branch" in `TASKS.md` rather than treating it as a settled part of this diagram.

## Execution and trust boundaries

| Boundary | Allowed | Explicitly not allowed |
|---|---|---|
| GitHub-hosted CI | Check out PR code; install locked dependencies; lint/test; scan source; build and scan a local image | Reach the Hyper-V runner/k3d; use deployment credentials; publish a PR image |
| `master` publish path | Authenticate to GHCR after every deterministic gate passes; publish the SHA tag; record the digest | Publish from pull requests or feature branches; use a mutable release tag |
| Hyper-V deployment runner | Trigger only after the hosted image job succeeds on a protected `master` push; update the digest-pinned Deployment and smoke-test it | Run PR code; build images; use Docker; alter Services/Ingresses; read secrets/pods/other namespaces; hold cluster-admin credentials |
| `master` branch ruleset | Merge via a reviewed pull request once `lint-and-test`, `filesystem-security`, and `image-build` all pass | Direct push, force-push, or branch deletion on `master`, by anyone, with no bypass |

The self-hosted runner is valuable because it can reach a private local cluster, not because it is a cheaper replacement for hosted CI. Ephemeral Hyper-V runners remain a possible future lab exercise, but are not required for the one-computer v1.

## Data Flow

```
[commit] -> [GitHub Actions: lint/test] -> pass/fail
pass -> [Trivy: two-pass repo scan] -> pass/fail
pass -> [Docker build] -> image
image -> [Trivy: two-pass image scan] -> pass/fail
pass + PR/feature event -> [verified only; no publish]
pass + master push -> [ghcr.io push, tag=commit SHA] -> registry image + digest

registry digest -> [self-hosted runner (Hyper-V Ubuntu Server VM): deploy to k3d] -> running pod
running pod -> [rollout + readyz/livez + ingress poll] -> healthy/unhealthy
running pod -> [structured logs, request IDs] -> traceable per-request output
run metadata (logs, diff, commits) -> [Claude Code Action] -> release summary (PR/commit comment)
```

## Tech Choices & Rationale

| Decision area | Choice | Why (see DECISIONS.md for full discussion) |
|---|---|---|
| CI/CD orchestrator | GitHub Actions | Widely used, deep free-tier support, direct hands-on practice with the tool this project is centered on learning |
| Dev/runner environment | Isolated Hyper-V Ubuntu Server VM (`infra/hyperv-runner/`), not native Windows — replaces the original WSL setup | Linux-native tooling for the self-hosted runner and k3d avoids Windows-specific quirks and matches how these tools are documented/supported upstream; Hyper-V also removes WSL2's shared-kernel/mounted-drive risk for a runner holding deploy authority — see DECISIONS.md (2026-07-28) |
| Demo app language | Node + Express | Ubiquitous in Kubernetes health-check tutorials/patterns; chosen to build breadth beyond the user's primary Python background |
| Local Kubernetes | k3d | Lightweight, fast cluster spin-up, good fit for iterative local dev |
| Runner model | Hybrid: disposable GitHub-hosted CI plus a protected, isolated deployment runner (now Hyper-V) | Hosted runners safely handle PR build/test/scan work; the self-hosted runner is reserved for the one job that requires local k3d reachability |
| Security scanning | Trivy | Single tool covers container vulns + dependency scanning + secrets + IaC/K8s manifest misconfig |
| Container registry | ghcr.io | Free, native GitHub Actions auth, no extra account or rate-limit concerns (vs. Docker Hub) |
| AI pipeline stage | Official `anthropics/claude-code-action`, OAuth token auth | Zero incremental cost (uses existing Claude Pro subscription quota, not pay-per-token API billing); direct hands-on practice with Anthropic's own CI/CD tooling |
| Process tracking | Real free-tier Jira + Confluence | Gives real hands-on reps on tools flagged as new, plus a referenceable artifact |
| Observability | Structured JSON logging + request IDs, plus a Prometheus `/metrics` endpoint (request-duration histogram by method/route/status, a classify-events-by-category counter, and Node default process metrics) and a Prometheus + Grafana deployment in `k8s/observability/` with a starter dashboard (request rate, error rate, p95 latency, classify events by category) | Metrics generation and the app-level `/metrics` endpoint are implemented and verified locally (unit tests, lint, and a live `curl` against a running instance). The Prometheus/Grafana manifests are written and YAML/JSON-validated but **not yet verified against a live k3d cluster** — that requires `kubectl apply` on the Hyper-V runner (WSL is decommissioned); see DECISIONS.md |
| Cloud deployment | Deferred — local k3d is v1; a real free-tier cloud VM (k3s) is an explicit stretch task | Keeps cost at $0 and avoids cloud VM maintenance risk before the core pipeline logic is proven |
