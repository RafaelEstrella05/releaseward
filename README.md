# releaseward

A self-hosted, AI-assisted CI/CD release pipeline — built hands-on to learn GitHub Actions, self-hosted Kubernetes, and Claude-driven pipeline automation.

## Status

Early development, built iteratively via the `builder` workflow. See `PROJECT_BRIEF.md` for the full brief, `ARCHITECTURE.md` for the design, and `TASKS.md` for current progress.

## Setup

Prerequisites: WSL2 with an Ubuntu distro, Docker Engine and Node.js installed inside it (not Docker Desktop — see `DECISIONS.md` for why).

```bash
cd app
npm install
docker build -t releaseward-demo:dev .
```

## Usage

```bash
docker run -d --name releaseward-demo -p 3000:3000 releaseward-demo:dev

curl http://localhost:3000/livez
# {"status":"alive"}

curl http://localhost:3000/readyz
# {"status":"not ready"}   <- for ~2.5s while it "warms up", then:
# {"status":"ready"}

curl -X POST http://localhost:3000/classify \
  -H 'Content-Type: application/json' \
  -d '{"text":"Badge access denied at rear entrance, after hours, repeated attempts"}'
# {"category":"access_denied","confidence":0.25}
```

Or open `http://localhost:3000/` for a minimal form UI over the same endpoint.

See `app/SECURITY_FLAWS.md` for the two intentional, documented vulnerabilities the pipeline's Trivy stage is meant to catch.

## Project layout

- `app/` — the Node + Express demo service (health endpoints, structured logging, the security-event classify feature, intentional Trivy fixtures)
- `PROJECT_BRIEF.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `TASKS.md` — living project state (see each file's own header for how it's used)
