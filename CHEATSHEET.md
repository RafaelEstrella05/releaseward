# Local dev cheat sheet

Quick reference for poking at this project by hand — WSL2, Docker, k3d/Kubernetes, and the app itself.

See `docs/k8s-architecture-comparison.svg` for a diagram of how this local WSL2/k3d setup (one machine, Docker-in-Docker) differs from a real production Kubernetes cluster (separate control-plane and worker machines) — useful context for why the cgroup-driver bug below happened at all.

See `docs/releaseward-hybrid-pipeline.svg` for the current GitHub-hosted CI, GHCR publishing, and protected deployment-runner boundaries (now the Hyper-V VM below — the WSL runner has been decommissioned).

## Git feature-branch flow

Start each change from an up-to-date default branch and keep `master` out of day-to-day edits:

```bash
git switch master
git pull --ff-only
git switch -c feature/short-description

# work, then inspect exactly what will be committed
git status
git diff
git add <files>
git diff --cached
git commit -m "Short imperative summary"
git push -u origin feature/short-description
```

Open a pull request into `master`. The feature push and pull request build, test, and scan on disposable GitHub-hosted runners but do not publish or touch k3d. After review and merge, the resulting `master` push reruns the gates, publishes the commit-SHA image to GHCR, and sends its immutable digest to the deployment-only self-hosted runner (Hyper-V, `releaseward-hyperv-deploy` — see below).

## Deployment-only WSL runner (decommissioned — historical reference)

One-time cluster and short-lived credential setup:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/runner-rbac.yaml
kubectl apply -f k8s/service.yaml -f k8s/ingress.yaml
sudo bash scripts/bootstrap-runner-kubeconfig.sh \
  releasewardrunner "$USER" 168h
```

The dedicated account and checksum-verified runner package are already installed on this workstation. Register it using the one-hour token shown under GitHub **Settings -> Actions -> Runners -> New self-hosted runner**. Include the custom label `releaseward-deploy`; read the token into a shell variable as shown in the README instead of placing it in shell history.

Start it from your normal WSL account by running the foreground runner script that used to live at `scripts/start-local-runner.sh`. Keeping that terminal open kept the WSL distribution and Docker/k3d alive while the runner waited for trusted deployment jobs; `Ctrl+C` took it offline. The runner account had no Docker, Service, or Ingress authority and its Deployment-only kubeconfig expired after seven days.

**Decommissioned 2026-07-28, script deleted 2026-07-29**: this WSL runner has been taken offline and replaced by the disposable Hyper-V runner below, and `scripts/start-local-runner.sh` itself has been removed now that a real deploy has round-tripped through the Hyper-V runner (see `DECISIONS.md`, 2026-07-28 and 2026-07-29 20:22 entries). The commands above are left for historical reference only — they won't run as-is anymore.

## Disposable Hyper-V deploy runner (now active — replaced the WSL runner above)

**Status (2026-07-29 20:22): confirmed working via a real deploy.** `releaseward-hyperv-deploy`
is the sole registered self-hosted runner, and a real `master`-push
`deploy-development` job has round-tripped through it successfully — see the
"Replace WSL deploy runner..." entry in `TASKS.md` (now done) and `DECISIONS.md`.

Rationale: WSL2 shares the Windows host's kernel and mounts its drives in
both directions, which is too much shared blast radius for a runner holding
any cluster-deploy authority. This VM is a genuinely isolated, disposable
Hyper-V guest that can be rebuilt from `infra/hyperv-runner/` instead of
hand-patched — same trust boundary as before (deploy-only, no Docker
group, restricted namespace RBAC), different host.

### 1. Build the autoinstall seed ISO (PowerShell, on the Windows host)

Fill in the two `REPLACE_ME_*` placeholders in
`infra/hyperv-runner/autoinstall.yaml` first — your SSH public key, and an
`openssl passwd -6` hash for console/sudo recovery (generate that hash from
WSL: `openssl passwd -6`).

```powershell
mkdir C:\vms\releaseward-runner-seed
copy infra\hyperv-runner\autoinstall.yaml C:\vms\releaseward-runner-seed\user-data
copy infra\hyperv-runner\meta-data        C:\vms\releaseward-runner-seed\meta-data

