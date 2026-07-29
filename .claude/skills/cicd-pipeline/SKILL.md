---
name: cicd-pipeline
description: releaseward's CI/CD conventions — GitHub Actions job order, Trivy two-pass gating, GHCR publish rules, self-hosted runner trust boundary, k8s deploy pattern. Load before editing .github/workflows, k8s/, Trivy config, or runner scripts, or when asked how the pipeline works.
---

Condensed operating knowledge for this repo's pipeline, so you don't have to re-read
ARCHITECTURE.md/DECISIONS.md/CHEATSHEET.md in full every session. This is a summary of
what's **actually implemented** — TASKS.md and ARCHITECTURE.md remain the source of
truth if this drifts from them.

## Pipeline shape (`.github/workflows/ci.yml`)

Four jobs, strictly chained via `needs:`:

1. `lint-and-test` (hosted, always) — `npm ci` / lint / unit tests in `app/`.
2. `filesystem-security` (hosted, always) — two-pass Trivy repo/fs scan.
3. `image-build` (hosted, always) — multi-stage Docker build tagged
   `ghcr.io/<owner>/<repo>:<commit-sha>`, two-pass Trivy image scan, then **publish
   only if** `github.event_name == 'push' && github.ref == 'refs/heads/master'`.
4. `deploy-development` (self-hosted `[self-hosted, linux, x64, releaseward-deploy]`,
   `if:` master push only) — validates the digest, applies the digest-pinned
   Deployment to `releaseward-dev`, waits for rollout, smoke-tests `/livez` + `/readyz`
   through the ingress.

## Trust boundary — the load-bearing rule

- Pull requests and feature-branch pushes: **build and verify only**. Hosted runners,
  no GHCR login, no path to k3d. This is why PR code is safe to run untrusted.
- `master` push: the only ref allowed to publish to GHCR (SHA tag) and the only ref
  that can trigger `deploy-development`.
- The self-hosted WSL runner is **deploy-only**: no Docker socket, no Docker group,
  namespace-scoped RBAC that explicitly forbids `patch services`,
  `patch ingresses.networking.k8s.io`, `get secrets` (the workflow asserts this with
  `kubectl auth can-i` before doing anything). It deploys by digest, not by pulling/
  building — k3d's containerd pulls the public GHCR image directly.
- Never suggest giving the deploy runner broader RBAC, Docker access, or Service/
  Ingress write — that's a deliberate, decision-logged restriction
  (see DECISIONS.md, 2026-07-27 entries), not an oversight.

## Trivy convention — always two-pass

Every scan stage (fs and image) runs Trivy **twice**:

- Evidence pass: `TRIVY_IGNOREFILE: /dev/null`, `exit-code: "0"` — reports everything,
  never fails the job.
- Enforcement pass: `TRIVY_IGNOREFILE: .trivyignore`, `exit-code: "1"` — fails on
  anything not explicitly allowlisted.

`.trivyignore` must only ever contain the **documented intentional fixtures** (the
outdated lodash dependency, the synthetic `releaseward_demo_...` secret used to
exercise the secret-scanner). A new HIGH/CRITICAL finding is a real bug to fix (see
DECISIONS.md's Alpine/npm hardening entry for the pattern: upgrade packages, shrink
the image, drop unneeded tooling) — never add it to `.trivyignore` without first
confirming with the user it's actually one of the intentional fixtures.

## Supply-chain pinning convention

Third-party Actions (`aquasecurity/trivy-action`, `docker/login-action`, etc.) are
pinned to a full commit SHA with the version as a trailing comment, not a floating
tag — this repo already hit a real Trivy Actions supply-chain compromise and reacted
by moving off tag pinning (see DECISIONS.md). Keep new third-party Action references
SHA-pinned.

## Security-first pipeline mindset

This pipeline should be built and reviewed as if it belonged to a security-product
company — assume a customer's security team could audit any gate, digest, or
credential scope at any time. Concretely:

