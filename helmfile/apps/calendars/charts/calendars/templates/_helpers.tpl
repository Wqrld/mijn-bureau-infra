{{- /*

SPDX-License-Identifier: APACHE-2.0
*/}}

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

{{/*
Render a NetworkPolicy for a named component.
Usage: include "calendars.networkpolicy" (dict
  "name"         "backend"        -- component suffix
  "values"       .Values.backend  -- component-specific values
  "hasIngress"   true             -- false for worker (no listening port)
  "backendEgress" false           -- true for frontend (needs to reach backend)
  "ctx"          $                -- root Helm context
)
*/}}
{{- define "calendars.networkpolicy" -}}
{{- $name         := .name -}}
{{- $vals         := .values -}}
{{- $ctx          := .ctx -}}
{{- $component    := printf "calendars-%s" $name -}}
{{- $hasIngress   := .hasIngress -}}
{{- $backendEgress := default false .backendEgress -}}
---
apiVersion: {{ include "common.capabilities.networkPolicy.apiVersion" $ctx }}
kind: NetworkPolicy
metadata:
  name: {{ include "common.names.fullname" $ctx }}-{{ $name }}
  namespace: {{ include "common.names.namespace" $ctx | quote }}
  labels: {{- include "common.labels.standard" ( dict "customLabels" $ctx.Values.commonLabels "context" $ctx ) | nindent 4 }}
    app.kubernetes.io/component: {{ $component }}
  {{- if $ctx.Values.commonAnnotations }}
  annotations: {{- include "common.tplvalues.render" ( dict "value" $ctx.Values.commonAnnotations "context" $ctx ) | nindent 4 }}
  {{- end }}
spec:
  {{- $podLabels := include "common.tplvalues.merge" ( dict "values" ( list $vals.podLabels $ctx.Values.commonLabels ) "context" $ctx ) }}
  podSelector:
    matchLabels: {{- include "common.labels.matchLabels" ( dict "customLabels" $podLabels "context" $ctx ) | nindent 6 }}
      app.kubernetes.io/component: {{ $component }}
  policyTypes:
    - Ingress
    - Egress
  egress:
    {{- if $ctx.Values.networkPolicy.allowExternalEgress }}
    - {}
    {{- else }}
    - ports:
        # Allow dns resolution
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
    {{- if $backendEgress }}
    # Allow egress to backend
    - ports:
        - port: {{ $ctx.Values.backend.containerPorts.http }}
          protocol: TCP
      to:
        - podSelector:
            matchLabels: {{- include "common.labels.matchLabels" ( dict "customLabels" $ctx.Values.commonLabels "context" $ctx ) | nindent 14 }}
              app.kubernetes.io/component: calendars-backend
    {{- end }}
    {{- if $vals.networkPolicy.extraEgress }}
    {{- include "common.tplvalues.render" ( dict "value" $vals.networkPolicy.extraEgress "context" $ctx ) | nindent 4 }}
    {{- end }}
    {{- if $ctx.Values.networkPolicy.extraEgress }}
    {{- include "common.tplvalues.render" ( dict "value" $ctx.Values.networkPolicy.extraEgress "context" $ctx ) | nindent 4 }}
    {{- end }}
    {{- end }}
  {{- if $hasIngress }}
  ingress:
    - ports:
        - port: {{ $vals.containerPorts.http }}
      {{- if not $ctx.Values.networkPolicy.allowExternal }}
      from:
        - podSelector:
            matchLabels: {{- include "common.labels.matchLabels" ( dict "customLabels" $ctx.Values.commonLabels "context" $ctx ) | nindent 14 }}
        {{- if $ctx.Values.networkPolicy.ingressNSMatchLabels }}
        - namespaceSelector:
            matchLabels: {{- include "common.tplvalues.render" (dict "value" $ctx.Values.networkPolicy.ingressNSMatchLabels "context" $ctx ) | nindent 14 }}
          {{- if $ctx.Values.networkPolicy.ingressNSPodMatchLabels }}
          podSelector:
            matchLabels: {{- include "common.tplvalues.render" (dict "value" $ctx.Values.networkPolicy.ingressNSPodMatchLabels "context" $ctx ) | nindent 14 }}
          {{- end }}
        {{- end }}
      {{- end }}
    {{- if $ctx.Values.networkPolicy.extraIngress }}
    {{- include "common.tplvalues.render" ( dict "value" $ctx.Values.networkPolicy.extraIngress "context" $ctx ) | nindent 4 }}
    {{- end }}
  {{- else }}
  ingress: []
  {{- end }}
{{ end -}}

