#!/usr/bin/env python3
"""
Bedrock integration utilities for customer status summarization.
"""

import boto3
import json
import logging
import time
from typing import Dict, List, Any, Optional

# Import Langfuse integration
try:
    import langfuse_integration
    LANGFUSE_ENABLED = True
    logging.info("Langfuse integration loaded for Bedrock")
except ImportError:
    LANGFUSE_ENABLED = False
    logging.warning("Langfuse integration not found for Bedrock")

logger = logging.getLogger()
logger.setLevel(logging.INFO)

class BedrockSummarizer:
    """
    Utility class for summarizing customer status using Amazon Bedrock.
    """
    
    def __init__(self, region_name: str = 'us-east-1'):
        """Initialize Bedrock client with the specified region"""
        self.client = boto3.client('bedrock-runtime', region_name=region_name)
        self.model_id = "anthropic.claude-3-sonnet-20240229-v1:0"  # Use Claude 3 Sonnet
    
    def summarize_customer_status(self, 
                                  customer_data: Dict[str, Any], 
                                  milestones: List[Dict[str, Any]],
                                  trace_id: Optional[str] = None,
                                  tenant_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Generate a concise summary of customer implementation status.
        
        Args:
            customer_data: Dictionary containing customer information and status
            milestones: List of milestone dictionaries for the customer
            trace_id: Optional Langfuse trace ID for observability
            tenant_id: Optional tenant ID for the request
            
        Returns:
            Dictionary containing the generated summary and structured status data
        """
        start_time = time.time()
        try:
            # Format the customer data into a structured prompt
            prompt = self._format_status_prompt(customer_data, milestones)
            
            # Call Bedrock to generate the summary
            response = self._invoke_bedrock(prompt)
            
            # Parse the response
            summary = self._parse_summary_response(response)
            
            # Track with Langfuse if enabled
            execution_time_ms = int((time.time() - start_time) * 1000)
            if LANGFUSE_ENABLED and trace_id and tenant_id:
                try:
                    langfuse_integration.trace_bedrock_call(
                        trace_id=trace_id,
                        prompt=prompt,
                        response=summary,
                        model=self.model_id,
                        purpose="customer_status_summary",
                        execution_time_ms=execution_time_ms,
                        metadata={
                            "tenant_id": tenant_id,
                            "customer_name": customer_data.get('customer_name', 'Unknown'),
                            "customer_stage": customer_data.get('stage_name', 'Unknown'),
                            "summary_length": len(summary)
                        }
                    )
                except Exception as e:
                    logger.error(f"Error tracking Bedrock call with Langfuse: {str(e)}")
            
            return {
                "summary": summary,
                "raw_status_data": customer_data,
                "raw_milestones": milestones
            }
        
        except Exception as e:
            logger.error(f"Error summarizing customer status: {str(e)}")
            
            # Fallback response if Bedrock fails
            return {
                "summary": f"Customer {customer_data.get('customer_name', 'Unknown')} is currently in the {customer_data.get('stage_name', 'Unknown')} stage.",
                "raw_status_data": customer_data,
                "raw_milestones": milestones
            }
    
    def _format_status_prompt(self, 
                             customer_data: Dict[str, Any], 
                             milestones: List[Dict[str, Any]]) -> str:
        """
        Format customer data into a structured prompt for Bedrock.
        """
        # Create a markdown formatted representation of the data
        prompt = f"""<human>
Based on the following customer implementation status data, provide a concise executive summary of where the customer is in their implementation journey. Include key milestones, timelines, health status, and any risks or issues that should be highlighted.

## Customer Information
- Name: {customer_data.get('customer_name', 'Unknown')}
- Current Stage: {customer_data.get('stage_name', 'Unknown')} (Stage {customer_data.get('stage_order', '?')} of 8)
- Implementation Start Date: {customer_data.get('implementation_start_date', 'Unknown')}
- Projected Completion Date: {customer_data.get('projected_completion_date', 'Unknown')}
- Progress: {customer_data.get('progress_percentage', 0)}%
- Health Status: {customer_data.get('health_status', 'Unknown')}

## Milestones
"""
        
        # Add milestone information
        for idx, milestone in enumerate(milestones):
            prompt += f"""
{idx + 1}. **{milestone.get('milestone_name', 'Unknown Milestone')}**
   - Status: {milestone.get('status', 'Unknown')}
   - Planned Date: {milestone.get('planned_date', 'Unknown')}
   - Description: {milestone.get('milestone_description', 'No description available')}
"""
        
        prompt += """
## Requirements for Summary:
1. Start with a one-sentence overview of current implementation status
2. Highlight the current stage and progress
3. Mention key completed and upcoming milestones
4. Note any risks or concerns based on health status
5. Keep the summary under 150 words

The summary should be concise, factual, and highlight the most important aspects of the implementation status.
</human>"""
        
        return prompt

    def _invoke_bedrock(self, prompt: str) -> Dict[str, Any]:
        """
        Invoke Bedrock to generate text using the Claude model.
        """
        try:
            # Prepare the request payload
            request_body = {
                "anthropic_version": "bedrock-2023-05-31",
                "max_tokens": 1000,
                "temperature": 0.5,
                "messages": [
                    {"role": "user", "content": prompt}
                ]
            }
            
            # Invoke the model
            response = self.client.invoke_model(
                modelId=self.model_id,
                body=json.dumps(request_body)
            )
            
            # Parse the response
            response_body = json.loads(response.get('body').read())
            
            return response_body
            
        except Exception as e:
            logger.error(f"Error invoking Bedrock: {str(e)}")
            raise
    
    def _parse_summary_response(self, response: Dict[str, Any]) -> str:
        """
        Parse the Bedrock response to extract the generated summary.
        """
        try:
            content = response.get('content', [])
            if content:
                # Extract the text from the first content block
                return content[0].get('text', '')
            return "No summary generated."
        except Exception as e:
            logger.error(f"Error parsing Bedrock response: {str(e)}")
            return "Error generating summary."
