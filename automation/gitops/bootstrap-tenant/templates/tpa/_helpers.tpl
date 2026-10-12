{{- define "tpa.namespace" -}}
{{- printf "tpa-%s" .Values.guid -}}
{{- end -}}

{{- define "tpa.rhdaNamespace" -}}
{{- printf "rhda-%s" .Values.guid -}}
{{- end -}}

{{- define "tpa.url" -}}
{{- printf "https://tpa-%s.%s" .Values.guid .Values.deployer.domain -}}
{{- end -}}

{{- define "tpa.keycloakHost" -}}
{{- printf "sso.%s" .Values.deployer.domain -}}
{{- end -}}
