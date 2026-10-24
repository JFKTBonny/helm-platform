# 05 · Templating with environment values

How one chart produces different manifests for dev, staging and prod, and how to use `define`, `include`, `toYaml` and `range` in templates.

---

## 1. How environment values work

### The idea

One chart, one set of templates, many value files:

```text
charts/myapp/values.yaml              # defaults, shared by every env
environments/dev/myapp.values.yaml    # only what differs in dev
environments/prod/myapp.values.yaml   # only what differs in prod
```

Helm **merges** the files, then renders the templates with the result (`.Values`).

### Merge order (lowest → highest priority)

1. `charts/myapp/values.yaml`
2. Each `-f` file, left to right (later wins)
3. `--set` / `--set-string` (highest)

```bash
helm upgrade --install myapp ./charts/myapp \
  -n myapp-prod --create-namespace \
  -f environments/prod/myapp.values.yaml \
  --set-string image.tag=1.28
```

### Merge rules

| Type | Behaviour |
|---|---|
| Map (object) | **Deep-merged**: keys you set are overridden, the others are kept |
| List | **Replaced** entirely, never merged |
| Scalar | Replaced |
| `null` | **Deletes** the key from the defaults |

Example:

```yaml
# values.yaml
env:
  LOG_LEVEL: info
  APP_MODE: standard
hosts:
  - a.example.com
  - b.example.com
```

```yaml
# environments/prod/myapp.values.yaml
env:
  LOG_LEVEL: warn
hosts:
  - prod.example.com
```

Result in prod:

```yaml
env:
  LOG_LEVEL: warn        # overridden
  APP_MODE: standard     # kept from defaults
hosts:
  - prod.example.com     # whole list replaced
```

Remove a default key in one environment:

```yaml
# environments/dev/myapp.values.yaml
resources:
  limits: null
```

### See the merged values

```bash
# What Helm will use (no cluster needed): render and inspect
helm template myapp ./charts/myapp -f environments/prod/myapp.values.yaml

# What a deployed release actually uses
helm get values myapp -n myapp-prod --all
```

### Same thing with Helmfile

```yaml
releases:
  - name: myapp
    chart: ../charts/myapp
    values:
      - ../environments/{{ .Environment.Name }}/myapp.values.yaml
```

```bash
helmfile -e prod template
```

### Use the environment name inside templates

The release namespace is often the cleanest signal:

```yaml
data:
  environment: {{ .Release.Namespace | quote }}
```

Or set it explicitly in each env file and read it:

```yaml
# environments/prod/myapp.values.yaml
environment: prod
```

```yaml
{{- if eq .Values.environment "prod" }}
# prod-only content
{{- end }}
```

Prefer feature flags (`autoscaling.enabled: true`) over `if eq .Values.environment "prod"`; flags keep templates environment-agnostic.

---

## 2. Reading values

```yaml
replicas: {{ .Values.replicaCount }}
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
```

| Need | Write |
|---|---|
| Fallback | `{{ .Values.image.tag \| default .Chart.AppVersion }}` |
| Fail if missing | `{{ required "image.repository is required" .Values.image.repository }}` |
| Quote a string | `{{ .Values.host \| quote }}` |
| Conditional block | `{{- if .Values.ingress.enabled }} ... {{- end }}` |
| Root context inside a loop | `{{ $.Release.Name }}` |

Whitespace control: `{{-` removes whitespace and newlines **before** the tag, `-}}` removes them **after**. Use `{{-` on lines that only contain logic (`if`, `range`, `end`) so they don't leave blank lines.

---

## 3. `define` and `include`

### `define`: create a named, reusable snippet

Put definitions in `templates/_helpers.tpl`. Files starting with `_` are never rendered as manifests.

```yaml
{{/* templates/_helpers.tpl */}}

{{- define "myapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "myapp.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "myapp.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

Rules:

- Prefix names with the chart name (`myapp.`) to avoid clashes with subcharts.
- Start with `{{- define ... -}}` so the output has no leading/trailing newlines.
- A definition can call other definitions (`myapp.labels` includes `myapp.selectorLabels`).

### `include`: call it and get a string back

```yaml
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.labels" . | nindent 4 }}
```

- The `.` passes the current context (Values, Release, Chart) to the snippet. Forget it and the snippet sees nothing.
- `include` returns a string, so it can be piped (`| nindent 4`). The built-in `template` action cannot be piped, so always use `include`.

### Passing custom arguments with `dict`

```yaml
{{- define "myapp.containerPort" -}}
- name: {{ .name }}
  containerPort: {{ .port }}
  protocol: TCP
{{- end }}
```

```yaml
ports:
  {{- include "myapp.containerPort" (dict "name" "http" "port" 80) | nindent 2 }}
