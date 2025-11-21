#!/bin/bash

# Script to fix Langfuse integration

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=========================================================="
echo "  FIXING LANGFUSE INTEGRATION"
echo -e "==========================================================${NC}"

# Set AWS region for this session
export AWS_DEFAULT_REGION=us-east-1
export AWS_REGION=us-east-1
echo -e "Using AWS Region: ${GREEN}$AWS_DEFAULT_REGION${NC}"

# Create an updated version of the Langfuse integration module
echo -e "\n${YELLOW}Creating updated Langfuse integration module...${NC}"

mkdir -p langfuse_fix
cat > langfuse_fix/langfuse_integration.py << 'EOF'
"""
Langfuse integration for Cloudable.AI
This module provides observability and LLM monitoring capabilities for the platform.
"""

import os
import json
import logging
import uuid
import base64
from typing import Dict, Any, List, Optional, Union
from datetime import datetime

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# URL for Langfuse API
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

class LangfuseClient:
    def __init__(self, public_key, secret_key, host):
        """Initialize Langfuse client"""
        self.public_key = public_key
        self.secret_key = secret_key
        self.host = host
        self.auth_header = f"Basic {base64.b64encode(f'{public_key}:{secret_key}'.encode()).decode()}"
        
        # Store traces to flush later
        self.traces = []
        self.spans = []
        self.generations = []
        self.events = []
        
        # Test connection
        try:
            self._test_connection()
            self.connection_ok = True
            logger.info("Langfuse connection successful")
        except Exception as e:
            self.connection_ok = False
            logger.error(f"Langfuse connection failed: {e}")
    
    def _test_connection(self):
        """Test the connection to Langfuse"""
        import requests
        response = requests.get(
            f"{self.host}/api/public/traces?limit=1",
            headers={"Authorization": self.auth_header}
        )
        if response.status_code != 200:
            logger.error(f"Langfuse test connection failed: {response.status_code} {response.text}")
            raise Exception(f"Langfuse connection test failed: {response.status_code}")
    
    def _make_request(self, endpoint, data):
        """Make a request to the Langfuse API"""
        import requests
        try:
            response = requests.post(
                f"{self.host}/api/public/{endpoint}",
                headers={"Authorization": self.auth_header, "Content-Type": "application/json"},
                json=data
            )
            if response.status_code != 200:
                logger.error(f"Langfuse API error: {response.status_code} {response.text}")
                return None
            return response.json()
        except Exception as e:
            logger.error(f"Langfuse API request failed: {e}")
            return None
    
    def create_trace(self, name, **kwargs):
        """Create a new trace"""
        trace_id = str(uuid.uuid4())
        trace = {
            "id": trace_id,
            "name": name,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            **kwargs
        }
        self.traces.append(trace)
        return trace_id
    
    def create_span(self, trace_id, name, **kwargs):
        """Create a new span in a trace"""
        span_id = str(uuid.uuid4())
        span = {
            "id": span_id,
            "traceId": trace_id,
            "name": name,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            **kwargs
        }
        self.spans.append(span)
        return span_id
    
    def create_generation(self, trace_id, name, **kwargs):
        """Create a new generation in a trace"""
        gen_id = str(uuid.uuid4())
        generation = {
            "id": gen_id,
            "traceId": trace_id,
            "name": name,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            **kwargs
        }
        self.generations.append(generation)
        return gen_id
    
    def flush(self):
        """Flush all pending operations to Langfuse"""
        if not self.connection_ok:
            logger.warning("Skipping Langfuse flush - connection test failed")
            return
            
        try:
            # Flush traces
            if self.traces:
                logger.info(f"Flushing {len(self.traces)} traces to Langfuse")
                for trace in self.traces:
                    self._make_request("traces", trace)
                self.traces = []
                
            # Flush spans
            if self.spans:
                logger.info(f"Flushing {len(self.spans)} spans to Langfuse")
                for span in self.spans:
                    self._make_request("spans", span)
                self.spans = []
                
            # Flush generations
            if self.generations:
                logger.info(f"Flushing {len(self.generations)} generations to Langfuse")
                for generation in self.generations:
                    self._make_request("generations", generation)
                self.generations = []
                
            logger.info("Flush to Langfuse completed")
        except Exception as e:
            logger.error(f"Error flushing to Langfuse: {e}")