{{/*
Render a Deployment for a named component.
Usage: include "calendars.deployment" (dict
  "name"      "backend"        -- component suffix appended to release name
  "values"    .Values.backend  -- component-specific values
  "envValues" .Values.backend  -- source for envVars iteration (optional, defaults to "values")
  "hasHPA"    true             -- whether replicas is gated by autoscaling.hpa.enabled
  "hasPorts"  true             -- whether to render ports and probes
  "probeType" "tcpSocket"      -- "httpGet" or "tcpSocket" (ignored when hasPorts is false)
  "ctx"       $                -- root Helm context
)
*/}}
{{- define "calendars.deployment" -}}
{{- $name      := .name -}}
{{- $vals      := .values -}}
{{- $ctx       := .ctx -}}
{{- $component := printf "calendars-%s" $name -}}
{{- $envVals   := default .values .envValues -}}
{{- $hasPorts  := .hasPorts -}}
{{- $hasHPA    := .hasHPA -}}
{{- $probeType := default "" .probeType -}}
apiVersion: {{ include "common.capabilities.deployment.apiVersion" $ctx }}
kind: Deployment
metadata:
  name: {{ include "common.names.fullname" $ctx }}-{{ $name }}
  namespace: {{ include "common.names.namespace" $ctx | quote }}
  labels: {{- include "common.labels.standard" ( dict "customLabels" $ctx.Values.commonLabels "context" $ctx ) | nindent 4 }}
    app.kubernetes.io/component: {{ $component }}
  {{- if or $vals.deploymentAnnotations $ctx.Values.commonAnnotations }}
  {{- $annotations := include "common.tplvalues.merge" (dict "values" (list $vals.deploymentAnnotations $ctx.Values.commonAnnotations) "context" $ctx) }}
  annotations: {{- include "common.tplvalues.render" ( dict "value" $annotations "context" $ctx ) | nindent 4 }}
  {{- end }}
