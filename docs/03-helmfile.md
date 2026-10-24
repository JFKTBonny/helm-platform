# 03 · Helmfile

Helmfile is a declarative file listing **many Helm releases** for an environment. It calls `helm` (and the `helm-diff` plugin) under the hood.

## When to use it

Use Helmfile when you need at least one of:

- Several releases deployed together (ingress, cert-manager, metrics, apps).
- Install ordering between releases (`needs`).
- The same stack across dev/staging/prod with different values.
- A full `diff` of an environment before changing it.
- Third-party chart versions pinned in Git.

Stay with plain Helm for one app going into a cluster whose platform is already managed.

## Install

```bash
# macOS
brew install helmfile

# Linux
HELMFILE_VERSION=1.2.3
curl -fsSL "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz" \
  | sudo tar -xz -C /usr/local/bin helmfile

helmfile --version

# helm-diff is required (Helm 4 needs --verify=false)
helm plugin install https://github.com/databus23/helm-diff --verify=false
```

## Layout in this repo

```text
helmfile/
├── helmfile.yaml.gotmpl            # environments + repositories + releases
├── environments/
│   ├── common.yaml                 # shared values (chart versions, flags)
│   ├── dev.yaml
│   ├── staging.yaml
│   └── prod.yaml
├── values/                         # values for third-party charts
│   ├── cert-manager.yaml
│   ├── cluster-issuers.yaml.gotmpl
│   ├── metrics-server.yaml.gotmpl
│   └── traefik.yaml.gotmpl
└── charts/
    └── cluster-issuers/            # tiny local chart deployed after cert-manager
```

Files ending in `.gotmpl` are rendered by Helmfile first, so they can use `{{ .Values.x }}`, `{{ .Environment.Name }}` and `{{ env "VAR" }}`. In Helmfile v1 the main file must be `helmfile.yaml.gotmpl` to use templating.

## Anatomy

```yaml
environments:
  dev:
    values:
      - environments/common.yaml
      - environments/dev.yaml
  prod:
    values:
      - environments/common.yaml
      - environments/prod.yaml

---

helmDefaults:
  wait: true
  timeout: 600
  historyMax: 10
  createNamespace: true

repositories:
  - name: traefik
    url: https://traefik.github.io/charts
  - name: myorg
    url: ghcr.io/your-github-user/charts
    oci: true

releases:
  - name: traefik
    namespace: traefik
    chart: traefik/traefik
    version: {{ .Values.versions.traefik }}
    labels:
      tier: platform
    values:
      - values/traefik.yaml.gotmpl

  - name: myapp
    namespace: myapp-{{ .Environment.Name }}
    chart: {{ .Values.myapp.chart }}
    {{- if .Values.myapp.version }}
    version: {{ .Values.myapp.version | quote }}
    {{- end }}
    needs:
      - traefik/traefik
    labels:
      tier: app
    values:
      - ../environments/{{ .Environment.Name }}/myapp.values.yaml
```

The `---` separates the environment section from the releases: values from the environment are only available below it.

## Key fields

| Field | Purpose |
|---|---|
| `installed: false` | Remove (or never install) the release in that environment |
| `needs: [ns/name]` | Install after another release |
| `labels` | Select subsets with `-l tier=app` |
| `version` | Pin the chart version (always do it for third-party charts) |
| `chart: ../charts/myapp` | Local folder (dev) |
| `chart: myorg/myapp` + `version` | Published OCI chart (staging/prod) |

## Commands

```bash
cd helmfile

helmfile -e dev lint
helmfile -e dev template
helmfile -e dev build              # print the merged state
helmfile -e dev diff
helmfile -e dev apply              # only releases with changes
helmfile -e dev sync               # upgrade every release, changed or not
helmfile -e dev destroy            # uninstall everything in the env

# Only part of the stack
helmfile -e prod -l tier=app diff
helmfile -e prod -l app=myapp apply

# Override the image tag from CI
MYAPP_IMAGE_TAG=1.28 helmfile -e dev apply
```

From the repo root:

```bash
helmfile -f helmfile/helmfile.yaml.gotmpl -e dev diff
make hf-diff ENV=dev
make hf-apply ENV=dev
```

## Promotion pattern

- **dev** uses `chart: ../charts/myapp`, so every merge is testable immediately.
- **staging/prod** use `chart: myorg/myapp` with an explicit `version`.
- To promote, change `myapp.version` in `environments/staging.yaml`, then in `environments/prod.yaml`, each through a PR, and run `diff` → `apply`.

## Secrets

Do not put secrets in these files. Options:

- Pre-create Kubernetes Secrets and reference them (`existingSecret`).
- External Secrets Operator pulling from a cloud secret manager.
- `helm-secrets` + SOPS: Helmfile reads `secrets:` entries and decrypts them at deploy time.

```yaml
releases:
  - name: myapp
    secrets:
      - ../environments/{{ .Environment.Name }}/myapp.secrets.yaml   # SOPS-encrypted
```
