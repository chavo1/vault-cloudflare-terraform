#!/usr/bin/env bash

VAULT_VERSION="1.3.1"
PKG="wget unzip vim curl jq net-tools dnsutils sshpass"

which ${PKG} &>/dev/null || {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ${PKG}
}

mkdir -p /vagrant/pkg/

which vault &>/dev/null || {
    # check - vault file exist.
    CHECKFILE="/vagrant/pkg/vault_${VAULT_VERSION}_linux_amd64.zip"
    if [ ! -f "$CHECKFILE" ]; then
        pushd /vagrant/pkg
          sudo wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
        popd
 
    fi
    
    pushd /usr/local/bin/
      unzip /vagrant/pkg/vault_${VAULT_VERSION}_linux_amd64.zip
      sudo chmod +x vault
    popd
}
