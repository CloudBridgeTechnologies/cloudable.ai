# Locals that reference the existing VPC module
locals {
  vpc_id = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
}