# Initialize client if API keys are available
if LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY:
    try:
        import requests
        _client = LangfuseClient(LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY, LANGFUSE_HOST)
        LANGFUSE_ENABLED = True
        logger.info("Langfuse client initialized")
    except ImportError:
        logger.error("Failed to import requests module - Langfuse integration disabled")
        LANGFUSE_ENABLED = False
        _client = None
    except Exception as e:
        logger.error(f"Error initializing Langfuse client: {e}")
        LANGFUSE_ENABLED = False
        _client = None
else:
    logger.warning("Langfuse API keys not configured - Langfuse integration disabled")
    LANGFUSE_ENABLED = False
    _client = None

def create_trace(name: str, 
                 tenant_id: str, 
                 user_id: Optional[str] = None, 
                 metadata: Optional[Dict[str, Any]] = None) -> str:
    """Create a new trace for an LLM request"""
    if not LANGFUSE_ENABLED or not _client:
        return str(uuid.uuid4())
    
    try:
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        if user_id:
            metadata["user_id"] = user_id
        
        trace_id = _client.create_trace(
            name=name,
            user_id=user_id or "anonymous",
            metadata=metadata,
            project_id=LANGFUSE_PROJECT_ID
        )
        logger.info(f"Created Langfuse trace: {trace_id}")
        return trace_id
    except Exception as e:
        logger.error(f"Error creating Langfuse trace: {e}")
        return str(uuid.uuid4())

def trace_kb_query(trace_id: str, 
                   query: str, 
                   results: List[Dict], 
                   tenant_id: str,
                   execution_time_ms: int,
                   metadata: Optional[Dict[str, Any]] = None) -> None:
    """Trace a KB query operation"""
    if not LANGFUSE_ENABLED or not _client:
        return
    
    try:
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        metadata["result_count"] = len(results)
        metadata["execution_time_ms"] = execution_time_ms
        
        _client.create_span(
            trace_id=trace_id,
            name="kb_query",
            input={"query": query},
            output={"results": results},
            metadata=metadata
        )
        
        logger.info(f"Traced KB query in trace: {trace_id}")
    except Exception as e:
        logger.error(f"Error tracing KB query: {e}")

def trace_chat(trace_id: str,
               message: str,
               response: str, 
               source_documents: List[Dict],
               tenant_id: str,
               use_kb: bool,
               execution_time_ms: int,
               token_count: int = 0,
               metadata: Optional[Dict[str, Any]] = None) -> None:
    """Trace a chat interaction"""
    if not LANGFUSE_ENABLED or not _client:
        return
    
    try:
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        metadata["use_kb"] = use_kb
        metadata["source_count"] = len(source_documents)
        metadata["execution_time_ms"] = execution_time_ms
        metadata["token_count"] = token_count
        
        _client.create_generation(
            trace_id=trace_id,
            name="chat_response",
            model="bedrock.claude-3-sonnet",  # Assuming Claude 3 Sonnet
            prompt=message,
            completion=response,
            metadata=metadata
        )
        
        logger.info(f"Traced chat interaction in trace: {trace_id}")
    except Exception as e:
        logger.error(f"Error tracing chat: {e}")

def trace_bedrock_call(trace_id: str,
                       prompt: str,
                       response: str,
                       model: str,
                       purpose: str,
                       execution_time_ms: int,
                       metadata: Optional[Dict[str, Any]] = None) -> None:
    """Trace a call to AWS Bedrock"""
    if not LANGFUSE_ENABLED or not _client:
        return
    
    try:
        metadata = metadata or {}
        metadata["purpose"] = purpose
        metadata["execution_time_ms"] = execution_time_ms
        
        _client.create_generation(
            trace_id=trace_id,
            name=f"bedrock_{purpose}",
            model=model,
            prompt=prompt,
            completion=response,
            metadata=metadata
        )
        
        logger.info(f"Traced Bedrock call in trace: {trace_id}")
    except Exception as e:
        logger.error(f"Error tracing Bedrock call: {e}")

