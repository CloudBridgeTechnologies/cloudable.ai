#!/usr/bin/env python3
"""
Script to visualize metrics data collected by the tenant_metrics module.
This simulates what would be visible in a real metrics dashboard.
"""

import json
import os
import sys
from datetime import datetime

# Simulate metrics data as it would be stored in a database
METRICS_DATA = {
    "acme": {
        "api_calls": {
            "upload_url": [
                {"timestamp": "2025-11-14T14:34:59.123456+00:00", "user_id": "user-admin-001", "status_code": 200, "execution_time_ms": 125},
            ],
            "kb_query": [
                {"timestamp": "2025-11-14T14:35:00.234567+00:00", "user_id": "user-reader-001", "status_code": 200, "execution_time_ms": 310},
                {"timestamp": "2025-11-14T14:35:01.345678+00:00", "user_id": "user-admin-001", "status_code": 200, "execution_time_ms": 285},
                {"timestamp": "2025-11-14T14:35:02.456789+00:00", "user_id": "user-admin-001", "status_code": 200, "execution_time_ms": 305},
                {"timestamp": "2025-11-14T14:35:03.567890+00:00", "user_id": "user-admin-001", "status_code": 200, "execution_time_ms": 278},
                {"timestamp": "2025-11-14T14:35:04.678901+00:00", "user_id": "user-admin-001", "status_code": 200, "execution_time_ms": 295},
                {"timestamp": "2025-11-14T14:35:05.789012+00:00", "user_id": "user-admin-001", "status_code": 200, "execution_time_ms": 312},
            ],
            "chat": [
                {"timestamp": "2025-11-14T14:35:06.890123+00:00", "user_id": "user-writer-001", "status_code": 200, "execution_time_ms": 450},
                {"timestamp": "2025-11-14T14:35:07.901234+00:00", "user_id": "user-writer-001", "status_code": 200, "execution_time_ms": 475},
                {"timestamp": "2025-11-14T14:35:08.012345+00:00", "user_id": "user-writer-001", "status_code": 200, "execution_time_ms": 460},
                {"timestamp": "2025-11-14T14:35:09.123456+00:00", "user_id": "user-writer-001", "status_code": 200, "execution_time_ms": 480},
            ]
        },
        "kb_queries": [
            {"timestamp": "2025-11-14T14:35:00.234567+00:00", "user_id": "user-reader-001", "query": "What is the implementation status?", "result_count": 1},
            {"timestamp": "2025-11-14T14:35:02.456789+00:00", "user_id": "user-admin-001", "query": "Query 1 for metrics test", "result_count": 1},
            {"timestamp": "2025-11-14T14:35:03.567890+00:00", "user_id": "user-admin-001", "query": "Query 2 for metrics test", "result_count": 1},
            {"timestamp": "2025-11-14T14:35:04.678901+00:00", "user_id": "user-admin-001", "query": "Query 3 for metrics test", "result_count": 1},
            {"timestamp": "2025-11-14T14:35:05.789012+00:00", "user_id": "user-admin-001", "query": "Query 4 for metrics test", "result_count": 1},
            {"timestamp": "2025-11-14T14:35:06.890123+00:00", "user_id": "user-admin-001", "query": "Query 5 for metrics test", "result_count": 1},
        ],
        "chat_sessions": [
            {"timestamp": "2025-11-14T14:35:06.890123+00:00", "user_id": "user-writer-001", "message": "What is our implementation status?", "tokens": 48},
            {"timestamp": "2025-11-14T14:35:07.901234+00:00", "user_id": "user-writer-001", "message": "Chat message 1 for metrics test", "tokens": 35},
            {"timestamp": "2025-11-14T14:35:08.012345+00:00", "user_id": "user-writer-001", "message": "Chat message 2 for metrics test", "tokens": 38},
            {"timestamp": "2025-11-14T14:35:09.123456+00:00", "user_id": "user-writer-001", "message": "Chat message 3 for metrics test", "tokens": 41},
        ],
        "user_activity": {
            "user-admin-001": {"last_activity": "2025-11-14T14:35:06.890123+00:00", "total_api_calls": 7},
            "user-reader-001": {"last_activity": "2025-11-14T14:35:00.234567+00:00", "total_api_calls": 1},
            "user-writer-001": {"last_activity": "2025-11-14T14:35:09.123456+00:00", "total_api_calls": 4},
        }
    },
    "globex": {
        "api_calls": {
            "kb_query": [
                {"timestamp": "2025-11-14T14:35:10.234567+00:00", "user_id": "user-admin-001", "status_code": 200, "execution_time_ms": 298},
                {"timestamp": "2025-11-14T14:35:11.345678+00:00", "user_id": "user-admin-001", "status_code": 200, "execution_time_ms": 312},
            ]
        },
        "kb_queries": [
            {"timestamp": "2025-11-14T14:35:10.234567+00:00", "user_id": "user-admin-001", "query": "Globex query 1 for metrics test", "result_count": 1},
            {"timestamp": "2025-11-14T14:35:11.345678+00:00", "user_id": "user-admin-001", "query": "Globex query 2 for metrics test", "result_count": 1},
        ],
        "chat_sessions": [],
        "user_activity": {
            "user-admin-001": {"last_activity": "2025-11-14T14:35:11.345678+00:00", "total_api_calls": 2},
        }
    }
}

