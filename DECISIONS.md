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

**Status**: Superseded by [2026-07-28 10:19] Deploy runner moves from WSL to a disposable Hyper-V VM, provisioned via autoinstall — the runner and k3d moved off WSL entirely (still Linux, still not native Windows; the host changed, not the "not Windows" reasoning here).

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

### [2026-07-25 16:12] Trivy two-pass security gate with an explicit fixture baseline

**Decision**: The filesystem security job runs after lint/test in two passes: an unsuppressed evidence scan reports every HIGH/CRITICAL vulnerability, secret, and misconfiguration, then a blocking scan suppresses only the exact intentional fixture IDs in .trivyignore and fails on any other finding. A project-specific Trivy rule detects a guaranteed synthetic releaseward_demo_ secret fixture. The Trivy Action v0.36.0 reference is pinned to immutable commit ed142fd0673e97e23eac54620cfb913e5ce36c25. Image scanning remains part of the next Docker build/publish task, when the workflow has an image artifact to scan.

**Alternatives considered**: Considered allowing the intentional fixtures to fail every workflow, which would block all downstream build/deploy work; making the scan warning-only, which would not be a real gate; broadly excluding fixture files or scanner categories, which could hide unrelated findings; and referencing the Trivy Action by a movable version tag instead of a full commit SHA.

**Why**: The two-pass design keeps visible proof that Trivy detects the demo flaws while preserving a usable pipeline and failing closed on new HIGH/CRITICAL findings. Exact-ID suppression is narrower than skipping files or scanners. SHA pinning is especially important because Trivy GitHub Actions tags were force-moved during the March 2026 supply-chain compromise. Local negative testing also proved that removing the allowlist produces exit code 1 rather than a false green result.

**Status**: Active

### [2026-07-26 20:35] Hybrid runner trust boundary for public pull requests

**Decision**: All pull-request quality checks, filesystem scanning, Docker builds, and image scanning run on disposable GitHub-hosted Ubuntu runners. Pull requests and non-default-branch pushes are build-and-verify only: they cannot publish an image or access the laptop's k3d cluster. Publishing is restricted to a successful `push` event on `master`. The later self-hosted WSL runner will be deployment-only, limited to trusted refs and explicit labels; it will pull a previously verified image rather than execute pull-request code.

**Alternatives considered**: Running the entire workflow on the persistent WSL self-hosted runner; exposing k3d to GitHub-hosted runners; creating an ephemeral Hyper-V Ubuntu VM for every job; and replacing the push-based deployment runner with a pull-based GitOps controller.

**Why**: A public-repository pull request can change application code and, depending on trigger design, workflow behavior. Running that code on the laptop would expose a persistent machine with Docker/k3d access. GitHub-hosted runners provide a fresh CI environment and no network path to the local cluster. A disposable Hyper-V runner is technically possible, but VM image creation, registration-token handling, cleanup, networking, and recovery would add substantial platform work before the core pipeline is complete. The hybrid boundary preserves the reason for a self-hosted runner—local cluster reachability—without using it as a general CI executor.

**Status**: Active

### [2026-07-26 20:36] Image release policy: scan every build, publish only immutable master artifacts

**Decision**: The `image-build` job runs only after lint/test and the filesystem security gate. It builds `ghcr.io/<owner>/<repository>:<commit-sha>`, runs the same two-pass Trivy evidence/enforcement pattern against the final image, and fails on any unaccepted HIGH/CRITICAL vulnerability or secret. Only a successful `master` push logs in to GHCR and publishes the SHA tag; the returned repository digest is recorded in the GitHub Actions job summary. Feature branches and pull requests stop after build and verification.

**Alternatives considered**: Publishing images from every branch or pull request; using mutable tags such as `latest`; scanning only the repository lockfile; pushing before scanning; and allowing all image findings while the demo contains intentional fixtures.

**Why**: A commit SHA creates a direct source-to-image identity, while the registry digest provides the content identity needed for later deployment-by-digest. Scanning the actual runtime image catches operating-system and globally installed tool vulnerabilities that a repository scan cannot see. Event-gated login keeps package-write capability off the execution path for pull requests, and exact fixture suppression preserves the intentional security demonstration without hiding unrelated findings.

**Status**: Active

### [2026-07-26 20:37] Trivy findings drove a smaller, patched runtime image

**Decision**: Replace the single-stage `npm install` image with a two-stage Docker build. The dependency stage uses lockfile-enforced `npm ci --omit=dev`. The runtime stage upgrades Alpine packages, copies only production dependencies and runtime source, removes npm/npx and npm's bundled dependency tree, and continues to run as numeric non-root UID/GID `10001`.

