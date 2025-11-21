#!/usr/bin/env python3
"""
Tenant Usage Metrics Module for Cloudable.AI

This module provides functions for:
1. Tracking tenant API usage
2. Monitoring resource consumption
3. Collecting usage statistics for billing
4. Generating usage reports

In a production environment, metrics would be stored in:
- CloudWatch Metrics for real-time monitoring
- DynamoDB for short-term usage tracking
- S3 for long-term analytics data
"""

import boto3
import json
import logging
import os
import time
import uuid
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List, Union

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize clients (commented out for local testing)
# cloudwatch_client = boto3.client('cloudwatch')
# dynamodb_client = boto3.client('dynamodb')

# In-memory cache for metrics (for demo/testing)
# In production, this would be replaced with persistent storage
_metrics_cache = {}

class MetricType:
    """Types of metrics to track"""
    API_CALL = "api_call"
    DOC_UPLOAD = "document_upload"
    KB_SYNC = "kb_sync"
    KB_QUERY = "kb_query"
    CHAT_SESSION = "chat_session"
    TOKEN_USAGE = "token_usage"
    EMBEDDING_OPERATION = "embedding_operation"
    STORAGE_USAGE = "storage_usage"

def track_api_call(
    tenant_id: str,
    user_id: str,
    api_name: str,
    status_code: int,
    execution_time_ms: int = 0,
    request_size_bytes: int = 0,
    response_size_bytes: int = 0,
    additional_data: Optional[Dict[str, Any]] = None
) -> str:
    """
    Track an API call for tenant usage metrics
    
    Args:
        tenant_id: Tenant identifier
        user_id: User identifier
        api_name: Name of the API endpoint called
        status_code: HTTP status code of the response
        execution_time_ms: Time taken to execute the request in milliseconds
        request_size_bytes: Size of the request payload in bytes
        response_size_bytes: Size of the response payload in bytes
        additional_data: Any additional data to store with the metric
        
    Returns:
        str: Metric ID
    """
    # Generate a unique ID for this metric
    metric_id = str(uuid.uuid4())
    
    # Capture the current timestamp in UTC
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # Create the metric object
    metric = {
        "id": metric_id,
        "tenant_id": tenant_id,
        "user_id": user_id,
        "metric_type": MetricType.API_CALL,
        "api_name": api_name,
        "status_code": status_code,
        "execution_time_ms": execution_time_ms,
        "request_size_bytes": request_size_bytes,
        "response_size_bytes": response_size_bytes,
        "timestamp": timestamp
    }
    
    # Add any additional data
    if additional_data:
        for key, value in additional_data.items():
            if key not in metric:  # Don't override existing fields
                metric[key] = value
    
    # Store the metric (in-memory for demo)
    _store_metric(metric)
    
    # In production, we would also send to CloudWatch Metrics
    # _send_to_cloudwatch(metric)
    
    logger.info(f"Tracked API call: {api_name} for tenant: {tenant_id}, user: {user_id}")
    return metric_id

def track_document_upload(
    tenant_id: str,
    user_id: str,
    document_key: str,
    file_size_bytes: int,
    file_type: str,
    status_code: int = 200,
    additional_data: Optional[Dict[str, Any]] = None
) -> str:
    """
    Track a document upload for tenant usage metrics
    
    Args:
        tenant_id: Tenant identifier
        user_id: User identifier
        document_key: S3 key of the uploaded document
        file_size_bytes: Size of the uploaded file in bytes
        file_type: MIME type or extension of the file
        status_code: HTTP status code of the upload operation
        additional_data: Any additional data to store with the metric
        
    Returns:
        str: Metric ID
    """
    # Generate a unique ID for this metric
    metric_id = str(uuid.uuid4())
    
    # Capture the current timestamp in UTC
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # Create the metric object
    metric = {
        "id": metric_id,
        "tenant_id": tenant_id,
        "user_id": user_id,
        "metric_type": MetricType.DOC_UPLOAD,
        "document_key": document_key,
        "file_size_bytes": file_size_bytes,
        "file_type": file_type,
        "status_code": status_code,
        "timestamp": timestamp
    }
    
    # Add any additional data
    if additional_data:
        for key, value in additional_data.items():
            if key not in metric:  # Don't override existing fields
                metric[key] = value
    
    # Store the metric (in-memory for demo)
    _store_metric(metric)
    
    logger.info(f"Tracked document upload: {document_key} for tenant: {tenant_id}, size: {file_size_bytes} bytes")
    return metric_id

