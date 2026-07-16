# Decisions Log: releaseward

> ADR-lite log. One entry per meaningful choice — architecture, tech stack, prompt design approach, model selection, etc. Append-only; if a decision is later reversed, add a new entry rather than editing the old one (the history is part of the value). Timestamp entries with date *and* time (check the system clock, don't guess) — useful when several decisions happen in one session.

## Format

```
### [YYYY-MM-DD HH:MM] [Short decision title]

**Decision**: [What was chosen]

**Alternatives considered**: [Other options that were on the table]

**Why**: [The reasoning — what tradeoff tipped it]

**Status**: Active | Superseded by [link to later entry]
```

---

<!-- Entries below this line -->

### [2026-07-14 11:10] Project framing: name, hosting, scope twists

**Decision**: Project named releaseward (collision-checked, clear). Local-first deployment (k3d) with real cloud deploy as a later stretch task, not v1. Skip LocalStack/AWS emulation entirely. Include real free-tier Jira + Confluence, used for actual task tracking and one architecture doc.

**Alternatives considered**: Considered shipgate/pipelane as names (pipelane collides with an existing npm/GitHub project, rejected). Considered a real free-tier cloud VM (k3s) as the primary v1 target instead of local-first. Considered including LocalStack for simulated S3/Secrets Manager as a cloud-native bonus twist. Considered skipping Jira/Confluence entirely and relying on this skill's own TASKS.md/DECISIONS.md as the only process artifact.

**Why**: Local-first keeps cost at $0 and avoids cloud VM maintenance risk before the core pipeline logic is proven. LocalStack would dilute focus while still new to Kubernetes/Actions fundamentals. Jira/Confluence give real hands-on reps on tools that are new, plus a concrete referenceable artifact.

**Status**: Active

### [2026-07-14 19:18] Walking-skeleton architecture locked in

**Decision**: Node+Express demo service (readyz/livez + one small feature) -> GitHub Actions (lint/test -> Trivy repo scan -> Docker build -> Trivy image scan -> ghcr.io push tagged by commit SHA) -> self-hosted GitHub Actions runner deploys to local k3d -> readyz/livez health poll -> official anthropics/claude-code-action (OAuth token auth) posts a plain-English release summary on the PR/commit. Jira + Confluence (free tier) track tasks and host one architecture doc. Monitoring (Prometheus/Grafana) and real cloud deploy are deferred past v1.

**Alternatives considered**: Considered kind (CI-standard, faster spin-up) and minikube (best learning feature set) over k3d — rejected in favor of k3d's lightweight, fast local dev experience. Considered Grype+Syft (faster, lower false-positive rate) and GitHub-native CodeQL/Dependabot over Trivy — rejected, Trivy's single-tool scope covers vuln + deps + secrets + IaC in one place. Considered a custom script calling the raw Anthropic Messages API instead of the official claude-code-action — rejected on cost grounds (pay-per-token API billing vs. free OAuth-token use of an existing Claude Pro subscription). Considered Python+FastAPI for the demo app (closer to the user's own background) over Node+Express — Node+Express chosen deliberately to build breadth into a second backend stack. Considered GitOps/pull-based deploy (Flux/ArgoCD watching the registry) instead of a self-hosted runner — self-hosted runner chosen as the simpler mechanism for a first Kubernetes project.

**Why**: Self-hosted runner was necessary, not just preferred: GitHub-hosted runners cannot reach a cluster running on a laptop, so local-first deployment requires either a self-hosted runner or a pull-based GitOps pattern — self-hosted was the simpler mechanism to learn first. Other choices favored tools with the broadest single-tool coverage and zero incremental cost, given the user's $0-beyond-existing-subscription budget constraint.

**Status**: Active

### [2026-07-14 20:05] Dev environment: WSL Ubuntu, strictly

**Decision**: The self-hosted GitHub Actions runner and k3d both run inside WSL (Ubuntu) rather than native Windows.

**Alternatives considered**: Running the self-hosted runner and k3d natively on Windows (Docker Desktop's Windows backend).

**Why**: Kubernetes/container tooling (k3d, the GitHub Actions runner, Trivy) is documented, supported, and troubleshot primarily against Linux; running inside WSL Ubuntu avoids Windows-specific edge cases and matches how these tools are used in most real-world deployments.

**Status**: Active

### [2026-07-14 20:05] Demo service includes intentional security flaws

**Decision**: The demo service ships with 1-2 deliberate, documented security flaws (e.g., a known-vulnerable dependency version, a hardcoded secret) rather than being flaw-free.

**Alternatives considered**: A clean demo service with no intentional vulnerabilities, relying on Trivy simply reporting "no findings."

**Why**: A pipeline security gate that never has anything to catch doesn't actually demonstrate the gate works. Deliberate, documented flaws give Trivy real findings to report, making the security stage's value legible rather than theoretical.

**Status**: Active

### [2026-07-14 20:05] Observability pulled into the walking skeleton, not deferred

**Decision**: Structured JSON logging and per-request traceability (request IDs) are part of the demo service from the walking skeleton onward. Centralized dashboarding (Prometheus/Grafana) remains a later increment.

**Alternatives considered**: Deferring all observability work (including basic structured logging) to a later increment, keeping the walking skeleton's demo service to plain console output.

**Why**: The whole point of building this is to have real, inspectable evidence of the work — plain unstructured logs don't hold up as "traceable like a real production environment." A full metrics/dashboard stack is still deferred since it isn't needed to prove the pipeline end-to-end, but basic structured logging is cheap enough to include from the start.

**Status**: Active

### [2026-07-14 20:05] Git workflow: explicit approval required for every commit/push

**Decision**: No `git commit` or `git push` runs without asking first and getting explicit approval — every time, not as a one-time blanket okay. This overrides the `builder` skill's default of committing automatically when a task is marked done.

**Alternatives considered**: Keeping the default auto-commit-on-task-done behavior with a single upfront opt-in.

**Why**: A previous commit/push cycle in this same project pushed content to the public repo that needed to be walked back (see the git history rewrite around this timestamp). Explicit per-action approval catches that kind of thing before it's public instead of after.

**Status**: Active

### [2026-07-16 09:30] Demo service feature theme: physical-security event triage

**Decision**: The demo service one small feature is a security-event classify endpoint themed around physical-security/access-control operations (categories: access_denied, after_hours, tailgating, device_offline, visitor) rather than a generic record classifier.

**Alternatives considered**: First built with generic financial/personal/medical record categories (drawing on general data-classification patterns). Replaced after review.

**Why**: A physical-security-operations theme is a more relevant, coherent domain for a CI/CD pipeline portfolio project in this space than an arbitrary financial/medical categorization with no connection to the rest of the project. Kept entirely generic (no specific company or product named anywhere in the app or docs) per the standing rule on not exposing job-application context in a public repo.

**Status**: Active
