#!/usr/bin/env python3
"""
Simple dashboard to visualize Langfuse metrics for Cloudable.AI
This script uses the Langfuse API to fetch metrics and display them locally.

For development and demonstration purposes only.
In production, use the official Langfuse dashboard.
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta, timezone
import webbrowser
from http.server import HTTPServer, SimpleHTTPRequestHandler
import threading

try:
    import requests
    from tabulate import tabulate
    import pandas as pd
    import matplotlib.pyplot as plt
except ImportError:
    print("Required packages not found. Installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "tabulate", "pandas", "matplotlib"])
    import requests
    from tabulate import tabulate
    import pandas as pd
    import matplotlib.pyplot as plt

# Configuration
DEFAULT_API_HOST = "https://cloud.langfuse.com"
DEFAULT_OUTPUT_DIR = "langfuse_metrics"

class LangfuseMetricsClient:
    """Client for fetching metrics from Langfuse API"""
    
    def __init__(self, public_key, secret_key, host=DEFAULT_API_HOST):
        """Initialize client with API keys"""
        self.public_key = public_key
        self.secret_key = secret_key
        self.host = host
        self.auth = (self.public_key, self.secret_key)
    
    def get_traces(self, limit=100, start_date=None, end_date=None):
        """Get traces from the API"""
        if not start_date:
            start_date = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
        if not end_date:
            end_date = datetime.now(timezone.utc).isoformat()
            
        url = f"{self.host}/api/public/traces"
        params = {
            "limit": limit,
            "startTime": start_date,
            "endTime": end_date
        }
        
        try:
            response = requests.get(url, auth=self.auth, params=params)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Error fetching traces: {e}")
            return {"data": []}
    
    def get_generations(self, limit=100, start_date=None, end_date=None):
        """Get generations from the API"""
        if not start_date:
            start_date = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
        if not end_date:
            end_date = datetime.now(timezone.utc).isoformat()
            
        url = f"{self.host}/api/public/generations"
        params = {
            "limit": limit,
            "startTime": start_date,
            "endTime": end_date
        }
        
        try:
            response = requests.get(url, auth=self.auth, params=params)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Error fetching generations: {e}")
            return {"data": []}
    
    def get_scores(self, limit=100):
        """Get scores from the API"""
        url = f"{self.host}/api/public/scores"
        params = {"limit": limit}
        
        try:
            response = requests.get(url, auth=self.auth, params=params)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"Error fetching scores: {e}")
            return {"data": []}

def generate_dashboard(client, output_dir, days=7, limit=500):
    """Generate dashboard with metrics from Langfuse"""
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Calculate date range
    end_date = datetime.now(timezone.utc)
    start_date = end_date - timedelta(days=days)
    
    print(f"Fetching data from {start_date.date()} to {end_date.date()}...")
    
    # Fetch data
    traces = client.get_traces(limit=limit, 
                             start_date=start_date.isoformat(), 
                             end_date=end_date.isoformat())
    generations = client.get_generations(limit=limit, 
                                      start_date=start_date.isoformat(), 
                                      end_date=end_date.isoformat())
    
    # Process traces
    trace_data = traces.get("data", [])
    if not trace_data:
        print("No trace data found.")
        trace_df = pd.DataFrame()
    else:
        # Extract tenant information from metadata
        for trace in trace_data:
            metadata = trace.get("metadata", {})
            trace["tenant"] = metadata.get("tenant_id", "unknown")
            trace["api_path"] = metadata.get("path", "unknown")
        
        trace_df = pd.DataFrame(trace_data)
        
        # Generate trace statistics
        if not trace_df.empty and "name" in trace_df.columns:
            # Traces by name
            traces_by_name = trace_df["name"].value_counts().reset_index()
            traces_by_name.columns = ["Trace Name", "Count"]
            
            # Traces by tenant
            if "tenant" in trace_df.columns:
                traces_by_tenant = trace_df["tenant"].value_counts().reset_index()
                traces_by_tenant.columns = ["Tenant", "Count"]
            
                # Plot traces by tenant
                plt.figure(figsize=(10, 6))
                plt.bar(traces_by_tenant["Tenant"], traces_by_tenant["Count"])
                plt.title("Traces by Tenant")
                plt.xlabel("Tenant")
                plt.ylabel("Count")
                plt.tight_layout()
                plt.savefig(os.path.join(output_dir, "traces_by_tenant.png"))
            
            # Plot traces by name
            plt.figure(figsize=(12, 6))
            plt.bar(traces_by_name["Trace Name"][:10], traces_by_name["Count"][:10])
            plt.title("Top 10 Trace Names")
            plt.xlabel("Trace Name")
            plt.ylabel("Count")
            plt.xticks(rotation=45, ha="right")
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, "traces_by_name.png"))
    
    # Process generations
    generation_data = generations.get("data", [])
    if not generation_data:
        print("No generation data found.")
        generation_df = pd.DataFrame()
    else:
        generation_df = pd.DataFrame(generation_data)
        
        # Generate generation statistics
        if not generation_df.empty and "model" in generation_df.columns:
            # Generations by model
            gens_by_model = generation_df["model"].value_counts().reset_index()
            gens_by_model.columns = ["Model", "Count"]
            
            # Plot generations by model
            plt.figure(figsize=(10, 6))
            plt.bar(gens_by_model["Model"], gens_by_model["Count"])
            plt.title("Generations by Model")
            plt.xlabel("Model")
            plt.ylabel("Count")
            plt.xticks(rotation=45, ha="right")
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, "generations_by_model.png"))
    
    # Generate HTML dashboard
    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Cloudable.AI Langfuse Metrics Dashboard</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 20px; }}
            h1 {{ color: #333; }}
            h2 {{ color: #555; margin-top: 30px; }}
            .metric-card {{ 
                background-color: #f5f5f5; 
                border-radius: 8px; 
                padding: 20px; 
                margin-bottom: 20px; 
                box-shadow: 0 2px 4px rgba(0,0,0,0.1); 
            }}
            .chart {{ margin: 20px 0; max-width: 100%; }}
            .chart img {{ max-width: 100%; height: auto; }}
            table {{ border-collapse: collapse; width: 100%; }}
            th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
            th {{ background-color: #f2f2f2; }}
            tr:nth-child(even) {{ background-color: #f9f9f9; }}
            .dashboard-header {{ 
                background-color: #005a9c; 
                color: white; 
                padding: 20px; 
                margin-bottom: 20px; 
                border-radius: 8px; 
            }}
        </style>
    </head>
    <body>
        <div class="dashboard-header">
            <h1>Cloudable.AI Langfuse Metrics Dashboard</h1>
            <p>Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p>Date range: {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}</p>
        </div>
        
        <div class="metric-card">
            <h2>Summary</h2>
            <p>Total traces: {len(trace_data)}</p>
            <p>Total generations: {len(generation_data)}</p>
        </div>
    """
    
    # Add trace metrics if available
    if not trace_df.empty and "name" in trace_df.columns:
        traces_by_name = trace_df["name"].value_counts().reset_index()
        traces_by_name.columns = ["Trace Name", "Count"]
        
        html_content += f"""
        <div class="metric-card">
            <h2>Traces by Name</h2>
            <table>
                <tr>
                    <th>Trace Name</th>
                    <th>Count</th>
                </tr>
        """
        
        for _, row in traces_by_name.iterrows():
            html_content += f"""
                <tr>
                    <td>{row['Trace Name']}</td>
                    <td>{row['Count']}</td>
                </tr>
            """
        
        html_content += """
            </table>
        </div>
        """
        
        if "tenant" in trace_df.columns:
            html_content += """
            <div class="metric-card">
                <h2>Traces by Tenant</h2>
                <div class="chart">
                    <img src="traces_by_tenant.png" alt="Traces by Tenant">
                </div>
            </div>
            """
        
        html_content += """
        <div class="metric-card">
            <h2>Top 10 Trace Names</h2>
            <div class="chart">
                <img src="traces_by_name.png" alt="Top 10 Trace Names">
            </div>
        </div>
        """
    
    # Add generation metrics if available
    if not generation_df.empty and "model" in generation_df.columns:
        html_content += """
        <div class="metric-card">
            <h2>Generations by Model</h2>
            <div class="chart">
                <img src="generations_by_model.png" alt="Generations by Model">
            </div>
        </div>
        """
    
    # Close HTML
    html_content += """
    </body>
    </html>
    """
    
    # Write HTML to file
    with open(os.path.join(output_dir, "dashboard.html"), "w") as f:
        f.write(html_content)
    
    return os.path.join(output_dir, "dashboard.html")

