# plan to create a postgres

locals {
  # cloud-init config expressed in HCL as doing YAML by hand is painful
  cloud_config_postgres = {
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

resource "digitalocean_droplet" "postgres" {
  name   = "tf-retrospring-postgres-001"
  image  = "125976124" # id of "openSUSE-Leap-15.4-JeOS.x86_64"
  region = "fra1"
  size   = "s-2vcpu-2gb"

  vpc_uuid = digitalocean_vpc.rs_internal_fra1.id

  ssh_keys = local.rs_ssh_keys_fingerprints

  user_data = <<-YAML
    #cloud-config
    ${yamlencode(local.cloud_config_postgres)}
  YAML

  lifecycle {
    ignore_changes = [
      ssh_keys, # otherwise terraform needs to destroy and re-create the droplets whenever the ssh keys change
    ]

    # never destroy our precious postgres instance via terraform
    prevent_destroy = true
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

      "echo '### Installing postgres and configuring it ###'",
      "sudo zypper in -y postgresql15-server",
      "sudo systemctl enable --now postgresql.service",
    ]
  }
}

# create record for internal machines (doesn't matter that it's public,
# as they resolve to a 10.0.0.0/8 net anyway)
resource "digitalocean_record" "postgres_internal" {
  domain = var.rs_infra_zone
  type   = "A"
  name   = "${replace(digitalocean_droplet.postgres.name, "/^tf-/", "")}.int"
  value  = digitalocean_droplet.postgres.ipv4_address_private
  ttl    = 300
}

# create record for external machines
resource "digitalocean_record" "postgres_external" {
  domain = var.rs_infra_zone
  type   = "A"
  name   = "${replace(digitalocean_droplet.postgres.name, "/^tf-/", "")}.ext"
  value  = digitalocean_droplet.postgres.ipv4_address
  ttl    = 300
}

# register our droplet to the project
resource "digitalocean_project_resources" "postgres" {
  project   = digitalocean_project.tf-retrospring.id
  resources = [digitalocean_droplet.postgres.urn]
}

# only allow SSH access and 5432/tcp from the internal net and the old host
resource "digitalocean_firewall" "postgres" {
  name = "tf-retrospring-postgres-rules"

  droplet_ids = [digitalocean_droplet.postgres.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["10.210.16.0/24", "52.59.208.190/32"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "5432"
    source_addresses = ["10.210.16.0/24", "52.59.208.190/32"]
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

