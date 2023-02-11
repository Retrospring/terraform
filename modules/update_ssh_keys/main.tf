# update authorized keys directly on the hosts whenever they change
resource "null_resource" "update_ssh_keys" {
  for_each = var.droplets

  triggers = {
    public_keys = join(",", var.ssh_public_keys)
  }

  connection {
    type = "ssh"
    user = "justask"
    host = each.value.ipv4_address_private

    bastion_host = var.bastion_host
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOF
        keys=$(echo "${base64encode(join("\n", var.ssh_public_keys))}" | base64 -d)
        IFS=$'\n'
        for key in $keys; do
          echo ":: checking $${key}"
          if grep -q "$key" ~/.ssh/authorized_keys; then
            echo ":: key exists"
          else
            echo ":: key does not exist, appending it"
            echo "$key" >> ~/.ssh/authorized_keys
          fi
        done
      EOF
    ]
  }
}
