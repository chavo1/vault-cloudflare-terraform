terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
  }
}

# Configure the Cloudflare provider
provider "cloudflare" {
  email   = var.email
  api_key = var.api_key
}
# Create a record
resource "cloudflare_record" "www" {
  zone_id = var.zone_id
  name    = var.name
  value   = aws_instance.vault.public_ip
  type    = "A"
  proxied = false
  ttl     = 60
}
