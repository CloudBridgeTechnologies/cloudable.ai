"""
Agent Core Telemetry Helper

This module provides telemetry and tracing capabilities for the Cloudable.AI Agent Core.
It captures detailed metrics about agent operations, performance, and errors.
"""

import json
import time
import uuid
import logging
import os
import boto3
from datetime import datetime
from functools import wraps

# Configure logger
logger = logging.getLogger('agent_telemetry')
logger.setLevel(logging.INFO)

# Initialize AWS clients
cloudwatch = boto3.client('cloudwatch')
logs = boto3.client('logs')

# Constants
TELEMETRY_LOG_GROUP = os.environ.get('TELEMETRY_LOG_GROUP', '/aws/bedrock/agent-core-telemetry-dev')
TRACING_LOG_GROUP = os.environ.get('TRACING_LOG_GROUP', '/aws/bedrock/agent-core-tracing-dev')
METRICS_NAMESPACE = os.environ.get('METRICS_NAMESPACE', 'Cloudable/AgentCore')

class AgentTelemetry:
    """Class for handling Agent Core telemetry and tracing"""
    
    @staticmethod
    def create_log_groups():
        """Ensure log groups exist"""
        try:
            logs.create_log_group(logGroupName=TELEMETRY_LOG_GROUP)
        except logs.exceptions.ResourceAlreadyExistsException:
            pass
            
        try:
            logs.create_log_group(logGroupName=TRACING_LOG_GROUP)
        except logs.exceptions.ResourceAlreadyExistsException:
            pass
    
    @staticmethod
    def log_operation(tenant_id, operation_type, status_code, response_time, details=None):
        """Log operation details to CloudWatch Logs"""
        try:
            log_stream_name = f"{tenant_id}-{datetime.now().strftime('%Y-%m-%d')}"
            
            try:
                logs.create_log_stream(
                    logGroupName=TELEMETRY_LOG_GROUP,
                    logStreamName=log_stream_name
                )
            except logs.exceptions.ResourceAlreadyExistsException:
                pass
            
            log_event = {
                'timestamp': int(time.time() * 1000),
                'message': json.dumps({
                    'tenant_id': tenant_id,
                    'operation_id': str(uuid.uuid4()),
                    'operation_type': operation_type,
                    'status_code': status_code,
                    'response_time': response_time,
                    'timestamp': datetime.now().isoformat(),
                    'details': details or {}
                })
            }
            
            logs.put_log_events(
                logGroupName=TELEMETRY_LOG_GROUP,
                logStreamName=log_stream_name,
                logEvents=[log_event]
            )
            
        except Exception as e:
            logger.error(f"Failed to log operation: {str(e)}")
    
    @staticmethod
    def log_trace(tenant_id, trace_id, trace_type, content):
        """Log detailed trace information for debugging"""
        try:
            log_stream_name = f"{tenant_id}-traces-{datetime.now().strftime('%Y-%m-%d')}"
            
            try:
                logs.create_log_stream(
                    logGroupName=TRACING_LOG_GROUP,
                    logStreamName=log_stream_name
                )
            except logs.exceptions.ResourceAlreadyExistsException:
                pass
            
            log_event = {
                'timestamp': int(time.time() * 1000),
                'message': json.dumps({
                    'tenant_id': tenant_id,
                    'trace_id': trace_id,
                    'trace_type': trace_type,
                    'timestamp': datetime.now().isoformat(),
                    'content': content
                })
            }
            
            logs.put_log_events(
                logGroupName=TRACING_LOG_GROUP,
                logStreamName=log_stream_name,
                logEvents=[log_event]
            )
            
        except Exception as e:
            logger.error(f"Failed to log trace: {str(e)}")
    
    @staticmethod
    def put_metric(metric_name, value, unit, dimensions):
        """Put a custom metric to CloudWatch"""
        try:
            cloudwatch.put_metric_data(
                Namespace=METRICS_NAMESPACE,
                MetricData=[{
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': unit,
                    'Dimensions': [{'Name': k, 'Value': v} for k, v in dimensions.items()]
                }]
            )
        except Exception as e:
            logger.error(f"Failed to put metric: {str(e)}")

