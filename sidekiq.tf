# plan to create worker instances

locals {
  # cloud-init config expressed in HCL as doing YAML by hand is painful
  cloud_config_sidekiq = {
    # https://cloudinit.readthedocs.io/en/latest/reference/modules.html#users-and-groups
    users = [
      {
        name                = "justask"
        shell               = "/bin/bash"
        sudo                = ["ALL=(ALL) NOPASSWD:ALL"]
        ssh_authorized_keys = local.rs_ssh_keys_public_keys
      }
    ]
    disable_root      = true
    disable_root_opts = "no-port-forwarding,no-agent-forwarding,no-X11-forwarding,command=\"echo 'Please login as the user \\\"coyote\\\" rather than the user \\\"$DISABLE_USER\\\".';echo;sleep 10;exit 142\""
    runcmd = [
      "echo '### Installing software updates ###' && zypper up -y",
      "echo '### Installing utilities ###' && zypper in -y curl git htop jq ripgrep the_silver_searcher",
      "echo '### Marking cloud-init runcmd as done ###' && date > /var/lib/.tf_cloud_init_runcmd_done_at",
    ]
  }
}

resource "digitalocean_droplet" "sidekiq" {
  count = var.rs_sidekiq_instances

  name   = format("tf-retrospring-sidekiq-%03d", count.index + 1)
  image  = "125976124" # id of "openSUSE-Leap-15.4-JeOS.x86_64"
  region = var.rs_sidekiq_region
  size   = var.rs_sidekiq_droplet_size

  vpc_uuid = digitalocean_vpc.rs_internal_fra1.id

  ssh_keys = local.rs_ssh_keys_fingerprints

  user_data = <<-YAML
    #cloud-config
    ${yamlencode(local.cloud_config_sidekiq)}
  YAML

  lifecycle {
    ignore_changes = [
      ssh_keys, # otherwise terraform needs to destroy and re-create the droplets whenever the ssh keys change
    ]
  }

  connection {
    type = "ssh"
    user = "justask"
    host = self.ipv4_address_private

    bastion_host = digitalocean_droplet.bastion.ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /var/lib/.tf_cloud_init_runcmd_done_at ]; do echo '### Waiting for cloud-init to finish ###'; sleep 10; done",
      "echo '### cloud-init done ###'",
    ]
  }
}

# create record for internal machines (doesn't matter that they're public,
# as they resolve to a 10.0.0.0/8 net anyway)
resource "digitalocean_record" "sidekiq_internal" {
  for_each = { for droplet in digitalocean_droplet.sidekiq : droplet.name => droplet }

  domain = var.rs_infra_zone
  type   = "A"
  name   = "${replace(each.value.name, "/^tf-/", "")}.int"
  value  = each.value.ipv4_address_private
  ttl    = 300
}


# register our droplets to the project
resource "digitalocean_project_resources" "sidekiq" {
  project   = digitalocean_project.tf-retrospring.id
  resources = [for k, v in digitalocean_droplet.sidekiq : v.urn]
}

# only allow SSH access from the internal net
resource "digitalocean_firewall" "sidekiq" {
  name = "tf-retrospring-sidekiq-rules"

  droplet_ids = [for k, v in digitalocean_droplet.sidekiq : v.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["10.210.16.0/24"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::0"]
  }
}


# variable definitions used in sidekiq.auto.tfvars {{{

variable "rs_sidekiq_instances" {
  description = "number of instances to spawn"
  type        = number
}

variable "rs_sidekiq_region" {
  description = "region to deploy sidekiq to"
  type        = string
}

variable "rs_sidekiq_droplet_size" {
  description = "droplet size"
  type        = string
}

# }}}
