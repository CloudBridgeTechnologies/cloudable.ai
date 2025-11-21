#!/usr/bin/env python3
"""
Handler module for customer status API endpoints.
"""

import boto3
import json
import logging
import os
import time
from typing import Dict, List, Any, Optional
import uuid

# Import Langfuse integration
try:
    import langfuse_integration
    LANGFUSE_ENABLED = True
    logging.info("Langfuse integration loaded for customer status handler")
except ImportError:
    LANGFUSE_ENABLED = False
    logging.warning("Langfuse integration not found for customer status handler")

# Import Bedrock utilities for summarization
try:
    from bedrock_utils import BedrockSummarizer
    BEDROCK_ENABLED = True
except ImportError:
    BEDROCK_ENABLED = False
    print("Bedrock utilities not found, running without status summarization")

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rds_data_client = boto3.client('rds-data')

# Get environment variables
RDS_CLUSTER_ARN = os.environ.get('RDS_CLUSTER_ARN')
RDS_SECRET_ARN = os.environ.get('RDS_SECRET_ARN')
RDS_DATABASE = os.environ.get('RDS_DATABASE')

# Initialize Bedrock summarizer if available
bedrock_summarizer = BedrockSummarizer() if BEDROCK_ENABLED else None

def execute_statement(sql: str, parameters: List[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Execute an SQL statement using the RDS Data API
    """
    try:
        response = rds_data_client.execute_statement(
            resourceArn=RDS_CLUSTER_ARN,
            secretArn=RDS_SECRET_ARN,
            database=RDS_DATABASE,
            sql=sql,
            parameters=parameters or []
        )
        return response
    except Exception as e:
        logger.error(f"Error executing SQL: {e}")
        logger.error(f"SQL: {sql}")
        if parameters:
            logger.error(f"Parameters: {parameters}")
        raise

def get_customer_status(tenant_id: str, customer_id: Optional[str] = None) -> Dict[str, Any]:
    """
    Get customer status information for a specific tenant.
    
    Args:
        tenant_id: The tenant identifier
        customer_id: Optional customer ID to filter by
        
    Returns:
        Dictionary containing customer status information
    """
    try:
        # Ensure tenant isolation by validating tenant_id
        if not tenant_id or not isinstance(tenant_id, str):
            return {"error": "Invalid tenant ID"}
        
        # Sanitize tenant_id to prevent SQL injection
        tenant_id = tenant_id.lower().strip()
        allowed_tenants = ["acme", "globex", "initech", "umbrella"]
        
        if tenant_id not in allowed_tenants:
            return {"error": f"Unknown tenant: {tenant_id}"}
        
        # Build the SQL query
        view_name = f"customer_status.customer_status_view_{tenant_id}"
        
        if customer_id:
            # Query for a specific customer
            sql = f"""
                SELECT * FROM {view_name}
                WHERE customer_id = :customer_id
                ORDER BY stage_order;
            """
            parameters = [
                {"name": "customer_id", "value": {"stringValue": customer_id}}
            ]
        else:
            # Query for all customers in this tenant
            sql = f"""
                SELECT * FROM {view_name}
                ORDER BY stage_order, customer_name;
            """
            parameters = []
        
        # Execute the query
        response = execute_statement(sql, parameters)
        
        # Process the response
        customer_data = []
        
        if 'records' in response:
            column_metadata = response.get('columnMetadata', [])
            column_names = [col.get('name') for col in column_metadata]
            
            for record in response.get('records', []):
                customer = {}
                for i, field in enumerate(record):
                    # Get the column name
                    if i < len(column_names):
                        column_name = column_names[i]
                    else:
                        column_name = f"column_{i}"
                    
                    # Get the field value
                    field_value = None
                    if "stringValue" in field:
                        field_value = field["stringValue"]
                    elif "longValue" in field:
                        field_value = field["longValue"]
                    elif "doubleValue" in field:
                        field_value = field["doubleValue"]
                    elif "booleanValue" in field:
                        field_value = field["booleanValue"]
                    elif "isNull" in field and field["isNull"]:
                        field_value = None
                    
                    customer[column_name] = field_value
                
                customer_data.append(customer)
        
        # If a specific customer was requested, get their milestones
        if customer_id and customer_data:
            # Get milestones for this customer
            milestones_sql = f"""
                SELECT * FROM customer_status.customer_milestones_{tenant_id}
                WHERE customer_id = :customer_id
                ORDER BY planned_date;
            """
            milestones_parameters = [
                {"name": "customer_id", "value": {"stringValue": customer_id}}
            ]
            
            milestones_response = execute_statement(milestones_sql, milestones_parameters)
            
            # Process the milestones response
            milestones = []
            
            if 'records' in milestones_response:
                milestone_column_metadata = milestones_response.get('columnMetadata', [])
                milestone_column_names = [col.get('name') for col in milestone_column_metadata]
                
                for record in milestones_response.get('records', []):
                    milestone = {}
                    for i, field in enumerate(record):
                        # Get the column name
                        if i < len(milestone_column_names):
                            column_name = milestone_column_names[i]
                        else:
                            column_name = f"column_{i}"
                        
                        # Get the field value
                        field_value = None
                        if "stringValue" in field:
                            field_value = field["stringValue"]
                        elif "longValue" in field:
                            field_value = field["longValue"]
                        elif "doubleValue" in field:
                            field_value = field["doubleValue"]
                        elif "booleanValue" in field:
                            field_value = field["booleanValue"]
                        elif "isNull" in field and field["isNull"]:
                            field_value = None
                        
                        milestone[column_name] = field_value
                    
                    milestones.append(milestone)
            
            # If Bedrock summarization is enabled, generate a summary
            if BEDROCK_ENABLED and bedrock_summarizer and customer_data:
                try:
                    customer_summary = bedrock_summarizer.summarize_customer_status(
                        customer_data[0], 
                        milestones,
                        trace_id=None,  # Will be passed in real calls
                        tenant_id=tenant_id
                    )
                    
                    # Return the detailed customer data with summary
                    return {
                        "customer": customer_data[0],
                        "milestones": milestones,
                        "summary": customer_summary.get("summary", "No summary available")
                    }
                except Exception as e:
                    logger.error(f"Error generating customer summary: {str(e)}")
            
            # Return without summary if Bedrock is not available
            return {
                "customer": customer_data[0],
                "milestones": milestones
            }
        
        # Return all customers without details
        return {
            "customers": customer_data
        }
        
    except Exception as e:
        logger.error(f"Error getting customer status: {str(e)}")
        return {"error": f"Error retrieving customer status: {str(e)}"}

def handle_customer_status_request(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Handle API requests for customer status
    
    Args:
        event: API Gateway event
        context: Lambda context
        
    Returns:
        API Gateway response
    """
    start_time = time.time()
    trace_id = None
    
    try:
        # Extract request parameters
        body = {}
        if 'body' in event:
            if isinstance(event['body'], str):
                try:
                    body = json.loads(event['body'])
                except json.JSONDecodeError:
                    pass
            elif isinstance(event['body'], dict):
                body = event['body']
        
        # Get tenant and customer ID from request body
        tenant_id = body.get('tenant')
        customer_id = body.get('customer_id')  # Optional
        
        # Validate tenant (required)
        if not tenant_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({"error": "Missing required parameter: tenant"})
            }
            
        # Extract user ID from event
        user_id = None
        if 'headers' in event and event['headers'] and 'x-user-id' in event['headers']:
            user_id = event['headers']['x-user-id']
        
        # Create a trace in Langfuse if enabled
        if LANGFUSE_ENABLED:
            try:
                trace_id = langfuse_integration.create_trace(
                    name="customer_status_query",
                    tenant_id=tenant_id,
                    user_id=user_id,
                    metadata={
                        "customer_id": customer_id,
                        "request_type": "customer_status"
                    }
                )
            except Exception as e:
                logger.warning(f"Failed to create Langfuse trace: {str(e)}")
        
        # Get customer status
        status_data = get_customer_status(tenant_id, customer_id)
        
        # Check for errors
        if 'error' in status_data:
            status_code = 400 if "Unknown tenant" in status_data['error'] else 500
            
            # Track error in Langfuse if enabled
            if LANGFUSE_ENABLED and trace_id:
                try:
                    execution_time_ms = int((time.time() - start_time) * 1000)
                    langfuse_integration.trace_customer_status(
                        trace_id=trace_id,
                        tenant_id=tenant_id,
                        customer_id=customer_id,
                        response={"error": status_data['error']},
                        execution_time_ms=execution_time_ms,
                        metadata={
                            "status_code": status_code,
                            "error": True
                        }
                    )
                except Exception as e:
                    logger.warning(f"Failed to trace error in Langfuse: {str(e)}")
            
            return {
                'statusCode': status_code,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(status_data)
            }
        
        # Track with Langfuse if enabled
        execution_time_ms = int((time.time() - start_time) * 1000)
        if LANGFUSE_ENABLED and trace_id:
            try:
                langfuse_integration.trace_customer_status(
                    trace_id=trace_id,
                    tenant_id=tenant_id,
                    customer_id=customer_id,
                    response=status_data,
                    execution_time_ms=execution_time_ms,
                    metadata={
                        "has_summary": "summary" in status_data,
                        "has_milestones": "milestones" in status_data and len(status_data.get("milestones", [])) > 0
                    }
                )
                
                # Flush observations to Langfuse
                langfuse_integration.flush_observations()
            except Exception as e:
                logger.warning(f"Failed to trace in Langfuse: {str(e)}")
        
        # Track the API call if metrics are available
        try:
            from tenant_metrics import track_api_call
            
            # Track the API call
            track_api_call(
                tenant_id=tenant_id,
                user_id=user_id or "anonymous",
                api_name="customer_status",
                status_code=200,
                execution_time_ms=execution_time_ms,
                request_size_bytes=len(json.dumps(body)),
                response_size_bytes=len(json.dumps(status_data))
            )
        except Exception as e:
            logger.warning(f"Failed to track API call: {str(e)}")
        
        # Return successful response
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps(status_data)
        }
        
    except Exception as e:
        logger.error(f"Error handling customer status request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({"error": f"Internal server error: {str(e)}"})
        }