# oscdimg ships with the Windows ADK "Deployment Tools" component
& "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" `
  -n -d -lCIDATA C:\vms\releaseward-runner-seed C:\vms\releaseward-runner-seed.iso
```

Download the official Ubuntu Server 24.04 LTS ISO from `releases.ubuntu.com`
to e.g. `C:\vms\ubuntu-24.04-live-server-amd64.iso`.

### 2. Create the VM (PowerShell)

```powershell
New-VM -Name releaseward-runner -Generation 2 -MemoryStartupBytes 6GB `
  -NewVHDPath C:\vms\releaseward-runner\disk.vhdx -NewVHDSizeBytes 60GB `
  -SwitchName "Default Switch"
Set-VMProcessor releaseward-runner -Count 2

# Fixed, not dynamic — k3s/kubelet don't expect their memory ceiling to
# change under them after boot
Set-VMMemory releaseward-runner -DynamicMemoryEnabled $false

# Ubuntu's shim is signed for the UEFI CA template, not the Windows-only default
Set-VMFirmware releaseward-runner -SecureBootTemplate MicrosoftUEFICertificateAuthority

$install = Add-VMDvdDrive releaseward-runner -Path C:\vms\ubuntu-24.04-live-server-amd64.iso -Passthru
Add-VMDvdDrive releaseward-runner -Path C:\vms\releaseward-runner-seed.iso
Set-VMFirmware releaseward-runner -FirstBootDevice $install

Start-VM releaseward-runner
vmconnect.exe localhost releaseward-runner
```

`Default Switch` gives NAT networking with no shared clipboard/drives back
to the host — the same isolation model already used for the AI-test-lane
bot VM (see `TASKS.md`).

### 3. Install

