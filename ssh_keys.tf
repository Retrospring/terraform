# plan to manage SSH keys

resource "digitalocean_ssh_key" "ssh_keys" {
  for_each = var.rs_ssh_keys

  name       = "tf-${each.key}"
  public_key = each.value
}

# since everything is in the root module `locals` are used instead of outputs
locals {
  rs_ssh_keys_public_keys  = [for k, v in digitalocean_ssh_key.ssh_keys : v.public_key]
  rs_ssh_keys_fingerprints = [for k, v in digitalocean_ssh_key.ssh_keys : v.fingerprint]
}

# variable definitions used in ssh_keys.auto.tfvars {{{

variable "rs_ssh_keys" {
  description = "public SSH keys to be used to connect to droplets"
  type        = map(string)
}

# }}}
