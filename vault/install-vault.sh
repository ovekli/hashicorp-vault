#!/bin/bash

echo  "INFO: Create secret"
oc create secret generic vault-token --from-literal=VAULT_TOKEN=$(cat -v ../vault-transit/unwrapped-token.txt | awk '{gsub(/\^\[\[0m/,""); gsub(/\^M/,""); print $0}')

echo "INFO: Install helm chart"
helm upgrade --install vault helm-chart -f helm-chart/values.yaml

echo "INFO: Mount secret"
oc set env --from secret/vault-token statefulset vault  

echo "INFO: Delete pod"
oc delete pod vault-0

until [ "$(oc get pods --no-headers -l app.kubernetes.io/instance=vault | awk '/Running/{print $2}')" = "0/1" ]; do echo "Waiting for pod to become available..."; sleep 5; done

echo "INFO: nitialize vault"
oc rsh vault-0 /bin/sh -c "vault operator init" > vault-keys.txt 2>&1

until [ "$(oc get pods --no-headers -l app.kubernetes.io/instance=vault | awk '/Running/{print $2}')" = "1/1" ]; do echo "Waiting for pod to become in running state..."; sleep 5; done

echo "INFO: Get root token"
ROOT_TOKEN=$(cat -v vault-keys.txt | awk -F: '/Root Token/{gsub(/\^\[\[0m\^M/,""); gsub(/ /,"");print $2}')

echo "INFO: copy truststore to pod"
oc cp klingotrust.jks vault-0:/tmp

echo "INFO: Run some commands for test"
oc rsh vault-0 /bin/sh -c "
   unset VAULT_TOKEN &&
   vault login $ROOT_TOKEN &&
   echo 'INFO: Create kv secret truststores' &&
   vault secrets enable -path=truststores -version=2 kv &&
   echo 'INFO: add trusstores to kv secret' &&
   cat /tmp/klingotrust.jks | base64 |vault kv put truststores/klingotrust klingotrust=- &&
   cat /tmp/klingotrust.jks | base64 |vault kv patch truststores/klingotrust oveklitrust=-
   echo 'INFO: enable userpass' && 
   vault auth enable userpass &&
   echo 'INFO: Create user' && 
   vault write /auth/userpass/users/update-truststore-user password='Get my truststores' policies=truststores-policy &&
   vault auth list &&
   vault read /auth/userpass/users/update-truststore-user &&

   echo 'INFO: Add read policy to secret truststores/klingotrust' &&
   vault policy write truststores-policy - <<EOF
     path \"truststores/+/klingotrust\" {
     capabilities = [\"read\"]
   }
EOF
   echo 'INFO: create kv secret truststore-updater' &&
   vault secrets enable -path=secrets kv-v2 &&
   echo 'INFO: Create kv entry username/password to vault' &&
   vault kv put secrets/truststore-updater/config username=update-truststore-user password='Get my truststores' &&

   echo 'INFO: enable kubernetes auth' &&
   vault auth enable kubernetes &&
   vault write auth/kubernetes/config kubernetes_host=\"https://\$KUBERNETES_PORT_443_TCP_ADDR:443\" &&
   vault read auth/kubernetes/config &&

   echo 'INFO: add read policy to secret secrets/data/truststore-updater/config'
   vault policy write truststore-sa - <<EOF
    path \"secrets/data/truststore-updater/config\" {
    capabilities = [\"read\"]
   }
EOF
    echo 'INFO: create kubernetes auth role named truststore-sa'
    vault write auth/kubernetes/role/truststore-sa bound_service_account_names=truststore-sa bound_service_account_namespaces=keystore-site-verify policies=truststore-sa ttl=24h
"