In the VM console, at the GRUB menu press `e`, add ` autoinstall` to the
line starting `linux`, then boot (`Ctrl+X` or `F10`). Subiquity installs
non-interactively (`interactive-sections: []`) and reboots on its own —
no further console input needed. Once it reboots, detach both DVD drives
(`Set-VMDvdDrive releaseward-runner -Path $null` for each, or leave them —
they're harmless once the disk has an OS).

### 4. Find its IP and SSH in

```powershell
(Get-VM releaseward-runner | Get-VMNetworkAdapter).IPAddresses
```

```bash
ssh opsadmin@<vm-ip>
```

### 5. Post-boot bootstrap (inside the VM, as opsadmin)

Needs a GitHub self-hosted runner registration token (repo **Settings ->
Actions -> Runners -> New self-hosted runner**, one-hour lifetime — read it
into a shell variable, don't leave it in shell history) and this repo's
clone URL:

```bash
export RELEASEWARD_REPO_URL="https://github.com/<owner>/releaseward.git"
bash infra/hyperv-runner/bootstrap-post-install.sh "$REG_TOKEN"
```

This installs kubectl + a checksum-verified k3d, creates the `releaseward`
k3d cluster, applies `k8s/namespace.yaml` / `k8s/runner-rbac.yaml` /
`k8s/service.yaml` / `k8s/ingress.yaml`, installs the GitHub Actions runner
as a systemd service under `releasewardrunner` with the `releaseward-deploy`
label (survives reboots — no foreground terminal to keep open, unlike the
WSL runner), and finishes by running the existing
`scripts/bootstrap-runner-kubeconfig.sh` to issue its scoped, Deployment-only
kubeconfig. Rerun that last script every 7 days to rotate the token, same as
the WSL setup.

**Done 2026-07-29**: a real deployment round-tripped through this VM successfully, `TASKS.md` and `ARCHITECTURE.md` are updated, and the WSL runner is fully retired — `scripts/start-local-runner.sh` has been deleted.

**Decommissioned 2026-07-28**: this WSL runner has been taken offline and replaced by the disposable Hyper-V runner below. Left here for historical reference only — don't start it back up alongside the Hyper-V runner (see `DECISIONS.md`, 2026-07-28 entries, for why running both at once is a real problem: they'd share the same `releaseward-deploy` label).

## Disposable Hyper-V deploy runner (now active — replaced the WSL runner above)

**Status (2026-07-28 17:46): VM booted, runner registered and online, WSL runner decommissioned — not yet smoke-tested with a real deploy.** See the
"Replace WSL deploy runner..." entry in `TASKS.md`. `releaseward-hyperv-deploy`
is now the sole registered self-hosted runner; nothing has triggered a real
`deploy-development` job through it yet, so treat the next `master` push as
its first real test.

Rationale: WSL2 shares the Windows host's kernel and mounts its drives in
both directions, which is too much shared blast radius for a runner holding
any cluster-deploy authority. This VM is a genuinely isolated, disposable
Hyper-V guest that can be rebuilt from `infra/hyperv-runner/` instead of
hand-patched — same trust boundary as before (deploy-only, no Docker
group, restricted namespace RBAC), different host.

### 1. Build the autoinstall seed ISO (PowerShell, on the Windows host)

Fill in the two `REPLACE_ME_*` placeholders in
`infra/hyperv-runner/autoinstall.yaml` first — your SSH public key, and an
`openssl passwd -6` hash for console/sudo recovery (generate that hash from
WSL: `openssl passwd -6`).

```powershell
mkdir C:\vms\releaseward-runner-seed
copy infra\hyperv-runner\autoinstall.yaml C:\vms\releaseward-runner-seed\user-data
copy infra\hyperv-runner\meta-data        C:\vms\releaseward-runner-seed\meta-data

# oscdimg ships with the Windows ADK "Deployment Tools" component
& "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" `
  -n -d -lCIDATA C:\vms\releaseward-runner-seed C:\vms\releaseward-runner-seed.iso
```

Download the official Ubuntu Server 24.04 LTS ISO from `releases.ubuntu.com`
to e.g. `C:\vms\ubuntu-24.04-live-server-amd64.iso`.

### 2. Create the VM (PowerShell)

```powershell
New-VM -Name releaseward-runner -Generation 2 -MemoryStartupBytes 6GB `
  -NewVHDPath C:\vms\releaseward-runner\disk.vhdx -NewVHDSizeBytes 60GB `
  -SwitchName "Default Switch"
Set-VMProcessor releaseward-runner -Count 2

# Fixed, not dynamic — k3s/kubelet don't expect their memory ceiling to
# change under them after boot
Set-VMMemory releaseward-runner -DynamicMemoryEnabled $false

# Ubuntu's shim is signed for the UEFI CA template, not the Windows-only default
Set-VMFirmware releaseward-runner -SecureBootTemplate MicrosoftUEFICertificateAuthority

$install = Add-VMDvdDrive releaseward-runner -Path C:\vms\ubuntu-24.04-live-server-amd64.iso -Passthru
Add-VMDvdDrive releaseward-runner -Path C:\vms\releaseward-runner-seed.iso
Set-VMFirmware releaseward-runner -FirstBootDevice $install

Start-VM releaseward-runner
vmconnect.exe localhost releaseward-runner
```

`Default Switch` gives NAT networking with no shared clipboard/drives back
to the host — the same isolation model already used for the AI-test-lane
bot VM (see `TASKS.md`).

### 3. Install

In the VM console, at the GRUB menu press `e`, add ` autoinstall` to the
line starting `linux`, then boot (`Ctrl+X` or `F10`). Subiquity installs
non-interactively (`interactive-sections: []`) and reboots on its own —
no further console input needed. Once it reboots, detach both DVD drives
(`Set-VMDvdDrive releaseward-runner -Path $null` for each, or leave them —
they're harmless once the disk has an OS).

### 4. Find its IP and SSH in

```powershell
(Get-VM releaseward-runner | Get-VMNetworkAdapter).IPAddresses
```

```bash
ssh opsadmin@<vm-ip>
```

### 5. Post-boot bootstrap (inside the VM, as opsadmin)

Needs a GitHub self-hosted runner registration token (repo **Settings ->
Actions -> Runners -> New self-hosted runner**, one-hour lifetime — read it
into a shell variable, don't leave it in shell history) and this repo's
clone URL:

```bash
export RELEASEWARD_REPO_URL="https://github.com/<owner>/releaseward.git"
bash infra/hyperv-runner/bootstrap-post-install.sh "$REG_TOKEN"
```

This installs kubectl + a checksum-verified k3d, creates the `releaseward`
k3d cluster, applies `k8s/namespace.yaml` / `k8s/runner-rbac.yaml` /
`k8s/service.yaml` / `k8s/ingress.yaml`, installs the GitHub Actions runner
as a systemd service under `releasewardrunner` with the `releaseward-deploy`
label (survives reboots — no foreground terminal to keep open, unlike the
WSL runner), and finishes by running the existing
`scripts/bootstrap-runner-kubeconfig.sh` to issue its scoped, Deployment-only
kubeconfig. Rerun that last script every 7 days to rotate the token, same as
the WSL setup.

Once a real deployment has round-tripped through this VM successfully,
update `TASKS.md` and `ARCHITECTURE.md` and retire the WSL runner
(`sudo "$HOME/actions-runner/svc.sh" stop` there, or just stop starting
`scripts/start-local-runner.sh`) — don't retire it before that.

## Reproduce the hosted image checks locally

From the repository root inside WSL:

```bash
cd app
npm ci
npm run lint
npm test
cd ..

docker build --pull -t releaseward-demo:validation ./app
docker run --rm -d --name releaseward-validation -p 3000:3000 releaseward-demo:validation
curl http://localhost:3000/livez
curl http://localhost:3000/readyz
docker stop releaseward-validation
```

The workflow is authoritative for the complete two-pass Trivy scans. Never add an unexpected finding to `.trivyignore` merely to make the run green; first identify and remove or patch the component that introduced it.

## Get into WSL

Don't prefix every command with `wsl -d Ubuntu-24.04 --` — just live inside it:

```powershell
wsl -d Ubuntu-24.04
```

This drops you into a real Ubuntu shell. Everything below (except the WSL2 section) runs from there. Type `exit` to leave back to PowerShell.

## WSL2 itself (run from PowerShell, not inside WSL)

```powershell
wsl -l -v          # list distros, confirm which are running and WSL version (should say "2")
wsl --status       # default distro, default version
```

## Docker

```bash
docker ps                    # running containers
docker ps -a                 # all containers, including stopped/crashed ones
docker images                # images you've built/pulled
docker logs <name>           # a container's logs
docker logs -f <name>        # stream logs live (Ctrl+C to stop)
docker stats                 # live CPU/memory per container
docker exec -it <name> sh    # shell inside a running container
```

Try it: `docker ps` should show `k3d-releaseward-server-0` and `k3d-releaseward-serverlb` running.

## k3d / Kubernetes

**You never need to `docker exec` into `k3d-releaseward-server-0` to run any of this.** `kubectl` is a client that talks to the Kubernetes API server *over the network*, using `~/.kube/config` (which k3d wrote automatically, pointing at the port `k3d-releaseward-serverlb` exposes). Same as a real cluster — you don't SSH into a control-plane machine to run `kubectl` there either.

```bash
k3d cluster list                       # k3d clusters (should show "releaseward", 1/1 servers)
kubectl get nodes                      # cluster nodes
kubectl get pods -A                    # every pod, every namespace — the big picture
kubectl get deploy,svc,ingress -n releaseward-dev
kubectl describe pod -n releaseward-dev -l app=releaseward-demo
kubectl logs -n releaseward-dev -l app=releaseward-demo
kubectl logs -n releaseward-dev -l app=releaseward-demo -f
kubectl exec -n releaseward-dev -it deploy/releaseward-demo -- sh
```

### If you actually want to look inside the node itself (rare, different purpose)

Only needed for infrastructure-level debugging — e.g. inspecting the node's own OS, or the cgroup/systemd issue from `DECISIONS.md` — not for anything pod/app-related, since `kubectl` already covers that without entering any container:

```bash
docker exec -it k3d-releaseward-server-0 sh   # shell into the NODE container itself
```

## Observability (Prometheus + Grafana)

Both live in `k8s/observability/` and deploy into the existing `releaseward-dev` namespace. Confirmed working end-to-end on the Hyper-V deploy runner's k3d cluster on 2026-07-29 (see `DECISIONS.md`) — not yet part of the automated deploy pipeline, so apply it by hand:

```bash
kubectl apply -f k8s/observability/
kubectl get pods -n releaseward-dev -l releaseward.dev/component=observability
```

Both `prometheus-...` and `grafana-...` pods should reach `1/1 Running` within a few seconds.

### Reaching them from Windows, through the Hyper-V runner's SSH-only firewall

`infra/hyperv-runner/bootstrap-post-install.sh` locks `ufw` down to SSH only, so a `kubectl port-forward` on the VM isn't reachable at the VM's IP directly — tunnel through the SSH connection you already have instead of opening a port.

On the VM (`ssh opsadmin@<vm-ip>`), background both port-forwards in one shell so you get your prompt back:

```bash
kubectl port-forward -n releaseward-dev svc/prometheus 9090:9090 > /tmp/pf-prometheus.log 2>&1 &
kubectl port-forward -n releaseward-dev svc/grafana 3000:3000 > /tmp/pf-grafana.log 2>&1 &
jobs                     # confirm both are running
# kill %1 / kill %2      # stop one without killing the other
```

Then tunnel both local ports from Windows to the VM over SSH. OpenSSH:

```
ssh -L 9090:localhost:9090 -L 3000:localhost:3000 opsadmin@<vm-ip>
```

PuTTY: **Connection -> SSH -> Tunnels**, add Source port `9090` -> Destination `localhost:9090`, then Source port `3000` -> Destination `localhost:3000` (both **Local**, click **Add** after each) before connecting — or add them to an already-open session live via right-click the title bar -> **Change Settings...** -> same Tunnels page -> **Apply** (no reconnect needed).

### What to check

- Prometheus: `http://localhost:9090/targets` — the `releaseward-demo` job should show `1/1 up`, scraping every ~5s.
- Grafana: `http://localhost:3000` — anonymous Viewer access, no login prompt. The starter dashboard isn't on the default Home page — go to **Dashboards -> releaseward demo service** for the 4 panels (request rate, 5xx error rate, p95 latency, classify events by category). The first three populate from the `/livez`/`/readyz` probes and `/metrics` scrapes alone; the classify panel stays at "No data" until something actually calls `/classify` (see "Actually hitting the app" above).

## Recreating the cluster from scratch

If the cluster ever needs a clean rebuild (and both WSL2 environment fixes in the README's Setup section are already applied):

```bash
k3d cluster delete releaseward
k3d cluster create releaseward --port '8080:80@loadbalancer' \
  --k3s-arg '--kubelet-arg=cgroup-driver=cgroupfs@server:*' --wait
k3d image import releaseward-demo:dev -c releaseward
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/runner-rbac.yaml
kubectl apply -f k8s/service.yaml -f k8s/ingress.yaml
kubectl set image -f k8s/deployment.yaml \
  releaseward-demo=releaseward-demo:dev --local -o yaml |
  kubectl apply -f -
kubectl rollout status -n releaseward-dev \
  deployment/releaseward-demo --timeout=60s
```

If `kubectl` then errors with `couldn't get current server API group list` / `the server could not find the requested resource` even though the cluster looks healthy, clear its stale discovery cache (very likely after any cluster recreation, since each one gets a new random API port):

```bash
rm -rf ~/.kube/cache
```

## Actually hitting the app

Through the real k3d/ingress deployment (from inside WSL):

```bash
curl -H 'Host: releaseward.localhost' http://localhost:8080/livez
curl -H 'Host: releaseward.localhost' http://localhost:8080/readyz
curl -X POST -H 'Host: releaseward.localhost' -H 'Content-Type: application/json' \
  -d '{"text":"Badge access denied at rear entrance after hours"}' \
  http://localhost:8080/classify
```

## Front end in an actual browser

```bash
docker run -d --name releaseward-demo-dev -p 3000:3000 releaseward-demo:dev
```

Then open **http://localhost:3000/** in a normal Windows browser (WSL2 forwards this port automatically — confirmed working). Type something into the form and hit Classify.

## If something looks broken

Check `KNOWN_ISSUES.md` first — the k3d server node has a known, not-fully-eliminated cgroup fragility inside WSL2. If `kubectl` can't reach the cluster, try:

```bash
docker start k3d-releaseward-server-0
```

before assuming anything else is wrong. See `DECISIONS.md` for the full WSL2/k3d stability troubleshooting history (VM idle-timeout, cgroup driver) before assuming it's the app or the manifests.

### Working as your own user, not root

If `docker`/`kubectl` commands fail with permission errors under your own WSL username, you likely need to be added to the `docker` group and get a kubeconfig written for your user (one-time fix, run as root):

```bash
sudo usermod -aG docker $USER
mkdir -p ~/.kube
k3d kubeconfig get releaseward > ~/.kube/config
chmod 600 ~/.kube/config
```

Then close and reopen your WSL terminal (group membership only takes effect on a new login session).