def telemetry_wrapper(operation_type):
    """Decorator to add telemetry to functions"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            tenant_id = kwargs.get('tenant_id', 'unknown')
            trace_id = str(uuid.uuid4())
            
            # Log the beginning of the operation
            AgentTelemetry.log_trace(
                tenant_id=tenant_id,
                trace_id=trace_id,
                trace_type='operation_start',
                content={
                    'operation_type': operation_type,
                    'args': [str(arg) for arg in args],
                    'kwargs': {k: str(v) for k, v in kwargs.items()}
                }
            )
            
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                status_code = result.get('statusCode', 200) if isinstance(result, dict) else 200
                
                # Calculate response time in milliseconds
                response_time = (time.time() - start_time) * 1000
                
                # Log successful operation
                AgentTelemetry.log_operation(
                    tenant_id=tenant_id,
                    operation_type=operation_type,
                    status_code=status_code,
                    response_time=response_time,
                    details={'result_type': type(result).__name__}
                )
                
                # Add custom metrics
                AgentTelemetry.put_metric(
                    metric_name='OperationDuration',
                    value=response_time,
                    unit='Milliseconds',
                    dimensions={
                        'TenantId': tenant_id,
                        'OperationType': operation_type
                    }
                )
                
                if status_code >= 200 and status_code < 300:
                    AgentTelemetry.put_metric(
                        metric_name='SuccessfulOperations',
                        value=1,
                        unit='Count',
                        dimensions={
                            'TenantId': tenant_id,
                            'OperationType': operation_type
                        }
                    )
                else:
                    AgentTelemetry.put_metric(
                        metric_name='FailedOperations',
                        value=1,
                        unit='Count',
                        dimensions={
                            'TenantId': tenant_id,
                            'OperationType': operation_type
                        }
                    )
                
                # Log the end of the operation
                AgentTelemetry.log_trace(
                    tenant_id=tenant_id,
                    trace_id=trace_id,
                    trace_type='operation_end',
                    content={
                        'operation_type': operation_type,
                        'status_code': status_code,
                        'response_time': response_time
                    }
                )
                
                return result
                
            except Exception as e:
                # Calculate response time in milliseconds
                response_time = (time.time() - start_time) * 1000
                
                # Log failed operation
                AgentTelemetry.log_operation(
                    tenant_id=tenant_id,
                    operation_type=operation_type,
                    status_code=500,
                    response_time=response_time,
                    details={'error': str(e)}
                )
                
                # Log the error trace
                AgentTelemetry.log_trace(
                    tenant_id=tenant_id,
                    trace_id=trace_id,
                    trace_type='operation_error',
                    content={
                        'operation_type': operation_type,
                        'error': str(e),
                        'response_time': response_time
                    }
                )
                
                # Add failure metric
                AgentTelemetry.put_metric(
                    metric_name='FailedOperations',
                    value=1,
                    unit='Count',
                    dimensions={
                        'TenantId': tenant_id,
                        'OperationType': operation_type,
                        'ErrorType': type(e).__name__
                    }
                )
                
                raise
                
        return wrapper
    return decorator

# Ensure log groups exist on module import
AgentTelemetry.create_log_groups()
Agent Core Telemetry Helper

This module provides telemetry and tracing capabilities for the Cloudable.AI Agent Core.
It captures detailed metrics about agent operations, performance, and errors.
"""

import json
import time
import uuid
import logging
import os
import boto3
from datetime import datetime
from functools import wraps

# Configure logger
logger = logging.getLogger('agent_telemetry')
logger.setLevel(logging.INFO)

# Initialize AWS clients
cloudwatch = boto3.client('cloudwatch')
logs = boto3.client('logs')

# Constants
TELEMETRY_LOG_GROUP = os.environ.get('TELEMETRY_LOG_GROUP', '/aws/bedrock/agent-core-telemetry-dev')
TRACING_LOG_GROUP = os.environ.get('TRACING_LOG_GROUP', '/aws/bedrock/agent-core-tracing-dev')
METRICS_NAMESPACE = os.environ.get('METRICS_NAMESPACE', 'Cloudable/AgentCore')

