---
name: ai-engineer
description: Conventions for AI/LLM-integrated pipeline work in releaseward — autonomy/authority boundaries, eval requirements, the Claude Code Action release-summary stage. Load when touching evals/, any AI/LLM call, the ai-test lane's autonomous-repair behavior, or the release-summary task.
---

Condensed rules for AI-component work in this repo, pulled from `AI_AUTOMATION.md`,
`AI_FIRST_CICD.md`, and CLAUDE.md's builder workflow — read those in full only when
you need the underlying argument, not for routine work.

## Core principle

> Give AI **high autonomy inside a low-authority, disposable environment**. AI may
> propose and prove a change. It may not authorize its own promotion.

A disposable `ai-test/**` branch is for attribution/recovery, not a security boundary.
The actual boundaries are: workflow/branch permissions, filesystem/network isolation,
runner lifetime/trust, credential scope/lifetime, protected files, independently
executed tests/policies, and environment/promotion authority. When reasoning about
what an AI-driven step is allowed to do, check those, not "is it on a test branch."

## Deterministic controls stay deterministic

Build, lint, unit/integration/contract/smoke tests remain objective pass/fail gates.
**Never** make a deterministic gate's result depend on model judgment — an LLM step
summarizes or recommends on top of a gate's result, it doesn't replace the gate.

## The autonomy ladder (`AI_FIRST_CICD.md`)

```
Deterministic CI/CD -> structured evidence/observability -> AI summaries/recommendations
-> shadow-mode measurement -> reviewable proposed actions -> bounded reversible automation
-> higher authority only when supported by evidence
```

This repo is at "deterministic CI/CD" with structured JSON logging/request IDs
already in place, and is about to add the next rung (AI summaries, via the Claude
Code Action task). Don't design or suggest behavior from further up the ladder
(auto-fix-and-commit, self-approval, production authority) unless a task explicitly
calls for it — that's future/stretch scope, not v1.

## Claude Code Action release-summary task (todo in TASKS.md)

- Auth via OAuth token off the existing Claude Pro subscription — no incremental
  per-token API billing. Don't introduce a separate API key/billing path for this.
- v1 scope: read the completed run's logs/diff/commits, post a plain-English summary
  as a PR/commit comment. Auto-fix-and-commit is an explicit possible stretch, not
  default behavior — don't build it in without the user asking.

## Eval requirement (CLAUDE.md builder workflow)

Any new or changed AI/LLM call needs 3-5 cases in `evals/` before the task is `done`,
using the `eval-case.md` format from the `builder` skill. **Known gap on this
sandbox VM**: the `builder` skill (and its `scripts/append_log.py` DECISIONS.md
helper) is not installed here — `evals/` currently only has a `.gitkeep`, and
`scripts/` only has the runner/kubeconfig helpers. If a task needs `eval-case.md`
format and the skill isn't available, ask the user rather than guessing the format;
fall back to CLAUDE.md's own instruction to append DECISIONS.md entries directly
when the helper script isn't present.

## AI-test lane authority limits (ties to [[cicd-pipeline]])

An AI agent working the "AI-writable candidate branch" task may: push to `ai-test/**`,
run bounded local validation, open a PR. It may not: touch protected workflow/policy
paths, push/merge to `master`, approve its own PR, reach the WSL deployment runner,
or advance a passing candidate straight to staging/production — that promotion gate
is explicitly still undefined (TASKS.md).

## AI output is untrusted input at every boundary it can influence

Treat any AI-proposed change — including your own — the same way the pipeline
treats pull-request code: unverified until the deterministic gates say otherwise.
Concretely:

- An AI agent must never edit `.trivyignore`, weaken a Trivy severity threshold, or
  otherwise soften a security gate in order to make its own change pass. If a fix
  triggers a new finding, the fix is wrong or incomplete — not the gate.
- The Claude Code Action release-summary stage's write scope should be exactly
  "post a PR/commit comment" — no permission to modify workflow files, merge,
  approve, or touch deployment credentials. Its authority should be a strict subset
  of what a human reviewer can do, not a shortcut around them.
- If a future task gives an AI step the ability to *propose* a fix (per the autonomy
  ladder above), the proposal still goes through the same filesystem/image Trivy
  gates, lint, and tests as any other change before it can merge — no
  AI-authored-code fast path.

## Push breadth of AI usage, keep authority narrow

A legitimate goal here is applying AI aggressively across pipeline *operations* —
not just one release-summary comment. Reasonable surface area to design toward:
recurring changelog/release-note generation, translating run evidence into
stakeholder-facing status updates, and assisting with regression/anomaly triage
once production monitoring exists. Being conservative about *where* Claude gets
used is not the goal here — being disciplined about *what authority* each use gets
is. Every new AI-driven surface should get the same treatment as the
release-summary stage: a clearly bounded write scope (e.g. "post a comment,"
"open a draft PR," never "merge" or "modify pipeline config"), independent of how
broad its read/analysis scope is.

## Where to look for more

- `AI_AUTOMATION.md` — full autonomy/authority argument and intended-use list.
- `AI_FIRST_CICD.md` — full future-state architecture (proposed, not implemented).
- `ARCHITECTURE.md` / `TASKS.md` — current source of truth for what's actually built.
- `AI_DETECTION_SCENARIOS.md` — real incidents captured live (trigger, signals,
  attributed actions, root cause, target summary) as raw material for the
  release-summary task's eventual `evals/` cases. Add an entry whenever a real
  debugging session happens, not just when the task itself is being built.
