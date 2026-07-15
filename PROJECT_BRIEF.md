# Project Brief: releaseward

> Filled in during Stage 0 (Framing).

## Name & Repo

- **Name**: releaseward — collision-checked (GitHub/npm) on 2026-07-14: clear. No conflicting project with this exact name found.
- **Repo**: https://github.com/RafaelEstrella05/releaseward (public)

## Purpose

A self-hosted, AI-assisted CI/CD release pipeline: push a code change and watch it get tested, security-scanned, containerized, deployed to a local Kubernetes cluster, monitored, and summarized — with Claude doing real work at specific pipeline stages, not just as a chat sidebar. Built to gain genuine hands-on experience with GitHub Actions, self-hosted Kubernetes, and AI-driven pipeline automation — a public portfolio piece useful for any future application in this space, not tied to one specific opportunity.

## Users

Just the builder (Rafael) for now. A general portfolio/learning project — audience is whoever looks at the public GitHub repo (potential employers, other engineers), not a specific named individual or company.

## Input → Output

Trigger: a `git push` / pull request against the repo.
Flow: GitHub Actions runs tests + security/dependency scans → builds a Docker image → pushes it to a registry → deploys to a local self-hosted Kubernetes cluster (k3d) via a self-hosted runner → runs health checks (`readyz`/`livez`) → Claude reads the pipeline run (logs, diffs, commits) and produces a human-readable release summary / anomaly flag → the release summary is posted as a PR/commit comment; structured logs/traces are captured throughout for real observability.
Output: a deployed, running service plus an AI-generated release note and a pass/fail signal a stakeholder could read without touching the pipeline internals.

## Constraints

- **Budget**: $0 target. Free-tier only — GitHub Actions free minutes, free Atlassian (Jira + Confluence) tier, Claude usage via existing $20/mo Pro subscription (OAuth token auth, not separate API billing), local k3d instead of paid cloud Kubernetes.
- **Latency**: None hard — this is a demo pipeline, not a production SLA. Should feel snappy in a live walkthrough (each run in a few minutes, not tens of minutes).
- **Privacy/data handling**: No sensitive data. The "workload" being deployed is a small demo service — real content is the pipeline itself, not proprietary data. This repo is public — nothing naming a specific target company, hiring manager, or job application goes in any committed file.
- **Deployment**: Local-first, strictly inside WSL (Ubuntu) — not native Windows. Runs on a local k3d cluster via a self-hosted GitHub Actions runner, demoed via README instructions + recorded walkthrough (screen recording/GIFs). A real cloud deploy (free-tier VM running k3s) is an explicit stretch task once the local pipeline is solid — not required for v1.
- **Observability**: Structured, traceable logging is a first-class requirement from the walking skeleton onward (not deferred) — every request/pipeline run should be loggable and traceable like a real production system, so the work is legible from logs/runs, not just from reading the repo.
- **Realistic security surface**: The demo service intentionally includes a couple of known, deliberate security flaws (e.g., a vulnerable dependency version, a hardcoded secret) so the Trivy scanning stage has something real to catch and report on — not a hypothetical.

## Success Criteria (v1 "done" — the walking skeleton)

- [ ] A containerized service exists in this repo with a Dockerfile, `readyz`/`livez` health endpoints, structured logging, and 1-2 intentional, documented security flaws for Trivy to catch.
- [ ] A GitHub Actions workflow runs on push/PR: lint/test → Trivy scan (repo + image) → build image → push to a registry.
- [ ] The image deploys to a local k3d cluster (running in WSL Ubuntu) via a self-hosted GitHub Actions runner, and health checks pass automatically post-deploy.
- [ ] One AI-driven pipeline stage is live: Claude reads a completed pipeline run and produces a plain-English release summary (posted as a PR comment at minimum).
- [ ] A real Jira project tracks this build's tasks, and one Confluence page documents the architecture — both linkable from the README.
- [ ] README walks a stranger through running the whole thing locally in under 15 minutes.

Longer-term (post-v1, tracked in `TASKS.md` as it's built out): centralized monitoring/log aggregation (Grafana/Prometheus dashboard), Claude-driven anomaly detection on deploy metrics, real free-tier cloud deploy.
