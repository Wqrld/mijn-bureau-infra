{{- /*

SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper image name for frontend
*/}}
{{- define "calendars.frontend.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.frontend.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper image name for backend
*/}}
{{- define "calendars.backend.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.backend.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper image name for worker
*/}}
{{- define "calendars.worker.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.worker.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper image name for caldav
*/}}
{{- define "calendars.caldav.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.caldav.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "calendars.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.frontend.image .Values.backend.image .Values.caldav.image) "context" $) }}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "calendars.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}
