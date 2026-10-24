# 04 · Workflow, CI/CD and operations

## Versioning rules

| Change | Bump |
|---|---|
| Anything inside `charts/myapp/` | `version` in `Chart.yaml` (CI fails otherwise) |
| Default app image changed | `appVersion` in `Chart.yaml` too |
| Only `environments/*.values.yaml` | Nothing; values are not part of the chart |
| Third-party chart upgrade | `versions.*` in `helmfile/environments/common.yaml` |

Use semver: patch for fixes, minor for new optional values, major for breaking value changes.

## Pipelines

| Workflow | Trigger | What it does |
|---|---|---|
| `lint-test.yaml` | PR touching charts or environments | `helm lint --strict` + `helm template` for dev/staging/prod; `ct lint` + `ct install` on kind |
| `release.yaml` | Push to `main` touching `charts/` | Packages each chart and pushes versions not yet in GHCR |
| `deploy.yaml` | Manual | `helm upgrade --install` of myapp into one environment, then `helm test` |
| `helmfile.yaml` | PR touching helmfile/environments/charts; manual | PR: `helmfile lint` + `template` per env. Manual: `diff` or `apply` |

## Change an app

```bash
git switch -c feat/myapp-probes
# edit charts/myapp/templates/deployment.yaml
# bump charts/myapp/Chart.yaml version: 0.1.0 -> 0.1.1
make lint ENV=prod
make template ENV=prod | less
git commit -am "myapp: tune probes"
git push -u origin feat/myapp-probes
```

After merge, `release.yaml` publishes `myapp:0.1.1`. Then promote:

```bash
git switch -c promote/myapp-0.1.1-staging
sed -i 's/^  version: .*/  version: 0.1.1/' helmfile/environments/staging.yaml
git commit -am "staging: myapp 0.1.1"
git push -u origin promote/myapp-0.1.1-staging
```

Merge, then Actions → **Helmfile** → `staging` → `diff`, then `apply`.

## Change only configuration

Edit `environments/<env>/myapp.values.yaml`, open a PR, merge, then deploy with **Deploy (Helm)** or **Helmfile** (`selector: app=myapp`).

## Add a third-party component

1. Add the repo under `repositories:` in `helmfile/helmfile.yaml.gotmpl`.
2. Add the release with a pinned `version`, `labels: {tier: platform}`.
3. Put its values in `helmfile/values/<name>.yaml` (or `.yaml.gotmpl` if it needs env values).
4. Add the version to `helmfile/environments/common.yaml`.
5. PR → `helmfile.yaml` validates every environment.

## Secrets

- Never commit secrets (`.gitignore` blocks `secrets*.yaml`, `*.secret.yaml`).
- Apps read Secrets by name via `existingSecret`.
- CI cluster access: one `KUBECONFIG` secret per GitHub environment. Prefer short-lived credentials (OIDC to your cloud) when available.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `another operation (install/upgrade/rollback) is in progress` | `helm history <rel> -n <ns>`, then `helm rollback <rel> <last-good-rev> -n <ns>` |
| `field is immutable` on Deployment selector | Selector labels changed. Revert them, or uninstall/reinstall |
| `values don't meet the specifications of the schema` | Fix the value named in the error (see `values.schema.json`) |
| `helm diff` / Helmfile says plugin missing | `make tools` |
| Plugin install fails on Helm 4 | Add `--verify=false` |
| GHCR `denied` / `unauthorized` | `helm registry login ghcr.io`; check package visibility/repo access |
| `--wait` times out with no clear reason (Helm 4) | Check RBAC allows `watch` on the resources; `kubectl get events -n <ns>` |
| Hook Job failed | `kubectl logs job/<release>-myapp-migrate -n <ns>` |

## Housekeeping

```bash
# Release history is stored as Secrets in the release namespace
kubectl get secrets -n myapp-dev -l owner=helm

# Keep history short
helm upgrade ... --history-max 10
```

## Growing beyond this repo

When there are many apps and clusters, a common next step is GitOps: keep `charts/` + `release.yaml` here, move `environments/` and `helmfile/` into a config repo reconciled by Argo CD or Flux.