```

Need the root context too? Pass it in the dict:

```yaml
{{- define "myapp.portName" -}}
{{ .root.Release.Name }}-{{ .name }}
{{- end }}
```

```yaml
name: {{ include "myapp.portName" (dict "root" $ "name" "metrics") }}
```

---

## 4. `toYaml` (with `nindent`)

`toYaml` turns a whole map or list from values into YAML, so the template doesn't need to know every field.

```yaml
# values.yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

```yaml
# template
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

```yaml
# output
          resources:
            limits:
              cpu: 200m
              memory: 256Mi
            requests:
              cpu: 50m
              memory: 64Mi
```

How to pick the number for `nindent`: count the spaces in front of the **child** lines you want. `resources:` sits at 10 spaces, its children at 12, so `nindent 12`.

`nindent N` = add a newline, then indent every line by N. `indent N` = same without the leading newline. Use `{{- toYaml ... | nindent N }}` (with the `-`) so the newline from `nindent` replaces the one you trimmed.

### Skip the block when the value is empty: `with`

```yaml
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

Inside `with`, `.` is `.Values.nodeSelector`. If it's empty (`{}`, `[]`, `""`, `null`), the whole block disappears.

Notes:

- `toYaml` sorts map keys alphabetically.
- Use it for structures (`resources`, `affinity`, `tolerations`, `securityContext`, `annotations`), not for single scalars.

---

## 5. `range`

### Over a map

```yaml
# values.yaml
env:
  LOG_LEVEL: info
  APP_MODE: standard
```

```yaml
          env:
            {{- range $key, $value := .Values.env }}
            - name: {{ $key }}
              value: {{ $value | quote }}
            {{- end }}
```

```yaml
          env:
            - name: APP_MODE
              value: "standard"
            - name: LOG_LEVEL
              value: "info"
```

Maps are iterated in **alphabetical key order**.

### Over a list of strings

```yaml
# values.yaml
hosts:
  - app.example.com
  - www.example.com
```

```yaml
  tls:
    - hosts:
        {{- range .Values.hosts }}
        - {{ . | quote }}
        {{- end }}
```

Inside `range`, `.` is the current item.

### Over a list of objects

```yaml
# values.yaml
extraPorts:
  - name: metrics
    port: 9090
  - name: admin
    port: 8081
```

```yaml
          ports:
            - name: http
              containerPort: 80
            {{- range .Values.extraPorts }}
            - name: {{ .name }}
              containerPort: {{ .port }}
            {{- end }}
```

### With an index

```yaml
{{- range $i, $host := .Values.hosts }}
# host {{ $i }}: {{ $host }}
{{- end }}
```

### Root context inside `range`: use `$`

Inside the loop `.` is the item, so `.Release` no longer works:

```yaml
{{- range .Values.extraPorts }}
- name: {{ $.Release.Name }}-{{ .name }}
  port: {{ .port }}
{{- end }}
```

Same for `include` inside a loop: pass `$`, not `.`:

```yaml
{{- range .Values.extraPorts }}
  labels:
    {{- include "myapp.selectorLabels" $ | nindent 4 }}
{{- end }}
```

### One resource per item

```yaml
{{- range .Values.cronJobs }}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "myapp.fullname" $ }}-{{ .name }}
spec:
  schedule: {{ .schedule | quote }}
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: {{ .name }}
              image: {{ $.Values.image.repository }}:{{ $.Values.image.tag }}
              command:
                {{- toYaml .command | nindent 16 }}
{{- end }}
```

```yaml
# values.yaml
cronJobs:
  - name: cleanup
    schedule: "0 3 * * *"
    command: ["/bin/sh", "-c", "echo cleanup"]
```

---

## 6. Full example: one template, two environments

### `charts/myapp/values.yaml`

```yaml
replicaCount: 1

image:
  repository: nginx
  tag: "1.27"

env:
  LOG_LEVEL: info
  APP_MODE: standard

extraPorts: []

resources:
  requests:
    cpu: 50m
    memory: 64Mi

nodeSelector: {}
```

