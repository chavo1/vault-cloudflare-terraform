provider "aws" {
  region = var.region
}
resource "aws_instance" "vault" {
  ami           = "ami-04763b3055de4860b"
  instance_type = "t2.micro"
  key_name      = var.key_name
  private_ip    = "172.31.16.31"
  subnet_id     = "subnet-ef814da2"

  tags = {
    Name  = "chavo-vault"
    vault = "app"
  }
  user_data = <<REALEND
#!/bin/bash
echo "Download Vaul"

which wget unzip vim curl jq net-tools dnsutils &>/dev/null || {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y wget unzip vim curl jq net-tools dnsutils
}

mkdir -p /vagrant/pkg/

which vault &>/dev/null || {
    # check - vault file exist.
    CHECKFILE="/vagrant/pkg/vault_1.9.0_linux_amd64.zip"
    if [ ! -f "$CHECKFILE" ]; then
        pushd /vagrant/pkg
          sudo wget https://releases.hashicorp.com/vault/1.9.0/vault_1.9.0_linux_amd64.zip
        popd
 
    fi
    
    pushd /usr/local/bin/
      unzip /vagrant/pkg/vault_1.9.0_linux_amd64.zip
      sudo chmod +x vault
    popd
}

echo "Start Vaul"


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
CN = chavo.eu
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

REALEND
}