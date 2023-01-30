# plan to manage SSH keys

resource "digitalocean_ssh_key" "ssh_keys" {
  for_each = var.rs_ssh_keys

  name       = "tf-${each.key}"
  public_key = each.value
}

# variable definitions used in ssh_keys.auto.tfvars {{{

variable "rs_ssh_keys" {
  description = "public SSH keys to be used to connect to droplets"
  type        = map(string)
}

# }}}
