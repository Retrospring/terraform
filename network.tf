# plan to set up a VPC

resource "digitalocean_vpc" "rs_internal_fra1" {
  name        = "tf-retrospring-internal-fra1"
  region      = "fra1"
  description = "Internal network for web and sidekiq (Frankfurt)"

  ip_range = "10.210.16.0/24"
}
