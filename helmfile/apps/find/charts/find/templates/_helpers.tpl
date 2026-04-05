{{/*

SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Full name for find backend
*/}}
{{- define "find.backend.fullname" -}}
{{ include "common.names.fullname" . }}-backend
{{- end -}}

{{/*
Full name for find celery worker
*/}}
{{- define "find.celery.fullname" -}}
{{ include "common.names.fullname" . }}-backend-celery
{{- end -}}

{{/*
Return the proper find image name
*/}}
{{- define "find.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.find.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper volume-permissions image name
*/}}
{{- define "find.volumePermissions.image" -}}
{{- include "common.images.image" ( dict "imageRoot" .Values.defaultInitContainers.volumePermissions.image "global" .Values.global ) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "find.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.find.image .Values.defaultInitContainers.volumePermissions.image) "context" $) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "find.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return true if cert-manager required annotations for TLS signed certificates are set in the Ingress annotations
Ref: https://cert-manager.io/docs/usage/ingress/#supported-annotations
*/}}
{{- define "find.ingress.certManagerRequest" -}}
{{ if or (hasKey . "cert-manager.io/cluster-issuer") (hasKey . "cert-manager.io/issuer") }}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "find.validateValues" -}}
{{- $messages := list -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}

{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message -}}
{{- end -}}
{{- end -}}
