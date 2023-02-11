# plan to set up a bastion host

locals {
  # cloud-init config expressed in HCL as doing YAML by hand is painful
  cloud_config_bastion = {
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
      "echo '### Installing utilities ###' && zypper in -y ansible curl git htop jq ripgrep the_silver_searcher",
      "echo '### Marking cloud-init runcmd as done ###' && date > /var/lib/.tf_cloud_init_runcmd_done_at",
    ]
  }
}

resource "digitalocean_droplet" "bastion" {
  name   = "tf-retrospring-bastion"
  image  = "125976124" # id of "openSUSE-Leap-15.4-JeOS.x86_64"
  region = "fra1"
  size   = "s-1vcpu-512mb-10gb"

  vpc_uuid = digitalocean_vpc.rs_internal_fra1.id

  ssh_keys = local.rs_ssh_keys_fingerprints

  user_data = <<-YAML
    #cloud-config
    ${yamlencode(local.cloud_config_bastion)}
  YAML

  lifecycle {
    ignore_changes = [
      # otherwise terraform needs to destroy and re-create the droplets whenever the ssh keys change
      ssh_keys,
      user_data,
    ]
  }

  connection {
    type = "ssh"
    user = "justask"
    host = self.ipv4_address
  }

  provisioner "remote-exec" {
    inline = [
      "while [ ! -f /var/lib/.tf_cloud_init_runcmd_done_at ]; do echo '### Waiting for cloud-init to finish ###'; sleep 10; done",
      "echo '### cloud-init done ###'",
    ]
  }
}

# update authorized keys directly on the hosts whenever they change
module "update_ssh_keys_bastion" {
  source = "./modules/update_ssh_keys"

  bastion_host    = digitalocean_droplet.bastion.ipv4_address
  droplets        = { "${digitalocean_droplet.bastion.name}" = digitalocean_droplet.bastion }
  ssh_public_keys = local.rs_ssh_keys_public_keys
}

# create public hostname
resource "digitalocean_record" "bastion" {
  domain = var.rs_infra_zone
  type   = "A"
  name   = replace(digitalocean_droplet.bastion.name, "/^tf-/", "")
  value  = digitalocean_droplet.bastion.ipv4_address
  ttl    = 300
}

# register our droplet to the project
resource "digitalocean_project_resources" "bastion" {
  project   = digitalocean_project.tf-retrospring.id
  resources = [digitalocean_droplet.bastion.urn]
}

# only allow SSH access from the outside
resource "digitalocean_firewall" "bastion" {
  name = "tf-retrospring-bastion-rules"

  droplet_ids = [digitalocean_droplet.bastion.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::0"]
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


