terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

# Set the variable value in *.tfvars file
# or using -var="do_token=..." CLI option
variable "rs_do_token" {}

variable "rs_infra_zone" {
  description = "the DNS zone used for publicly resolvable hostnames"
  type        = string
  default     = "do.infra.retrospring.net"
}

# Configure the DigitalOcean Provider
provider "digitalocean" {
  token = var.rs_do_token
}