class AgentTelemetry:
    """Class for handling Agent Core telemetry and tracing"""
    
    @staticmethod
    def create_log_groups():
        """Ensure log groups exist"""
        try:
            logs.create_log_group(logGroupName=TELEMETRY_LOG_GROUP)
        except logs.exceptions.ResourceAlreadyExistsException:
            pass
            
        try:
            logs.create_log_group(logGroupName=TRACING_LOG_GROUP)
        except logs.exceptions.ResourceAlreadyExistsException:
            pass
    
    @staticmethod
    def log_operation(tenant_id, operation_type, status_code, response_time, details=None):
        """Log operation details to CloudWatch Logs"""
        try:
            log_stream_name = f"{tenant_id}-{datetime.now().strftime('%Y-%m-%d')}"
            
            try:
                logs.create_log_stream(
                    logGroupName=TELEMETRY_LOG_GROUP,
                    logStreamName=log_stream_name
                )
            except logs.exceptions.ResourceAlreadyExistsException:
                pass
            
            log_event = {
                'timestamp': int(time.time() * 1000),
                'message': json.dumps({
                    'tenant_id': tenant_id,
                    'operation_id': str(uuid.uuid4()),
                    'operation_type': operation_type,
                    'status_code': status_code,
                    'response_time': response_time,
                    'timestamp': datetime.now().isoformat(),
                    'details': details or {}
                })
            }
            
            logs.put_log_events(
                logGroupName=TELEMETRY_LOG_GROUP,
                logStreamName=log_stream_name,
                logEvents=[log_event]
            )
            
        except Exception as e:
            logger.error(f"Failed to log operation: {str(e)}")
    
    @staticmethod
    def log_trace(tenant_id, trace_id, trace_type, content):
        """Log detailed trace information for debugging"""
        try:
            log_stream_name = f"{tenant_id}-traces-{datetime.now().strftime('%Y-%m-%d')}"
            
            try:
                logs.create_log_stream(
                    logGroupName=TRACING_LOG_GROUP,
                    logStreamName=log_stream_name
                )
            except logs.exceptions.ResourceAlreadyExistsException:
                pass
            
            log_event = {
                'timestamp': int(time.time() * 1000),
                'message': json.dumps({
                    'tenant_id': tenant_id,
                    'trace_id': trace_id,
                    'trace_type': trace_type,
                    'timestamp': datetime.now().isoformat(),
                    'content': content
                })
            }
            
            logs.put_log_events(
                logGroupName=TRACING_LOG_GROUP,
                logStreamName=log_stream_name,
                logEvents=[log_event]
            )
            
        except Exception as e:
            logger.error(f"Failed to log trace: {str(e)}")
    
    @staticmethod
    def put_metric(metric_name, value, unit, dimensions):
        """Put a custom metric to CloudWatch"""
        try:
            cloudwatch.put_metric_data(
                Namespace=METRICS_NAMESPACE,
                MetricData=[{
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': unit,
                    'Dimensions': [{'Name': k, 'Value': v} for k, v in dimensions.items()]
                }]
            )
        except Exception as e:
            logger.error(f"Failed to put metric: {str(e)}")

def telemetry_wrapper(operation_type):
    """Decorator to add telemetry to functions"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            tenant_id = kwargs.get('tenant_id', 'unknown')
            trace_id = str(uuid.uuid4())
            
            # Log the beginning of the operation
            AgentTelemetry.log_trace(
                tenant_id=tenant_id,
                trace_id=trace_id,
                trace_type='operation_start',
                content={
                    'operation_type': operation_type,
                    'args': [str(arg) for arg in args],
                    'kwargs': {k: str(v) for k, v in kwargs.items()}
                }
            )
            
            start_time = time.time()
            try:
                result = func(*args, **kwargs)
                status_code = result.get('statusCode', 200) if isinstance(result, dict) else 200
                
                # Calculate response time in milliseconds
                response_time = (time.time() - start_time) * 1000
                
                # Log successful operation
                AgentTelemetry.log_operation(
                    tenant_id=tenant_id,
                    operation_type=operation_type,
                    status_code=status_code,
                    response_time=response_time,
                    details={'result_type': type(result).__name__}
                )
                
                # Add custom metrics
                AgentTelemetry.put_metric(
                    metric_name='OperationDuration',
                    value=response_time,
                    unit='Milliseconds',
                    dimensions={
                        'TenantId': tenant_id,
                        'OperationType': operation_type
                    }
                )
                
                if status_code >= 200 and status_code < 300:
                    AgentTelemetry.put_metric(
                        metric_name='SuccessfulOperations',
                        value=1,
                        unit='Count',
                        dimensions={
                            'TenantId': tenant_id,
                            'OperationType': operation_type
                        }
                    )
                else:
                    AgentTelemetry.put_metric(
                        metric_name='FailedOperations',
                        value=1,
                        unit='Count',
                        dimensions={
                            'TenantId': tenant_id,
                            'OperationType': operation_type
                        }
                    )
                
                # Log the end of the operation
                AgentTelemetry.log_trace(
                    tenant_id=tenant_id,
                    trace_id=trace_id,
                    trace_type='operation_end',
                    content={
                        'operation_type': operation_type,
                        'status_code': status_code,
                        'response_time': response_time
                    }
                )
                
                return result
                
            except Exception as e:
                # Calculate response time in milliseconds
                response_time = (time.time() - start_time) * 1000
                
                # Log failed operation
                AgentTelemetry.log_operation(
                    tenant_id=tenant_id,
                    operation_type=operation_type,
                    status_code=500,
                    response_time=response_time,
                    details={'error': str(e)}
                )
                
                # Log the error trace
                AgentTelemetry.log_trace(
                    tenant_id=tenant_id,
                    trace_id=trace_id,
                    trace_type='operation_error',
                    content={
                        'operation_type': operation_type,
                        'error': str(e),
                        'response_time': response_time
                    }
                )
                
                # Add failure metric
                AgentTelemetry.put_metric(
                    metric_name='FailedOperations',
                    value=1,
                    unit='Count',
                    dimensions={
                        'TenantId': tenant_id,
                        'OperationType': operation_type,
                        'ErrorType': type(e).__name__
                    }
                )
                
                raise
                
        return wrapper
    return decorator

# Ensure log groups exist on module import
AgentTelemetry.create_log_groups()












