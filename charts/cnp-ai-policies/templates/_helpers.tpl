{{- define "cnp-ai.project" -}}
{{- required "project is required" .Values.project -}}
{{- end -}}

{{- define "cnp-ai.enabled" -}}
{{- if and .Values.ai (dig "enabled" false .Values.ai) -}}true{{- end -}}
{{- end -}}

{{/*
Every client of the project the gateway knows, by azp, as JSON:
  {"agent-p-a": {"kind":"agent","name":"a","models":[..],"budget":N,
                 "webSearch":bool,"tools":[..],"suspended":bool,"callers":[azp..]}}
Rights come from the ProjectRecord only: an agent's models are cut to the
project's, web_search needs spec.ai.webSearch.
*/}}
{{- define "cnp-ai.clients" -}}
{{- $p := include "cnp-ai.project" . -}}
{{- $ai := .Values.ai -}}
{{- $gw := .Values.gateway -}}
{{- $projectModels := dig "models" (list "claude-haiku-5-5") $ai -}}
{{- $projectWebSearch := dig "webSearch" false $ai -}}
{{- $clients := dict -}}
{{- $agents := dig "agents" (list) $ai -}}
{{- range $agents -}}
  {{- $models := list -}}
  {{- range (dig "models" $projectModels .) -}}
    {{- if has . $projectModels -}}{{- $models = append $models . -}}{{- end -}}
  {{- end -}}
  {{- $tools := dig "tools" (list) . -}}
  {{- $mcpTools := without $tools "web_search" -}}
  {{- $callers := list -}}
  {{- range (dig "callers" (list) .) -}}
    {{- $parts := splitList ":" . -}}
    {{- $kind := index $parts 0 -}}
    {{- $who := join ":" (rest $parts) -}}
    {{- if eq $kind "app" -}}{{- $callers = append $callers (printf "app-%s-%s" $p $who) -}}
    {{- else if eq $kind "agent" -}}{{- $callers = append $callers (printf "agent-%s-%s" $p $who) -}}
    {{- else if and (eq $kind "user") (eq $who "members") -}}{{- $callers = append $callers $gw.membersCaller -}}
    {{- else -}}{{- fail (printf "agent %s: unknown caller %q (app:<name>, agent:<name> or user:members)" .name .) -}}
    {{- end -}}
  {{- end -}}
  {{- $name := .name -}}
  {{- /* A scheduled agent triggers itself through its own A2A route. */ -}}
  {{- $callers = append $callers (printf "agent-%s-%s" $p .name) -}}
  {{- range $agents -}}
    {{- if has $name (dig "calls" (list) .) -}}{{- $callers = append $callers (printf "agent-%s-%s" $p .name) -}}{{- end -}}
  {{- end -}}
  {{- $_ := set $clients (printf "agent-%s-%s" $p .name) (dict
        "kind" "agent" "name" .name "models" $models
        "budget" (int (dig "dailyTokenBudget" $gw.defaultDailyTokenBudget .))
        "webSearch" (and $projectWebSearch (has "web_search" $tools))
        "tools" $mcpTools
        "suspended" (eq (dig "status" "active" .) "suspended")
        "callers" (uniq $callers)) -}}
{{- end -}}
{{- range (dig "apps" (list) $ai) -}}
  {{- if dig "enabled" true . -}}
  {{- $_ := set $clients (dig "azp" (printf "app-%s-%s" $p .name) .) (dict
        "kind" "app" "name" .name "models" $projectModels
        "budget" (int (dig "dailyTokenBudget" $gw.defaultDailyTokenBudget .))
        "webSearch" false "tools" (list) "suspended" false "callers" (list)) -}}
  {{- end -}}
{{- end -}}
{{- toJson $clients -}}
{{- end -}}

{{/*
The caller the gateway accounts for. A token exchanged by sandbox-runner is
charged to the agent that ran the code (claim agent, the service account
username service-account-<agent client id>).
*/}}
{{- define "cnp-ai.caller" -}}
(jwt.azp == "sandbox-runner" ? string(default(jwt.agent, "")).regexReplace("^service-account-", "") : jwt.azp)
{{- end -}}

{{- define "cnp-ai.jwt" -}}
jwtAuthentication:
  mode: Strict
  providers:
    - issuer: {{ .Values.gateway.issuer }}
      audiences: [{{ .Values.gateway.audience }}]
      jwks:
        remote:
          jwksPath: {{ .Values.gateway.jwks.path }}
          cacheDuration: 5m
          backendRef:
            group: ""
            kind: Service
            name: {{ .Values.gateway.jwks.service }}
            namespace: {{ .Values.gateway.jwks.namespace }}
            port: {{ .Values.gateway.jwks.port }}
{{- end -}}

{{- define "cnp-ai.labels" -}}
app.kubernetes.io/managed-by: cnp-ai-policies
cnp.3istor.com/project: {{ include "cnp-ai.project" . }}
{{- end -}}

{{/* JSON body of the 403 a suspended agent gets. */}}
{{- define "cnp-ai.suspendedBody" -}}
{"error":"ai_agent_suspended","message":"Cet agent est suspendu (kill switch du projet {{ include "cnp-ai.project" . }}). Un responsable du projet peut le réactiver dans le CMP."}
{{- end -}}

{{/*
Keys and tokens only. The built-in PII patterns (PhoneNumber above all) masked
dates and tool output numbers in the trial, so they stay off.
*/}}
{{- define "cnp-ai.secretPatterns" -}}
- '\bsk-ant-[A-Za-z0-9_-]{10,}'
- '\bsk-(?:proj-)?[A-Za-z0-9_-]{32,}'
- '\bgh[pousr]_[A-Za-z0-9]{36,}'
- '\bgithub_pat_[A-Za-z0-9_]{40,}'
- '\bglpat-[A-Za-z0-9_-]{20,}'
- '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b'
- '\bAIza[0-9A-Za-z_-]{35}'
- '\bxox[abposr]-[A-Za-z0-9-]{10,}'
- '\bhv[sbr]\.[A-Za-z0-9_-]{24,}'
- '\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'
- '-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----[\s\S]*?-----END (?:[A-Z]+ )?PRIVATE KEY-----'
- '(?i)\b(?:password|passwd|secret|api[_-]?key|access[_-]?token)\s*[:=]\s*["'']?[^\s"'']{8,}'
{{- end -}}
