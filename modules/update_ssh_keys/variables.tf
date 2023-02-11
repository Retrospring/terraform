variable "bastion_host" {
  type        = string
  description = "The IP address of the bastion host"
}

variable "droplets" {
  type        = map(any)
  description = "Map containing the droplets to add the SSH hosts to"
}

variable "ssh_public_keys" {
  type        = list(string)
  description = "List of SSH public keys to add to the hosts"
}