spec:
  {{- if or (not $hasHPA) (not $vals.autoscaling.hpa.enabled) }}
  replicas: {{ $vals.replicaCount }}
  {{- end }}
  {{- $podLabels := include "common.tplvalues.merge" (dict "values" (list $vals.podLabels $ctx.Values.commonLabels) "context" $ctx) }}
  selector:
    matchLabels: {{- include "common.labels.matchLabels" ( dict "customLabels" $podLabels "context" $ctx ) | nindent 6 }}
      app.kubernetes.io/component: {{ $component }}
  template:
    metadata:
      {{- if $vals.podAnnotations }}
      annotations: {{- include "common.tplvalues.render" (dict "value" $vals.podAnnotations "context" $ctx) | nindent 8 }}
      {{- end }}
      labels: {{- include "common.labels.standard" ( dict "customLabels" $podLabels "context" $ctx ) | nindent 8 }}
        app.kubernetes.io/component: {{ $component }}
    spec:
      {{- include "calendars.imagePullSecrets" $ctx | nindent 6 }}
      serviceAccountName: {{ include "calendars.serviceAccountName" $ctx }}
      automountServiceAccountToken: {{ $vals.automountServiceAccountToken }}
      {{- if $vals.hostAliases }}
      hostAliases: {{- include "common.tplvalues.render" (dict "value" $vals.hostAliases "context" $ctx) | nindent 8 }}
      {{- end }}
      {{- if $vals.affinity }}
      affinity: {{- include "common.tplvalues.render" ( dict "value" $vals.affinity "context" $ctx) | nindent 8 }}
      {{- else }}
      affinity:
        podAffinity: {{- include "common.affinities.pods" (dict "type" $vals.podAffinityPreset "component" $component "customLabels" $podLabels "context" $ctx) | nindent 10 }}
        podAntiAffinity: {{- include "common.affinities.pods" (dict "type" $vals.podAntiAffinityPreset "component" $component "customLabels" $podLabels "context" $ctx) | nindent 10 }}
        nodeAffinity: {{- include "common.affinities.nodes" (dict "type" $vals.nodeAffinityPreset.type "key" $vals.nodeAffinityPreset.key "values" $vals.nodeAffinityPreset.values) | nindent 10 }}
      {{- end }}
      {{- if $vals.nodeSelector }}
      nodeSelector: {{- include "common.tplvalues.render" ( dict "value" $vals.nodeSelector "context" $ctx) | nindent 8 }}
      {{- end }}
      {{- if $vals.tolerations }}
      tolerations: {{- include "common.tplvalues.render" (dict "value" $vals.tolerations "context" $ctx) | nindent 8 }}
      {{- end }}
      {{- if $vals.priorityClassName }}
      priorityClassName: {{ $vals.priorityClassName | quote }}
      {{- end }}
      {{- if $vals.schedulerName }}
      schedulerName: {{ $vals.schedulerName | quote }}
      {{- end }}
      {{- if $vals.runtimeClassName }}
      runtimeClassName: {{ $vals.runtimeClassName | quote }}
      {{- end }}
      {{- if $vals.topologySpreadConstraints }}
      topologySpreadConstraints: {{- include "common.tplvalues.render" (dict "value" $vals.topologySpreadConstraints "context" $ctx) | nindent 8 }}
      {{- end }}
      {{- if $vals.podSecurityContext.enabled }}
      securityContext: {{- omit $vals.podSecurityContext "enabled" | toYaml | nindent 8 }}
      {{- end }}
      {{- if $vals.terminationGracePeriodSeconds }}
      terminationGracePeriodSeconds: {{ $vals.terminationGracePeriodSeconds }}
      {{- end }}
      {{- if $vals.initContainers }}
      initContainers:
        {{- include "common.tplvalues.render" (dict "value" $vals.initContainers "context" $ctx) | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ $component }}
          image: {{ include "common.images.image" (dict "imageRoot" $vals.image "global" $ctx.Values.global) }}
          imagePullPolicy: {{ $vals.image.pullPolicy }}
          {{- if $vals.containerSecurityContext.enabled }}
          securityContext: {{- include "common.compatibility.renderSecurityContext" (dict "secContext" $vals.containerSecurityContext "context" $ctx) | nindent 12 }}
          {{- end }}
          {{- if $ctx.Values.diagnosticMode.enabled }}
          command: {{- include "common.tplvalues.render" (dict "value" $ctx.Values.diagnosticMode.command "context" $ctx) | nindent 12 }}
          {{- else if $vals.command }}
          command: {{- include "common.tplvalues.render" (dict "value" $vals.command "context" $ctx) | nindent 12 }}
          {{- end }}
          {{- if $ctx.Values.diagnosticMode.enabled }}
          args: {{- include "common.tplvalues.render" (dict "value" $ctx.Values.diagnosticMode.args "context" $ctx) | nindent 12 }}
          {{- else if $vals.args }}
          args: {{- include "common.tplvalues.render" (dict "value" $vals.args "context" $ctx) | nindent 12 }}
          {{- end }}
          env:
            {{- range $key, $value := $envVals.envVars }}
            - name: {{ $key }}
              value: {{ $value | quote }}
            {{- end }}
            {{- if $vals.extraEnvVars }}
            {{- include "common.tplvalues.render" (dict "value" $vals.extraEnvVars "context" $ctx) | nindent 12 }}
            {{- end }}
          {{- if or $vals.extraEnvVarsCM $vals.extraEnvVarsSecret }}
          envFrom:
            {{- if $vals.extraEnvVarsCM }}
            - configMapRef:
                name: {{ include "common.tplvalues.render" (dict "value" $vals.extraEnvVarsCM "context" $ctx) }}
            {{- end }}
            {{- if $vals.extraEnvVarsSecret }}
            - secretRef:
                name: {{ include "common.tplvalues.render" (dict "value" $vals.extraEnvVarsSecret "context" $ctx) }}
            {{- end }}
          {{- end }}
          {{- if $vals.resources }}
          resources: {{- toYaml $vals.resources | nindent 12 }}
          {{- else if ne $vals.resourcesPreset "none" }}
          resources: {{- include "common.resources.preset" (dict "type" $vals.resourcesPreset) | nindent 12 }}
          {{- end }}
          {{- if $hasPorts }}
          ports:
            - name: http
              containerPort: {{ $vals.containerPorts.http }}
          {{- if not $ctx.Values.diagnosticMode.enabled }}
          {{- if $vals.livenessProbe.enabled }}
          livenessProbe: {{- include "common.tplvalues.render" (dict "value" (omit $vals.livenessProbe "enabled") "context" $ctx) | nindent 12 }}
            {{- if eq $probeType "httpGet" }}
            httpGet:
              path: /
              port: {{ $vals.containerPorts.http }}
            {{- else }}
            tcpSocket:
              port: {{ $vals.containerPorts.http }}
            {{- end }}
          {{- end }}
          {{- if $vals.readinessProbe.enabled }}
          readinessProbe: {{- include "common.tplvalues.render" (dict "value" (omit $vals.readinessProbe "enabled") "context" $ctx) | nindent 12 }}
            {{- if eq $probeType "httpGet" }}
            httpGet:
              path: /
              port: {{ $vals.containerPorts.http }}
            {{- else }}
            tcpSocket:
              port: {{ $vals.containerPorts.http }}
            {{- end }}
          {{- end }}
          {{- if $vals.startupProbe.enabled }}
          startupProbe: {{- include "common.tplvalues.render" (dict "value" (omit $vals.startupProbe "enabled") "context" $ctx) | nindent 12 }}
            {{- if eq $probeType "httpGet" }}
            httpGet:
              path: /
              port: {{ $vals.containerPorts.http }}
            {{- else }}
            tcpSocket:
              port: {{ $vals.containerPorts.http }}
            {{- end }}
          {{- end }}
          {{- end }}
          {{- end }}
          {{- if $vals.lifecycleHooks }}
          lifecycle: {{- include "common.tplvalues.render" (dict "value" $vals.lifecycleHooks "context" $ctx) | nindent 12 }}
          {{- end }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            {{- if $vals.extraVolumeMounts }}
            {{- include "common.tplvalues.render" (dict "value" $vals.extraVolumeMounts "context" $ctx) | nindent 12 }}
            {{- end }}
        {{- if $vals.sidecars }}
        {{- include "common.tplvalues.render" ( dict "value" $vals.sidecars "context" $ctx) | nindent 8 }}
        {{- end }}
      volumes:
        - name: tmp
          emptyDir: {}
        {{- if $vals.extraVolumes }}
        {{- include "common.tplvalues.render" (dict "value" $vals.extraVolumes "context" $ctx) | nindent 8 }}
        {{- end }}
{{- end -}}