def display_tenant_metrics(tenant_id):
    """Display metrics for a specific tenant"""
    if tenant_id not in METRICS_DATA:
        print(f"No metrics data found for tenant: {tenant_id}")
        return

    tenant_data = METRICS_DATA[tenant_id]
    
    print("\n" + "=" * 80)
    print(f"METRICS DASHBOARD FOR TENANT: {tenant_id.upper()}")
    print("=" * 80)
    
    # API Call Summary
    total_api_calls = sum(len(calls) for calls in tenant_data["api_calls"].values())
    print(f"\nAPI CALL SUMMARY (Total: {total_api_calls})")
    print("-" * 40)
    for api_name, calls in tenant_data["api_calls"].items():
        avg_time = sum(call["execution_time_ms"] for call in calls) / len(calls) if calls else 0
        print(f"{api_name.ljust(15)}: {len(calls)} calls, {avg_time:.1f}ms avg response time")

    # KB Query Summary
    if tenant_data["kb_queries"]:
        print(f"\nKNOWLEDGE BASE QUERIES (Total: {len(tenant_data['kb_queries'])})")
        print("-" * 40)
        for idx, query in enumerate(tenant_data["kb_queries"][:5]):  # Show up to 5 queries
            timestamp = datetime.fromisoformat(query["timestamp"]).strftime("%H:%M:%S")
            print(f"{timestamp} - User: {query['user_id']}, Query: \"{query['query']}\"")
        if len(tenant_data["kb_queries"]) > 5:
            print(f"... and {len(tenant_data['kb_queries']) - 5} more queries")
    
    # Chat Session Summary
    if tenant_data["chat_sessions"]:
        total_tokens = sum(session["tokens"] for session in tenant_data["chat_sessions"])
        print(f"\nCHAT SESSIONS (Total: {len(tenant_data['chat_sessions'])}, Tokens: {total_tokens})")
        print("-" * 40)
        for idx, session in enumerate(tenant_data["chat_sessions"][:5]):  # Show up to 5 sessions
            timestamp = datetime.fromisoformat(session["timestamp"]).strftime("%H:%M:%S")
            print(f"{timestamp} - User: {session['user_id']}, Message: \"{session['message']}\"")
        if len(tenant_data["chat_sessions"]) > 5:
            print(f"... and {len(tenant_data['chat_sessions']) - 5} more chat sessions")
    
    # User Activity
    print(f"\nUSER ACTIVITY (Total users: {len(tenant_data['user_activity'])})")
    print("-" * 40)
    for user_id, activity in tenant_data["user_activity"].items():
        last_activity = datetime.fromisoformat(activity["last_activity"]).strftime("%Y-%m-%d %H:%M:%S")
        print(f"{user_id.ljust(20)}: {activity['total_api_calls']} API calls, Last activity: {last_activity}")
    
    print("\n" + "=" * 80)

def display_all_metrics():
    """Display summary metrics for all tenants"""
    print("\n" + "=" * 80)
    print("MULTI-TENANT METRICS DASHBOARD")
    print("=" * 80)
    
    print("\nTENANT SUMMARY")
    print("-" * 40)
    for tenant_id, tenant_data in METRICS_DATA.items():
        total_api_calls = sum(len(calls) for calls in tenant_data["api_calls"].values())
        total_kb_queries = len(tenant_data["kb_queries"])
        total_chat_sessions = len(tenant_data["chat_sessions"])
        total_users = len(tenant_data["user_activity"])
        
        print(f"{tenant_id.ljust(15)}: {total_api_calls} API calls, {total_kb_queries} KB queries, {total_chat_sessions} chat sessions, {total_users} active users")
    
    print("\n" + "=" * 80)
    print("To view detailed metrics for a specific tenant, run:")
    print("python view_metrics.py <tenant_id>")
    print("=" * 80 + "\n")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        tenant_id = sys.argv[1].lower()
        display_tenant_metrics(tenant_id)
    else:
        display_all_metrics()
