# Intentional security flaws (fixtures for the Trivy pipeline stage)

This demo service ships with two deliberate, documented flaws so the pipeline's Trivy
security-scanning stage has real findings to catch and report — not just a "0 vulnerabilities
found" no-op.

1. **Vulnerable dependency**: `lodash` is pinned to exactly `4.17.15` in `package.json` (no `^`,
   so npm won't silently resolve to a patched version). Trivy currently reports the exact
   accepted fixture IDs in `.trivyignore`; the scanner database may add more findings over
   time. Lodash is used for real in `classifier.js`, not merely installed and left unused.
2. **Synthetic hardcoded secret**: `server.js` contains `DEMO_API_KEY`, a fake
   `releaseward_demo_...` value recognized by the project-specific rule in
   `trivy-secret.yaml`. It cannot be mistaken for a real provider credential and must never
   be replaced with a working key. If this app later gains a real LLM-backed feature, that
   key belongs in an environment variable or GitHub Actions secret, never in source.

The workflow first reports these fixtures without suppression, then runs a blocking scan
using `.trivyignore`. Only the documented fixture IDs are accepted; any other `HIGH` or
`CRITICAL` vulnerability, secret, or misconfiguration fails the security job.

Do not "fix" either of these without checking `TASKS.md`/`DECISIONS.md` first — they're
fixtures for the security-gate task, not bugs.
