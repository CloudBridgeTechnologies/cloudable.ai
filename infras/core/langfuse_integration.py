"""
Langfuse integration for Cloudable.AI
This module provides observability and LLM monitoring capabilities for the platform.
"""

import os
import json
import logging
import uuid
from typing import Dict, Any, List, Optional, Union
from datetime import datetime

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Mock Langfuse client for local development and testing
# In production, replace with actual Langfuse client
class MockLangfuseClient:
    def __init__(self):
        self.traces = []
        self.spans = []
        self.generations = []
        self.events = []
        logger.info("Initialized MockLangfuseClient")
        
    def trace(self, name, **kwargs):
        trace_id = str(uuid.uuid4())
        trace = {
            "id": trace_id,
            "name": name,
            "timestamp": datetime.now().isoformat(),
            **kwargs
        }
        self.traces.append(trace)
        logger.info(f"Created trace: {name} ({trace_id})")
        return trace_id
        
    def span(self, trace_id, name, **kwargs):
        span_id = str(uuid.uuid4())
        span = {
            "id": span_id,
            "trace_id": trace_id,
            "name": name,
            "timestamp": datetime.now().isoformat(),
            **kwargs
        }
        self.spans.append(span)
        logger.info(f"Created span: {name} in trace {trace_id}")
        return span_id
        
    def generation(self, trace_id, name, **kwargs):
        gen_id = str(uuid.uuid4())
        generation = {
            "id": gen_id,
            "trace_id": trace_id,
            "name": name,
            "timestamp": datetime.now().isoformat(),
            **kwargs
        }
        self.generations.append(generation)
        logger.info(f"Recorded generation: {name} in trace {trace_id}")
        return gen_id
        
    def event(self, trace_id, name, **kwargs):
        event_id = str(uuid.uuid4())
        event = {
            "id": event_id,
            "trace_id": trace_id,
            "name": name,
            "timestamp": datetime.now().isoformat(),
            **kwargs
        }
        self.events.append(event)
        logger.info(f"Recorded event: {name} in trace {trace_id}")
        return event_id
    
    def get_all_observations(self):
        """Return all observations for debugging"""
        return {
            "traces": self.traces,
            "spans": self.spans,
            "generations": self.generations,
            "events": self.events
        }

# Initialize mock client
_mock_client = MockLangfuseClient()

try:
    # Try to import actual Langfuse client
    from langfuse import Langfuse
    
    # Check if Langfuse API keys are set
    langfuse_public_key = os.getenv("LANGFUSE_PUBLIC_KEY")
    langfuse_secret_key = os.getenv("LANGFUSE_SECRET_KEY")
    
    if langfuse_public_key and langfuse_secret_key:
        _langfuse_client = Langfuse(
            public_key=langfuse_public_key,
            secret_key=langfuse_secret_key,
            host=os.getenv("LANGFUSE_HOST", "https://cloud.langfuse.com")
        )
        logger.info("Initialized actual Langfuse client")
    else:
        logger.warning("Langfuse API keys not found, using mock client")
        _langfuse_client = _mock_client
except ImportError:
    logger.warning("Langfuse package not installed, using mock client")
    _langfuse_client = _mock_client

# Determine if we're using the real client or mock
using_mock_client = _langfuse_client is _mock_client

def create_trace(name: str, 
                 tenant_id: str, 
                 user_id: Optional[str] = None, 
                 metadata: Optional[Dict[str, Any]] = None) -> str:
    """
    Create a new trace for a user interaction
    
    Args:
        name: Name of the trace
        tenant_id: ID of the tenant
        user_id: ID of the user (optional)
        metadata: Additional metadata
        
    Returns:
        Trace ID
    """
    try:
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        if user_id:
            metadata["user_id"] = user_id
        
        trace_id = _langfuse_client.trace(
            name=name,
            user_id=user_id or "anonymous",
            metadata=metadata
        )
        return trace_id
    except Exception as e:
        logger.error(f"Error creating Langfuse trace: {str(e)}")
        return str(uuid.uuid4())  # Return dummy ID if there's an error

def trace_kb_query(trace_id: str, 
                   query: str, 
                   results: List[Dict], 
                   tenant_id: str,
                   execution_time_ms: int,
                   metadata: Optional[Dict[str, Any]] = None) -> None:
    """
    Trace a knowledge base query
    
    Args:
        trace_id: ID of the parent trace
        query: User query
        results: Query results
        tenant_id: ID of the tenant
        execution_time_ms: Time taken to execute query in ms
        metadata: Additional metadata
    """
    try:
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        metadata["result_count"] = len(results)
        metadata["execution_time_ms"] = execution_time_ms
        
        span_id = _langfuse_client.span(
            trace_id=trace_id,
            name="kb_query",
            input={"query": query},
            output={"results": results},
            metadata=metadata,
        )
        
        # Record each result as an event
        for i, result in enumerate(results):
            _langfuse_client.event(
                trace_id=trace_id,
                name=f"kb_result_{i+1}",
                input={"query": query},
                output={"text": result.get("text", ""), "score": result.get("score", 0)},
                metadata={
                    "source": result.get("metadata", {}).get("source", "Unknown"),
                    "kb_id": result.get("metadata", {}).get("kb_id", "Unknown"),
                    "relevance_score": result.get("score", 0)
                }
            )
    except Exception as e:
        logger.error(f"Error tracing KB query: {str(e)}")