**Alternatives considered**: Adding the newly reported OpenSSL/npm CVEs to `.trivyignore`; leaving npm in the runtime image; changing the security gate to warning-only; or switching base images without understanding which components introduced the findings.

**Why**: The first strict image scan correctly found unintentional HIGH vulnerabilities in the base image's OpenSSL packages and in npm's bundled tooling. They were not part of the documented demo fixture and therefore should not be allowlisted. Upgrading the runtime packages fixed the OpenSSL findings, while removing a package manager that the running service does not need eliminated its vulnerable transitive tooling and reduced attack surface. The rebuilt image passed the strict scan with only the exact intentional lodash fixture suppressed.

**Status**: Active

### [2026-07-26 20:38] OneDrive checkout is not the authoritative clean-install environment

**Decision**: Treat GitHub-hosted Ubuntu and WSL/Docker as the authoritative clean-build environments. Native Windows commands remain convenient for editing and quick checks, but clean dependency installation and release validation must not depend on the OneDrive-backed working tree. When native `npm ci` is blocked by inherited OneDrive ACL/reparse-point behavior, use an isolated non-OneDrive validation directory or the container build, then restore the ignored local dependency folder without changing tracked files.

**Alternatives considered**: Disabling the lockfile clean install in CI; weakening the test requirement; forcibly deleting OneDrive-managed directories; moving the repository immediately; or treating the Windows filesystem error as an application failure.

**Why**: A native `npm ci` attempt failed while removing `node_modules/acorn-jsx` because the OneDrive parent carries a deny-delete ACL and placeholder/reparse attributes. The same locked dependencies, lint, and seven tests passed from an isolated `C:\tmp` copy, proving the failure was environmental rather than a source defect. The local `node_modules` tree was restored and the real project path subsequently passed lint and all tests with normal host permissions. Keeping clean builds on disposable Linux runners also matches the production-like environment and avoids making an interview demo depend on OneDrive internals.

**Status**: Active

### [2026-07-27] Correction: WSL VM lifetime and distribution lifetime are separate

**Decision**: Keep `vmIdleTimeout=-1`, but stop treating it as sufficient to keep Ubuntu's systemd services alive. Testing showed one stable WSL kernel boot while `docker.service` was explicitly stopped each time the last `wsl.exe` process exited. A temporary foreground process kept Docker and k3d stable; the permanent demo mechanism is the GitHub runner itself running in a foreground WSL terminal through `scripts/start-local-runner.sh`.

**Alternatives considered**: A systemd runner service, Hyper-V VM provisioning, Windows Task Scheduler, and an arbitrary keepalive process.

**Why**: A systemd service did not hold this distribution open, while a foreground Windows-to-WSL process did. The runner naturally supplies that process and avoids adding another daemon or VM platform four days before the interview. Task Scheduler remains an option if unattended startup later becomes a real requirement.

**Status**: Active

### [2026-07-27] Development deployment uses a digest and no Docker socket

**Decision**: A successful protected `master` push publishes a commit-SHA image on a disposable hosted runner and passes the returned GHCR digest to a deployment-only job. The WSL job validates the repository/digest prefix, applies only trusted manifests to `releaseward-dev`, annotates the Deployment with source revision and digest, waits for rollout, and checks liveness/readiness through ingress. k3d's containerd pulls the public GHCR image directly; the runner does not run `docker pull`, import images, or receive Docker-group access.

**Alternatives considered**: Giving the runner Docker access and importing the image into k3d, deploying a mutable tag, publishing from feature branches, and treating the registry tag as an environment.

**Why**: The commit SHA and registry digest identify source and content; neither is a deployment environment. `master` establishes reviewed provenance, while the Kubernetes namespace establishes the current development target. Removing the Docker socket eliminates a root-equivalent host capability and still permits exact artifact promotion.

**Status**: Active

### [2026-07-27] Namespace-scoped deployment identity for the public repository runner

**Decision**: Run the self-hosted agent as a dedicated `releasewardrunner` Unix account with no Docker membership and no access to the normal user's cluster-admin kubeconfig. Its seven-day service-account credential can create/update/watch only Deployments in `releaseward-dev`. Service and Ingress changes remain one-time cluster-admin operations. The workflow requires the `releaseward-deploy` label and is conditional on a `push` to `master`; pull-request jobs remain hosted.

