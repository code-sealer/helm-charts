{{/*
###################### Chart helpers ######################
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "codesealer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "codesealer.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "codesealer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "codesealer.labels" -}}
helm.sh/chart: {{ include "codesealer.chart" . }}
app.kubernetes.io/name: {{ include "codesealer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "codesealer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "codesealer.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
###################### Worker helpers ######################
*/}}

{{/*
Name of the Worker.
*/}}
{{- define "worker.name" -}}
{{- default .Values.worker.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Worker labels
*/}}
{{- define "worker.labels" -}}
{{ include "codesealer.labels" . }}
{{ include "worker.selectorLabels" . }}
{{- end }}

{{/*
Worker Selector labels
*/}}
{{- define "worker.selectorLabels" -}}
codesealer-app: {{ include "worker.name" . }}
{{- end }}

{{/*
Create the name of the Worker service to use
*/}}
{{- define "worker.serviceName" -}}
{{- .Values.worker.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create service fully qualified hostname for the Worker service
*/}}
{{- define "worker.service.fullname" -}}
{{- default ( printf "%s.%s.svc.cluster.local" (include "worker.serviceName" .) .Values.namespace ) }}
{{- end }}

{{/*
Generate Worker certificate authority
*/}}
{{- define "worker.gen-certs" -}}
{{- $expiration := (.Values.worker.ca.expiration | int) -}}
{{- if (or (empty .Values.worker.ca.cert) (empty .Values.worker.ca.key)) -}}
{{- $ca :=  genCA "worker-ca" $expiration -}}
{{- template "worker.gen-client-tls" (dict "RootScope" . "CA" $ca) -}}
{{- end -}}
{{- end -}}

{{/*
Generate Worker client key and cert from CA
*/}}
{{- define "worker.gen-client-tls" -}}
{{- $altNames := list ( include "worker.service.fullname" .RootScope) (printf "*.%s" ( include "worker.service.fullname" .RootScope)) "127.0.0.1" "localhost" -}}
{{- $expiration := (.RootScope.Values.worker.ca.expiration | int) -}}
{{- $cert := genSignedCert ( include "codesealer.fullname" .RootScope) nil $altNames $expiration .CA -}}
{{- $clientCert := $cert.Cert | b64enc -}}
{{- $clientKey := $cert.Key | b64enc -}}
caCert: {{ .CA.Cert | b64enc }}
clientCert: {{ $clientCert }}
clientKey: {{ $clientKey }}
{{- end -}}

{{/*
###################### Manager helpers ######################
*/}}

{{/*
Name of the Manager.
*/}}
{{- define "manager.name" -}}
{{- default .Values.manager.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
manager labels
*/}}
{{- define "manager.labels" -}}
{{ include "codesealer.labels" . }}
{{ include "manager.selectorLabels" . }}
{{- end }}

{{/*
manager Selector labels
*/}}
{{- define "manager.selectorLabels" -}}
codesealer-app: {{ include "manager.name" . }}
{{- end }}

{{/*
Create the name of the Manager service to use
*/}}
{{- define "manager.serviceName" -}}
{{- .Values.manager.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create service fully qualified hostname for the Manager service
*/}}
{{- define "manager.service.fullname" -}}
{{- default ( printf "%s.%s.svc.cluster.local" (include "manager.serviceName" .) .Values.namespace ) }}
{{- end }}

{{/*
Generate Manager certificate authority
*/}}
{{- define "manager.gen-certs" -}}
{{- $expiration := (.Values.manager.ca.expiration | int) -}}
{{- if (or (empty .Values.manager.ca.cert) (empty .Values.manager.ca.key)) -}}
{{- $ca :=  genCA "manager-ca" $expiration -}}
{{- template "manager.gen-client-tls" (dict "RootScope" . "CA" $ca) -}}
{{- end -}}
{{- end -}}

