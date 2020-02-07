output "public_ip" {
  value = aws_instance.vault.*.public_ip
}
output "public_dns" {
  value = aws_instance.vault.*.public_dns
}
output "hostname" {
  value = cloudflare_record.www.*.hostname
}
