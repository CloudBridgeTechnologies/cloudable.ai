#!/usr/bin/env python3
"""
Load testing script for Cloudable.AI APIs with Langfuse observability
"""

import argparse
import json
import os
import random
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from typing import Dict, Any, List, Tuple

try:
    import requests
    from tqdm import tqdm
except ImportError:
    print("Required packages not found. Installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "tqdm"])
    import requests
    from tqdm import tqdm

# Test data
TENANTS = ["acme", "globex", "initech", "umbrella"]

KB_QUERIES = [
    "What is our current implementation status?",
    "What are the key success metrics for our project?",
    "What are the next steps in our implementation plan?",
    "Tell me about our digital transformation goals",
    "Who are the key stakeholders for our project?",
    "What risks have been identified for our implementation?",
    "How are we measuring success in this project?",
    "What is the timeline for completing the implementation?",
    "What technical challenges have been encountered?",
    "How does this implementation align with our business strategy?"
]

CHAT_MESSAGES = [
    "How is our implementation progressing?",
    "What success metrics are we tracking and what's our progress on them?",
    "What are the key challenges we're facing in our implementation?",
    "Summarize our current status and next steps",
    "What stage are we in our implementation journey?",
    "What are the key risks we need to be aware of?",
    "Tell me about our key stakeholders and their roles",
    "When is our projected completion date?",
    "What resources are allocated to this project?",
    "How does this implementation compare to industry benchmarks?"
]

class LoadTester:
    """Load tester for Cloudable.AI APIs"""
    
    def __init__(self, api_endpoint: str, verbose: bool = False):
        """Initialize load tester"""
        self.api_endpoint = api_endpoint
        self.verbose = verbose
        
    def log(self, message: str):
        """Log message if verbose is enabled"""
        if self.verbose:
            print(f"[{datetime.now().strftime('%H:%M:%S')}] {message}")
    
    def get_random_user_id(self, tenant: str) -> str:
        """Get a random user ID for a tenant"""
        roles = ["admin", "contributor", "reader"]
        role = random.choice(roles)
        user_number = random.randint(1, 999)
        return f"user-{role}-{user_number:03d}"
    
    def test_kb_query(self, tenant: str, query: str) -> Tuple[bool, Dict[str, Any], float]:
        """
        Test KB query API
        
        Returns:
            (success, response_data, latency)
        """
        start_time = time.time()
        
        try:
            # Create payload
            payload = {
                "tenant": tenant,
                "query": query,
                "max_results": 3
            }
            
            # Generate a unique request ID
            request_id = str(uuid.uuid4())
            
            # Get random user ID
            user_id = self.get_random_user_id(tenant)
            
            # Call API
            response = requests.post(
                f"{self.api_endpoint}/api/kb/query",
                json=payload,
                headers={
                    "Content-Type": "application/json",
                    "x-tenant-id": tenant,
                    "x-user-id": user_id,
                    "x-request-id": request_id
                }
            )
            
            latency = time.time() - start_time
            
            # Check response
            if response.status_code == 200:
                try:
                    response_data = response.json()
                    self.log(f"KB query success: tenant={tenant}, query='{query}'")
                    return True, response_data, latency
                except json.JSONDecodeError:
                    self.log(f"KB query error: Invalid JSON response")
                    return False, {"error": "Invalid JSON response"}, latency
            else:
                self.log(f"KB query error: status_code={response.status_code}")
                return False, {"error": f"HTTP {response.status_code}"}, latency
                
        except Exception as e:
            latency = time.time() - start_time
            self.log(f"KB query exception: {str(e)}")
            return False, {"error": str(e)}, latency
    
    def test_chat(self, tenant: str, message: str) -> Tuple[bool, Dict[str, Any], float]:
        """
        Test chat API
        
        Returns:
            (success, response_data, latency)
        """
        start_time = time.time()
        
        try:
            # Create payload
            payload = {
                "tenant": tenant,
                "message": message,
                "use_kb": True
            }
            
            # Generate a unique request ID
            request_id = str(uuid.uuid4())
            
            # Get random user ID
            user_id = self.get_random_user_id(tenant)
            
            # Call API
            response = requests.post(
                f"{self.api_endpoint}/api/chat",
                json=payload,
                headers={
                    "Content-Type": "application/json",
                    "x-tenant-id": tenant,
                    "x-user-id": user_id,
                    "x-request-id": request_id
                }
            )
            
            latency = time.time() - start_time
            
            # Check response
            if response.status_code == 200:
                try:
                    response_data = response.json()
                    self.log(f"Chat success: tenant={tenant}, message='{message}'")
                    return True, response_data, latency
                except json.JSONDecodeError:
                    self.log(f"Chat error: Invalid JSON response")
                    return False, {"error": "Invalid JSON response"}, latency
            else:
                self.log(f"Chat error: status_code={response.status_code}")
                return False, {"error": f"HTTP {response.status_code}"}, latency
                
        except Exception as e:
            latency = time.time() - start_time
            self.log(f"Chat exception: {str(e)}")
            return False, {"error": str(e)}, latency
    
    def test_customer_status(self, tenant: str, customer_id: str = None) -> Tuple[bool, Dict[str, Any], float]:
        """
        Test customer status API
        
        Returns:
            (success, response_data, latency)
        """
        start_time = time.time()
        
        try:
            # Create payload
            payload = {"tenant": tenant}
            if customer_id:
                payload["customer_id"] = customer_id
            
            # Generate a unique request ID
            request_id = str(uuid.uuid4())
            
            # Get random user ID
            user_id = self.get_random_user_id(tenant)
            
            # Call API
            response = requests.post(
                f"{self.api_endpoint}/api/customer-status",
                json=payload,
                headers={
                    "Content-Type": "application/json",
                    "x-tenant-id": tenant,
                    "x-user-id": user_id,
                    "x-request-id": request_id
                }
            )
            
            latency = time.time() - start_time
            
            # Check response
            if response.status_code == 200:
                try:
                    response_data = response.json()
                    self.log(f"Customer status success: tenant={tenant}, customer_id={customer_id}")
                    return True, response_data, latency
                except json.JSONDecodeError:
                    self.log(f"Customer status error: Invalid JSON response")
                    return False, {"error": "Invalid JSON response"}, latency
            else:
                self.log(f"Customer status error: status_code={response.status_code}")
                return False, {"error": f"HTTP {response.status_code}"}, latency
                
        except Exception as e:
            latency = time.time() - start_time
            self.log(f"Customer status exception: {str(e)}")
            return False, {"error": str(e)}, latency

def run_kb_query_test(args):
    """Run KB query test"""
    tester, tenant, query = args
    return tester.test_kb_query(tenant, query)

def run_chat_test(args):
    """Run chat test"""
    tester, tenant, message = args
    return tester.test_chat(tenant, message)

def run_customer_status_test(args):
    """Run customer status test"""
    tester, tenant, customer_id = args
    return tester.test_customer_status(tenant, customer_id)

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Load test Cloudable.AI APIs with Langfuse observability")
    parser.add_argument("--endpoint", required=True, help="API endpoint URL")
    parser.add_argument("--kb-queries", type=int, default=20, help="Number of KB queries to test")
    parser.add_argument("--chat-messages", type=int, default=20, help="Number of chat messages to test")
    parser.add_argument("--customer-status", type=int, default=10, help="Number of customer status requests to test")
    parser.add_argument("--concurrency", type=int, default=4, help="Number of concurrent requests")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    args = parser.parse_args()
    
    # Create tester
    tester = LoadTester(args.endpoint, args.verbose)
    
    print(f"=== Cloudable.AI Load Testing with Langfuse ===")
    print(f"API Endpoint: {args.endpoint}")
    print(f"Concurrency: {args.concurrency}")
    print(f"Test start time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Prepare test data
    kb_test_data = []
    chat_test_data = []
    cs_test_data = []
    
    for _ in range(args.kb_queries):
        tenant = random.choice(TENANTS)
        query = random.choice(KB_QUERIES)
        kb_test_data.append((tester, tenant, query))
    
    for _ in range(args.chat_messages):
        tenant = random.choice(TENANTS)
        message = random.choice(CHAT_MESSAGES)
        chat_test_data.append((tester, tenant, message))
    
    for _ in range(args.customer_status):
        tenant = random.choice(TENANTS)
        customer_id = f"cust-{random.randint(1, 999):03d}" if random.random() > 0.3 else None
        cs_test_data.append((tester, tenant, customer_id))
    
    # Run tests
    results = {
        "kb_query": {"success": 0, "failure": 0, "latencies": []},
        "chat": {"success": 0, "failure": 0, "latencies": []},
        "customer_status": {"success": 0, "failure": 0, "latencies": []}
    }
    
    # Run KB query tests
    if kb_test_data:
        print(f"Running {len(kb_test_data)} KB query tests...")
        with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
            for success, _, latency in tqdm(executor.map(run_kb_query_test, kb_test_data), total=len(kb_test_data)):
                key = "success" if success else "failure"
                results["kb_query"][key] += 1
                results["kb_query"]["latencies"].append(latency)
    
    # Run chat tests
    if chat_test_data:
        print(f"Running {len(chat_test_data)} chat tests...")
        with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
            for success, _, latency in tqdm(executor.map(run_chat_test, chat_test_data), total=len(chat_test_data)):
                key = "success" if success else "failure"
                results["chat"][key] += 1
                results["chat"]["latencies"].append(latency)
    
    # Run customer status tests
    if cs_test_data:
        print(f"Running {len(cs_test_data)} customer status tests...")
        with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
            for success, _, latency in tqdm(executor.map(run_customer_status_test, cs_test_data), total=len(cs_test_data)):
                key = "success" if success else "failure"
                results["customer_status"][key] += 1
                results["customer_status"]["latencies"].append(latency)
    
    # Print results
    print("\n=== Test Results ===")
    
    for test_type, data in results.items():
        total = data["success"] + data["failure"]
        if total > 0:
            success_rate = data["success"] / total * 100
            avg_latency = sum(data["latencies"]) / len(data["latencies"]) if data["latencies"] else 0
            p95_latency = sorted(data["latencies"])[int(len(data["latencies"]) * 0.95)] if data["latencies"] else 0
            
            print(f"\n{test_type.replace('_', ' ').title()}:")
            print(f"  Requests: {total}")
            print(f"  Success: {data['success']} ({success_rate:.1f}%)")
            print(f"  Failure: {data['failure']}")
            print(f"  Avg Latency: {avg_latency:.2f}s")
            print(f"  P95 Latency: {p95_latency:.2f}s")
    
    print(f"\nTest end time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("\nCheck Langfuse dashboard for detailed observability metrics.")
    
    # Return success if all tests have some successes
    for data in results.values():
        if data["success"] == 0 and data["failure"] > 0:
            return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