{{/*
Generate Manager client key and cert from CA
*/}}
{{- define "manager.gen-client-tls" -}}
{{- $altNames := list ( include "manager.service.fullname" .RootScope) (printf "*.%s" ( include "manager.service.fullname" .RootScope)) "127.0.0.1" "localhost" -}}
{{- $expiration := (.RootScope.Values.manager.ca.expiration | int) -}}
{{- $cert := genSignedCert ( include "codesealer.fullname" .RootScope) nil $altNames $expiration .CA -}}
{{- $clientCert := $cert.Cert | b64enc -}}
{{- $clientKey := $cert.Key | b64enc -}}
caCert: {{ .CA.Cert | b64enc }}
clientCert: {{ $clientCert }}
clientKey: {{ $clientKey }}
{{- end -}}

{{/*
###################### Webhook helpers ######################
*/}}

{{/*
Name of the webhook.
*/}}
{{- define "webhook.name" -}}
{{- default .Values.webhook.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Webhook labels
*/}}
{{- define "webhook.labels" -}}
{{ include "codesealer.labels" . }}
{{ include "webhook.selectorLabels" . }}
{{- end }}

{{/*
Webhook Selector labels
*/}}
{{- define "webhook.selectorLabels" -}}
codesealer-app: {{ include "webhook.name" . }}
{{- end }}

{{/*
Create the name of the service to use
*/}}
{{- define "webhook.serviceName" -}}
{{- .Values.webhook.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create service fully qualified hostname
*/}}
{{- define "webhook.service.fullname" -}}
{{- default ( printf "%s.%s.svc" (include "webhook.serviceName" .) .Release.Namespace ) }}
{{- end }}

{{/*
Generate certificate authority
*/}}
{{- define "webhook.gen-certs" -}}
{{- $expiration := (.Values.webhook.ca.expiration | int) -}}
{{- if (or (empty .Values.webhook.ca.cert) (empty .Values.webhook.ca.key)) -}}
{{- $ca :=  genCA "webhook-ca" $expiration -}}
{{- template "webhook.gen-client-tls" (dict "RootScope" . "CA" $ca) -}}
{{- end -}}
{{- end -}}

{{/*
Generate client key and cert from CA
*/}}
{{- define "webhook.gen-client-tls" -}}
{{- $altNames := list ( include "webhook.service.fullname" .RootScope) -}}
{{- $expiration := (.RootScope.Values.webhook.ca.expiration | int) -}}
{{- $cert := genSignedCert ( include "codesealer.fullname" .RootScope) nil $altNames $expiration .CA -}}
{{- $clientCert := $cert.Cert | b64enc -}}
{{- $clientKey := $cert.Key | b64enc -}}
caCert: {{ .CA.Cert | b64enc }}
clientCert: {{ $clientCert }}
clientKey: {{ $clientKey }}
{{- end -}}

{{/*
###################### Redis helpers ######################
*/}}

{{/*
Get name of the Redis master service
*/}}
{{- define "redis.serviceName" -}}
{{- if (.Values.redis.install) -}}
{{- printf "%s-master.%s.svc.cluster.local:%v" (include "common.names.fullname" .Subcharts.redis) .Values.namespace .Values.redis.service.ports.redis -}}
{{- else -}}
{{- printf "%s.%s.svc.cluster.local:%v" .Values.redis.service.name .Values.redis.namespace .Values.redis.service.ports.redis -}}
{{- end -}}
{{- end -}}

{{/*
###################### Other helpers ######################
*/}}

{{/*
Create the json for the docker registry credentials
*/}}
{{- define "codesealer.imagePullSecret" -}}
{{- printf "{\"auths\":{\"ghcr.io/code-sealer\":{\"username\":\"%s\",\"password\":\"%s\",\"auth\":\"%s\"}}}" "code-sealer" (required ".codesealerToken must be passed" .Values.codesealerToken) (printf "%s:%s" "code-sealer" .Values.codesealerToken | b64enc) | b64enc }}
{{- end }}

