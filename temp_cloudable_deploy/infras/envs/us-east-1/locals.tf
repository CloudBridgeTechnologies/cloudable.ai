locals {
  tags = {
    project = "cloudable"
    env     = var.env
  }

  tenants_list = [for k, v in var.tenants : { id = k, name = v.name }]
}

