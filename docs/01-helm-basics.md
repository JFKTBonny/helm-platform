# 01 · Helm basics

## Concepts

| Term | Meaning |
|---|---|
| **Chart** | Package of Kubernetes templates + default values |
| **Values** | Configuration that fills the templates |
| **Release** | One installed instance of a chart |
| **Revision** | Numbered version of a release (every upgrade/rollback adds one) |
| **Repository** | Where charts live: classic HTTP repo or OCI registry |

## Install

```bash
# macOS
brew install helm

# Windows
choco install kubernetes-helm

# Linux (Helm 4)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

helm version
kubectl config current-context
```

## Repositories

```bash
# Classic HTTP repo
helm repo add traefik https://traefik.github.io/charts
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm repo list
helm search repo traefik
helm search repo traefik/traefik --versions
helm search hub cert-manager
helm repo remove traefik
```

```bash
# OCI registry: no "repo add", reference it directly
helm show chart oci://ghcr.io/your-github-user/charts/myapp --version 0.1.0
helm registry login ghcr.io -u your-github-user
```

## Inspect a chart

```bash
helm show chart traefik/traefik
helm show values traefik/traefik > traefik-values.yaml
helm show readme traefik/traefik
```

## Release lifecycle

Install:

```bash
helm install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --version 41.0.2 \
  -f traefik-values.yaml
```

Install or upgrade (idempotent, use in CI):

```bash
helm upgrade --install myapp ./charts/myapp \
  --namespace myapp-dev \
  --create-namespace \
  -f environments/dev/myapp.values.yaml \
  --wait \
  --rollback-on-failure \
  --timeout 5m \
  --history-max 10
```

Inspect:

```bash
helm list -A
helm status myapp -n myapp-dev
helm history myapp -n myapp-dev
helm get values myapp -n myapp-dev
helm get values myapp -n myapp-dev --all
helm get manifest myapp -n myapp-dev
```

Rollback and remove:

```bash
helm rollback myapp -n myapp-dev
helm rollback myapp 3 -n myapp-dev
helm uninstall myapp -n myapp-dev
```

## Values precedence

Lowest → highest:

1. Chart `values.yaml`
2. `-f a.yaml -f b.yaml` (later file wins)
3. `--set`, `--set-string`, `--set-file`, `--set-json`

```bash
--set replicaCount=3
--set image.tag=1.27
--set ingress.hosts[0].host=example.com
--set-string image.tag=1.20
--set nodeSelector."kubernetes\.io/os"=linux
--set args="{--a\,b,--c}"
--set-file config=./app.conf
--set-json 'resources={"limits":{"cpu":"500m"}}'
```

- `\.` escapes a dot inside a key.
- `\,` escapes a comma inside a value.
- `--set-string` keeps number-like values as strings (`1.20` stays `"1.20"`).

## Debug and validate

```bash
helm lint ./charts/myapp --strict
helm template myapp ./charts/myapp -f environments/prod/myapp.values.yaml
helm template myapp ./charts/myapp -s templates/deployment.yaml
helm upgrade --install myapp ./charts/myapp -n myapp-dev --dry-run=server --debug
helm diff upgrade myapp ./charts/myapp -n myapp-dev -f environments/dev/myapp.values.yaml
helm test myapp -n myapp-dev
```

## Helm 3 → 4 notes

| Helm 3 | Helm 4 |
|---|---|
| `--atomic` | `--rollback-on-failure` |
| `--force` | `--force-replace` |
| Plugins install unsigned | `--verify=false` needed for unsigned plugins |
| `--post-renderer ./script.sh` | Post-renderer must be a named plugin |
| `--wait` checks pods | `--wait` uses kstatus (needs `watch` RBAC) |

Old flags still work in Helm 4 with deprecation warnings.

## Cheat sheet

```bash
helm repo add <name> <url>
helm repo update
helm search repo <keyword> --versions
helm show values <chart>
helm upgrade --install <release> <chart> -n <ns> --create-namespace -f values.yaml --wait
helm list -A
helm status <release> -n <ns>
helm history <release> -n <ns>
helm rollback <release> <revision> -n <ns>
helm uninstall <release> -n <ns>
helm get values <release> -n <ns> --all
helm get manifest <release> -n <ns>
helm lint <chart-dir> --strict
helm template <release> <chart-dir> -f values.yaml
helm package <chart-dir>
helm push <chart>-<version>.tgz oci://<registry>/<path>
```
