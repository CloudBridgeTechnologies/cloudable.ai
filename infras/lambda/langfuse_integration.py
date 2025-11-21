"""
Langfuse integration module for Cloudable.AI
This module provides observability and LLM monitoring capabilities for the platform.
"""

import os
import json
import logging
import uuid
import time
from typing import Dict, Any, List, Optional, Union
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# URL for Langfuse API - Getting from environment variable with EU default
LANGFUSE_HOST = os.environ.get('LANGFUSE_HOST', 'https://eu.cloud.langfuse.com')

# API keys from environment variables
LANGFUSE_PUBLIC_KEY = os.environ.get('LANGFUSE_PUBLIC_KEY')
LANGFUSE_SECRET_KEY = os.environ.get('LANGFUSE_SECRET_KEY')

# Project and Organization IDs
LANGFUSE_PROJECT_ID = os.environ.get('LANGFUSE_PROJECT_ID', 'cmhz8tqhk00duad07xptpuo06')
LANGFUSE_ORG_ID = os.environ.get('LANGFUSE_ORG_ID', 'cmhz8tcqz00dpad07ee341p57')

# Log Langfuse configuration at startup
logger.info(f"Langfuse Host: {LANGFUSE_HOST}")
logger.info(f"Langfuse Public Key configured: {LANGFUSE_PUBLIC_KEY is not None}")
logger.info(f"Langfuse Project ID: {LANGFUSE_PROJECT_ID}")
logger.info(f"Langfuse Organization ID: {LANGFUSE_ORG_ID}")

# Global variables for request-response mapping
_trace_map = {}
_current_request_id = None

def _get_auth_header():
    """Get basic auth header for Langfuse API"""
    if not LANGFUSE_PUBLIC_KEY or not LANGFUSE_SECRET_KEY:
        return None
    
    try:
        import base64
        auth_string = f"{LANGFUSE_PUBLIC_KEY}:{LANGFUSE_SECRET_KEY}"
        encoded = base64.b64encode(auth_string.encode()).decode()
        return f"Basic {encoded}"
    except Exception as e:
        logger.error(f"Error creating auth header: {e}")
        return None

def _make_langfuse_request(endpoint, data):
    """Make a request to the Langfuse API"""
    try:
        import requests
        
        auth_header = _get_auth_header()
        if not auth_header:
            logger.error("No auth header available")
            return None
        
        headers = {
            "Authorization": auth_header,
            "Content-Type": "application/json"
        }
        
        url = f"{LANGFUSE_HOST}/api/public/{endpoint}"
        logger.info(f"Making request to Langfuse: {url}")
        
        response = requests.post(
            url,
            headers=headers,
            json=data
        )
        
        if response.status_code != 200:
            logger.error(f"Langfuse API error: {response.status_code} {response.text}")
            return None
        
        return response.json()
    except ImportError:
        logger.error("Requests library not available")
        return None
    except Exception as e:
        logger.error(f"Error making Langfuse request: {e}")
        return None

def create_trace(name, tenant_id, user_id=None, metadata=None):
    """Create a trace in Langfuse"""
    try:
        trace_id = str(uuid.uuid4())
        
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        
        if user_id:
            metadata["user_id"] = user_id
            
        trace_data = {
            "id": trace_id,
            "name": name,
            "userId": user_id or "anonymous",
            "metadata": metadata,
            "projectId": LANGFUSE_PROJECT_ID,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
        
        # Store the trace for flushing later
        _trace_map[trace_id] = {
            "data": trace_data,
            "spans": [],
            "generations": []
        }
        
        logger.info(f"Created trace with ID: {trace_id}")
        return trace_id
    except Exception as e:
        logger.error(f"Error creating trace: {e}")
        return str(uuid.uuid4())  # Return a dummy ID that won't be used

def trace_kb_query(trace_id, query, results, tenant_id, execution_time_ms):
    """Trace a KB query operation"""
    try:
        if trace_id not in _trace_map:
            logger.warning(f"Trace ID {trace_id} not found")
            return
            
        span_id = str(uuid.uuid4())
        
        span_data = {
            "id": span_id,
            "traceId": trace_id,
            "name": "kb_query",
            "startTime": datetime.utcnow().isoformat() + "Z",
            "metadata": {
                "tenant_id": tenant_id,
                "result_count": len(results),
                "execution_time_ms": execution_time_ms
            },
            "input": {"query": query},
            "output": {"results": results}
        }
        
        _trace_map[trace_id]["spans"].append(span_data)
        logger.info(f"Added KB query span to trace {trace_id}")
    except Exception as e:
        logger.error(f"Error tracing KB query: {e}")

def trace_chat(trace_id, message, response, source_docs, tenant_id, execution_time_ms):
    """Trace a chat interaction"""
    try:
        if trace_id not in _trace_map:
            logger.warning(f"Trace ID {trace_id} not found")
            return
            
        gen_id = str(uuid.uuid4())
        
        gen_data = {
            "id": gen_id,
            "traceId": trace_id,
            "name": "chat_response",
            "startTime": datetime.utcnow().isoformat() + "Z",
            "model": "ai.cloudable.custom",
            "modelParameters": {
                "temperature": 0.7,
                "use_kb": True
            },
            "metadata": {
                "tenant_id": tenant_id,
                "source_count": len(source_docs),
                "execution_time_ms": execution_time_ms
            },
            "prompt": message,
            "completion": response
        }
        
        _trace_map[trace_id]["generations"].append(gen_data)
        logger.info(f"Added chat generation to trace {trace_id}")
    except Exception as e:
        logger.error(f"Error tracing chat: {e}")

def flush_observations():
    """Flush all observations to Langfuse"""
    if not LANGFUSE_PUBLIC_KEY or not LANGFUSE_SECRET_KEY:
        logger.warning("Langfuse API keys not configured, skipping flush")
        return
        
    try:
        logger.info(f"Flushing {len(_trace_map)} traces to Langfuse")
        
        success_count = 0
        for trace_id, trace_data in _trace_map.items():
            # Send trace
            trace_result = _make_langfuse_request("traces", trace_data["data"])
            if not trace_result:
                logger.error(f"Failed to send trace {trace_id}")
                continue
                
            # Send spans
            for span in trace_data["spans"]:
                span_result = _make_langfuse_request("spans", span)
                if not span_result:
                    logger.error(f"Failed to send span {span['id']} for trace {trace_id}")
            
            # Send generations
            for gen in trace_data["generations"]:
                gen_result = _make_langfuse_request("generations", gen)
                if not gen_result:
                    logger.error(f"Failed to send generation {gen['id']} for trace {trace_id}")
                    
            success_count += 1
            
        # Clear the trace map
        _trace_map.clear()
        
        logger.info(f"Successfully flushed {success_count} traces to Langfuse")
    except Exception as e:
        logger.error(f"Error flushing observations: {e}")
