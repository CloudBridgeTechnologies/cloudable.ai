"""
Orchestrator Lambda function for handling various API requests

This Lambda acts as the central orchestrator for the following operations:
1. Chat with the agent via agent_core
2. Knowledge base queries via agent_core
3. KB upload URL generation via kb_manager
4. KB synchronization via kb_manager
"""

import os
import json
import sys
import logging
import traceback

# Setup logging to CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    """
    Lambda handler for orchestrator with enhanced debugging
    """
    try:
        # Log the full event for debugging
        logger.info(f"ORCHESTRATOR RECEIVED EVENT: {json.dumps(event)}")
        
        # Determine request type from path
        path = event.get("path", "")
        logger.info(f"Path: {path}")
        
        # Parse the body
        try:
            body = json.loads(event.get("body") or "{}")
            logger.info(f"Parsed body: {json.dumps(body)}")
        except Exception as e:
            logger.error(f"Error parsing body: {str(e)}")
            return _resp(400, {"error": f"Invalid JSON body: {str(e)}"})
            
        # Handle KB Query request
        if "/kb/query" in path:
            return handle_kb_query(body)
        # Handle Chat request
        elif "/chat" in path:
            return handle_chat(body)
        # Default response for other endpoints
        else:
            logger.info(f"Unimplemented endpoint: {path}")
            return _resp(501, {"message": f"Endpoint {path} not yet implemented"})
    
    except Exception as e:
        # Log the full exception with traceback
        exception_type = type(e).__name__
        exception_message = str(e)
        exception_traceback = traceback.format_exc()
        
        logger.error(f"UNHANDLED EXCEPTION: {exception_type}: {exception_message}")
        logger.error(f"TRACEBACK:\n{exception_traceback}")
        
        # Return a meaningful error response
        return _resp(500, {
            "error": "Internal server error",
            "type": exception_type,
            "message": exception_message,
            "debug_info": "See CloudWatch logs for details"
        })

def handle_kb_query(body):
    """Handle knowledge base query with detailed logging"""
    logger.info("HANDLING KB QUERY")
    
    # Extract required parameters
    tenant_id = body.get("tenant_id")
    query = body.get("query")
    
    # Validate parameters
    if not tenant_id or not query:
        logger.warning(f"Missing parameters: tenant_id={tenant_id}, query={query}")
        return _resp(400, {"error": "tenant_id and query are required parameters"})
    
    # Log parameters
    logger.info(f"KB query parameters: tenant_id={tenant_id}, query={query}")
    
    # For now, just echo back the request with a stub response
    # This is to verify the basic request/response flow works
    response = {
        "answer": f"This is a test response for query: '{query}' from tenant: '{tenant_id}'",
        "sources_count": 0,
        "confidence_scores": []
    }
    
    return _resp(200, response)

def handle_chat(body):
    """Handle chat requests with detailed logging"""
    logger.info("HANDLING CHAT REQUEST")
    
    # Extract required parameters
    message = body.get("message", "")
    tenant_id = body.get("tenant_id")
    customer_id = body.get("customer_id")
    
    # Validate parameters
    if not message or not tenant_id or not customer_id:
        logger.warning(f"Missing parameters: message={bool(message)}, tenant_id={tenant_id}, customer_id={customer_id}")
        return _resp(400, {"error": "message, tenant_id, and customer_id are required parameters"})
    
    # Log parameters
    logger.info(f"Chat parameters: tenant_id={tenant_id}, customer_id={customer_id}, message={message}")
    
    # For now, just echo back the request with a stub response
    response = {
        "answer": f"This is a test response for message: '{message}' from tenant: '{tenant_id}'",
        "session_id": "test-session",
        "trace_id": "test-trace"
    }
    
    return _resp(200, response)

def _resp(code, payload):
    """Format a response for API Gateway with CORS headers"""
    response = {
        "statusCode": code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key",
            "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS"
        },
        "body": json.dumps(payload)
    }
    
    # Log the response we're sending
    logger.info(f"Sending response: statusCode={code}, body={json.dumps(payload)}")
    
    return response