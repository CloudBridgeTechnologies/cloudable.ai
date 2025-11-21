# Automatically set VPC and subnet IDs from VPC module
locals {
  vpc_id_final     = coalesce(var.vpc_id, local.vpc_id)
  subnet_ids_final = length(var.subnet_ids) > 0 ? var.subnet_ids : local.private_subnet_ids
}
