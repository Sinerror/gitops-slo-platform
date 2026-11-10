{{- define "boutique.labels" -}}
app.kubernetes.io/part-of: boutique
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
boutique.env: {{ .Values.environment }}
{{- end }}

{{- define "boutique.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{- define "boutique.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
privileged: false
capabilities:
  drop: [ALL]
{{- end }}

{{/* Образ сервиса: свой из GHCR, если CI прописал тег, иначе апстрим */}}
{{- define "boutique.image" -}}
{{- $root := index . 0 -}}
{{- $name := index . 1 -}}
{{- if and (eq $name "checkoutservice") $root.Values.images.checkoutservice.tag -}}
{{ $root.Values.own.registry }}/checkoutservice:{{ $root.Values.images.checkoutservice.tag }}
{{- else -}}
{{ $root.Values.upstream.registry }}/{{ $name }}:{{ $root.Values.upstream.tag }}
{{- end -}}
{{- end }}

{{- define "boutique.spread" -}}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: {{ . }}
{{- end }}
