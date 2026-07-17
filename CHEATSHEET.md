# Local dev cheat sheet

Quick reference for poking at this project by hand — WSL2, Docker, k3d/Kubernetes, and the app itself.

See `docs/k8s-architecture-comparison.svg` for a diagram of how this local WSL2/k3d setup (one machine, Docker-in-Docker) differs from a real production Kubernetes cluster (separate control-plane and worker machines) — useful context for why the cgroup-driver bug below happened at all.

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
kubectl get deploy,svc,ingress         # our app's Deployment, Service, and Ingress in one shot
kubectl describe pod -l app=releaseward-demo   # full detail + Events on our pod (probes, restarts, etc.)
kubectl logs -l app=releaseward-demo           # our app's logs, straight from the pod
kubectl logs -l app=releaseward-demo -f        # stream them live
kubectl exec -it deploy/releaseward-demo -- sh # shell into the APP's own pod (Kubernetes-level)
```

### If you actually want to look inside the node itself (rare, different purpose)

Only needed for infrastructure-level debugging — e.g. inspecting the node's own OS, or the cgroup/systemd issue from `DECISIONS.md` — not for anything pod/app-related, since `kubectl` already covers that without entering any container:

```bash
docker exec -it k3d-releaseward-server-0 sh   # shell into the NODE container itself
```

## Recreating the cluster from scratch

If the cluster ever needs a clean rebuild (and both WSL2 environment fixes in the README's Setup section are already applied):

```bash
k3d cluster delete releaseward
k3d cluster create releaseward --port '8080:80@loadbalancer' \
  --k3s-arg '--kubelet-arg=cgroup-driver=cgroupfs@server:*' --wait
k3d image import releaseward-demo:dev -c releaseward
kubectl apply -f k8s/
kubectl rollout status deployment/releaseward-demo --timeout=60s
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
