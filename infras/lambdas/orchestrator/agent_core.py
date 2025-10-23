"""
Agent Core - Central reasoning and decision-making module for Cloudable.AI

This module implements the core agent functionality, including:
1. Reasoning and decision-making logic
2. Context management
3. Operation routing
4. Knowledge integration
5. Langfuse tracing and observability

The Agent Core is responsible for orchestrating the interactions between
different components of the Cloudable.AI system, providing a cohesive
and intelligent experience.
"""

import os
import json
import logging
import boto3
import sys
import time
import uuid
from datetime import datetime

# Add parent directory to path for importing telemetry_helper and langfuse_client
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from langfuse_client import LangfuseTracer, langfuse_trace
    LANGFUSE_AVAILABLE = True
except ImportError:
    LANGFUSE_AVAILABLE = False
    # Stub decorator if langfuse_client is not available
    def langfuse_trace(tracer, operation_name):
        def decorator(func):
            return func
        return decorator

# Configure logger
logger = logging.getLogger('agent_core')
logger.setLevel(logging.INFO)

# Initialize AWS clients
bedrock_agent = boto3.client('bedrock-agent-runtime', region_name=os.environ.get('REGION', 'us-east-1'))
bedrock = boto3.client('bedrock-runtime', region_name=os.environ.get('REGION', 'us-east-1'))
ssm = boto3.client('ssm')

