# myapp chart

Example application chart: Deployment, Service, optional Ingress, HPA, ConfigMap and a pre-upgrade migration Job.

## Install

From this repo:

```bash
helm upgrade --install myapp ./charts/myapp \
  --namespace myapp-dev \
  --create-namespace \
  -f environments/dev/myapp.values.yaml
```

From the published OCI package:

```bash
helm upgrade --install myapp oci://ghcr.io/your-github-user/charts/myapp \
  --version 0.1.0 \
  --namespace myapp-dev \
  --create-namespace \
  -f environments/dev/myapp.values.yaml
```

## Key values

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `1` | Ignored when `autoscaling.enabled=true` |
| `image.repository` | `nginx` | Container image |
| `image.tag` | `""` | Empty uses `appVersion` from `Chart.yaml` |
| `service.type` / `service.port` | `ClusterIP` / `80` | Service exposure |
| `ingress.enabled` | `false` | Requires `ingress.host` when `true` |
| `ingress.className` | `""` | e.g. `traefik` |
| `ingress.tls.enabled` | `false` | Uses `<fullname>-tls` unless `secretName` is set |
| `env` | `{LOG_LEVEL: info}` | Plain env vars (map) |
| `existingSecret` | `""` | Secret loaded with `envFrom` |
| `config.enabled` | `true` | Mounts `files/app.conf` at `/etc/myapp`, restarts pods on change |
| `autoscaling.enabled` | `false` | Creates an HPA (needs metrics-server) |
| `migrations.enabled` | `false` | Pre-install / pre-upgrade Job |

`values.schema.json` validates values on every `install`, `upgrade`, `lint` and `template`.

## Test

```bash
helm lint ./charts/myapp
helm template myapp ./charts/myapp -f environments/prod/myapp.values.yaml
helm test myapp -n myapp-dev
```
