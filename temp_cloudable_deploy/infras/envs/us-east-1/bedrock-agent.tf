resource "aws_bedrockagent_agent" "tenant" {
  for_each                = var.enable_bedrock_agents ? var.tenants : {}
  agent_name              = "agent-${var.env}-${each.value.name}"
  instruction             = <<EOF
You are an intelligent AI assistant for ${each.value.name} with advanced reasoning capabilities. You can:

1. **Personal Data Operations**: Access customer journey status and assessment summaries
2. **Knowledge Base Queries**: Search company policies, procedures, and documentation
3. **Intelligent Routing**: Determine the best approach based on query context
4. **Multi-step Reasoning**: Break down complex requests into actionable steps
5. **Context Awareness**: Maintain conversation context and provide personalized responses

**Core Capabilities:**
- Journey Status: Retrieve and analyze customer progress through onboarding/engagement stages
- Assessment Analysis: Access and summarize customer assessment results
- Knowledge Search: Query company knowledge base for policies and procedures
- Intelligent Decision Making: Choose appropriate actions based on query intent

**Reasoning Process:**
1. Analyze the user's intent and context
2. Determine if the query requires personal data, company knowledge, or both
3. Route to appropriate action groups or knowledge base
4. Synthesize information from multiple sources when needed
5. Provide comprehensive, contextual responses

**Allowed Operations:**
- journey.status: Get customer journey progress
- assessment.summary: Retrieve assessment results
- knowledge.search: Query company knowledge base
- multi.step.analysis: Combine personal data with company knowledge

Always call the appropriate action group or knowledge base rather than using your own knowledge. Provide detailed, actionable responses based on the retrieved data.
EOF
  foundation_model        = "anthropic.claude-3-sonnet-20240229-v1:0"
  agent_resource_role_arn = aws_iam_role.agent.arn

  # Note: Inference configuration not supported in current provider version
  # Will be configured via AWS console or API

  # guardrail_configuration {
  #   guardrail_identifier = aws_bedrock_guardrail.tenant[each.key].guardrail_id
  #   guardrail_version    = "DRAFT"
  # }

  idle_session_ttl_in_seconds = 1800  # Increased for longer conversations
  tags                        = merge(local.tags, { tenant_id = each.key })
}

resource "aws_bedrockagent_agent_action_group" "tenant_db" {
  for_each          = var.enable_bedrock_agents ? var.tenants : {}
  action_group_name = "customer_data_operations"
  agent_id          = aws_bedrockagent_agent.tenant[each.key].id
  agent_version     = "DRAFT"
  description       = "Customer data operations for journey tracking and assessment analysis"

  action_group_executor { lambda = aws_lambda_function.db_actions.arn }
  api_schema {
    payload = <<EOF
openapi: "3.0.0"
info:
  title: "Customer Data Operations"
  version: "2.0.0"
  description: "Advanced customer data operations with intelligent analysis capabilities"
paths:
  /journey_status:
    post:
      description: "Retrieve comprehensive journey status with progress analysis and next steps"
      operationId: get_journey_status
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
                include_analysis:
                  type: boolean
                  description: "Include AI-powered analysis of journey progress"
                  default: true
      responses:
        "200":
          description: "Journey status with analysis"
          content:
            application/json:
              schema:
                type: object
                properties:
                  result:
                    type: string
                    description: "Formatted journey status with analysis"
                  stage:
                    type: string
                    description: "Current journey stage"
                  progress:
                    type: number
                    description: "Progress percentage"
                  next_steps:
                    type: array
                    items:
                      type: string
                    description: "Recommended next steps"
  /assessments_summary:
    post:
      description: "Retrieve assessment summary with trend analysis and insights"
      operationId: get_assessments_summary
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
                include_trends:
                  type: boolean
                  description: "Include trend analysis across assessments"
                  default: true
      responses:
        "200":
          description: "Assessment summary with insights"
          content:
            application/json:
              schema:
                type: object
                properties:
                  result:
                    type: string
                    description: "Formatted assessment summary"
                  latest_score:
                    type: number
                    description: "Latest assessment score"
                  trend:
                    type: string
                    description: "Performance trend (improving/stable/declining)"
                  insights:
                    type: array
                    items:
                      type: string
                    description: "AI-generated insights"
  /customer_insights:
    post:
      description: "Generate comprehensive customer insights combining journey and assessment data"
      operationId: get_customer_insights
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
                insight_type:
                  type: string
                  enum: ["comprehensive", "journey_focus", "assessment_focus"]
                  description: "Type of insights to generate"
                  default: "comprehensive"
      responses:
        "200":
          description: "Comprehensive customer insights"
          content:
            application/json:
              schema:
                type: object
                properties:
                  result:
                    type: string
                    description: "Formatted customer insights"
                  journey_summary:
                    type: string
                    description: "Journey progress summary"
                  assessment_summary:
                    type: string
                    description: "Assessment performance summary"
                  recommendations:
                    type: array
                    items:
                      type: string
                    description: "Personalized recommendations"
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

