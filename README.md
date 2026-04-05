# TheLivingLab

A local Kubernetes developer platform (Minimal Viable Platform) that provisions a full-stack, GitOps-managed infrastructure on your machine using [KinD](https://kind.sigs.k8s.io/).

One command gives you a 3-node Kubernetes cluster with ingress routing, GitOps delivery, and a full monitoring stack -- all running locally in Docker.

## What You Get

| Service | URL | Credentials |
|---|---|---|
| ArgoCD | https://argocd.localhost | `admin` / see [Getting the ArgoCD Password](#getting-the-argocd-password) |
| Grafana | http://grafana.localhost | `admin` / `admin` |
| Prometheus | http://prometheus.localhost | -- |

## Architecture

```
                  ┌─────────────────────────────────────────────────┐
                  │              KinD Cluster (living-lab)          │
                  │                                                 │
  localhost:80  ──┤  ┌──────────────────┐                           │
  localhost:443   │  │  NGINX Ingress   │  (control-plane node)     │
                  │  │  (hostPort)      │                           │
                  │  └──────┬───────────┘                           │
                  │         │                                       │
                  │  ┌──────▼───────────┐  ┌──────────────────────┐ │
                  │  │  ArgoCD          │  │  Prometheus + Grafana │ │
                  │  │  (GitOps)        │  │  (monitoring)         │ │
                  │  └──────┬───────────┘  └──────────────────────┘ │
                  │         │                                       │
                  │         │  watches git repo                     │
                  │         ▼                                       │
                  │  ┌──────────────────┐                           │
                  │  │  App-of-Apps     │  (apps/ directory)        │
                  │  │  root-app.yaml   │                           │
                  │  └──────────────────┘                           │
                  │                                                 │
                  │  ┌─────────┐  ┌─────────┐                      │
                  │  │ Worker 1│  │ Worker 2│                      │
                  │  └─────────┘  └─────────┘                      │
                  └─────────────────────────────────────────────────┘
```

### Cluster Topology

- **1 control-plane node** -- runs NGINX Ingress via hostPort, maps ports 80/443 to localhost
- **2 worker nodes** -- run application workloads
- **Kubernetes version:** v1.27.1

### GitOps Flow (App-of-Apps Pattern)

ArgoCD watches this Git repository and automatically reconciles the cluster state:

```
root-app.yaml (apps/)
  ├── ingress-nginx.yaml  →  Helm chart: ingress-nginx 4.*
  └── monitoring.yaml     →  Helm chart: kube-prometheus-stack 82.*
```

Each ArgoCD Application references a Helm chart and pulls its `values.yaml` from the `platform/` directory in this repo. Changes pushed to `main` are automatically synced with pruning and self-healing enabled.

## Project Structure

```
TheLivingLab/
├── bootstrap.sh                  # Single entry point -- provisions everything
├── Makefile                      # Standard commands (up, down, status, etc.)
├── apps/                         # ArgoCD Application manifests
│   ├── root-app.yaml             #   Root Application (App-of-Apps)
│   ├── ingress-nginx.yaml        #   NGINX Ingress Controller
│   └── monitoring.yaml           #   Prometheus + Grafana
├── platform/                     # Helm values for platform services
│   ├── argocd/
│   │   └── values.yaml           #   ArgoCD config (insecure mode, ingress)
│   ├── ingress-nginx/
│   │   └── values.yaml           #   NGINX config (hostPort, KinD tolerations)
│   └── monitoring/
│       └── values.yaml           #   Prometheus/Grafana config (KinD-optimized)
├── terraform/                    # Cluster provisioning
│   ├── providers.tf              #   Terraform >= 1.0.0, tehcyx/kind ~> 0.11.0
│   ├── main.tf                   #   KinD cluster definition (3 nodes)
│   └── outputs.tf                #   Exports: endpoint, kubeconfig path
└── micro-builds/                 # Placeholder for application workloads
    └── .gitkeep
```

## Prerequisites

The following tools must be installed and available on your `PATH`:

| Tool | Minimum Version | Purpose |
|---|---|---|
| [Docker](https://www.docker.com/products/docker-desktop) | -- | Container runtime for KinD |
| [Terraform](https://developer.hashicorp.com/terraform/install) | >= 1.0.0 | Cluster provisioning |
| [KinD](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) | -- | Local Kubernetes clusters |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | -- | Cluster interaction |
| [Helm](https://helm.sh/docs/intro/install/) | -- | Chart installation |

Docker Desktop must be running before you start.

### macOS (Homebrew)

```bash
brew install terraform kind kubectl helm
```

### Linux

```bash
# Terraform
sudo apt-get update && sudo apt-get install -y terraform

# KinD
go install sigs.k8s.io/kind@latest

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

## Quick Start

```bash
# Clone the repository
git clone https://github.com/JMrtzsn/TheLivingLab.git
cd TheLivingLab

# Bring up the entire platform
make up

# Set your KUBECONFIG (printed by bootstrap)
export KUBECONFIG=~/.kube/living-lab-config
```

That's it. After 3-5 minutes you'll have:
- ArgoCD at https://argocd.localhost
- Grafana at http://grafana.localhost (once ArgoCD syncs the monitoring app)
- Prometheus at http://prometheus.localhost (once ArgoCD syncs the monitoring app)

## Usage

### Makefile Targets

| Command | Description |
|---|---|
| `make up` | Bootstrap the full platform (cluster + services) |
| `make down` | Tear down cluster and all resources |
| `make status` | Show cluster nodes, pods across all namespaces, ArgoCD apps |
| `make argocd-password` | Print the ArgoCD admin password |
| `make kubeconfig` | Print the `export KUBECONFIG=...` command to set |
| `make pods` | List all pods across all namespaces |
| `make logs-argocd` | Tail ArgoCD server logs |
| `make logs-ingress` | Tail NGINX Ingress controller logs |
| `make sync` | Force-sync all ArgoCD applications |
| `make help` | Show all available targets |

### Getting the ArgoCD Password

```bash
make argocd-password

# Or manually:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Accessing Services

All services are exposed via NGINX Ingress on `localhost`. The hostnames (`*.localhost`) resolve to `127.0.0.1` on most systems without `/etc/hosts` changes.

If the `.localhost` domains don't resolve, add to `/etc/hosts`:

```
127.0.0.1 argocd.localhost grafana.localhost prometheus.localhost
```

### Setting KUBECONFIG

The bootstrap creates a kubeconfig at `~/.kube/living-lab-config`. Set it in your shell:

```bash
export KUBECONFIG=~/.kube/living-lab-config

# Or use it per-command:
kubectl --kubeconfig ~/.kube/living-lab-config get nodes
```

## Bootstrap Process

`bootstrap.sh` executes 6 sequential steps:

1. **Pre-flight checks** -- Verifies all required CLI tools are installed and Docker is running.
2. **Terraform apply** -- Creates the 3-node KinD cluster and writes the kubeconfig.
3. **Wait for nodes** -- Blocks until all nodes report `Ready`.
4. **Install NGINX Ingress** -- Direct Helm install (must exist before ArgoCD can create its own Ingress).
5. **Install ArgoCD** -- Direct Helm install (the "chicken" that manages everything else via GitOps).
6. **Apply root Application** -- `kubectl apply` of `apps/root-app.yaml`. ArgoCD takes over from here, syncing all other applications from Git.

Steps 4 and 5 install directly via Helm rather than through ArgoCD because ArgoCD itself depends on Ingress being available, and ArgoCD obviously can't install itself. Once running, ArgoCD assumes management of NGINX Ingress and the monitoring stack through the App-of-Apps pattern.

## Teardown

```bash
make down

# Or manually:
terraform -chdir=terraform destroy -auto-approve
```

This destroys the KinD cluster and all resources. The kubeconfig file at `~/.kube/living-lab-config` is also removed by Terraform.

## How It Works

### Terraform (Cluster Provisioning)

The `terraform/` directory uses the [`tehcyx/kind`](https://registry.terraform.io/providers/tehcyx/kind/latest) provider to declaratively manage the KinD cluster. The cluster definition in `main.tf`:

- Creates a cluster named `living-lab` with Kubernetes v1.27.1
- Configures 1 control-plane node with `ingress-ready=true` label and port mappings for 80/443
- Adds 2 worker nodes for workload scheduling
- Writes the kubeconfig to `~/.kube/living-lab-config`

State is stored locally (gitignored) since this is a local-only environment.

### NGINX Ingress (Routing)

Configured for KinD's constraints in `platform/ingress-nginx/values.yaml`:

- **hostPort mode** -- Binds directly to ports 80/443 on the control-plane node (KinD has no cloud LoadBalancer)
- **NodePort service type** -- Replaces the default LoadBalancer type
- **Control-plane scheduling** -- Tolerates control-plane taints and selects nodes with `ingress-ready=true`
- **Single replica** -- Sufficient for local development

### ArgoCD (GitOps)

Configured for local development in `platform/argocd/values.yaml`:

- **Insecure mode** -- No TLS on the server (localhost only)
- **Single replicas** -- All components run with 1 replica
- **Dex disabled** -- No SSO for local dev
- **Redis HA disabled** -- Single-instance Redis
- **Ingress** -- Accessible at `argocd.localhost` via NGINX

The root Application (`apps/root-app.yaml`) points at the `apps/` directory in this repo. ArgoCD discovers all `Application` manifests there and syncs them automatically with `prune: true` and `selfHeal: true`.

### Monitoring (Prometheus + Grafana)

The `kube-prometheus-stack` chart is deployed via ArgoCD with KinD-specific tuning in `platform/monitoring/values.yaml`:

- **Disabled scrapers** -- `kubeEtcd`, `kubeScheduler`, `kubeControllerManager`, `kubeProxy` are disabled because KinD control-plane components bind to `127.0.0.1` inside the container node (unreachable from the pod network)
- **Suppressed alert rules** -- Corresponding alert rules disabled to avoid false-positive "target down" alerts
- **Low resource requests** -- Tuned for running on a development machine
- **No persistent storage** -- Prometheus has 24h retention with no PVCs
- **Grafana** -- Accessible at `grafana.localhost`, default password `admin`

## Adding a New Service

To add a new service managed by ArgoCD:

1. Create a Helm values file in `platform/<service-name>/values.yaml`
2. Create an ArgoCD Application manifest in `apps/<service-name>.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-service
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  sources:
    - repoURL: https://example.com/helm-charts  # Helm chart repo
      chart: my-chart
      targetRevision: "1.*"
      helm:
        valueFiles:
          - $values/platform/my-service/values.yaml
    - repoURL: https://github.com/JMrtzsn/TheLivingLab.git
      targetRevision: HEAD
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: my-service
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

3. Push to `main`. ArgoCD will detect and sync the new application automatically.

## Troubleshooting

### ArgoCD shows "ComparisonError"

The root Application points to `https://github.com/JMrtzsn/TheLivingLab.git`. ArgoCD needs the repo to be pushed and accessible. If you're working on a fork, update the `repoURL` in `apps/root-app.yaml` and all Application manifests in `apps/`.

### Services not appearing after bootstrap

Grafana and Prometheus are deployed by ArgoCD via GitOps, not by the bootstrap script directly. After bootstrap completes, it takes 1-3 minutes for ArgoCD to sync. Check sync status:

```bash
make status
# or
kubectl -n argocd get applications
```

### Port 80/443 already in use

Another process is binding to ports 80 or 443. Common culprits: Apache, another NGINX, or another KinD cluster. Free the ports and re-run.

### `.localhost` domains not resolving

Most modern systems resolve `*.localhost` to `127.0.0.1` automatically (RFC 6761). If yours doesn't, add entries to `/etc/hosts`:

```
127.0.0.1 argocd.localhost grafana.localhost prometheus.localhost
```

### Cluster won't start

Ensure Docker Desktop is running and has enough resources allocated. The 3-node cluster needs approximately 4 GB of RAM and 4 CPU cores.
