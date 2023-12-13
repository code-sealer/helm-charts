{{ $tls := fromYaml ( include "worker.gen-certs" . ) }}
{{- if .Values.worker.secret.create }}
---
apiVersion: v1
kind: Secret
metadata:
  labels:
   {{- include "codesealer.labels" . | nindent 4 }}  
  name: {{ .Values.worker.secret.name }}
  namespace: {{ .Values.worker.ingress.namespace }}
type: {{ .Values.worker.secret.type }}
data:
  # Cert for {{ include "worker.service.fullname" . }}
  tls.crt: {{ $tls.clientCert }}
  tls.key: {{ $tls.clientKey }}
{{- end }}
---