variable "region" { type = string }
variable "env"    { type = string }
variable "project" {
  type    = string
  default = "cloudable"
}

variable "create_deployer_role" {
  description = "Create an IAM role to assume for Terraform deploys"
  type        = bool
  default     = true
}

variable "deployer_managed_policies" {
  description = "List of managed policy ARNs to attach to the deployer role"
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