def start_http_server(directory, port=8000):
    """Start HTTP server to serve the dashboard"""
    os.chdir(directory)
    server_address = ('', port)
    httpd = HTTPServer(server_address, SimpleHTTPRequestHandler)
    print(f"Starting HTTP server at http://localhost:{port}/")
    thread = threading.Thread(target=httpd.serve_forever)
    thread.daemon = True
    thread.start()
    return httpd

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Generate Langfuse metrics dashboard")
    parser.add_argument("--public-key", help="Langfuse public API key")
    parser.add_argument("--secret-key", help="Langfuse secret API key")
    parser.add_argument("--host", default=DEFAULT_API_HOST, help="Langfuse API host")
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR, help="Output directory")
    parser.add_argument("--days", type=int, default=7, help="Number of days to fetch data for")
    parser.add_argument("--limit", type=int, default=500, help="Limit number of records to fetch")
    parser.add_argument("--serve", action="store_true", help="Serve dashboard on HTTP server")
    parser.add_argument("--port", type=int, default=8000, help="Port for HTTP server")
    args = parser.parse_args()
    
    # Get API keys from args or environment variables
    public_key = args.public_key or os.environ.get("LANGFUSE_PUBLIC_KEY")
    secret_key = args.secret_key or os.environ.get("LANGFUSE_SECRET_KEY")
    
    if not public_key or not secret_key:
        print("Error: Langfuse API keys not provided.")
        print("Please provide keys using --public-key and --secret-key arguments or")
        print("set LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY environment variables.")
        return 1
    
    # Create client
    client = LangfuseMetricsClient(public_key, secret_key, args.host)
    
    # Generate dashboard
    dashboard_path = generate_dashboard(client, args.output_dir, args.days, args.limit)
    print(f"Dashboard generated at {dashboard_path}")
    
    # Open dashboard in browser
    webbrowser.open(f"file://{os.path.abspath(dashboard_path)}")
    
    # Start HTTP server if requested
    if args.serve:
        httpd = start_http_server(args.output_dir, args.port)
        print(f"Dashboard available at http://localhost:{args.port}/dashboard.html")
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("Stopping server...")
            httpd.shutdown()
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
