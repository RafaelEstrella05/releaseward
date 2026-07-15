# Architecture: releaseward

> Filled in during Stage 1 (Walking-skeleton design). Update as the architecture evolves — this should reflect current reality, not just the original plan.

**Design walkthrough confirmed**: 2026-07-14 19:18, user-narrated end-to-end.

## Walking Skeleton

```
git push / pull request
  -> GitHub Actions triggers (on: push, pull_request)
  -> lint + unit tests run first (fail fast, cheapest checks)
  -> Trivy scans the repo/filesystem (deps, secrets, IaC/K8s manifests)
  -> Docker image builds (Node + Express demo service)
  -> Trivy scans the built image (vulnerabilities baked into the image)
  -> if everything passed: image pushes to ghcr.io, tagged with the commit SHA
  -> self-hosted GitHub Actions runner (WSL Ubuntu) deploys the image to k3d
  -> readyz/livez get polled to confirm the new pod is actually healthy (smoke test)
  -> Claude Code Action reads the run (logs, diff, commits) and posts a plain-English
     release summary as a PR/commit comment
```

This is the thinnest slice that touches every major component. It is realized via a short chain of small tasks in `TASKS.md` rather than a single task, since Docker→Kubernetes, GitHub Actions, and a self-hosted runner are all being learned simultaneously.

## Components

| Component | Responsibility | Notes |
|---|---|---|
| Demo service | Node + Express REST API with `readyz`/`livez` health endpoints, structured JSON logging (request IDs for traceability), plus a minimal feature (small form/record-classify endpoint + light front end) | Deliberately minimal in scope — the pipeline is the star, not the app. Intentionally includes 1-2 documented security flaws (e.g., a vulnerable dependency version, a hardcoded secret) so the Trivy stage has something real to catch |
| GitHub Actions | Orchestrates the whole pipeline: triggers on push/PR, runs jobs in order, gates merges/deploys on job success | |
| Trivy | Security gate: scans repo/filesystem (deps, secrets, IaC/K8s manifests) and the built container image (vulnerabilities) | Single tool covering dependency scanning, secret detection, and vulnerability assessment |
| ghcr.io | Container registry — stores built images tagged by commit SHA | Free, native GitHub auth, no separate account/rate-limit concerns |
| Self-hosted GitHub Actions runner | Runs inside WSL (Ubuntu), registered as a GitHub Actions runner, so the deploy step can actually reach the local k3d cluster | Hosted runners are cloud VMs with no path to a local cluster — this is the mechanism that makes "local-first" actually work with GitHub Actions |
| k3d | Local self-hosted Kubernetes (running inside WSL Ubuntu) — orchestrates the demo service's container(s) | Lightweight, fast cluster spin-up, well suited to iterative local dev work |
| Claude Code Action | Reads the completed pipeline run (logs, diff, commits) and posts a plain-English release summary on the PR/commit | Authenticated via OAuth token off the existing $20/mo Claude Pro subscription — no incremental API billing. Self-healing (auto-fix-and-commit on failure) is a possible later stretch task, not in v1 scope |
| Jira | Tracks this build's own tasks as real tickets | Free tier |
| Confluence | Hosts one architecture/documentation page for the project | Free tier |

## Data Flow

```
[commit] -> [GitHub Actions: lint/test] -> pass/fail
pass -> [Trivy: repo scan] -> pass/fail
pass -> [Docker build] -> image
image -> [Trivy: image scan] -> pass/fail
pass -> [ghcr.io push, tag=commit SHA] -> registry image
registry image -> [self-hosted runner (WSL Ubuntu): deploy to k3d] -> running pod
running pod -> [readyz/livez poll] -> healthy/unhealthy
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
| Runner model | Self-hosted runner (WSL Ubuntu) | Required for "local-first": hosted runners can't reach a local k3d cluster; self-hosted was chosen over a GitOps/pull-based alternative for simplicity on a first Kubernetes project |
| Security scanning | Trivy | Single tool covers container vulns + dependency scanning + secrets + IaC/K8s manifest misconfig |
| Container registry | ghcr.io | Free, native GitHub Actions auth, no extra account or rate-limit concerns (vs. Docker Hub) |
| AI pipeline stage | Official `anthropics/claude-code-action`, OAuth token auth | Zero incremental cost (uses existing Claude Pro subscription quota, not pay-per-token API billing); direct hands-on practice with Anthropic's own CI/CD tooling |
| Process tracking | Real free-tier Jira + Confluence | Gives real hands-on reps on tools flagged as new, plus a referenceable artifact |
| Observability | Structured JSON logging + request IDs built into the demo service from the walking skeleton onward; centralized Prometheus + Grafana dashboarding is a later increment | Traceability is a first-class requirement, not deferred — but a full metrics/dashboard stack is more than the walking skeleton needs to prove the pipeline end-to-end |
| Cloud deployment | Deferred — local k3d is v1; a real free-tier cloud VM (k3s) is an explicit stretch task | Keeps cost at $0 and avoids cloud VM maintenance risk before the core pipeline logic is proven |
