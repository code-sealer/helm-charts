{{ $tls := fromYaml ( include "ingress.gen-certs" . ) }}
{{- if .Values.ingress.secret.create }}
---
apiVersion: v1
kind: Secret
metadata:
  labels:
   {{- include "codesealer.labels" . | nindent 4 }}  
  name: {{ .Values.ingress.secret.name }}
  namespace: {{ .Values.ingress.namespace }}
type: {{ .Values.ingress.secret.type }}
data:
  # Cert for {{ include "ingress.service.fullname" . }}
  tls.crt: {{ $tls.clientCert }}
  tls.key: {{ $tls.clientKey }}
{{- end }}
---