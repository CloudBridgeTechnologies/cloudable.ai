"""
Langfuse Client for Cloudable.AI Agent Core

This module provides integration with Langfuse for advanced AI observability,
including tracing, scoring, and analytics capabilities tailored for LLM applications.

Features:
- Trace generation and span creation for API calls
- Scoring for LLM responses and hallucination detection
- Session management for conversation analysis
- Prompt and completion tracking
- Error and exception handling

Usage:
    from langfuse_client import LangfuseTracer
    
    # Initialize tracer
    tracer = LangfuseTracer(tenant_id="t001")
    
    # Create a trace for a conversation
    trace = tracer.create_trace(customer_id="user123", session_id="session-456")
    
    # Add a span for a specific operation
    with tracer.create_span(trace_id=trace.id, name="kb_query") as span:
        # Your query operation here
        result = query_knowledge_base(...)
        span.add_metadata(result=result)
        
    # Score the response
    tracer.score(
        trace_id=trace.id,
        name="response_quality",
        value=0.95
    )
"""

import os
import time
import json
import logging
import boto3
import uuid
from datetime import datetime
from contextlib import contextmanager

# Configure logger
logger = logging.getLogger('langfuse_client')
logger.setLevel(logging.INFO)

# Check if langfuse package is available
try:
    from langfuse import Langfuse
    from langfuse.client import Trace, Span
    LANGFUSE_AVAILABLE = True
except ImportError:
    LANGFUSE_AVAILABLE = False
    logger.warning("Langfuse package not available. Using mock implementation.")
    
    # Mock classes for compatibility when Langfuse isn't installed
    class MockTrace:
        def __init__(self, id=None):
            self.id = id or str(uuid.uuid4())
            
    class MockSpan:
        def __init__(self, id=None):
            self.id = id or str(uuid.uuid4())
            
        def add_metadata(self, **kwargs):
            pass
            
        def end(self):
            pass
            
        def __enter__(self):
            return self
            
        def __exit__(self, exc_type, exc_val, exc_tb):
            self.end()
            
    class MockLangfuse:
        def __init__(self, *args, **kwargs):
            pass
            
        def trace(self, *args, **kwargs):
            return MockTrace()
            
        def span(self, *args, **kwargs):
            return MockSpan()
            
        def score(self, *args, **kwargs):
            pass
            
        def flush(self):
            pass

# Initialize AWS clients
ssm = boto3.client('ssm')

class LangfuseCredentials:
    """Retrieves and caches Langfuse credentials from SSM Parameter Store"""
    
    _instance = None
    _credentials = {}
    _last_fetched = 0
    _cache_ttl = 3600  # 1 hour in seconds
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(LangfuseCredentials, cls).__new__(cls)
        return cls._instance
    
    def get_credentials(self):
        """Get Langfuse credentials, refreshing from SSM if needed"""
        now = time.time()
        if not self._credentials or (now - self._last_fetched) > self._cache_ttl:
            self._fetch_credentials()
            self._last_fetched = now
        return self._credentials
    
    def _fetch_credentials(self):
        """Fetch Langfuse credentials from SSM Parameter Store"""
        try:
            env = os.environ.get('ENV', 'dev')
            
            # Get parameters from SSM
            public_key = ssm.get_parameter(Name=f"/cloudable/{env}/langfuse/public-key")['Parameter']['Value']
            secret_key = ssm.get_parameter(Name=f"/cloudable/{env}/langfuse/secret-key", WithDecryption=True)['Parameter']['Value']
            host = ssm.get_parameter(Name=f"/cloudable/{env}/langfuse/host")['Parameter']['Value']
            
            self._credentials = {
                'public_key': public_key,
                'secret_key': secret_key,
                'host': host
            }
            
            logger.info("Successfully retrieved Langfuse credentials from SSM")
            
        except Exception as e:
            logger.error(f"Failed to fetch Langfuse credentials: {str(e)}")
            self._credentials = {}

