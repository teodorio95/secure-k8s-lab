{{- define "juice-shop.name" -}}
{{- default "juice-shop" .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "juice-shop.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "juice-shop.name" . -}}
{{- end -}}
{{- end -}}

{{- define "juice-shop.labels" -}}
app.kubernetes.io/name: {{ include "juice-shop.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: secure-k8s-lab
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/* Stable selector labels — also used by NetworkPolicy podSelectors. */}}
{{- define "juice-shop.selectorLabels" -}}
app: {{ include "juice-shop.name" . }}
{{- end -}}