def track_kb_sync(
    tenant_id: str,
    user_id: str,
    document_key: str,
    execution_time_ms: int = 0,
    additional_data: Optional[Dict[str, Any]] = None
) -> str:
    """
    Track a knowledge base sync operation for tenant usage metrics
    
    Args:
        tenant_id: Tenant identifier
        user_id: User identifier
        document_key: S3 key of the document being synced
        execution_time_ms: Time taken to execute the sync in milliseconds
        additional_data: Any additional data to store with the metric
        
    Returns:
        str: Metric ID
    """
    # Generate a unique ID for this metric
    metric_id = str(uuid.uuid4())
    
    # Capture the current timestamp in UTC
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # Create the metric object
    metric = {
        "id": metric_id,
        "tenant_id": tenant_id,
        "user_id": user_id,
        "metric_type": MetricType.KB_SYNC,
        "document_key": document_key,
        "execution_time_ms": execution_time_ms,
        "timestamp": timestamp
    }
    
    # Add any additional data
    if additional_data:
        for key, value in additional_data.items():
            if key not in metric:  # Don't override existing fields
                metric[key] = value
    
    # Store the metric (in-memory for demo)
    _store_metric(metric)
    
    logger.info(f"Tracked KB sync for tenant: {tenant_id}, document: {document_key}")
    return metric_id

def track_kb_query(
    tenant_id: str,
    user_id: str,
    query: str,
    query_embedding_size: int = 0,
    result_count: int = 0,
    execution_time_ms: int = 0,
    additional_data: Optional[Dict[str, Any]] = None
) -> str:
    """
    Track a knowledge base query for tenant usage metrics
    
    Args:
        tenant_id: Tenant identifier
        user_id: User identifier
        query: The user's query string
        query_embedding_size: Size of the query embedding vector
        result_count: Number of results returned
        execution_time_ms: Time taken to execute the query in milliseconds
        additional_data: Any additional data to store with the metric
        
    Returns:
        str: Metric ID
    """
    # Generate a unique ID for this metric
    metric_id = str(uuid.uuid4())
    
    # Capture the current timestamp in UTC
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # Create the metric object
    metric = {
        "id": metric_id,
        "tenant_id": tenant_id,
        "user_id": user_id,
        "metric_type": MetricType.KB_QUERY,
        "query_length": len(query),
        "query_embedding_size": query_embedding_size,
        "result_count": result_count,
        "execution_time_ms": execution_time_ms,
        "timestamp": timestamp
    }
    
    # Add any additional data
    if additional_data:
        for key, value in additional_data.items():
            if key not in metric:  # Don't override existing fields
                metric[key] = value
    
    # Store the metric (in-memory for demo)
    _store_metric(metric)
    
    logger.info(f"Tracked KB query for tenant: {tenant_id}, results: {result_count}")
    return metric_id

def track_chat_session(
    tenant_id: str,
    user_id: str,
    message_count: int,
    total_tokens: int,
    use_kb: bool = True,
    session_duration_seconds: int = 0,
    additional_data: Optional[Dict[str, Any]] = None
) -> str:
    """
    Track a chat session for tenant usage metrics
    
    Args:
        tenant_id: Tenant identifier
        user_id: User identifier
        message_count: Number of messages in the chat session
        total_tokens: Total tokens used in the session
        use_kb: Whether the knowledge base was used
        session_duration_seconds: Duration of the session in seconds
        additional_data: Any additional data to store with the metric
        
    Returns:
        str: Metric ID
    """
    # Generate a unique ID for this metric
    metric_id = str(uuid.uuid4())
    
    # Capture the current timestamp in UTC
    timestamp = datetime.now(timezone.utc).isoformat()
    
    # Create the metric object
    metric = {
        "id": metric_id,
        "tenant_id": tenant_id,
        "user_id": user_id,
        "metric_type": MetricType.CHAT_SESSION,
        "message_count": message_count,
        "total_tokens": total_tokens,
        "use_kb": use_kb,
        "session_duration_seconds": session_duration_seconds,
        "timestamp": timestamp
    }
    
    # Add any additional data
    if additional_data:
        for key, value in additional_data.items():
            if key not in metric:  # Don't override existing fields
                metric[key] = value
    
    # Store the metric (in-memory for demo)
    _store_metric(metric)
    
    logger.info(f"Tracked chat session for tenant: {tenant_id}, messages: {message_count}, tokens: {total_tokens}")
    return metric_id

