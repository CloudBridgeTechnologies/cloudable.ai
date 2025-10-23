resource "aws_bedrockagent_agent" "tenant" {
  for_each                = var.enable_bedrock_agents ? var.tenants : {}
  agent_name              = "agent-${var.env}-${each.value.name}"
  instruction             = "You are the ${each.value.name} assistant. Allowed intents: journey.status, assessment.summary. For journey.status, call the rds_read action group POST /journey_status with JSON {tenant_id, customer_id}. For assessment.summary, call POST /assessments_summary with JSON {tenant_id, customer_id}. Do not answer from your own knowledge; always call the action to retrieve data, then return the action result. Refuse all other intents."
  foundation_model        = "anthropic.claude-3-sonnet-20240229-v1:0"
  agent_resource_role_arn = aws_iam_role.agent.arn

  # guardrail_configuration {
  #   guardrail_identifier = aws_bedrock_guardrail.tenant[each.key].guardrail_id
  #   guardrail_version    = "DRAFT"
  # }

  idle_session_ttl_in_seconds = 600
  tags                        = merge(local.tags, { tenant_id = each.key })
}

resource "aws_bedrockagent_agent_action_group" "tenant_db" {
  for_each          = var.enable_bedrock_agents ? var.tenants : {}
  action_group_name = "rds_read"
  agent_id          = aws_bedrockagent_agent.tenant[each.key].id
  agent_version     = "DRAFT"

    action_group_executor { lambda = aws_lambda_function.db_actions.arn }
  api_schema {
    payload = <<EOF
openapi: "3.0.0"
info:
  title: "DB Read"
  version: "1.0.0"
paths:
  /journey_status:
    post:
      description: "Invoke journey status lookup via Lambda with tenant_id and customer_id. Use for journey status requests."
      operationId: journey_status
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [tenant_id, customer_id]
              properties:
                tenant_id:
                  type: string
                  description: "Tenant identifier"
                customer_id:
                  type: string
                  description: "Customer identifier"
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  result:
                    type: string
                    description: "Formatted journey status summary"
  /assessments_summary:
    post:
      description: "Invoke assessments summary lookup via Lambda with tenant_id and customer_id. Use for assessment summary requests."
      operationId: assessments_summary
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [tenant_id, customer_id]
              properties:
                tenant_id:
                  type: string
                  description: "Tenant identifier"
                customer_id:
                  type: string
                  description: "Customer identifier"
      responses:
        "200":
          description: OK
          content:
            application/json:
              schema:
                type: object
                properties:
                  result:
                    type: string
                    description: "Formatted assessments summary"
EOF
  }
  skip_resource_in_use_check = true
}

# Temporarily disabled terraform_data resources to avoid circular dependency
# resource "terraform_data" "prepare_agent" {
#   for_each = var.enable_bedrock_agents ? var.tenants : {}
#   triggers_replace = {
#     a = sha256(jsonencode(aws_bedrockagent_agent.tenant[each.key]))
#     g = sha256(jsonencode(aws_bedrockagent_agent_action_group.tenant_db[each.key]))
#   }
#   provisioner "local-exec" {
#     command = "aws bedrock-agent prepare-agent --agent-id ${aws_bedrockagent_agent.tenant[each.key].id} --region ${var.region} --output json --no-cli-pager"
#   }
# }

# resource "terraform_data" "wait_agent_prepared" {
#   for_each = var.enable_bedrock_agents ? var.tenants : {}
#   triggers_replace = {
#     a = sha256(jsonencode(terraform_data.prepare_agent[each.key].id))
#   }
#   provisioner "local-exec" {
#     interpreter = ["/bin/sh", "-c"]
#     command = <<EOC
# set -e
# for i in $(seq 1 60); do
#   status=$(aws bedrock-agent get-agent --agent-id ${aws_bedrockagent_agent.tenant[each.key].id} --region ${var.region} --query agent.agentStatus --output text 2>/dev/null || echo UNKNOWN)
#   if [ "$status" = "PREPARED" ]; then
#     exit 0
#   fi
#   sleep 10
# done
# echo "Agent did not reach PREPARED state in time"
# exit 1
# EOC
#   }
# }

 


resource "aws_bedrockagent_agent_alias" "tenant" {
  for_each         = var.enable_bedrock_agents ? var.tenants : {}
  agent_id         = aws_bedrockagent_agent.tenant[each.key].id
  agent_alias_name = "live"
  description      = "Live alias"
  # depends_on       = [terraform_data.wait_agent_prepared]
}

resource "aws_bedrockagent_agent_knowledge_base_association" "tenant" {
  for_each           = var.enable_bedrock_agents ? var.tenants : {}
  agent_id           = aws_bedrockagent_agent.tenant[each.key].id
  agent_version      = "DRAFT"
  knowledge_base_id  = aws_bedrockagent_knowledge_base.tenant[each.key].id
  knowledge_base_state = "ENABLED"
  description        = "Knowledge base association for ${each.value.name}"
  depends_on         = [aws_bedrockagent_agent_action_group.tenant_db]
}

