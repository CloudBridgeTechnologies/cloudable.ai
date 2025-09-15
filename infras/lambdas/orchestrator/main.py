import os, json, boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock_agent = boto3.client("bedrock-agent-runtime", region_name="us-east-1")
bedrock = boto3.client("bedrock-runtime", region_name="us-east-1")

# In prod you’d resolve alias per tenant from config/SSM. For POC, accept aliasArn from client (server-validated).
def handler(event, context):
    logger.info(f"Received request: {json.dumps(event)}")
    
    body = json.loads(event.get("body") or "{}")
    message     = body.get("message","")
    tenant_id   = body.get("tenant_id")
    customer_id = body.get("customer_id")
    alias_arn   = body.get("agent_alias_arn")  # or fetch from SSM by tenant

    logger.info(f"Parsed parameters - message: {message}, tenant_id: {tenant_id}, customer_id: {customer_id}, alias_arn: {alias_arn}")

    if not (message and tenant_id and customer_id and alias_arn):
        logger.error(f"Missing parameters - message: {bool(message)}, tenant_id: {bool(tenant_id)}, customer_id: {bool(customer_id)}, alias_arn: {bool(alias_arn)}")
        return _resp(400, {"error":"message, tenant_id, customer_id, agent_alias_arn required"})

    session_id = f"{tenant_id}:{customer_id}"
    ctx = {
        "tenant_id": tenant_id,
        "customer_id": customer_id
    }

    # Convert alias ARN to agentId and agentAliasId
    # arn:aws:bedrock:REGION:ACCOUNT:agent-alias/AGENT_ID/ALIAS_ID
    try:
        resource = alias_arn.split(":", 5)[5]
        _, agent_id, alias_id = resource.split("/")
    except Exception:
        return _resp(400, {"error":"Invalid agent_alias_arn format"})

    try:
        logger.info(f"Invoking agent with sessionState: {ctx}")
        resp = bedrock_agent.invoke_agent(
            agentId        = agent_id,
            agentAliasId   = alias_id,
            sessionId      = session_id,
            inputText      = message,
            sessionState   = {"promptSessionAttributes": ctx},
            enableTrace    = True
        )

        # stream aggregator
        answer = ""
        traces = []
        for ev in resp.get("completion", []):
            if "trace" in ev:
                # Log orchestration traces to CloudWatch for debugging
                try:
                    print(json.dumps(ev["trace"]))
                    traces.append(ev["trace"])
                except Exception:
                    pass
            if "chunk" in ev:
                answer += ev["chunk"]["bytes"].decode()

        return _resp(200, {"answer": answer, "trace": traces})
    except Exception as e:
        # Return detailed error for troubleshooting
        return _resp(500, {
            "error": str(e),
            "agentId": agent_id,
            "agentAliasId": alias_id,
            "sessionId": session_id
        })

def _resp(code, payload):
    return {"statusCode": code, "headers": {"content-type":"application/json"}, "body": json.dumps(payload)}
