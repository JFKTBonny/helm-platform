# helm-platform

Helm charts, per-environment configuration, Helmfile stacks and CI/CD for deploying to Kubernetes.

- **Helm** packages and deploys a single application (`charts/`).
- **Helmfile** deploys a whole environment: platform components + apps, in order (`helmfile/`).
- **GitHub Actions** lint, test, publish charts to GHCR and deploy.

---

## Repository layout

```text
helm-platform/
├── charts/                          # Our charts (published to oci://ghcr.io/<owner>/charts)
│   └── myapp/
│       ├── Chart.yaml
│       ├── values.yaml              # Safe, environment-neutral defaults
│       ├── values.schema.json       # Validates values on install/upgrade/lint
│       ├── ci/test-values.yaml      # Used by chart-testing on kind
│       ├── files/app.conf           # Static file loaded into a ConfigMap
│       └── templates/
│           ├── _helpers.tpl
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── serviceaccount.yaml
│           ├── configmap.yaml
│           ├── ingress.yaml
│           ├── hpa.yaml
│           ├── job-migrate.yaml     # pre-install / pre-upgrade hook
│           ├── NOTES.txt
│           └── tests/test-connection.yaml
├── environments/                    # Per-environment values for our apps
│   ├── dev/myapp.values.yaml
│   ├── staging/myapp.values.yaml
│   └── prod/myapp.values.yaml
├── helmfile/                        # Whole-environment deployments
│   ├── helmfile.yaml.gotmpl
│   ├── environments/                # common.yaml + dev/staging/prod.yaml
│   ├── values/                      # Values for third-party charts
│   └── charts/cluster-issuers/      # Small local chart (cert-manager ClusterIssuers)
├── docs/
│   ├── 01-helm-basics.md
│   ├── 02-chart-authoring.md
│   ├── 03-helmfile.md
│   └── 04-workflow.md
├── .github/
│   ├── workflows/
│   │   ├── lint-test.yaml           # PR: lint, render per env, install on kind
│   │   ├── release.yaml             # main: package + push new versions to GHCR
│   │   ├── deploy.yaml              # manual: deploy ONE app with Helm
│   │   └── helmfile.yaml            # PR: validate stacks | manual: diff/apply an env
│   └── dependabot.yml
├── ct.yaml
├── Makefile
├── .editorconfig
└── .gitignore
```

---

## Helm or Helmfile?

| Situation | Use | How |
|---|---|---|
| Deploy or upgrade one app in a cluster that already has its platform | Helm | `make deploy ENV=dev` or the **Deploy (Helm)** workflow |
| Build or update a full environment (ingress, cert-manager, metrics, apps) | Helmfile | `make hf-apply ENV=dev` or the **Helmfile** workflow |
| Several releases must be installed in order (`needs`) | Helmfile | `needs:` in `helmfile.yaml.gotmpl` |
| Preview every change in an environment before applying | Helmfile | `make hf-diff ENV=prod` |
| Publish a reusable chart | Helm | `release.yaml` pushes to GHCR |

Both paths read the same `environments/<env>/myapp.values.yaml`, so app config lives in one place.

---

## Prerequisites

| Tool | Notes |
|---|---|
| `kubectl` | Configured for your cluster |
| `helm` | v4 recommended. Helm 3.21 gets security fixes until Feb 2027 |
| `helmfile` | v1.x (only for the Helmfile path) |
| `helm-diff` plugin | `make tools` |
| `kind` | Optional, for a local cluster |

```bash
# macOS
brew install helm helmfile kind

# Linux (Helm 4 install script)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash

# helm-diff (Helm 4 needs --verify=false; Helm 3 does not accept it)
helm plugin install https://github.com/databus23/helm-diff --verify=false
```

---

## Quick start (local)

```bash
git clone https://github.com/your-github-user/helm-platform.git
cd helm-platform

make kind-up
make tools

# Option A: one app with Helm
make lint ENV=dev
make deploy ENV=dev
make test ENV=dev

# Option B: the whole dev environment with Helmfile
make hf-diff ENV=dev
make hf-apply ENV=dev
```

---

## GitHub setup (one time)

1. Replace the placeholder owner everywhere:

    ```bash
    grep -rl "your-github-user" . | xargs sed -i 's/your-github-user/<your-github-user>/g'
    ```

    On macOS use `sed -i ''` instead of `sed -i`.

2. Push to GitHub:

    ```bash
    git init
    git add .
    git commit -m "Initial helm-platform"
    git branch -M main
    git remote add origin git@github.com:<your-github-user>/helm-platform.git
    git push -u origin main
    ```

3. **Settings → Environments**: create `dev`, `staging`, `prod`. In each one add a secret named `KUBECONFIG` with the kubeconfig file contents. Add required reviewers to `prod`.

4. **Settings → Actions → General → Workflow permissions**: allow read and write (needed to push packages).

5. After the first release, open the `charts/myapp` package in GHCR and either make it public or grant this repository access.

---

## Day-to-day flow

1. Branch, change `charts/myapp/...`, **bump `version` in `Chart.yaml`**.
2. `make lint ENV=prod` and `make template ENV=prod`.
3. Open a PR → `lint-test.yaml` (and `helmfile.yaml` if stacks changed) run.
4. Merge → `release.yaml` publishes the new chart version to GHCR.
5. Dev picks up the chart folder directly. For staging/prod, bump `myapp.version` in `helmfile/environments/<env>.yaml` in a PR.
6. Actions → **Helmfile** → `diff`, then `apply`.

Details in [docs/04-workflow.md](docs/04-workflow.md).

---

## Corrections to earlier notes

This repo updates the cheat sheets it was built from:

| Earlier | Now |
|---|---|
| Bitnami used in examples | Bitnami stopped publishing new charts/images to Docker Hub (Aug 2025). Examples use `nginx`, Jetstack, Traefik and metrics-server instead |
| `ingress.className: nginx` | Ingress NGINX was retired in March 2026. Traefik is used here |
| `--atomic` | Helm 4 name is `--rollback-on-failure` (`--atomic` still works with a deprecation warning) |
| `helm plugin install .../helm-diff` | Helm 4 needs `--verify=false` for unsigned plugins |
| Release workflow overwrote existing versions | Now skips versions already in GHCR |
| Three `KUBECONFIG_<ENV>` repo secrets | One `KUBECONFIG` secret per GitHub environment |
| `--set nodeSelector."kubernetes\.io/os"` described as "comma" escaping | It escapes a **dot** in a key; commas are escaped as `\,` |
