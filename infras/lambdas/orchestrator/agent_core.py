"""Agent Core module for orchestrating interactions with Bedrock agents."""
import os
import json
import logging
import time
import uuid
import boto3
import html

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
bedrock_client = boto3.client('bedrock-agent', region_name=os.environ.get('REGION', 'us-east-1'))
bedrock_runtime = boto3.client('bedrock-runtime', region_name=os.environ.get('REGION', 'us-east-1'))

class AgentCore:
    """AgentCore handles agent interactions with telemetry and error handling."""
    
    def __init__(self, tenant_id):
        """Initialize the AgentCore with tenant-specific configuration."""
        self.tenant_id = tenant_id
        # Get agent alias ARN for this tenant - with appropriate fallbacks
        try:
            self.alias_arn = os.environ.get(
                f'AGENT_ALIAS_{tenant_id.upper()}', 
                os.environ.get(
                    f'/cloudable/{os.environ.get("ENV", "dev")}/agent/{tenant_id}/alias_arn', 
                    None
                )
            )
            if not self.alias_arn:
                logger.warning(f"No agent alias configured for tenant: {tenant_id}")
        except Exception as e:
            logger.error(f"Error getting agent alias for tenant {tenant_id}: {str(e)}")
            self.alias_arn = None

        # Get knowledge base ID for tenant
        try:
            self.kb_id = os.environ.get(f'KB_ID_{tenant_id.upper()}', None)
            if not self.kb_id:
                logger.warning(f"No knowledge base configured for tenant: {tenant_id}")
        except Exception as e:
            logger.error(f"Error getting knowledge base for tenant {tenant_id}: {str(e)}")
            self.kb_id = None

    def invoke_agent(self, customer_id, message, session_id=None, trace_id=None):
        """Invoke the Bedrock agent with full telemetry."""
        # Generate session ID and trace ID if not provided
        if not session_id:
            session_id = f"s-{uuid.uuid4().hex}"
        if not trace_id:
            trace_id = f"t-{uuid.uuid4().hex}"
            
        try:
            # Log the start of agent invocation
            logger.info(f"Invoking agent with sessionState: tenant={self.tenant_id}, customer={customer_id}, trace={trace_id}")
            
            # If no agent alias is configured, handle it gracefully
            if not self.alias_arn:
                return {
                    "status": "error",
                    "error": "Agent not configured for this tenant",
                    "statusCode": 404,
                    "session_id": session_id,
                    "trace_id": trace_id
                }
                
            # Invoke the Bedrock agent with session state
            start_time = time.time()
            response = bedrock_runtime.invoke_agent(
                agentAliasId=self.alias_arn,
                sessionId=session_id,
                inputText=message,
                endSession=False
            )
            
            # Process agent response
            duration = time.time() - start_time
            completion = response.get('completion', '')
            
            logger.info(f"Agent response received: tenant={self.tenant_id}, customer={customer_id}, "
                        f"trace={trace_id}, duration={duration:.2f}s, chars={len(completion)}")
            
            # Return successful result with session and trace info
            return {
                "status": "success",
                "answer": completion,
                "session_id": session_id,
                "trace_id": trace_id,
                "duration": duration
            }
            
        except Exception as e:
            logger.error(f"Error invoking agent: {str(e)}")
            return {
                "status": "error",
                "error": f"Failed to invoke agent: {str(e)}",
                "statusCode": 500,
                "session_id": session_id,
                "trace_id": trace_id
            }
    
    def query_knowledge_base(self, query, customer_id=None, max_results=5):
        """Query the knowledge base for information."""
        try:
            # Validate and sanitize query
            if not query or len(query.strip()) < 3:
                return {
                    "status": "error",
                    "error": "Query must be at least 3 characters", 
                    "statusCode": 400
                }
            if len(query) > 1000:
                return {
                    "status": "error", 
                    "error": "Query too long (max 1000 characters)", 
                    "statusCode": 400
                }
                
            sanitized_query = html.escape(query.strip())
            
            # Get knowledge base ID
            kb_id = self.kb_id
            
            if not kb_id:
                return {
                    "status": "error",
                    "answer": "I don't know. No knowledge base is configured for your organization.",
                    "statusCode": 404
                }
                
            # Query the knowledge base
            response = bedrock_runtime.retrieve(
                knowledgeBaseId=kb_id,
                retrievalQuery={
                    'text': sanitized_query
                },
                retrievalConfiguration={
                    'vectorSearchConfiguration': {
                        'numberOfResults': max_results,
                        'overrideSearchType': 'HYBRID'
                    }
                }
            )
            
            # Process results
            results = response.get('retrievalResults', [])
            
            if not results:
                return {
                    "status": "success",
                    "answer": "I don't know. I couldn't find any relevant information in the knowledge base."
                }
                
            # Extract relevant content (lower threshold to improve recall)
            relevant_content = []
            for result in results:
                content = result.get('content', {}).get('text', '')
                score = result.get('score', 0)
                
                if score >= 0.2:  # Include moderate-confidence results
                    relevant_content.append(content)
                    
            if not relevant_content and results:
                # Fallback to top result snippet if available
                top = results[0].get('content', {}).get('text', '')
                if top:
                    relevant_content.append(top)
                    
            if not relevant_content:
                return {
                    "status": "success", 
                    "answer": "I don't know. The information I found doesn't seem relevant to your question."
                }
                
            # Format the response with context
            context = "\n\n".join(relevant_content[:3])  # Use top 3 results
            
            # Generate answer using the configured model
            model_arn = os.environ.get('CLAUDE_MODEL_ARN', 'anthropic.claude-3-sonnet-20240229-v1:0')
            
            answer_prompt = f"""Based on the following information from the knowledge base, please answer the user's question. If the information doesn't contain a clear answer, respond with "I don't know."

Context from knowledge base:
{context}

User question: {sanitized_query}

Please provide a helpful and accurate answer based only on the provided context. If you cannot answer based on the context, say "I don't know.":"""
            
            # Use Claude to generate a natural response
            claude_response = bedrock_runtime.invoke_model(
                modelId=model_arn,
                body=json.dumps({
                    "anthropic_version": "bedrock-2023-05-31",
                    "max_tokens": 500,
                    "messages": [
                        {
                            "role": "user",
                            "content": answer_prompt
                        }
                    ]
                })
            )
            
            claude_result = json.loads(claude_response['body'].read())
            answer = claude_result['content'][0]['text']
            
            logger.info(f"Knowledge base query successful for tenant {self.tenant_id}")
            
            return {
                "status": "success",
                "answer": answer,
                "sources_count": len(results),
                "confidence_scores": [r.get('score', 0) for r in results[:3]]
            }
                
        except Exception as e:
            logger.error(f"Error querying knowledge base: {str(e)}")
            return {
                "status": "error",
                "error": f"Failed to query knowledge base: {str(e)}",
                "statusCode": 500
            }

    def analyze_response(self, trace_id, response):
        """Analyze the agent response for insights."""
        # Simple response analytics
        metrics = {
            "response_length": len(response) if response else 0,
            "has_answer": bool(response and len(response) > 10),
            "timestamp": time.time()
        }
        
        return {"metrics": metrics}

# Global cache for agent cores by tenant
_agent_cores = {}

def get_agent_core(tenant_id):
    """Get or create an AgentCore instance for the tenant."""
    if tenant_id not in _agent_cores:
        _agent_cores[tenant_id] = AgentCore(tenant_id)
    return _agent_cores[tenant_id]