class AgentCore:
    """Core agent class implementing advanced reasoning and telemetry"""
    
    def __init__(self, tenant_id):
        """Initialize the Agent Core
        
        Args:
            tenant_id (str): Tenant identifier
        """
        self.tenant_id = tenant_id
        self.tracer = None
        
        if LANGFUSE_AVAILABLE:
            self.tracer = LangfuseTracer(tenant_id=tenant_id)
            logger.info(f"Initialized Agent Core for tenant {tenant_id} with Langfuse tracing")
        else:
            logger.info(f"Initialized Agent Core for tenant {tenant_id} without Langfuse")
    
    def get_agent_alias_id(self):
        """Get agent alias ID for tenant from SSM
        
        Returns:
            tuple: (agent_id, agent_alias_id) or (None, None) if not found
        """
        try:
            env = os.environ.get('ENV', 'dev')
            param_name = f"/cloudable/{env}/agent/{self.tenant_id}/alias_arn"
            
            response = ssm.get_parameter(Name=param_name)
            alias_arn = response['Parameter']['Value']
            
            # Parse agent_id and alias_id from ARN
            # Format: arn:aws:bedrock:REGION:ACCOUNT:agent-alias/AGENT_ID/ALIAS_ID
            resource = alias_arn.split(":", 5)[5]
            _, agent_id, alias_id = resource.split("/")
            
            return agent_id, alias_id
            
        except Exception as e:
            logger.error(f"Failed to get agent alias ID: {str(e)}")
            return None, None
    
    @langfuse_trace(tracer=None, operation_name="invoke_agent")  # tracer will be set in the method
    def invoke_agent(self, customer_id, message, session_id=None, trace_id=None):
        """Invoke Bedrock Agent with telemetry and tracing
        
        Args:
            customer_id (str): Customer identifier
            message (str): User message
            session_id (str): Optional session identifier
            trace_id (str): Optional trace identifier
            
        Returns:
            dict: Agent response
        """
        if self.tracer is None and LANGFUSE_AVAILABLE:
            self.tracer = LangfuseTracer(tenant_id=self.tenant_id)
            
        # Fix the decorator (it needs a reference to self.tracer)
        if hasattr(self.invoke_agent, '__wrapped__'):
            self.invoke_agent.__wrapped__.__defaults__ = (self.tracer, "invoke_agent")
            
        start_time = time.time()
        agent_id, alias_id = self.get_agent_alias_id()
        
        if not agent_id or not alias_id:
            return {
                "error": "Agent configuration not found",
                "status": "error",
                "statusCode": 500
            }
        
        # Generate session_id if not provided
        if not session_id:
            session_id = f"{self.tenant_id}:{customer_id}:{uuid.uuid4()}"
            
        # Create trace if not exists
        if not trace_id and self.tracer:
            trace = self.tracer.create_trace(
                customer_id=customer_id,
                session_id=session_id,
                name="agent_conversation"
            )
            trace_id = trace.id
            
        # Session state with context
        ctx = {
            "tenant_id": self.tenant_id,
            "customer_id": customer_id,
            "trace_id": trace_id
        }
            
        try:
            # Log the prompt if tracing enabled
            if self.tracer:
                self.tracer.log_llm_interaction(
                    trace_id=trace_id,
                    model="anthropic.claude-3-sonnet",
                    prompt=message,
                    completion="",  # Will be filled later
                    prompt_variables={
                        "tenant_id": self.tenant_id,
                        "customer_id": customer_id,
                        "session_id": session_id
                    }
                )
            
            # Invoke the agent
            logger.info(f"Invoking agent {agent_id}/{alias_id} for tenant {self.tenant_id}")
            resp = bedrock_agent.invoke_agent(
                agentId=agent_id,
                agentAliasId=alias_id,
                sessionId=session_id,
                inputText=message,
                sessionState={"promptSessionAttributes": ctx},
                enableTrace=True
            )
            
            # Process the response
            answer = ""
            traces = []
            
            for ev in resp.get("completion", []):
                if "trace" in ev:
                    # Log orchestration traces for debugging
                    try:
                        logger.debug(f"Trace: {json.dumps(ev['trace'])}")
                        traces.append(ev["trace"])
                    except Exception:
                        pass
                        
                if "chunk" in ev:
                    answer += ev["chunk"]["bytes"].decode()
            
            # Record the completion if tracing enabled
            if self.tracer:
                self.tracer.log_llm_interaction(
                    trace_id=trace_id,
                    model="anthropic.claude-3-sonnet",
                    prompt=message,
                    completion=answer,
                    token_usage={
                        "prompt_tokens": len(message) // 4,  # Approximate
                        "completion_tokens": len(answer) // 4  # Approximate
                    },
                    latency_ms=(time.time() - start_time) * 1000
                )
                
                # Score the response quality (simple heuristic)
                if len(answer) > 10 and not "error" in answer.lower():
                    self.tracer.score(
                        trace_id=trace_id,
                        name="response_quality",
                        value=0.9,
                        comment="Successful agent response"
                    )
                
                # Flush pending operations
                self.tracer.flush()
            
            return {
                "answer": answer,
                "trace": traces,
                "session_id": session_id,
                "trace_id": trace_id,
                "status": "success",
                "statusCode": 200
            }
            
        except Exception as e:
            error_msg = str(e)
            logger.error(f"Error invoking agent: {error_msg}")
            
            # Record error if tracing enabled
            if self.tracer:
                self.tracer.log_event(
                    trace_id=trace_id,
                    name="agent_error",
                    event_data={
                        "error": error_msg,
                        "tenant_id": self.tenant_id,
                        "customer_id": customer_id
                    }
                )
                
                self.tracer.score(
                    trace_id=trace_id,
                    name="response_quality",
                    value=0.0,
                    comment=f"Error: {error_msg}"
                )
                
                self.tracer.flush()
            
            return {
                "error": error_msg,
                "status": "error",
                "statusCode": 500,
                "session_id": session_id,
                "trace_id": trace_id,
                "agentId": agent_id,
                "agentAliasId": alias_id
            }
    
    def analyze_response(self, trace_id, response):
        """Analyze agent response for quality and insights
        
        Args:
            trace_id (str): Trace identifier
            response (str): Agent response to analyze
            
        Returns:
            dict: Analysis results with metrics
        """
        analysis = {
            "timestamp": datetime.now().isoformat(),
            "metrics": {}
        }
        
        # Simple analysis metrics
        if response:
            analysis["metrics"]["response_length"] = len(response)
            analysis["metrics"]["has_entities"] = any(entity in response.lower() for entity in 
                                                    ["customer", "journey", "assessment", "policy"])
            
        # Log analysis if tracing enabled
        if self.tracer:
            self.tracer.log_event(
                trace_id=trace_id,
                name="response_analysis",
                event_data=analysis
            )
        
        return analysis

# Initialize agent core module
def get_agent_core(tenant_id):
    """Get or create an AgentCore instance for tenant
    
    Args:
        tenant_id (str): Tenant identifier
        
    Returns:
        AgentCore: Agent core instance for tenant
    """
    return AgentCore(tenant_id=tenant_id)
