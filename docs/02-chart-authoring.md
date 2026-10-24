# 02 · Chart authoring

The reference chart is `charts/myapp`. This page explains the patterns it uses.

## Create a chart

```bash
helm create charts/otherapp
mkdir -p charts/otherapp/ci
cp charts/myapp/ci/test-values.yaml charts/otherapp/ci/
for env in dev staging prod; do
  touch environments/$env/otherapp.values.yaml
done
```

## Chart.yaml

```yaml
apiVersion: v2
name: myapp
description: Example application chart
type: application
version: 0.1.0      # chart version: bump on every chart change
appVersion: "1.27"  # app/image version deployed by default
kubeVersion: ">=1.29.0-0"
```

## Built-in objects

| Object | Example |
|---|---|
| `.Values` | `{{ .Values.replicaCount }}` |
| `.Release` | `{{ .Release.Name }}`, `{{ .Release.Namespace }}`, `{{ .Release.IsUpgrade }}` |
| `.Chart` | `{{ .Chart.Name }}`, `{{ .Chart.AppVersion }}` |
| `.Capabilities` | `{{ .Capabilities.KubeVersion.Version }}`, `{{ .Capabilities.APIVersions.Has "autoscaling/v2" }}` |
| `.Files` | `{{ .Files.Get "files/app.conf" }}` |
| `.Template` | `{{ .Template.BasePath }}` |

## Control structures

```yaml
{{- if .Values.ingress.enabled }}
# rendered only when enabled
{{- else }}
# rendered otherwise
{{- end }}
```

```yaml
env:
  {{- range $key, $value := .Values.env }}
  - name: {{ $key }}
    value: {{ $value | quote }}
  {{- end }}
```

```yaml
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
```

Inside `range`/`with`, `.` changes. Use `$` for the root: `{{ $.Release.Name }}`.

`{{-` trims whitespace before, `-}}` trims after.

## Functions you will use most

| Function | Example |
|---|---|
| `default` | `{{ .Values.image.tag \| default .Chart.AppVersion }}` |
| `quote` | `{{ .Values.host \| quote }}` |
| `required` | `{{ required "ingress.host is required" .Values.ingress.host }}` |
| `toYaml` + `nindent` | `{{- toYaml .Values.resources \| nindent 12 }}` |
| `include` | `{{ include "myapp.fullname" . }}` |
| `tpl` | `{{ tpl .Values.someTemplateString . }}` |
| `b64enc` | `{{ .Values.token \| b64enc }}` |
| `sha256sum` | checksum annotation (below) |
| `lookup` | `{{ lookup "v1" "Secret" .Release.Namespace "name" }}` (empty in `helm template`) |

## Named templates (`_helpers.tpl`)

```yaml
{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

```yaml
metadata:
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
```

Selector labels must never change after the first install, otherwise upgrades fail (Deployment selectors are immutable).

## Restart pods when config changes

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

## ConfigMap from a chart file

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "myapp.fullname" . }}-config
data:
  app.conf: |-
{{ .Files.Get "files/app.conf" | indent 4 }}
```

## Values schema

`values.schema.json` is checked on `install`, `upgrade`, `lint` and `template`:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["image"],
  "properties": {
    "replicaCount": { "type": "integer", "minimum": 1 },
    "image": {
      "type": "object",
      "required": ["repository"],
      "properties": {
        "repository": { "type": "string", "minLength": 1 },
        "tag": { "type": "string" }
      }
    }
  }
}
```

## Hooks

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "myapp.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: {{ include "myapp.image" . | quote }}
          command: ["./migrate", "up"]
```

Hook types: `pre-install`, `post-install`, `pre-upgrade`, `post-upgrade`, `pre-delete`, `post-delete`, `pre-rollback`, `post-rollback`, `test`.

Keep a resource after `helm uninstall`:

```yaml
metadata:
  annotations:
    "helm.sh/resource-policy": keep
```

## Chart tests

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "myapp.fullname" . }}-test-connection
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox:1.36
      command: ["wget"]
      args: ["-qO-", "{{ include "myapp.fullname" . }}:{{ .Values.service.port }}"]
```

```bash
helm test myapp -n myapp-dev
```

## Dependencies (subcharts)

```yaml
# Chart.yaml
dependencies:
  - name: redis
    version: "~1.2.0"
    repository: "oci://registry.example.com/charts"
    condition: redis.enabled
```

```yaml
# values.yaml of the parent
redis:
  enabled: true

global:
  imageRegistry: registry.example.com
```

```bash
helm dependency update charts/myapp   # writes Chart.lock and charts/*.tgz
helm dependency build charts/myapp    # rebuild from Chart.lock
```

Commit `Chart.lock`; `charts/*/charts/` is git-ignored.

Prefer Helmfile `needs:` over subcharts when the dependency is shared infrastructure (databases, ingress) that other apps also use.