**Alternatives considered**: Reusing the normal WSL user and admin kubeconfig, granting cluster-admin, storing a permanent service-account secret, or running all CI on the self-hosted machine.

**Why**: Repository workflow restrictions reduce which jobs should reach the machine, while the separate OS and Kubernetes identities reduce what a dispatched job could do. Trivy flagged runner write access to Services and Ingresses as HIGH because those resources can redirect traffic, so that unnecessary authority was removed instead of allowlisted. The credential lifetime covers the interview window and can be rotated with the bootstrap script. This is defense in depth, not a claim that a persistent runner on a public repository is risk-free.

**Status**: Active

### [2026-07-28 09:36] Documented the existing master branch ruleset as a named pipeline-security control

**Decision**: Record, in ARCHITECTURE.md and here, the `Protect Master` GitHub repository ruleset that was already configured through the GitHub UI on 2026-07-26 but never written down. Verified via `gh api repos/<owner>/releaseward/rulesets/<id>` rather than assumed. The active ruleset on `master`: blocks branch deletion (`deletion`) and force-pushes (`non_fast_forward`); requires a pull request to merge (`required_approving_review_count: 0` — no mandatory second reviewer, appropriate for a solo-maintainer repository); requires `lint-and-test`, `filesystem-security`, and `image-build` to report success before merge (`required_status_checks`, strict policy); and `current_user_can_bypass` is `never` for every actor, including repo admins.

**Alternatives considered**: Leaving the ruleset undocumented and implicit; requiring a mandatory human-approval count on a repository with one maintainer (rejected — no second reviewer exists to require); including `deploy-development` in the required status checks (rejected — that job only runs after a merge lands on `master`, so requiring it pre-merge is not meaningful).

**Why**: The workflow's lint/Trivy/build gates only matter if a change is actually forced through them. Without a branch ruleset, a direct push or a force-push to `master` bypasses every gate the workflow encodes. This makes the existing GitHub-level control an explicit, auditable part of the pipeline's security posture instead of an unwritten setting only visible in the repo UI.

**Status**: Active. Secret scanning / push protection status was **not verifiable** with the current token's permissions (`GET /repos/.../` returned `security_and_analysis: null`) — confirm directly in GitHub → Settings → Code security and add a follow-up entry once checked.

### [2026-07-28 09:45] Prometheus metrics + Grafana dashboard added, verified only where this environment allows

**Decision**: Instrument the demo service with `prom-client` (zero transitive dependencies, confirmed via `npm ls prom-client`): a `/metrics` endpoint, an `http_request_duration_seconds` histogram labeled by method/route/status code, a `releaseward_classify_events_total` counter labeled by classification category, and Node's default process metrics. Add `k8s/observability/` manifests: a single-replica Prometheus (static-config scrape of the existing `releaseward-demo` Service, no RBAC/pod-discovery needed) and a single-replica Grafana (anonymous Viewer access enabled — no admin credential is provisioned or checked in) with a provisioned datasource and a four-panel starter dashboard (request rate, 5xx error rate, p95 latency, classify events by category), all in the existing `releaseward-dev` namespace.

