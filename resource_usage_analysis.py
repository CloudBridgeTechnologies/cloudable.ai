#!/usr/bin/env python3
"""
Cloudable.AI Resource Usage Analysis for 10 Customers
Calculates average resource configuration and usage estimates
"""

import json

def analyze_resources():
    """Analyze resource usage for 10 customers"""
    
    # Base infrastructure (shared across all tenants)
    base_resources = {
        "vpc": {"count": 1, "cost_monthly": 0},
        "subnets": {"count": 4, "cost_monthly": 0},
        "internet_gateway": {"count": 1, "cost_monthly": 0},
        "nat_gateway": {"count": 1, "cost_monthly": 45.00},  # $0.045/hour
        "elastic_ip": {"count": 1, "cost_monthly": 3.65},   # $0.005/hour
        "route_tables": {"count": 2, "cost_monthly": 0},
        "security_groups": {"count": 2, "cost_monthly": 0}
    }
    
    # Aurora PostgreSQL Serverless v2
    aurora_config = {
        "cluster": 1,
        "instances": 1,
        "engine": "aurora-postgresql",
        "version": "15.12",
        "min_acu": 0.5,
        "max_acu": 1.0,
        "storage_encrypted": True,
        "backup_retention": 7,
        "data_api_enabled": True
    }
    
    # Estimate Aurora costs for 10 customers
    # Assuming average 0.75 ACU usage with moderate workload
    avg_acu_usage = 0.75
    acu_cost_per_hour = 0.12  # $0.12 per ACU-hour in us-east-1
    aurora_monthly_cost = avg_acu_usage * acu_cost_per_hour * 24 * 30
    
    # Storage estimate: 10GB per customer average
    storage_gb_per_customer = 10
    total_storage_gb = storage_gb_per_customer * 10
    storage_cost_monthly = total_storage_gb * 0.10  # $0.10 per GB/month
    
    # Lambda configuration
    lambda_config = {
        "function_name": "kb-manager-dev-core",
        "runtime": "python3.9",
        "memory_mb": 256,
        "timeout_seconds": 30,
        "concurrent_executions": 10  # Estimate for 10 customers
    }
    
    # Lambda usage estimates for 10 customers
    # Assuming 1000 requests per customer per month
    requests_per_customer = 1000
    total_requests = requests_per_customer * 10
    avg_duration_ms = 2000  # 2 seconds average
    
    # Lambda costs
    request_cost = (total_requests / 1000000) * 0.20  # $0.20 per 1M requests
    compute_cost = (total_requests * avg_duration_ms / 1000) * (256/1024) * 0.0000166667  # GB-seconds
    lambda_monthly_cost = request_cost + compute_cost
    
    # API Gateway HTTP API
    api_gateway_config = {
        "type": "HTTP API",
        "cors_enabled": True,
        "routes": 6,
        "stages": 1,
        "logging_enabled": True
    }
    
    # API Gateway costs (HTTP API is cheaper than REST API)
    api_requests_monthly = total_requests
    api_gateway_cost = (api_requests_monthly / 1000000) * 1.00  # $1.00 per million requests
    
    # CloudWatch Logs
    # Estimate 100MB logs per customer per month
    logs_gb_per_customer = 0.1
    total_logs_gb = logs_gb_per_customer * 10
    cloudwatch_logs_cost = total_logs_gb * 0.50  # $0.50 per GB ingested
    
    # Secrets Manager
    secrets_count = 1  # One secret for RDS
    secrets_cost = secrets_count * 0.40  # $0.40 per secret per month
    
    # S3 Storage (estimated per customer)
    s3_gb_per_customer = 5  # 5GB documents per customer
    total_s3_gb = s3_gb_per_customer * 10
    s3_storage_cost = total_s3_gb * 0.023  # $0.023 per GB/month standard storage
    
    # S3 API requests (uploads, downloads)
    s3_put_requests = 100 * 10  # 100 uploads per customer
    s3_get_requests = 500 * 10  # 500 downloads per customer
    s3_requests_cost = (s3_put_requests / 1000) * 0.005 + (s3_get_requests / 1000) * 0.0004
    
    # AWS Bedrock usage (external service)
    # Estimate 10,000 tokens per customer per month for embeddings + LLM
    tokens_per_customer = 10000
    total_tokens = tokens_per_customer * 10
    bedrock_cost_estimate = (total_tokens / 1000) * 0.0008  # Rough estimate for Claude/embeddings
    
    # Calculate totals
    infrastructure_cost = sum(resource["cost_monthly"] for resource in base_resources.values())
    database_cost = aurora_monthly_cost + storage_cost_monthly
    compute_cost_total = lambda_monthly_cost + api_gateway_cost
    storage_cost_total = s3_storage_cost + s3_requests_cost
    monitoring_cost = cloudwatch_logs_cost + secrets_cost
    
    total_monthly_cost = (infrastructure_cost + database_cost + compute_cost_total + 
                         storage_cost_total + monitoring_cost + bedrock_cost_estimate)
    
    cost_per_customer = total_monthly_cost / 10
    
    # Resource summary
    resource_summary = {
        "infrastructure": {
            "vpc_subnets": 4,
            "nat_gateway": 1,
            "security_groups": 2,
            "monthly_cost": infrastructure_cost
        },
        "database": {
            "aurora_cluster": aurora_config,
            "estimated_storage_gb": total_storage_gb,
            "monthly_cost": database_cost
        },
        "compute": {
            "lambda_function": lambda_config,
            "estimated_monthly_invocations": total_requests,
            "api_gateway_requests": api_requests_monthly,
            "monthly_cost": compute_cost_total
        },
        "storage": {
            "s3_total_gb": total_s3_gb,
            "monthly_requests": s3_put_requests + s3_get_requests,
            "monthly_cost": storage_cost_total
        },
        "monitoring": {
            "cloudwatch_logs_gb": total_logs_gb,
            "secrets_manager_secrets": secrets_count,
            "monthly_cost": monitoring_cost
        },
        "bedrock_ai": {
            "estimated_tokens_monthly": total_tokens,
            "monthly_cost": bedrock_cost_estimate
        },
        "totals": {
            "total_monthly_cost": round(total_monthly_cost, 2),
            "cost_per_customer": round(cost_per_customer, 2),
            "customers": 10
        }
    }
    
    return resource_summary

