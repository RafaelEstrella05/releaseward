## Builder Workflow

This project follows the `builder` iterative methodology. Apply these rules in every session, not just when `/builder` is explicitly invoked:

- **State lives in files**: `PROJECT_BRIEF.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TASKS.md`, `README.md`, `evals/`. Check `TASKS.md` for the current task before starting work.
- **One task at a time**: work the next `todo`/`in-progress` task in `TASKS.md`. Don't start new ones until the current one is `done`.
- **Scope guardrail**: if a request mid-task falls outside that task's stated Purpose, say so explicitly and default to queuing it as a new `TASKS.md` entry rather than folding it in silently.
- **Soft check-ins**: at natural pauses — run results, start of debugging, and (occasionally, for tasks spanning multiple architecture components) a mid-implementation progress check — let the user report/explain first, ungated. Reps, not gates; routine single-component tasks skip the mid-implementation one.
- **Run it for real**: after implementing a task, execute it and show real output — don't just describe what the code should do.
- **Eval AI components**: any new/changed AI/LLM call gets 3-5 cases in `evals/` (see the `builder` skill's `eval-case.md` format), run before considering the task done.
- **Log via the script, not by hand**: `DECISIONS.md` is an append-only log — append to it with the `builder` skill's `scripts/append_log.py DECISIONS.md` (entry as JSON on stdin) instead of reading and editing the file directly. Always pass a real `[YYYY-MM-DD HH:MM]` timestamp (check the system clock, don't guess).
- **Capture raw material honestly**: when marking a task `done`, note any snag, mistake, or ambiguity hit — this and `DECISIONS.md` are what the separate `interview-coach` skill draws on later. Nothing here drills the user on it; just capture it truthfully.
- **Git requires approval, every time**: never run `git commit` or `git push` without asking first — a one-time yes does not cover future commits. Prepare the commit/push and wait for explicit go-ahead each time.
- **Debugging**: when something breaks, isolate the layer (orchestration/data/prompt/tool-call) before changing code — see the `builder` skill's debugging playbook. Add a regression eval case once fixed.

If `PROJECT_BRIEF.md` doesn't exist yet, run `/builder` first to bootstrap the project.

## Context for this project specifically

- General hands-on skill-building project: GitHub Actions CI/CD, self-hosted Kubernetes, and Claude-driven pipeline automation, built as a public portfolio piece.
- **Never commit content that reveals a specific target company, hiring manager, or job application** in this repo — no mentions of specific employers/interviewers anywhere in `README.md`, `PROJECT_BRIEF.md`, `ARCHITECTURE.md`, `DECISIONS.md`, or code comments. Keep all rationale framed in general technical/learning terms. This is a hard rule, not a style preference.
- User (Rafael) is new to Kubernetes, GitHub Actions, CI/CD, Jira, and Confluence — strong at Docker and at using Claude to accelerate learning. Explain K8s/Actions concepts as they come up, don't assume prior exposure.
- Development environment is WSL (Ubuntu) — strictly. All shell commands, the self-hosted runner, and k3d run inside WSL Ubuntu, not native Windows.
- The demo service is deliberately built with a couple of intentional, known security flaws (e.g., an outdated vulnerable dependency, a hardcoded secret) so the Trivy stage has something real to catch — don't "fix" these without checking whether they're an intentional eval fixture first.
- Observability (structured logging, request tracing) is a first-class requirement from the walking skeleton onward, not a deferred nice-to-have — see `ARCHITECTURE.md`.