**Alternatives considered**: a full `kube-prometheus-stack` Helm install (rejected as more operational surface than a v1 needs, and Helm isn't otherwise used in this repo); Kubernetes service-discovery scraping via a `ClusterRole` (rejected — a static target against the existing Service avoids adding new RBAC surface for a first pass); a real Grafana admin password (rejected — anonymous Viewer access covers "look at the dashboard" without checking a credential, even a placeholder one, into a manifest, which would risk becoming a real, undocumented secret finding rather than the deliberate fixture already tracked in `SECURITY_FLAWS.md`); a separate `releaseward-monitoring` namespace (deferred — adds RBAC/ingress work disproportionate to the remaining time budget; revisit if the observability stack needs its own trust boundary later).

**Why**: Structured JSON logs prove a request happened but don't surface a regression or anomaly on their own — this was an explicit, named gap in `ARCHITECTURE.md`. This session's sandbox environment has Node/npm but **no Docker, kubectl, or k3d** (confirmed: `docker info` unreachable, `kubectl`/`k3d` not on `PATH`) — by design, this is the isolated AI-agent environment, not the machine that runs the actual cluster. So the app-level instrumentation was built and verified for real here (`npm ci`, lint, all 7 unit tests, and a live `curl` against a running `node server.js` confirming `/metrics`, the duration histogram across 200/400/404 status codes, and the classify counter across categories). The Prometheus/Grafana manifests were authored carefully and validated for YAML/JSON syntax (`python3 -c "import yaml"` parsing all five files plus the embedded `prometheus.yml` and dashboard JSON), and current stable image tags (`prom/prometheus:v2.53.5`, `grafana/grafana:13.1.1`) were confirmed to exist before pinning them — but `kubectl apply` and an actual Grafana dashboard load have **not** been verified, since this environment cannot reach a cluster.

**Status**: Active, partially verified. **Open follow-up**: apply `k8s/observability/*.yaml` against the real k3d cluster and confirm the dashboard renders live data before calling this task fully done — do not treat "manifests exist and parse" as equivalent to "the pipeline proved this end-to-end." Note (2026-07-28): the k3d cluster this refers to now lives on the Hyper-V deploy runner (`infra/hyperv-runner/`), not WSL — see the 2026-07-28 10:19 entry below.

### [2026-07-28 10:19] Deploy runner moves from WSL to a disposable Hyper-V VM, provisioned via autoinstall

**Decision**: Write `infra/hyperv-runner/autoinstall.yaml` (Ubuntu 24.04 LTS Subiquity autoinstall, headless, pubkey-only SSH, `interactive-sections: []`) plus `infra/hyperv-runner/meta-data` and a companion `infra/hyperv-runner/bootstrap-post-install.sh` to stand up the self-hosted deployment runner on an isolated Hyper-V guest instead of inside WSL2. The dedicated `releasewardrunner` account is created by autoinstall's `late-commands` but deliberately left out of the `docker` group; the admin account (`opsadmin`) gets `docker` group membership. GitHub Actions runner registration and k3d/kubectl installation are kept out of the autoinstall image entirely — a registration token is a short-lived secret that shouldn't be baked into a reusable install artifact — and instead run from the post-boot script, which checksum-verifies the k3d binary against the release's own `sha256sum.txt` and prompts the operator to confirm the Actions runner tarball's checksum against the GitHub release page before extracting it. `scripts/bootstrap-runner-kubeconfig.sh` and `k8s/runner-rbac.yaml` are reused unchanged (already Linux-generic, not WSL-specific); `scripts/start-local-runner.sh` is not reused since its foreground-keepalive model was a WSL-specific workaround (see the 2026-07-27 "WSL VM lifetime" entry) — the new VM registers the runner as a real systemd service via `svc.sh install`/`svc.sh start` instead.

**Alternatives considered**: Leaving the runner on WSL2 (rejected per the user's explicit direction below); re-mastering the Ubuntu ISO with the seed baked in (rejected — a separate NoCloud CIDATA seed ISO, attached as a second virtual DVD, needs no ISO surgery and is easier to regenerate when the SSH key or password hash changes); using `curl | sh` for k3d/the Actions runner install as most quick-start guides do (rejected — this repo already moved off floating-tag/unverified third-party install patterns once, for the Trivy Action supply-chain incident, so the new runner gets the same checksum-verification treatment rather than reintroducing an unverified download); baking kubectl/k3d installation into autoinstall's `late-commands` (rejected — those commands execute inside curtin's install-time chroot, where snapd/dbus aren't reliably available and a failed network step is much harder to retry than in a normal post-boot shell).

**Why**: The user judged WSL2's shared-kernel, bidirectionally-mounted-drive model too risky for a runner holding any cluster-deploy authority, even the already-restricted one documented in the 2026-07-27 "Namespace-scoped deployment identity" entry, and asked to replace it outright rather than add a separate staging/production VM alongside it. This changes a premise the "Staging and production environments on isolated Hyper-V VMs" `TASKS.md` entry had stated (that the existing WSL dev runner would be left as-is) — noted directly on that task rather than silently reinterpreted.

**Status**: Active. Booted for real on the Hyper-V host: the runner (`releaseward-hyperv-deploy`) is registered and online, and the WSL runner has been decommissioned outright rather than left running alongside it — it is not a parallel/standby runner, it's retired. `releaseward-hyperv-deploy` is now the sole registered self-hosted runner. Not yet exercised by a real `deploy-development` job — `gh run list` shows nothing since the last WSL-runner deploy on 2026-07-27T22:20Z, and this AI-bot session's scoped PAT can't independently confirm runner registration via the API (`GET /actions/runners` → 403), so that part rests on the user's direct report. Confirm one real `master`-push deploy round-trips successfully through it before marking the "Replace WSL deploy runner..." task done in `TASKS.md`.

### [2026-07-27 15:58] Self-hosted deploy task closed after a real Actions-triggered run

**Decision**: Merge `feature/k3d-dev-deployment` into `master` (PR #2, `1678662`) and mark the self-hosted-runner deployment task done, on the strength of a real `git push`-triggered Actions run rather than only the earlier manual/local exercise of the restricted deployment identity.

**Alternatives considered**: Marking the task done on local verification alone; waiting for an additional run before closing it.

**Why**: The task's own purpose was "does the pipeline actually ship it" — that requires proof the WSL runner picks up a job dispatched by GitHub Actions itself, not just that the kubeconfig and manifests work when invoked by hand. The observed run (`lint-and-test` 18s, `filesystem-security` 17s, `image-build` 43s, `deploy-development` 14s, total 1m45s, all green) is that proof.

**Status**: Active

### [2026-07-29 20:22] Hyper-V deploy runner closed out after fixing real bugs found in live debugging

**Decision**: Mark the "Replace WSL deploy runner..." task done, after a live debugging session (not just accepting the user's earlier "reported online" status) uncovered and fixed several concrete bugs rather than just retrying blindly, then confirmed a real `master`-push `deploy-development` job actually succeeded on the rebuilt runner.

**Alternatives considered**: Accepting the 2026-07-28 17:34 "reported online" update as sufficient (rejected — that entry itself said the task should stay in-progress until a real round-trip landed, and the runner turned out to be silently crash-looping the whole time); patching around the symptoms with ad hoc commands each time instead of fixing the underlying script (rejected — several of these were reusable bugs in checked-in `infra/hyperv-runner/bootstrap-post-install.sh` that would recur on any future rebuild, including the planned staging/production VMs).

**Why**: `systemctl status` showed the service `active (running)` the entire time because `runsvc.sh`'s auto-restart loop was masking a `Runner.Listener` process that crashed on every launch — a `FileStream`/permission exception opening `releasewardrunner`-owned `.credentials` (mode 600) from a process actually running as `opsadmin`. Root cause: a manual `sudo ./svc.sh install` (no explicit user argument) silently defaults the systemd service to whatever user `sudo` resolves to, not the intended `releasewardrunner` — `svc.sh` gives no warning that it registered the wrong identity. Separately, `svc.sh` requires its directory to be the shell's actual `cwd`; an absolute path alone fails with "Must run from runner root or install is corrupt."

Rebuilding from scratch surfaced two real, fixable bugs in `bootstrap-post-install.sh` itself: (1) it fetched a k3d checksum file named `sha256sum.txt`, but k3d's actual release asset (verified live against the v5.7.4 GitHub release) is named `checksums.txt` — 404, script aborted under `set -e`; (2) the shared `tmp_dir` from `mktemp -d` defaults to mode 700 owned by `opsadmin` (who runs the script), but the runner tarball inside it is later `tar`'d as `releasewardrunner` via `sudo -u` — permission denied until a `chmod 711` was added immediately after the directory's creation. Both fixed directly in the script rather than worked around by hand, since the same bugs would otherwise hit the staging/production Hyper-V VMs that are meant to reuse this exact script.

Two more non-script snags, resolved but not requiring a code fix: a stale, differently-named runner registration (`releaseward-runner`, missing the `releaseward-deploy` label — leftover from an earlier ad hoc/manual registration, not this script) had no visible removal path in the GitHub web UI for either the AI-bot's scoped identity or the user's own repo-admin browser session (only "Copy label" appeared); it had to be force-deleted via `gh api -X DELETE repos/.../actions/runners/<id>` using the user's personally-authenticated `gh` session, since the AI-bot's PAT is deliberately scoped without runners-administration access and 403s on that endpoint. And the bootstrap script's final step (`scripts/bootstrap-runner-kubeconfig.sh`, installing the restricted deploy-only kubeconfig) was skipped during manual recovery after `svc.sh install` first failed, causing the first real `deploy-development` attempt to fail on a bare `kubectl get deployments.apps` — traced to a completely missing `~/.kube/config` for `releasewardrunner`, fixed by running that script by hand; its own self-check confirmed the RBAC boundary (deployments patchable; namespace-list, secrets, services, and ingress-patch all correctly refused).

**Status**: Active. Confirmed via workflow run `30473735741` (`master` push, re-triggered after the fixes): `lint-and-test`, `filesystem-security`, `image-build`, and `deploy-development` all completed successfully, with `deploy-development` actually executing on `releaseward-hyperv-deploy`. `infra/hyperv-runner/bootstrap-post-install.sh` now downloads the correct k3d checksum filename and chmods its shared temp directory so the runner-tarball extraction step (which intentionally runs as a different, unprivileged user) can read it.
