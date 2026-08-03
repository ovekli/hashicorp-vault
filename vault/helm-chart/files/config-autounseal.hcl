ui			= true
default_lease_ttl	= "168h"
max_lease_ttl		= "720h"
disable_mlock		= true

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = true
}

api_addr = "http://127.0.0.1:8200"

storage "file" {
  path = "/var/lib/vault/data"
}

seal "transit" {
  address = "http://vault-transit.vault-transit-verify.svc:8200"
  disable_renewal = "false"
  key_name = "autounseal"
  mount_path = "transit/"
  tls_skip_verify = "true"
}