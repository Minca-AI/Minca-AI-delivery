{{/*
Helpers shared by the Deployment and the migration Job. Both must run the same
image, identity, env, secrets and security context: a migration that runs under
a different configuration than the pods it gates proves nothing about them.
*/}}

{{- define "minca-service.name" -}}
{{- required "values.name is required (DNS-1123 label, e.g. codifier)" .Values.name -}}
{{- end -}}

{{- define "minca-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "minca-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Selector labels stay minimal because a Deployment's selector is immutable; the
full set below may grow without forcing a replace.
*/}}
{{- define "minca-service.labels" -}}
{{ include "minca-service.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: minca
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/*
image@digest. A tag is mutable and is never rendered: the digest pinned by
promote is the only thing that decides what runs.
*/}}
{{- define "minca-service.image" -}}
{{- $repo := required "values.image.repository is required" .Values.image.repository -}}
{{- $digest := required "values.image.digest is required (sha256:...)" .Values.image.digest -}}
{{- if .Values.image.registry -}}
{{- printf "%s/%s@%s" (trimSuffix "/" .Values.image.registry) $repo $digest -}}
{{- else -}}
{{- printf "%s@%s" $repo $digest -}}
{{- end -}}
{{- end -}}

{{/* Kubernetes object name of the Secret materialised for one secrets[] entry. */}}
{{- define "minca-service.secretName" -}}
{{- printf "%s-%s" .root.Values.name (.entry.name | lower | replace "_" "-") | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Name shared by the ConfigMap (env) and the Secret (secretEnv) of the service. */}}
{{- define "minca-service.envObjectName" -}}
{{- printf "%s-env" (include "minca-service.name" .) -}}
{{- end -}}

{{/*
envFrom: the ConfigMap from `env`, then the Secret from `secretEnv`. On a
duplicate key the later source wins, so a secret value overrides plain config.
*/}}
{{- define "minca-service.envFrom" -}}
{{- if or .Values.env .Values.secretEnv -}}
envFrom:
  {{- if .Values.env }}
  - configMapRef:
      name: {{ include "minca-service.envObjectName" . }}
  {{- end }}
  {{- if .Values.secretEnv }}
  - secretRef:
      name: {{ include "minca-service.envObjectName" . }}
  {{- end }}
{{- end }}
{{- end -}}

{{/* env: one secretKeyRef per ExternalSecret (`secrets[]`, optional). */}}
{{- define "minca-service.env" -}}
{{- $root := . -}}
{{- with .Values.secrets -}}
env:
  {{- range . }}
  - name: {{ .name }}
    valueFrom:
      secretKeyRef:
        name: {{ include "minca-service.secretName" (dict "root" $root "entry" .) }}
        key: {{ .name }}
  {{- end }}
{{- end }}
{{- end -}}

{{- define "minca-service.podSecurityContext" -}}
securityContext:
  runAsNonRoot: {{ .Values.security.runAsNonRoot }}
  {{- with .Values.security.runAsUser }}
  runAsUser: {{ . }}
  {{- end }}
  {{- with .Values.security.fsGroup }}
  fsGroup: {{ . }}
  {{- end }}
  seccompProfile:
    type: RuntimeDefault
{{- end -}}

{{- define "minca-service.containerSecurityContext" -}}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: {{ .Values.security.readOnlyRootFilesystem }}
  capabilities:
    drop: ["ALL"]
{{- end -}}

{{- define "minca-service.command" -}}
{{- with .command -}}
command:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .args }}
args:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{- define "minca-service.tmpMount" -}}
volumeMounts:
  - name: tmp
    mountPath: /tmp
{{- end -}}

{{- define "minca-service.tmpVolume" -}}
volumes:
  - name: tmp
    emptyDir:
      sizeLimit: {{ .Values.tmp.sizeLimit }}
{{- end -}}

{{/*
Pod-level fields shared by the Deployment and the Job. automountServiceAccountToken
is false because no workload calls the Kubernetes API; IRSA does not need it, the
EKS pod identity webhook projects its own token volume.
*/}}
{{- define "minca-service.podCommon" -}}
serviceAccountName: {{ include "minca-service.name" . }}
automountServiceAccountToken: false
enableServiceLinks: false
{{ include "minca-service.podSecurityContext" . }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{ include "minca-service.tmpVolume" . }}
{{- end -}}
