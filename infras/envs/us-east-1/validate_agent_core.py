#!/usr/bin/env python3
"""
Agent Core Validation Script

This script validates the Agent Core implementation and configuration
to ensure it's properly set up and functioning correctly.

Usage:
    python validate_agent_core.py
"""

import os
import sys
import json
import boto3
import argparse
import time
from datetime import datetime

# Add parent directories to path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../lambdas')))

try:
    from orchestrator.agent_core import AgentCore
    AGENT_CORE_AVAILABLE = True
except ImportError:
    AGENT_CORE_AVAILABLE = False
    print("WARNING: AgentCore module not found, will perform basic validation only")

# Initialize AWS clients
ssm = boto3.client('ssm')
bedrock_agent = boto3.client('bedrock-agent-runtime')
cloudwatch = boto3.client('cloudwatch')

def validate_terraform_config():
    """Validate Terraform configuration files for Agent Core"""
    print("\n=== Validating Terraform Configuration ===")
    
    files_to_check = [
        "bedrock-agent.tf",
        "agent-core-telemetry.tf", 
        "agent-langfuse.tf"
    ]
    
    all_valid = True
    for filename in files_to_check:
        if os.path.exists(filename):
            print(f"✅ {filename} exists")
            # Check file size as basic validation
            size = os.path.getsize(filename)
            if size > 100:
                print(f"  - File size: {size} bytes (valid)")
            else:
                print(f"  - File size: {size} bytes (too small, might be incomplete)")
                all_valid = False
        else:
            print(f"❌ {filename} not found")
            all_valid = False
    
    return all_valid

def validate_agent_configuration(tenant_id):
    """Validate Bedrock Agent configuration for tenant"""
    print(f"\n=== Validating Agent Configuration for tenant {tenant_id} ===")
    
    try:
        # Get agent and alias IDs from SSM
        env = os.environ.get('ENV', 'dev')
        param_name = f"/cloudable/{env}/agent/{tenant_id}/alias_arn"
        
        try:
            response = ssm.get_parameter(Name=param_name)
            alias_arn = response['Parameter']['Value']
            print(f"✅ Agent alias ARN found in SSM: {alias_arn}")
            
            # Parse agent_id and alias_id from ARN
            resource = alias_arn.split(":", 5)[5]
            _, agent_id, alias_id = resource.split("/")
            print(f"  - Agent ID: {agent_id}")
            print(f"  - Alias ID: {alias_id}")
            
            # Check if the agent exists
            try:
                agent_response = bedrock_agent.get_agent(
                    agentId=agent_id
                )
                print(f"✅ Agent found: {agent_response['agent']['agentName']}")
                
                # Check agent status
                status = agent_response['agent']['agentStatus']
                print(f"  - Agent status: {status}")
                if status != "PREPARED":
                    print(f"  - WARNING: Agent status is {status}, not PREPARED")
                
                return True
                
            except Exception as e:
                print(f"❌ Failed to get agent: {str(e)}")
                return False
                
        except Exception as e:
            print(f"❌ Agent alias ARN not found in SSM: {str(e)}")
            return False
            
    except Exception as e:
        print(f"❌ Error validating agent configuration: {str(e)}")
        return False

def validate_telemetry_resources():
    """Validate CloudWatch resources for telemetry"""
    print("\n=== Validating Telemetry Resources ===")
    
    env = os.environ.get('ENV', 'dev')
    resources_to_check = [
        f"/aws/bedrock/agent-core-telemetry-{env}",
        f"/aws/bedrock/agent-core-tracing-{env}"
    ]
    
    all_valid = True
    for resource in resources_to_check:
        try:
            response = cloudwatch.describe_log_groups(
                logGroupNamePrefix=resource
            )
            
            if response['logGroups']:
                print(f"✅ Log group found: {resource}")
            else:
                print(f"❌ Log group not found: {resource}")
                all_valid = False
                
        except Exception as e:
            print(f"❌ Error checking log group {resource}: {str(e)}")
            all_valid = False
    
    # Check for dashboard
    try:
        dashboard_name = f"agent-core-dashboard-{env}"
        response = cloudwatch.get_dashboard(
            DashboardName=dashboard_name
        )
        print(f"✅ Dashboard found: {dashboard_name}")
    except Exception as e:
        print(f"❌ Dashboard not found: {str(e)}")
        all_valid = False
    
    return all_valid