def get_tenant_metrics(
    tenant_id: str,
    metric_type: Optional[str] = None,
    start_time: Optional[str] = None,
    end_time: Optional[str] = None,
    limit: int = 100
) -> List[Dict[str, Any]]:
    """
    Get usage metrics for a specific tenant
    
    Args:
        tenant_id: Tenant identifier
        metric_type: Optional filter by metric type
        start_time: Optional start time for filtering (ISO format)
        end_time: Optional end time for filtering (ISO format)
        limit: Maximum number of metrics to return
        
    Returns:
        List of metric objects
    """
    # In production, this would query DynamoDB or another datastore
    
    # Get all metrics for this tenant
    tenant_metrics = []
    if tenant_id in _metrics_cache:
        tenant_metrics = list(_metrics_cache[tenant_id].values())
    
    # Apply filters
    filtered_metrics = tenant_metrics
    
    if metric_type:
        filtered_metrics = [m for m in filtered_metrics if m.get("metric_type") == metric_type]
    
    if start_time:
        start_dt = datetime.fromisoformat(start_time)
        filtered_metrics = [m for m in filtered_metrics if datetime.fromisoformat(m.get("timestamp", "")) >= start_dt]
    
    if end_time:
        end_dt = datetime.fromisoformat(end_time)
        filtered_metrics = [m for m in filtered_metrics if datetime.fromisoformat(m.get("timestamp", "")) <= end_dt]
    
    # Sort by timestamp (most recent first) and apply limit
    sorted_metrics = sorted(filtered_metrics, key=lambda m: m.get("timestamp", ""), reverse=True)
    return sorted_metrics[:limit]

def get_tenant_usage_summary(tenant_id: str) -> Dict[str, Any]:
    """
    Get a summary of usage metrics for a tenant
    
    Args:
        tenant_id: Tenant identifier
        
    Returns:
        Dictionary with usage summary
    """
    # Get all metrics for this tenant
    tenant_metrics = []
    if tenant_id in _metrics_cache:
        tenant_metrics = list(_metrics_cache[tenant_id].values())
    
    # Calculate summary statistics
    api_calls = len([m for m in tenant_metrics if m.get("metric_type") == MetricType.API_CALL])
    doc_uploads = len([m for m in tenant_metrics if m.get("metric_type") == MetricType.DOC_UPLOAD])
    kb_queries = len([m for m in tenant_metrics if m.get("metric_type") == MetricType.KB_QUERY])
    chat_sessions = len([m for m in tenant_metrics if m.get("metric_type") == MetricType.CHAT_SESSION])
    
    # Calculate total tokens (sum from chat sessions)
    total_tokens = sum(m.get("total_tokens", 0) for m in tenant_metrics if m.get("metric_type") == MetricType.CHAT_SESSION)
    
    # Calculate total storage (sum of file sizes from document uploads)
    total_storage_bytes = sum(m.get("file_size_bytes", 0) for m in tenant_metrics if m.get("metric_type") == MetricType.DOC_UPLOAD)
    
    # Calculate unique users
    unique_users = set(m.get("user_id") for m in tenant_metrics if "user_id" in m)
    
    # Calculate first and last activity timestamps
    timestamps = [datetime.fromisoformat(m.get("timestamp")) for m in tenant_metrics if "timestamp" in m]
    first_activity = min(timestamps).isoformat() if timestamps else None
    last_activity = max(timestamps).isoformat() if timestamps else None
    
    # Return the summary
    return {
        "tenant_id": tenant_id,
        "api_calls": api_calls,
        "document_uploads": doc_uploads,
        "kb_queries": kb_queries,
        "chat_sessions": chat_sessions,
        "total_tokens": total_tokens,
        "total_storage_bytes": total_storage_bytes,
        "unique_users": len(unique_users),
        "first_activity": first_activity,
        "last_activity": last_activity,
        "generated_at": datetime.now(timezone.utc).isoformat()
    }

def _store_metric(metric: Dict[str, Any]) -> None:
    """
    Store a metric in the in-memory cache
    
    In production, this would store in DynamoDB and send to CloudWatch
    """
    tenant_id = metric.get("tenant_id")
    metric_id = metric.get("id")
    
    if not tenant_id or not metric_id:
        logger.error(f"Invalid metric: missing tenant_id or id: {metric}")
        return
    
    # Initialize tenant dictionary if needed
    if tenant_id not in _metrics_cache:
        _metrics_cache[tenant_id] = {}
    
    # Store the metric
    _metrics_cache[tenant_id][metric_id] = metric

def _send_to_cloudwatch(metric: Dict[str, Any]) -> None:
    """
    Send a metric to CloudWatch
    
    This is a placeholder for the actual CloudWatch implementation
    """
    # This would be implemented in production
    pass