def trace_chat(trace_id: str,
               message: str,
               response: str, 
               source_documents: List[Dict],
               tenant_id: str,
               use_kb: bool,
               execution_time_ms: int,
               token_count: int = 0,
               metadata: Optional[Dict[str, Any]] = None) -> None:
    """
    Trace a chat interaction
    
    Args:
        trace_id: ID of the parent trace
        message: User message
        response: AI response
        source_documents: Source documents used
        tenant_id: ID of the tenant
        use_kb: Whether KB was used
        execution_time_ms: Time taken to generate response in ms
        token_count: Estimated token count
        metadata: Additional metadata
    """
    try:
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        metadata["use_kb"] = use_kb
        metadata["source_count"] = len(source_documents)
        metadata["execution_time_ms"] = execution_time_ms
        metadata["token_count"] = token_count
        
        generation_id = _langfuse_client.generation(
            trace_id=trace_id,
            name="chat_response",
            model="bedrock.claude-3-sonnet",  # Assuming Claude 3 Sonnet from Bedrock
            prompt=message,
            completion=response,
            metadata=metadata
        )
        
        # Record source documents as events
        for i, doc in enumerate(source_documents):
            _langfuse_client.event(
                trace_id=trace_id,
                name=f"chat_source_{i+1}",
                metadata={
                    "source": doc.get("metadata", {}).get("source", "Unknown"),
                    "kb_id": doc.get("metadata", {}).get("kb_id", "Unknown"),
                    "text": doc.get("text", "")
                }
            )
    except Exception as e:
        logger.error(f"Error tracing chat: {str(e)}")

def trace_bedrock_call(trace_id: str,
                       prompt: str,
                       response: str,
                       model: str,
                       purpose: str,
                       execution_time_ms: int,
                       metadata: Optional[Dict[str, Any]] = None) -> None:
    """
    Trace a call to AWS Bedrock
    
    Args:
        trace_id: ID of the parent trace
        prompt: Prompt sent to Bedrock
        response: Response from Bedrock
        model: Bedrock model used
        purpose: Purpose of the call (e.g., "summarization")
        execution_time_ms: Time taken to get response in ms
        metadata: Additional metadata
    """
    try:
        metadata = metadata or {}
        metadata["purpose"] = purpose
        metadata["execution_time_ms"] = execution_time_ms
        
        _langfuse_client.generation(
            trace_id=trace_id,
            name=f"bedrock_{purpose}",
            model=model,
            prompt=prompt,
            completion=response,
            metadata=metadata
        )
    except Exception as e:
        logger.error(f"Error tracing Bedrock call: {str(e)}")

def trace_customer_status(trace_id: str,
                          tenant_id: str,
                          customer_id: Optional[str],
                          response: Dict[str, Any],
                          execution_time_ms: int,
                          metadata: Optional[Dict[str, Any]] = None) -> None:
    """
    Trace a customer status query
    
    Args:
        trace_id: ID of the parent trace
        tenant_id: ID of the tenant
        customer_id: ID of the customer (optional)
        response: Response data
        execution_time_ms: Time taken to get status in ms
        metadata: Additional metadata
    """
    try:
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        metadata["customer_id"] = customer_id
        metadata["execution_time_ms"] = execution_time_ms
        
        _langfuse_client.span(
            trace_id=trace_id,
            name="customer_status_query",
            input={"customer_id": customer_id},
            output=response,
            metadata=metadata
        )
    except Exception as e:
        logger.error(f"Error tracing customer status query: {str(e)}")

def flush_observations():
    """
    Flush observations to Langfuse
    """
    try:
        if not using_mock_client:
            # Real Langfuse client has a flush method
            _langfuse_client.flush()
            logger.info("Flushed observations to Langfuse")
        else:
            logger.info("Using mock client, no need to flush")
    except Exception as e:
        logger.error(f"Error flushing observations: {str(e)}")

def get_mock_observations():
    """
    Get all mock observations for debugging
    Only works with mock client
    """
    if using_mock_client:
        return _mock_client.get_all_observations()
    return {"error": "Not using mock client"}
