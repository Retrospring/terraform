resource "digitalocean_project" "tf-retrospring" {
  name        = "tf-retrospring"
  description = "This only contains resources managed by Terraform."
  purpose     = "Web Application"
  environment = "Production"
}