def validate_agent_core(tenant_id):
    """Validate Agent Core functionality"""
    print("\n=== Validating Agent Core Functionality ===")
    
    if not AGENT_CORE_AVAILABLE:
        print("❌ AgentCore module not available, skipping functional validation")
        return False
    
    try:
        # Initialize Agent Core
        agent_core = AgentCore(tenant_id=tenant_id)
        print("✅ AgentCore initialized successfully")
        
        # Validate core methods exist
        required_methods = ['invoke_agent', 'analyze_response', 'get_agent_alias_id']
        for method in required_methods:
            if hasattr(agent_core, method) and callable(getattr(agent_core, method)):
                print(f"✅ Method available: {method}")
            else:
                print(f"❌ Method missing: {method}")
                return False
        
        return True
        
    except Exception as e:
        print(f"❌ Error initializing AgentCore: {str(e)}")
        return False

def validate_langfuse_configuration():
    """Validate Langfuse configuration"""
    print("\n=== Validating Langfuse Configuration ===")
    
    env = os.environ.get('ENV', 'dev')
    params_to_check = [
        f"/cloudable/{env}/langfuse/public-key",
        f"/cloudable/{env}/langfuse/secret-key",
        f"/cloudable/{env}/langfuse/host"
    ]
    
    all_valid = True
    for param in params_to_check:
        try:
            response = ssm.get_parameter(
                Name=param,
                WithDecryption=False  # Don't expose secret values
            )
            print(f"✅ SSM parameter found: {param}")
        except Exception as e:
            print(f"❌ SSM parameter not found: {param}")
            print(f"  - Error: {str(e)}")
            all_valid = False
    
    return all_valid

def main():
    """Main validation function"""
    parser = argparse.ArgumentParser(description="Validate Agent Core configuration")
    parser.add_argument("--tenant-id", default="t001", help="Tenant ID to validate (default: t001)")
    parser.add_argument("--env", default="dev", help="Environment (default: dev)")
    args = parser.parse_args()
    
    # Set environment variable for ENV
    os.environ['ENV'] = args.env
    
    print(f"Starting Agent Core validation for tenant {args.tenant_id} in {args.env} environment")
    print(f"Timestamp: {datetime.now().isoformat()}")
    
    # Run validation checks
    terraform_valid = validate_terraform_config()
    agent_valid = validate_agent_configuration(args.tenant_id)
    telemetry_valid = validate_telemetry_resources()
    core_valid = validate_agent_core(args.tenant_id)
    langfuse_valid = validate_langfuse_configuration()
    
    # Print summary
    print("\n=== Validation Summary ===")
    print(f"Terraform Configuration: {'✅ PASS' if terraform_valid else '❌ FAIL'}")
    print(f"Agent Configuration: {'✅ PASS' if agent_valid else '❌ FAIL'}")
    print(f"Telemetry Resources: {'✅ PASS' if telemetry_valid else '❌ FAIL'}")
    print(f"Agent Core Functionality: {'✅ PASS' if core_valid else '❌ FAIL'}")
    print(f"Langfuse Configuration: {'✅ PASS' if langfuse_valid else '❌ FAIL'}")
    
    overall_status = all([terraform_valid, agent_valid, telemetry_valid, core_valid, langfuse_valid])
    print(f"\nOverall Validation: {'✅ PASSED' if overall_status else '❌ FAILED'}")
    
    return 0 if overall_status else 1

if __name__ == "__main__":
    sys.exit(main())