### `environments/dev/myapp.values.yaml`

```yaml
env:
  LOG_LEVEL: debug
```

### `environments/prod/myapp.values.yaml`

```yaml
replicaCount: 3

env:
  LOG_LEVEL: warn

extraPorts:
  - name: metrics
    port: 9090

resources:
  requests:
    cpu: 200m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 512Mi

nodeSelector:
  kubernetes.io/os: linux
```

### `charts/myapp/templates/_helpers.tpl`

```yaml
{{- define "myapp.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "myapp.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

### `charts/myapp/templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "myapp.fullname" . }}
  labels:
    {{- include "myapp.selectorLabels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "myapp.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "myapp.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - name: http
              containerPort: 80
            {{- range .Values.extraPorts }}
            - name: {{ .name }}
              containerPort: {{ .port }}
            {{- end }}
          env:
            {{- range $key, $value := .Values.env }}
            - name: {{ $key }}
              value: {{ $value | quote }}
            {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

### Render

```bash
helm template myapp ./charts/myapp -f environments/dev/myapp.values.yaml
helm template myapp ./charts/myapp -f environments/prod/myapp.values.yaml
```

### Output: dev

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-myapp
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/instance: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: myapp
      app.kubernetes.io/instance: myapp
  template:
    metadata:
      labels:
        app.kubernetes.io/name: myapp
        app.kubernetes.io/instance: myapp
    spec:
      containers:
        - name: myapp
          image: "nginx:1.27"
          ports:
            - name: http
              containerPort: 80
          env:
            - name: APP_MODE
              value: "standard"
            - name: LOG_LEVEL
              value: "debug"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
```

### Output: prod

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-myapp
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/instance: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: myapp
      app.kubernetes.io/instance: myapp
  template:
    metadata:
      labels:
        app.kubernetes.io/name: myapp
        app.kubernetes.io/instance: myapp
    spec:
      containers:
        - name: myapp
          image: "nginx:1.27"
          ports:
            - name: http
              containerPort: 80
            - name: metrics
              containerPort: 9090
          env:
            - name: APP_MODE
              value: "standard"
            - name: LOG_LEVEL
              value: "warn"
          resources:
            limits:
              cpu: "1"
              memory: 512Mi
            requests:
              cpu: 200m
              memory: 256Mi
      nodeSelector:
        kubernetes.io/os: linux
```

What changed and why:

| Field | dev | prod | Mechanism |
|---|---|---|---|
| `replicas` | 1 | 3 | Scalar override |
| `LOG_LEVEL` | debug | warn | Map deep-merge; `APP_MODE` kept from defaults |
| `metrics` port | absent | present | `range` over a list that is empty in dev |
| `resources` | requests only | requests + limits | Map deep-merge + `toYaml` |
| `nodeSelector` | absent | present | `with` skips the block when the map is empty |

---

## 7. Common mistakes

| Mistake | Fix |
|---|---|
| `include "myapp.labels"` without `.` | `include "myapp.labels" .` |
| `.Release.Name` inside `range`/`with` | `$.Release.Name` |
| Wrong indentation after `toYaml` | Count the child's indent and use that number in `nindent` |
| Blank lines in output | Use `{{-` on logic-only lines |
| Expecting lists to merge across env files | Lists are replaced; repeat the full list in the env file |
| Numbers/versions changing type (`1.20` → `1.2`) | Quote them in YAML (`"1.20"`) or use `--set-string` |
| `template` piped to `nindent` fails | Use `include` |
| Env-specific `if` logic everywhere | Add a flag in values and toggle it per env |

## 8. Debug commands

```bash
# Render everything
helm template myapp ./charts/myapp -f environments/prod/myapp.values.yaml

# Render one file
helm template myapp ./charts/myapp -f environments/prod/myapp.values.yaml -s templates/deployment.yaml

# Show the rendered output even when it is invalid YAML
helm template myapp ./charts/myapp -f environments/prod/myapp.values.yaml --debug

# Lint with the env values
helm lint ./charts/myapp -f environments/prod/myapp.values.yaml --strict

# Compare two environments
diff \
  <(helm template myapp ./charts/myapp -f environments/dev/myapp.values.yaml) \
  <(helm template myapp ./charts/myapp -f environments/prod/myapp.values.yaml)
```