def trace_customer_status(trace_id: str,
                          tenant_id: str,
                          customer_id: Optional[str],
                          response: Dict[str, Any],
                          execution_time_ms: int,
                          metadata: Optional[Dict[str, Any]] = None) -> None:
    """Trace a customer status query"""
    if not LANGFUSE_ENABLED or not _client:
        return
    
    try:
        metadata = metadata or {}
        metadata["tenant_id"] = tenant_id
        metadata["customer_id"] = customer_id
        metadata["execution_time_ms"] = execution_time_ms
        
        _client.create_span(
            trace_id=trace_id,
            name="customer_status_query",
            input={"customer_id": customer_id},
            output=response,
            metadata=metadata
        )
        
        logger.info(f"Traced customer status query in trace: {trace_id}")
    except Exception as e:
        logger.error(f"Error tracing customer status query: {e}")

def flush_observations():
    """Flush all observations to Langfuse"""
    if not LANGFUSE_ENABLED or not _client:
        return
    
    try:
        _client.flush()
        logger.info("Flushed observations to Langfuse")
    except Exception as e:
        logger.error(f"Error flushing observations to Langfuse: {e}")
EOF

echo -e "${GREEN}Created updated Langfuse integration module${NC}"

# Install required packages
echo -e "\n${YELLOW}Installing required Python packages...${NC}"
pip install requests

# Update Lambda function with new module
echo -e "\n${YELLOW}Deploying updated Langfuse module to Lambda function...${NC}"

# Create a deployment package
cd langfuse_fix
zip -r langfuse_update.zip langfuse_integration.py
cd ..

# Upload the package to Lambda
aws lambda update-function-code \
    --function-name kb-manager-dev-core \
    --zip-file fileb://langfuse_fix/langfuse_update.zip

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to update Lambda function code${NC}"
    exit 1
else
    echo -e "${GREEN}Lambda function code updated successfully${NC}"
fi

# Update Lambda environment variables with updated Langfuse configuration
echo -e "\n${YELLOW}Configuring Langfuse parameters in Lambda...${NC}"

# Get the current environment variables
ENV_VARS=$(aws lambda get-function-configuration \
    --function-name kb-manager-dev-core \
    --query "Environment.Variables" \
    --output json)

# Update the environment variables with EU region and project ID
UPDATED_ENV=$(cat << EOF
{
    "LANGFUSE_HOST": "https://eu.cloud.langfuse.com",
    "RDS_DATABASE": "$RDS_DATABASE",
    "RDS_SECRET_ARN": "$RDS_SECRET_ARN",
    "CUSTOMER_STATUS_ENABLED": "true",
    "LANGFUSE_PUBLIC_KEY": "pk-lf-dfa751eb-07c4-4f93-8edf-222e93e95466",
    "LANGFUSE_SECRET_KEY": "sk-lf-35fe11d6-e8ad-4371-be13-b83a1dfec6bd",
    "RDS_CLUSTER_ARN": "$RDS_CLUSTER_ARN",
    "LANGFUSE_PROJECT_ID": "cmhz8tqhk00duad07xptpuo06",
    "LANGFUSE_ORG_ID": "cmhz8tcqz00dpad07ee341p57"
}
EOF
)

aws lambda update-function-configuration \
    --function-name kb-manager-dev-core \
    --environment "Variables=$UPDATED_ENV"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to update Lambda environment variables${NC}"
    exit 1
else
    echo -e "${GREEN}Lambda environment variables updated successfully${NC}"
fi

echo -e "\n${BLUE}=========================================================="
echo "  LANGFUSE INTEGRATION FIX COMPLETED"
echo -e "==========================================================${NC}"

# Clean up
rm -rf langfuse_fix

echo -e "\nNext steps:"
echo -e "1. Test the customer status API"
echo -e "2. Run comprehensive tests to verify all functionality"
echo -e "3. Check Langfuse dashboard for traces"
