# AI Detection Scenarios

Raw material for the "Claude Code Action release-summary stage" task (`TASKS.md`,
still todo). Each entry below is a **real incident** captured while it happened —
what signals were available, what actions a human and an AI assistant actually took
to diagnose and resolve it, and what a good plain-English summary of the incident
should say. This is the input/output pairing the eventual release-summary feature
needs to be evaluated against; formal `evals/` cases get written once that stage is
actually implemented (see `.claude/skills/ai-engineer` for why this project keeps
deterministic gates and AI summarization strictly separate).

Format per entry: Trigger, Signals available, Actions taken (attributed), Root
cause, Resolution, Target summary (what a good AI-written summary of this incident
should say — the rubric a future eval case would check against).

---

## Scenario 001: `deploy-development` fails after 14 days of inactivity — expired self-hosted-runner kubeconfig

**Date**: 2026-08-13

**Trigger**: PR #8 (`ai-test/releaseward-test-namespace` → `master`) merged. The resulting `master` push workflow run (`31746880789`) failed on the `deploy-development` job.

**Signals available**:
- `gh run view 31746880789`: `lint-and-test`, `filesystem-security`, `image-build` all green; `deploy-development` failed at step "Verify development cluster" (7s in).
- `gh run view 31746880789 --log-failed`: `error: You must be logged in to the server (the server has asked for the client to provide credentials)` — a `kubectl` auth failure, not an app/manifest error.
- `gh run list`: last **successful** `deploy-development` was run `30504935987`, 2026-07-30 — 14 days before this failure.
- `DECISIONS.md` (2026-07-29 20:22 entry): the `releasewardrunner` deploy identity's kubeconfig is a **7-day** token, provisioned by `scripts/bootstrap-runner-kubeconfig.sh`.

**Actions taken**:
- [AI] Read the failed job's logs via `gh run view --log-failed` rather than guessing from the job name alone.
- [AI] Cross-checked the last successful run's timestamp against the current date and against the documented 7-day kubeconfig TTL from a prior `DECISIONS.md` entry, rather than assuming the cause was related to the just-merged namespace/permission changes (those touched `releaseward-test`, not `releaseward-dev`, and the failure is an auth error at the `kubectl version`/`kubectl get deployments` step, before anything namespace-specific runs).
- [AI] Named the hypothesis explicitly (expired 7-day kubeconfig) and stated it as a hypothesis pending confirmation, rather than asserting it as fact, per this project's debugging convention of isolating the layer (credential/infra vs. code) before changing anything.
- [AI] Read `scripts/bootstrap-runner-kubeconfig.sh` directly rather than trusting the earlier `DECISIONS.md` note from memory — confirmed the script's own default `token_duration="168h"` (exactly 7 days) matches the documented TTL, before telling the human what to run.
- [Human] Ran `sudo ./scripts/bootstrap-runner-kubeconfig.sh` on the Hyper-V runner (`opsadmin`, cluster-admin `KUBECONFIG` exported first). Output: `Installed a 168h kubeconfig for releasewardrunner. Access is limited to Deployments in releaseward-dev.`
- [AI] Triggered `gh run rerun 31746880789 --failed` to re-execute only the failed `deploy-development` job against the renewed credential, and monitored the run to completion rather than assuming the fix worked from the script's success message alone.

**Root cause**: The self-hosted runner's namespace-scoped `releasewardrunner` kubeconfig carries a 7-day token TTL by design (`scripts/bootstrap-runner-kubeconfig.sh` default). No `master` push occurred between 2026-07-30 and 2026-08-13 (14 days), so the token expired from inactivity, not from any change in this session's PR.

**Resolution**: Re-ran `scripts/bootstrap-runner-kubeconfig.sh` to issue a fresh 168h token; `gh run rerun 31746880789 --failed` re-executed `deploy-development` against the renewed credential and it passed in 12s. Confirmed via `gh run view` (all four jobs green), not assumed from the script's success message alone.

**Open follow-up**: the 7-day TTL will expire again after any 7+ day gap between `master` pushes. Worth deciding: longer-lived token (weakens the credential-lifetime boundary Trivy originally flagged as HIGH risk), or a scheduled renewal job, or just accept this as a known low-frequency manual step. Not decided yet — raised here as a candidate follow-up task, not resolved.

**Target summary** (what a good AI-written release-summary comment should say about this incident):
> `deploy-development` failed on the `master` push from PR #8, but the failure is unrelated to that PR's changes (a new namespace manifest and a local permission-scoping change). The self-hosted runner's deployment credential appears to have expired from 14 days of inactivity, against a documented 7-day TTL. `lint-and-test`, `filesystem-security`, and `image-build` all passed — the built image is verified and ready to deploy once the runner's kubeconfig is renewed.

---

