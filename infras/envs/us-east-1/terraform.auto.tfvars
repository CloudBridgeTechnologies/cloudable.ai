env                  = "dev"
domain_name          = "cloudable.ai"
aurora_engine_version = "15.12"

# Override any other variables as needed
vpc_id               = ""
subnet_ids           = []
availability_zones   = ["us-east-1a", "us-east-1b"]

# Force destroy all resources
force_destroy        = true
prevent_destroy      = false
