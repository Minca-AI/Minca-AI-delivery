{{/*
HTTP probes, only for a workload with ports. A worker (ports: []) gets none: a
shell exec probe would need /bin/sh, which a distroless image does not have.

The startup probe guards the Fargate cold start (30-60 s): until it passes,
liveness is not evaluated, so a slow boot is never killed. Explicit timeouts
because Kubernetes defaults an unset timeout to one second, which fails a
CPU-limited process that is merely busy.
*/}}
{{- define "minca-service.probes" -}}
{{- $p := .Values.probes -}}
{{- if .Values.ports -}}
{{- with $p.readiness }}
readinessProbe:
  httpGet:
    path: {{ . }}
    port: {{ $p.port }}
  periodSeconds: 5
  timeoutSeconds: 5
  failureThreshold: 6
{{- end }}
{{- with $p.liveness }}
livenessProbe:
  httpGet:
    path: {{ . }}
    port: {{ $p.port }}
  periodSeconds: 20
  timeoutSeconds: 5
  failureThreshold: 6
{{- end }}
{{- with ($p.readiness | default $p.liveness) }}
startupProbe:
  httpGet:
    path: {{ . }}
    port: {{ $p.port }}
  periodSeconds: 5
  timeoutSeconds: 5
  failureThreshold: {{ $p.startupFailureThreshold }}
{{- end }}
{{- end }}
{{- end -}}
