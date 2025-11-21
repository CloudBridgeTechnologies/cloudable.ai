resource "aws_bedrock_guardrail" "tenant" {
  for_each                  = var.enable_bedrock_agents ? var.tenants : {}
  name                      = "gr-${var.env}-${each.value.name}"
  description               = "Guardrail for ${each.value.name}"
  blocked_input_messaging   = "That request isn’t allowed for this assistant."
  blocked_outputs_messaging = "I can’t share that."

  content_policy_config {
    filters_config {
      type            = "HATE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "INSULTS"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "SEXUAL"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "MEDIUM"
      output_strength = "MEDIUM"
    }
  }

  tags = merge(local.tags, { tenant_id = each.key })
}