def print_analysis(summary):
    """Print formatted analysis"""
    print("=" * 60)
    print("CLOUDABLE.AI RESOURCE USAGE ANALYSIS - 10 CUSTOMERS")
    print("=" * 60)
    
    print(f"\n📊 COST BREAKDOWN:")
    print(f"Infrastructure (VPC, NAT, etc.): ${summary['infrastructure']['monthly_cost']:.2f}")
    print(f"Database (Aurora + Storage):     ${summary['database']['monthly_cost']:.2f}")
    print(f"Compute (Lambda + API Gateway):  ${summary['compute']['monthly_cost']:.2f}")
    print(f"Storage (S3):                    ${summary['storage']['monthly_cost']:.2f}")
    print(f"Monitoring & Secrets:            ${summary['monitoring']['monthly_cost']:.2f}")
    print(f"AI/ML (Bedrock estimate):        ${summary['bedrock_ai']['monthly_cost']:.2f}")
    print(f"{'-' * 40}")
    print(f"TOTAL MONTHLY COST:              ${summary['totals']['total_monthly_cost']:.2f}")
    print(f"COST PER CUSTOMER:               ${summary['totals']['cost_per_customer']:.2f}")
    
    print(f"\n🔧 RESOURCE CONFIGURATION:")
    print(f"Aurora ACU Range: {summary['database']['aurora_cluster']['min_acu']}-{summary['database']['aurora_cluster']['max_acu']}")
    print(f"Lambda Memory: {summary['compute']['lambda_function']['memory_mb']}MB")
    print(f"Lambda Timeout: {summary['compute']['lambda_function']['timeout_seconds']}s")
    print(f"Estimated Storage: {summary['database']['estimated_storage_gb']}GB (DB) + {summary['storage']['s3_total_gb']}GB (S3)")
    
    print(f"\n📈 USAGE ESTIMATES:")
    print(f"Monthly API Requests: {summary['compute']['estimated_monthly_invocations']:,}")
    print(f"Monthly S3 Requests: {summary['storage']['monthly_requests']:,}")
    print(f"Monthly AI Tokens: {summary['bedrock_ai']['estimated_tokens_monthly']:,}")
    print(f"CloudWatch Logs: {summary['monitoring']['cloudwatch_logs_gb']}GB/month")

if __name__ == "__main__":
    analysis = analyze_resources()
    print_analysis(analysis)
    
    # Save to JSON
    with open('/Users/adrian/Projects/Cloudable.AI/resource_analysis_10_customers.json', 'w') as f:
        json.dump(analysis, f, indent=2)
    
    print(f"\n💾 Analysis saved to: resource_analysis_10_customers.json")