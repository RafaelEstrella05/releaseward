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

planned next:
  -> protected self-hosted runner (WSL Ubuntu) pulls the verified image
  -> deploys it to k3d without executing pull-request code
  -> polls rollout, readyz/livez, and ingress smoke checks
  -> Claude Code Action later summarizes trusted pipeline evidence
```

This is the thinnest slice that touches every major component. The hosted build-and-publish path is implemented; deployment and AI summarization remain planned tasks in `TASKS.md`. The split is also a security boundary: public pull-request code runs only on fresh hosted infrastructure with no route to the laptop's cluster.

## Components

| Component | Responsibility | Notes |
|---|---|---|
| Demo service | Node + Express REST API with `readyz`/`livez` health endpoints, structured JSON logging (request IDs for traceability), plus a minimal feature (a security-event triage/classify endpoint + light front end, themed around physical-security operations — e.g. access-denied, after-hours entry, tailgating, device-offline, visitor check-in) | Deliberately minimal in scope — the pipeline is the star, not the app. Intentionally includes 1-2 documented security flaws (e.g., a vulnerable dependency version, a hardcoded secret) so the Trivy stage has something real to catch. Feature keeps evolving in small increments once the pipeline exists, to exercise it with real usage rather than staying static |
| GitHub Actions | Orchestrates the whole pipeline: triggers on push/PR, runs jobs in order, gates publishing/deployment on job success | Hosted jobs have explicit timeouts and job-scoped permissions |
| GitHub-hosted runner | Runs lint/test, filesystem scanning, Docker build, and image scanning in a fresh Ubuntu VM | Handles all pull-request code; cannot reach the local k3d network |
| Trivy | Security gate: scans repo/filesystem (deps, secrets, IaC/K8s manifests) and the built container image (vulnerabilities) | Single tool covering dependency scanning, secret detection, and vulnerability assessment |
| ghcr.io | Container registry — stores successful `master` images tagged by commit SHA and addressable by returned digest | Pull requests build and scan but do not authenticate or publish |
| Self-hosted GitHub Actions runner *(planned next)* | Runs inside WSL Ubuntu so the deploy step can reach the local k3d cluster | Deployment-only trusted zone: restricted refs/labels, no pull-request code, no general CI |
| k3d | Local self-hosted Kubernetes (running inside WSL Ubuntu) — orchestrates the demo service's container(s) | Lightweight, fast cluster spin-up, well suited to iterative local dev work |
| Claude Code Action | Reads the completed pipeline run (logs, diff, commits) and posts a plain-English release summary on the PR/commit | Authenticated via OAuth token off the existing $20/mo Claude Pro subscription — no incremental API billing. Self-healing (auto-fix-and-commit on failure) is a possible later stretch task, not in v1 scope |
| Jira | Tracks this build's own tasks as real tickets | Free tier |
| Confluence | Hosts one architecture/documentation page for the project | Free tier |

## Execution and trust boundaries

| Boundary | Allowed | Explicitly not allowed |
|---|---|---|
| GitHub-hosted CI | Check out PR code; install locked dependencies; lint/test; scan source; build and scan a local image | Reach WSL/k3d; use deployment credentials; publish a PR image |
| `master` publish path | Authenticate to GHCR after every deterministic gate passes; publish the SHA tag; record the digest | Publish from pull requests or feature branches; use a mutable release tag |
| WSL deployment runner *(planned)* | Trigger from a trusted protected-branch workflow; pull the verified registry artifact; deploy and smoke-test k3d | Run arbitrary PR code; perform general-purpose builds; expose cluster-admin access to AI analysis |

The self-hosted runner is valuable because it can reach a private local cluster, not because it is a cheaper replacement for hosted CI. Ephemeral Hyper-V runners remain a possible future lab exercise, but are not required for the one-computer v1.

## Data Flow

```
[commit] -> [GitHub Actions: lint/test] -> pass/fail
pass -> [Trivy: two-pass repo scan] -> pass/fail
pass -> [Docker build] -> image
image -> [Trivy: two-pass image scan] -> pass/fail
pass + PR/feature event -> [verified only; no publish]
pass + master push -> [ghcr.io push, tag=commit SHA] -> registry image + digest

planned:
registry digest -> [self-hosted runner (WSL Ubuntu): deploy to k3d] -> running pod
running pod -> [rollout + readyz/livez + ingress poll] -> healthy/unhealthy
running pod -> [structured logs, request IDs] -> traceable per-request output
run metadata (logs, diff, commits) -> [Claude Code Action] -> release summary (PR/commit comment)
```

## Tech Choices & Rationale

| Decision area | Choice | Why (see DECISIONS.md for full discussion) |
|---|---|---|
| CI/CD orchestrator | GitHub Actions | Widely used, deep free-tier support, direct hands-on practice with the tool this project is centered on learning |
| Dev/runner environment | WSL (Ubuntu), strictly — not native Windows | Linux-native tooling for the self-hosted runner and k3d avoids Windows-specific quirks and matches how these tools are documented/supported upstream |
| Demo app language | Node + Express | Ubiquitous in Kubernetes health-check tutorials/patterns; chosen to build breadth beyond the user's primary Python background |
| Local Kubernetes | k3d | Lightweight, fast cluster spin-up, good fit for iterative local dev |
| Runner model | Hybrid: disposable GitHub-hosted CI plus a protected WSL deployment runner | Hosted runners safely handle PR build/test/scan work; the self-hosted runner is reserved for the one job that requires local k3d reachability |
| Security scanning | Trivy | Single tool covers container vulns + dependency scanning + secrets + IaC/K8s manifest misconfig |
| Container registry | ghcr.io | Free, native GitHub Actions auth, no extra account or rate-limit concerns (vs. Docker Hub) |
| AI pipeline stage | Official `anthropics/claude-code-action`, OAuth token auth | Zero incremental cost (uses existing Claude Pro subscription quota, not pay-per-token API billing); direct hands-on practice with Anthropic's own CI/CD tooling |
| Process tracking | Real free-tier Jira + Confluence | Gives real hands-on reps on tools flagged as new, plus a referenceable artifact |
| Observability | Structured JSON logging + request IDs built into the demo service from the walking skeleton onward; centralized Prometheus + Grafana dashboarding is a later increment | Traceability is a first-class requirement, not deferred — but a full metrics/dashboard stack is more than the walking skeleton needs to prove the pipeline end-to-end |
| Cloud deployment | Deferred — local k3d is v1; a real free-tier cloud VM (k3s) is an explicit stretch task | Keeps cost at $0 and avoids cloud VM maintenance risk before the core pipeline logic is proven |
