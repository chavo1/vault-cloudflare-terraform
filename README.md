# This repo contain Terraform code creates a Vault server and add a DNS record in AWS.
## Prerequisites

- Active domain name - You can take one from provider of your choice
- Register or transfer the domain in Cloudflare
- AWS Account
- Install [Terraform](https://www.terraform.io/)
### How to use it
- Clone the repo
```
git clone https://github.com/chavo1/vault-cloudflare-terraform.git
cd vault-cloudflare-terraform
terraform init
terraform apply
```
- Access Vault server on dedicated domain name in my case: 
</br>
https://vault.chavo.eu:8200
