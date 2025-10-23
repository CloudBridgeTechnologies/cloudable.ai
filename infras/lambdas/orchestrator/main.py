import os, json, sys
import logging
from agent_core import get_agent_core

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Lambda handler for orchestrator with enhanced Agent Core functionality
    
    This handler processes API Gateway requests and uses the Agent Core module
    for intelligent routing, telemetry, and tracing of interactions.
    """
    logger.info(f"Received request: {json.dumps(event)}")
    
    body = json.loads(event.get("body") or "{}")
    message     = body.get("message","")
    tenant_id   = body.get("tenant_id")
    customer_id = body.get("customer_id")
    session_id  = body.get("session_id")  # Optional session ID for conversation continuity
    trace_id    = body.get("trace_id")    # Optional trace ID for observability

    logger.info(f"Parsed parameters - message: {message}, tenant_id: {tenant_id}, customer_id: {customer_id}")

    # Validate required parameters
    if not (message and tenant_id and customer_id):
        logger.error(f"Missing parameters - message: {bool(message)}, tenant_id: {bool(tenant_id)}, customer_id: {bool(customer_id)}")
        return _resp(400, {"error":"message, tenant_id, customer_id required"})

    # Initialize Agent Core for this tenant
    agent_core = get_agent_core(tenant_id)
    
    # Invoke Agent Core with full telemetry and observability
    result = agent_core.invoke_agent(
        customer_id=customer_id,
        message=message,
        session_id=session_id,
        trace_id=trace_id
    )
    
    # Handle error cases
    if result.get("status") == "error":
        return _resp(result.get("statusCode", 500), {
            "error": result.get("error", "Unknown error"),
            "session_id": result.get("session_id"),
            "trace_id": result.get("trace_id")
        })
        
    # Process successful result
    # Analyze response for additional insights (quality, entities, sentiment)
    analysis = agent_core.analyze_response(
        trace_id=result.get("trace_id"), 
        response=result.get("answer", "")
    )
    
    # Return enhanced response with observability data
    return _resp(200, {
        "answer": result.get("answer", ""),
        "trace": result.get("trace", []),
        "session_id": result.get("session_id"),
        "trace_id": result.get("trace_id"),
        "analysis": analysis.get("metrics", {})
    })

def _resp(code, payload):
    return {"statusCode": code, "headers": {"content-type":"application/json"}, "body": json.dumps(payload)}
