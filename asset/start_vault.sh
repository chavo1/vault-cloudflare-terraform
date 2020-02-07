#!/usr/bin/env bash

DOMAIN=consul
HOST=$(hostname)

set -x

# kill vault
killall vault &>/dev/null

sleep 5

# Create vault configuration
mkdir -p /etc/vault.d
mkdir -p /opt
# create vault user
sudo useradd --system --home /etc/vault.d --shell /bin/false vault
# /opt must be owned by vault user 
sudo chown vault:vault /opt

sudo tee /etc/vault.d/config.hcl > /dev/null << EOF
storage "file" {
  path = "/opt"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_cert_file = "/etc/vault.d/vault.crt"
  tls_key_file = "/etc/vault.d/vault.key"
}

listener "tcp" {
  address   = "172.31.16.31:8200"
  tls_cert_file = "/etc/vault.d/vault.crt"
  tls_key_file = "/etc/vault.d/vault.key"
}
ui = true
EOF

sudo tee /etc/vault.d/vault.hcl > /dev/null << EOF
path "sys/mounts/*" {
  capabilities = [ "create", "read", "update", "delete", "list" ]
}

# List enabled secrets engine
path "sys/mounts" {
  capabilities = [ "read", "list" ]
}

# Work with pki secrets engine
path "pki*" {
  capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
}
EOF

################
# openssl conf # Creating openssl conf /// more info  https://www.phildev.net/ssl/opensslconf.html
################
cat << EOF >/usr/lib/ssl/req.conf
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
C = BG
ST = Sofia
L = Sofia
O = chavo
OU = chavo
CN = chavo.consul
[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = localhost
IP.1 = 127.0.0.1
IP.2 = 172.31.16.31
EOF

######################################
# generate self signed certificate #
######################################
pushd /etc/vault.d
  openssl req -x509 -batch -nodes -newkey rsa:2048 -keyout vault.key -out vault.crt -config /usr/lib/ssl/req.conf -days 365
  cat vault.crt >> /usr/lib/ssl/certs/ca-certificates.crt
popd

# setup .bashrc
grep VAULT_ADDR ~/.bashrc || {
  echo export VAULT_ADDR=https://127.0.0.1:8200 | sudo tee -a ~/.bashrc
}

source ~/.bashrc
##################
# starting vault #
##################
vault -autocomplete-install
complete -C /usr/local/bin/vault vault
sudo setcap cap_ipc_lock=+ep /usr/local/bin/vault

# Create a Vault service file at /etc/systemd/system/vault.service
sudo cat << EOF >/etc/systemd/system/vault.service
[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/config.hcl

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/config.hcl 
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl start vault
echo vault started

sleep 3 

# Initialize Vault
sudo mkdir -p /opt/token
vault operator init > /opt/token/keys.txt
vault operator unseal $(cat /opt/token/keys.txt | grep "Unseal Key 1:" | cut -c15-)
vault operator unseal $(cat /opt/token/keys.txt | grep "Unseal Key 2:" | cut -c15-)
vault operator unseal $(cat /opt/token/keys.txt | grep "Unseal Key 3:" | cut -c15-)
vault login $(cat /opt/token/keys.txt | grep "Initial Root Token:" | cut -c21-)

# enable secret KV version 1
VAULT_ADDR="https://127.0.0.1:8200" vault secrets enable -version=1 kv

# setup .bashrc
grep VAULT_TOKEN ~/.bashrc || {
  echo export VAULT_TOKEN=\`cat /home/ubuntu/.vault-token\` | sudo tee -a ~/.bashrc
}

VAULT_ADDR="https://127.0.0.1:8200" vault secrets enable pki
VAULT_ADDR="https://127.0.0.1:8200" vault secrets tune -max-lease-ttl=87600h pki
VAULT_ADDR="https://127.0.0.1:8200" vault write -field=certificate pki/root/generate/internal common_name="example.com" \
      ttl=87600h > CA_cert.crt
VAULT_ADDR="https://127.0.0.1:8200" vault write pki/config/urls \
      issuing_certificates="https://127.0.0.1:8200/v1/pki/ca" \
      crl_distribution_points="https://127.0.0.1:8200/v1/pki/crl"
VAULT_ADDR="https://127.0.0.1:8200" vault secrets enable -path=pki_int pki
VAULT_ADDR="https://127.0.0.1:8200" vault secrets tune -max-lease-ttl=43800h pki_int
VAULT_ADDR="https://127.0.0.1:8200" vault write -format=json pki_int/intermediate/generate/internal \
        common_name="example.com Intermediate Authority" ttl="43800h" \
        | jq -r '.data.csr' > pki_intermediate.csr
VAULT_ADDR="https://127.0.0.1:8200" vault write -format=json pki/root/sign-intermediate csr=@pki_intermediate.csr \
        format=pem_bundle \
        | jq -r '.data.certificate' > intermediate.cert.pem
VAULT_ADDR="https://127.0.0.1:8200" vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem
VAULT_ADDR="https://127.0.0.1:8200" vault write pki_int/roles/example-dot-com \
        allowed_domains="${DOMAIN}" \
        allow_subdomains=true \
        max_ttl="720h"

# Sealing Vault 
vault operator seal
set +x