- **Supply chain integrity is a first-class concern, not just dependency scanning.**
  SHA-pinning third-party Actions (above) is the floor, not the ceiling. When
  hardening this further, prefer real provenance/attestation (e.g. build
  provenance, image signing with Sigstore/cosign) over just trusting a registry
  push — evaluate this as a natural next step, don't add it silently without
  discussing the added complexity with the user first.
- **Evidence over logs.** `GITHUB_STEP_SUMMARY` output (published digest, deployment
  revision/digest annotations, health-check results) exists so a reviewer never has
  to dig through raw logs to answer "what shipped, from what commit, and did it pass
  its gates." Keep extending that pattern to any new job rather than leaving results
  log-only.
- **Runtime-verified least privilege, not just design-time.** The deploy job doesn't
  just have restricted RBAC — it actively asserts that restriction with
  `kubectl auth can-i` before doing anything (see the workflow). That
  "verify-then-act" pattern, not a one-time permissions review, is the model for any
  new credential or runner added later.
- **A new HIGH/CRITICAL finding is a fix, not a suppression** — this is already the
  `.trivyignore` rule above, but it's worth restating as the general security
  posture: allowlisting is the exception that requires justification, not the
  default response to a failing gate.
- **AI-authored changes get zero special treatment at security gates** — see
  [[ai-engineer]] for how that applies to the AI-test lane specifically.
- **Repository-level hardening is part of "securing the pipeline," not just
  scanning code.** Branch protection rules/rulesets, required status checks,
  push protection/secret scanning at the GitHub level, and least-privilege
  collaborator/team permissions are as much a part of pipeline security as Trivy
  gates. As of this writing that configuration isn't documented anywhere in this
  repo (`ARCHITECTURE.md`/`DECISIONS.md`) — treat "is branch protection actually
  configured and does it match what's documented" as an open question, not a
  solved one, until it's been verified and written down.
- **Production observability is a named gap, not a deferred nice-to-have
  forever.** Structured JSON logging + request IDs is the current state;
  `ARCHITECTURE.md` already flags centralized dashboarding (e.g.
  Prometheus/Grafana-style metrics, or an error-tracking tool) as a later
  increment. Treat closing that gap — real regression/anomaly detection on
  production traffic, not just log lines — as a legitimate priority, not
  optional polish.
- **Prefer composable, reusable workflow design as the pipeline grows.** A
  single `ci.yml` was right for a walking skeleton; as jobs multiply, look for
  opportunities to factor shared logic into reusable workflows or composite
  actions (mirrors `IDEAL_FLOW.md`'s "mandatory gates as versioned reusable
  workflows" concept) rather than letting one file grow indefinitely.

## AI-test lane (in-progress task — don't assume it's finished)

A bounded coding agent (this may be you, running in the dedicated sandbox VM) is
restricted to:

- Push only to `ai-test/**` branches, never `master`.
- Cannot modify protected workflow/policy paths, approve its own PR, or reach the WSL
  deployment runner.
- Candidate images get a distinct `ai-test-<commit-sha>` tag/namespace, short
  retention, hosted runners only, deploy automatically only to a dedicated
  `releaseward-test` namespace.
- A passing candidate does **not** auto-promote to staging/production — that gate is
  explicitly still undefined (see TASKS.md).

## Where to look for more (don't inline these — grep/read on demand)

- `ARCHITECTURE.md` — current reality, component table, trust-boundary table.
- `DECISIONS.md` — append-only rationale log; grep by date or topic before assuming
  "why" on any pipeline choice.
- `CHEATSHEET.md` — hands-on commands (feature-branch flow, runner bootstrap).
- `IDEAL_FLOW.md` / `AI_FIRST_CICD.md` — **proposed future-state architecture**, not
  current implementation. Never cite these as "what the pipeline does today."
- `TASKS.md` — source of truth for done vs. todo.
