#!/bin/bash

echo "Install helm chart"
helm upgrade --install vault-transit helm-chart -f helm-chart/values.yaml

echo "Sleep for 10 sec..."
sleep 10

echo "Initialize vault"
oc rsh -c vault vault-transit-0 /bin/sh -c 'vault operator init' > vault-init-result.txt 2>&1

echo "Get unsealed keys"
UNSEAL_KEY_1=$(cat -v vault-init-result.txt | awk -F: '/Unseal Key 1/{gsub(/\^\[\[0m\^M/,""); gsub(/ /,"");print $2}')
UNSEAL_KEY_2=$(cat -v vault-init-result.txt | awk -F: '/Unseal Key 2/{gsub(/\^\[\[0m\^M/,""); gsub(/ /,"");print $2}')
UNSEAL_KEY_3=$(cat -v vault-init-result.txt | awk -F: '/Unseal Key 3/{gsub(/\^\[\[0m\^M/,""); gsub(/ /,"");print $2}')

echo "Create secret for unsealed keys"
oc create secret generic vault-transit --from-literal=UNSEAL_KEY_1=$(echo $UNSEAL_KEY_1) --from-literal=UNSEAL_KEY_2=$(echo $UNSEAL_KEY_2) --from-literal=UNSEAL_KEY_3=$(echo $UNSEAL_KEY_3)

echo "Add secret as volume to vault-transit statefulet"
oc set volumes statefulset vault-transit --add --type secret --name vault-transit-sec --secret-name vault-transit

echo "Add env to vault-transit statefulset from secret/vault-transit"
oc set env --from secret/vault-transit statefulset vault-transit  

echo "Restart vault-transit pod"
oc delete pod vault-transit-0

echo "Sleep for 45 sec..."
sleep 45

echo "Get root token"
ROOT_TOKEN=$(cat -v vault-init-result.txt | awk -F: '/Root Token/{gsub(/\^\[\[0m\^M/,""); gsub(/ /,"");print $2}')

echo "Enable transit secret, add secret autounseal and finally autounseal policy"
set -x
oc rsh vault-transit-0 /bin/sh -c "
   vault login $ROOT_TOKEN &&
   vault secrets enable transit &&
   vault write -f transit/keys/autounseal &&
   vault policy write autounseal -<<EOF
   path \"transit/encrypt/autounseal\" {
     capabilities = [ \"update\" ]
   }

   path \"transit/decrypt/autounseal\" {
      capabilities = [ \"update\" ]
   }
EOF
"


echo "Create a client token for autounseal operations"
vault token create -orphan -policy="autounseal" \
   -wrap-ttl=120 -period=24h \
   -field=wrapping_token > wrapping-token.txt