class LangfuseTracer:
    """Main Langfuse tracing client for Cloudable.AI Agent Core"""
    
    def __init__(self, tenant_id):
        """Initialize LangfuseTracer
        
        Args:
            tenant_id (str): Tenant identifier
        """
        self.tenant_id = tenant_id
        self.client = None
        self._initialize_client()
    
    def _initialize_client(self):
        """Initialize Langfuse client with credentials from SSM"""
        if not LANGFUSE_AVAILABLE:
            self.client = MockLangfuse()
            return
            
        try:
            credentials = LangfuseCredentials().get_credentials()
            
            if not credentials:
                logger.warning("No Langfuse credentials available, using mock client")
                self.client = MockLangfuse()
                return
                
            self.client = Langfuse(
                public_key=credentials.get('public_key'),
                secret_key=credentials.get('secret_key'),
                host=credentials.get('host')
            )
            
            logger.info(f"Initialized Langfuse client for tenant {self.tenant_id}")
            
        except Exception as e:
            logger.error(f"Failed to initialize Langfuse client: {str(e)}")
            self.client = MockLangfuse()
    
    def create_trace(self, customer_id=None, session_id=None, name=None):
        """Create a new trace for a conversation or operation sequence
        
        Args:
            customer_id (str): Customer identifier
            session_id (str): Session identifier
            name (str): Optional name for the trace
            
        Returns:
            Trace: Langfuse trace object
        """
        trace_name = name or f"{self.tenant_id}_trace"
        
        metadata = {
            'tenant_id': self.tenant_id,
            'timestamp': datetime.now().isoformat()
        }
        
        if customer_id:
            metadata['customer_id'] = customer_id
            
        if session_id:
            metadata['session_id'] = session_id
            
        try:
            trace = self.client.trace(
                name=trace_name,
                user_id=customer_id,
                id=session_id,  # Use session_id as trace id for continuity
                metadata=metadata,
                tags=[self.tenant_id]
            )
            
            logger.info(f"Created Langfuse trace: {trace.id}")
            return trace
            
        except Exception as e:
            logger.error(f"Failed to create Langfuse trace: {str(e)}")
            return MockTrace(id=session_id or str(uuid.uuid4()))
    
    @contextmanager
    def create_span(self, trace_id, name, metadata=None, input_=None, output=None):
        """Create a span for a specific operation within a trace
        
        Args:
            trace_id (str): Trace identifier
            name (str): Operation name
            metadata (dict): Additional metadata
            input_ (dict): Input data
            output (dict): Output data
            
        Returns:
            Span: Langfuse span object as context manager
        """
        span_metadata = {
            'tenant_id': self.tenant_id,
            'timestamp': datetime.now().isoformat()
        }
        
        if metadata:
            span_metadata.update(metadata)
            
        try:
            span = self.client.span(
                name=name,
                trace_id=trace_id,
                input=input_,
                output=output,
                metadata=span_metadata
            )
            
            yield span
            
        except Exception as e:
            logger.error(f"Error in Langfuse span: {str(e)}")
            span = MockSpan()
            yield span
        finally:
            try:
                if hasattr(span, 'end'):
                    span.end()
            except Exception:
                pass
    
    def log_llm_interaction(self, trace_id, model, prompt, completion, 
                           token_usage=None, latency_ms=None, 
                           prompt_template=None, prompt_variables=None):
        """Log LLM prompt and completion
        
        Args:
            trace_id (str): Trace identifier
            model (str): LLM model identifier
            prompt (str): Input prompt
            completion (str): Model completion
            token_usage (dict): Token usage statistics
            latency_ms (float): Latency in milliseconds
            prompt_template (str): Optional prompt template
            prompt_variables (dict): Optional prompt variables
        """
        try:
            self.client.generation(
                name=f"{model}_generation",
                trace_id=trace_id,
                model=model,
                prompt=prompt,
                completion=completion,
                usage=token_usage,
                latency_ms=latency_ms,
                prompt_template=prompt_template,
                prompt_variables=prompt_variables,
                metadata={'tenant_id': self.tenant_id}
            )
            
        except Exception as e:
            logger.error(f"Failed to log LLM interaction: {str(e)}")
    
    def score(self, trace_id, name, value, comment=None):
        """Score an operation or response
        
        Args:
            trace_id (str): Trace identifier
            name (str): Score name
            value (float): Score value (0.0 to 1.0)
            comment (str): Optional comment explaining the score
        """
        try:
            self.client.score(
                trace_id=trace_id,
                name=name,
                value=value,
                comment=comment
            )
            
        except Exception as e:
            logger.error(f"Failed to create score: {str(e)}")
    
    def log_event(self, trace_id, name, event_data):
        """Log a custom event
        
        Args:
            trace_id (str): Trace identifier
            name (str): Event name
            event_data (dict): Event data
        """
        try:
            self.client.event(
                trace_id=trace_id,
                name=name,
                input=event_data,
                metadata={'tenant_id': self.tenant_id}
            )
            
        except Exception as e:
            logger.error(f"Failed to log event: {str(e)}")
    
    def flush(self):
        """Flush pending operations to Langfuse"""
        try:
            if hasattr(self.client, 'flush'):
                self.client.flush()
        except Exception as e:
            logger.error(f"Failed to flush Langfuse client: {str(e)}")

# Function decorators for easier integration

def langfuse_trace(tracer, operation_name):
    """Decorator to add Langfuse tracing to functions
    
    Args:
        tracer (LangfuseTracer): Langfuse tracer instance
        operation_name (str): Operation name for the trace
        
    Returns:
        function: Decorated function with tracing
    """
    def decorator(func):
        def wrapper(*args, **kwargs):
            # Extract trace_id and customer_id from kwargs if available
            trace_id = kwargs.get('trace_id')
            customer_id = kwargs.get('customer_id')
            tenant_id = kwargs.get('tenant_id', tracer.tenant_id)
            
            # Create a new trace if none exists
            if not trace_id:
                trace = tracer.create_trace(
                    customer_id=customer_id, 
                    name=f"{operation_name}"
                )
                trace_id = trace.id
                kwargs['trace_id'] = trace_id
            
            # Create a span for this operation
            with tracer.create_span(
                trace_id=trace_id,
                name=operation_name,
                input_={k: str(v) for k, v in kwargs.items() if k != 'trace_id'},
            ) as span:
                try:
                    # Call the original function
                    result = func(*args, **kwargs)
                    
                    # Add the result to the span
                    if isinstance(result, dict):
                        output_data = result
                    else:
                        output_data = {'result': str(result)}
                        
                    span.add_metadata(output=output_data)
                    
                    # Score successful operations
                    if 'status' in output_data and output_data.get('status') == 'success':
                        tracer.score(trace_id=trace_id, name=f"{operation_name}_success", value=1.0)
                    
                    return result
                    
                except Exception as e:
                    # Log the error and re-raise
                    error_data = {
                        'error_type': type(e).__name__,
                        'error_message': str(e)
                    }
                    span.add_metadata(error=error_data)
                    tracer.score(trace_id=trace_id, name=f"{operation_name}_error", value=0.0, 
                               comment=f"Error: {str(e)}")
                    raise
                
        return wrapper
    return decorator
