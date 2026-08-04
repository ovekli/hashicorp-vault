#!/bin/bash

echo "INFO: Install helm chart"
helm upgrade --install truststore-updater helm-chart -f helm-chart/values.yaml

# Create patch to inject secrets
oc patch deployment truststore-updater --patch "$(cat <<EOF
spec:
   template:
      metadata:
        annotations:
           vault.hashicorp.com/agent-image: docker.io/hashicorp/vault
           vault.hashicorp.com/agent-inject: 'true'
           vault.hashicorp.com/role: 'truststore-sa'
           vault.hashicorp.com/service: 'http://vault.vault-verify.svc:8200'
           vault.hashicorp.com/agent-inject-template-vault-login.sh: |
             {{- with secret "secrets/data/truststore-updater/config" -}}
             vault login -method=userpass -token-only username={{ .Data.data.username }} password="{{ .Data.data.password }}"
             {{- end -}}
EOF
)"