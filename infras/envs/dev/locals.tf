locals {
  tags = merge({
    project = "cloudable"
    env     = var.env
  }, var.common_tags)

  tenants_list = [for k, v in var.tenants : { id = k, name = v.name }]
}

