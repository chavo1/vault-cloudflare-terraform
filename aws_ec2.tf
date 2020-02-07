provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}
resource "aws_instance" "vault" {
  ami           = "ami-04763b3055de4860b"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.chavo.id
  private_ip    = "172.31.16.31"
  subnet_id     = "subnet-ef814da2"

  tags = {
    Name  = "chavo-vault"
    vault = "app"
  }
  connection {
    user        = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host        = self.public_ip
  }
  provisioner "file" {
    source      = "asset/install_vault.sh"
    destination = "/tmp/install_vault.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/install_vault.sh",
    ]
  }

  provisioner "file" {
    source      = "asset/start_vault.sh"
    destination = "/tmp/start_vault.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo bash /tmp/start_vault.sh",
    ]
  }
}