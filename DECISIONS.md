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

### [2026-07-16 15:30] Troubleshooting: k3d server container restart traced to WSL2 idle-timeout VM shutdown

**Decision**: Root-caused the mid-Task-2 k3d-releaseward-server-0 restart to WSL2 tearing down the entire lightweight VM on an idle timeout (journalctl --list-boots showed repeated short-lived boots, current boot showing 0 min uptime right as the crash was investigated), not a docker/containerd/OOM issue -- ruled out OOM (OOMKilled=false, 30GB free) and app-level causes first. Fixed by creating a .wslconfig file (in the Windows user profile directory) with [wsl2] vmIdleTimeout=-1 to disable the idle shutdown, then wsl --shutdown plus restart to apply it. Verified the cluster and demo service recover cleanly through a deliberate shutdown/restart cycle (pods reschedule, ingress traffic works again within about a minute).

**Alternatives considered**: Could have ignored it as a one-off flake and moved on, or worked around it by keeping a terminal/process always attached to the WSL distro to keep the VM alive instead of disabling the timeout.

**Why**: A one-off dismissal would leave the same failure mode waiting to recur, and it matters a lot more once the self-hosted GitHub Actions runner (a later task) depends on this same WSL Ubuntu environment staying up continuously to pick up jobs. Disabling the idle timeout via .wslconfig is the durable fix at the platform level rather than a fragile workaround such as a keep-alive process.

**Status**: Active

### [2026-07-16 15:41] Troubleshooting: k3d server container crash-looping after VM stabilized, traced to cgroup/systemd corruption from earlier unclean shutdowns

**Decision**: After fixing the WSL2 idle-timeout (VM itself became stable, same boot for 8+ minutes), the k3d-releaseward-server-0 container still failed to restart cleanly, this time with a concrete error: failed to create shim task / OCI runtime create failed / unable to apply cgroup configuration / error creating systemd unit ... got failed. dmesg also showed systemd-journald reporting a corrupted/uncleanly-shut-down journal file. Concluded this was leftover damage (corrupted cgroup/systemd/journal state) from the earlier repeated unclean VM shutdowns, not a new independent bug. Fixed by deleting the k3d cluster entirely (k3d cluster delete) and recreating it fresh on the now-stable VM, then re-importing the image and reapplying the k8s/ manifests -- verified working end-to-end through the ingress again afterward.

**Alternatives considered**: Considered trying to repair the specific failing container/cgroup state in place (e.g. manually restarting just the affected container, clearing stale cgroup mounts) rather than deleting and recreating the whole cluster.

**Why**: Debugging corrupted systemd/cgroup state left over from multiple prior unclean shutdowns is a poor use of time when the cluster itself is fully disposable and cheap to recreate (that is the entire point of a local dev cluster). Recreating fresh on now-stable ground (post the vmIdleTimeout fix) was the faster and more reliable path than forensically repairing state that was corrupted by a problem that no longer exists.

**Status**: Active

### [2026-07-16 16:08] Troubleshooting correction: k3d server crash-loop was a Docker cgroup-driver bug, not leftover VM corruption

**Decision**: The earlier entry (Troubleshooting: k3d server container crash-looping after VM stabilized) diagnosed the recurring crash as leftover cgroup/systemd/journal corruption from prior unclean VM shutdowns, fixed by recreating the cluster. That was wrong -- the crash recurred identically on a fresh cluster on a VM stable for 24+ minutes (no reboot). The real cause: Docker daemon was running with Cgroup Driver: systemd (docker info), which makes Docker create a transient systemd scope unit (docker-<container-id>.scope) via dbus for every container it starts. That systemd unit-creation call was intermittently failing inside this nested WSL2 environment, killing the k3d-releaseward-server-0 container itself (not anything inside k3s/kubelet). Fixed at the correct layer: set exec-opts native.cgroupdriver=cgroupfs in /etc/docker/daemon.json, restarted docker.service, and also set --kubelet-arg=cgroup-driver=cgroupfs on the k3d server node (via --k3s-arg) so kubelet and Docker cgroup drivers match. Verified stable for 8+ minutes with RestartCount=0, past the ~6 minute mark where it crashed twice before.

**Alternatives considered**: The previous (incorrect) fix attempt: deleting and recreating the k3d cluster without changing the cgroup driver, which only delayed the recurrence rather than fixing it. Considered kernel command-line workarounds (cgroup_no_v1=all etc.) found during research, but these were reported to cause OOM issues elsewhere and address a different symptom (cgroup v1/v2 detection) than the systemd-unit-creation failure actually seen here.

**Why**: This is a good example of a plausible-sounding first diagnosis (clean exit code, recent unclean shutdowns, corrupted journal file all pointed toward VM-state corruption) turning out to be wrong once tested against a counterexample (fresh cluster, stable VM, same crash). The dbus/systemd unit-creation failure is a known fragile interaction for nested container runtimes on WSL2; forcing cgroupfs at the Docker daemon level removes the fragile path entirely rather than working around symptoms.

**Status**: Active

### [2026-07-16 17:02] Troubleshooting: kubectl get pods failed with couldn't get current server API group list

**Decision**: kubectl get pods intermittently failed with couldn't get current server API group list / the server could not find the requested resource, even though the cluster itself was healthy (kubectl version succeeded, kubectl get apiservices showed everything AVAILABLE: True, and the same command worked fine moments later). Traced to a stale local kubectl discovery cache at ~/.kube/cache/discovery/ -- kubectl caches API discovery info per server host:port, and after recreating the k3d cluster multiple times today (each recreation gets a new random host port for the API server), four separate stale cache directories had accumulated, including one for the current port that was likely cached in an incomplete state right as the cluster was still finishing startup (Traefik CRDs not yet registered). Fixed by rm -rf ~/.kube/cache, forcing a fresh discovery fetch.

**Alternatives considered**: Could have investigated further whether a specific APIService (metrics-server was the first suspect, given it caused a similar stale-discovery warning during the earlier cgroup crash investigation) was actually unhealthy -- ruled out this time since kubectl get apiservices showed everything available.

**Why**: Clearing the cache is the standard, safe fix for this class of kubectl discovery error and also cleans up genuinely dead entries (three of the four cached directories pointed at ports from clusters that no longer exist). Worth remembering this will likely recur every time the cluster gets deleted and recreated, since each recreation gets a fresh random API port.

**Status**: Active
