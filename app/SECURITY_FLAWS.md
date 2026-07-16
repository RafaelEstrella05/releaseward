# Intentional security flaws (fixtures for the Trivy pipeline stage)

This demo service ships with two deliberate, documented flaws so the pipeline's Trivy
security-scanning stage has real findings to catch and report — not just a "0 vulnerabilities
found" no-op.

1. **Vulnerable dependency**: `lodash` is pinned to exactly `4.17.15` in `package.json` (no `^`,
   so npm won't silently resolve to a patched version). That version has a known
   prototype-pollution vulnerability (CVE-2019-10744). It's used for real — merging the
   classification result object in `server.js` — not just sitting unused.
2. **Hardcoded secret**: `server.js` contains `DEMO_API_KEY`, a fake, DeepSeek/OpenAI-style
   (`sk-...`) API-key-shaped string. It is not a real credential and must never be replaced
   with a working one — it exists purely so Trivy's secret-detection scan has something to
   flag. If this app later gains a real LLM-backed feature, that key belongs in an
   environment variable / GitHub Actions secret, never in source.

Do not "fix" either of these without checking `TASKS.md`/`DECISIONS.md` first — they're
fixtures for the security-gate task, not bugs.
