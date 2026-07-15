# Tasks: releaseward

> Backlog of vertical-slice increments. Task #1 is always the walking skeleton. Each task needs a stated Purpose, agreed with the user, before it's added here (Stage 2).

## Format

```
### [ ] Task: [Short name]
- **Purpose**: [What problem this solves / how it serves PROJECT_BRIEF.md]
- **Status**: todo | in-progress | done
- **Notes**: [Filled in when done — what was learned or changed from plan]
```

---

<!-- Entries below this line. Mark done tasks with [x]. -->

### [ ] Task: Demo service running locally in Docker
- **Purpose**: Establishes the artifact everything else in the pipeline operates on — nothing can be built, tested, scanned, or shipped until this exists. Node + Express, `readyz`/`livez` health endpoints, structured JSON logging with request IDs, one small feature endpoint, and 1-2 intentional documented security flaws for Trivy to catch later.
- **Status**: todo
- **Notes**:

### [ ] Task: k3d cluster up, service deployed manually
- **Purpose**: Learn raw Kubernetes manifests (Deployment, Service, Ingress) and probe semantics by hand, in WSL Ubuntu, before automating any of it via CI.
- **Status**: todo
- **Notes**:

### [ ] Task: GitHub Actions CI — lint + unit test only
- **Purpose**: Smallest possible real Actions workflow (triggers, jobs, secrets) before layering anything else on top.
- **Status**: todo
- **Notes**:

### [ ] Task: Trivy security gate in the workflow
- **Purpose**: Add the repo/filesystem scan and (once there's an image) the image scan, so the pipeline actually catches the demo service's intentional flaws — the JD-style security-scanning stage.
- **Status**: todo
- **Notes**:

### [ ] Task: Docker build + push to ghcr.io in the workflow
- **Purpose**: Completes the "build and publish artifact" half of the pipeline, tagged by commit SHA.
- **Status**: todo
- **Notes**:

### [ ] Task: Self-hosted runner + automated deploy to k3d + health-check smoke test
- **Purpose**: Closes the loop on the core architectural insight — hosted runners can't reach local k8s, so a self-hosted runner (WSL Ubuntu) is required. This is the "does the pipeline actually ship it" moment.
- **Status**: todo
- **Notes**:

### [ ] Task: Claude Code Action release-summary stage
- **Purpose**: The AI-driven pipeline differentiator — Claude reads the completed run (logs, diff, commits) and posts a plain-English release summary as a PR/commit comment.
- **Status**: todo
- **Notes**:

### [ ] Task: Jira project + Confluence architecture page
- **Purpose**: Real hands-on reps on tools flagged as new, linked from the README as a referenceable artifact.
- **Status**: todo
- **Notes**:

### [ ] Task: README polish
- **Purpose**: Final legibility pass — a stranger should be able to run the whole thing locally in under 15 minutes from the README alone.
- **Status**: todo
- **Notes**:
