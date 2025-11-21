#!/usr/bin/env python3
"""
Automated reporting script for Langfuse metrics
Generates PDF and email reports from Langfuse data
"""

import argparse
import datetime
import json
import os
import sys
from datetime import datetime, timedelta, timezone

try:
    import requests
    import matplotlib.pyplot as plt
    from fpdf import FPDF
    import pandas as pd
except ImportError:
    print("Required packages not found. Installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", 
                          "requests", "matplotlib", "fpdf", "pandas"])
    import requests
    import matplotlib.pyplot as plt
    from fpdf import FPDF
    import pandas as pd

class LangfuseReportGenerator:
    """Generate reports from Langfuse metrics"""
    
    def __init__(self, public_key, secret_key, host="https://cloud.langfuse.com"):
        """Initialize client with API keys"""
        self.public_key = public_key
        self.secret_key = secret_key
        self.host = host
        self.auth = (self.public_key, self.secret_key)
    
    def get_traces(self, days=7, limit=500):
        """Get traces from the API"""
        end_date = datetime.now(timezone.utc)
        start_date = end_date - timedelta(days=days)
        
        url = f"{self.host}/api/public/traces"
        params = {
            "limit": limit,
            "startTime": start_date.isoformat(),
            "endTime": end_date.isoformat()
        }
        
        try:
            response = requests.get(url, auth=self.auth, params=params)
            response.raise_for_status()
            return response.json().get("data", [])
        except Exception as e:
            print(f"Error fetching traces: {e}")
            return []
    
    def get_generations(self, days=7, limit=500):
        """Get generations from the API"""
        end_date = datetime.now(timezone.utc)
        start_date = end_date - timedelta(days=days)
        
        url = f"{self.host}/api/public/generations"
        params = {
            "limit": limit,
            "startTime": start_date.isoformat(),
            "endTime": end_date.isoformat()
        }
        
        try:
            response = requests.get(url, auth=self.auth, params=params)
            response.raise_for_status()
            return response.json().get("data", [])
        except Exception as e:
            print(f"Error fetching generations: {e}")
            return []
    
    def get_scores(self, limit=500):
        """Get scores from the API"""
        url = f"{self.host}/api/public/scores"
        params = {"limit": limit}
        
        try:
            response = requests.get(url, auth=self.auth, params=params)
            response.raise_for_status()
            return response.json().get("data", [])
        except Exception as e:
            print(f"Error fetching scores: {e}")
            return []
    
    def generate_report(self, output_dir, days=7, limit=500):
        """
        Generate a PDF report
        
        Args:
            output_dir: Directory to save the report
            days: Number of days of data to include
            limit: Maximum number of records to fetch
        
        Returns:
            Path to the generated report
        """
        os.makedirs(output_dir, exist_ok=True)
        
        print(f"Fetching data for the last {days} days...")
        traces = self.get_traces(days, limit)
        generations = self.get_generations(days, limit)
        scores = self.get_scores(limit)
        
        print(f"Found {len(traces)} traces, {len(generations)} generations, and {len(scores)} scores")
        
        # Process data
        trace_df = pd.DataFrame(traces) if traces else pd.DataFrame()
        generation_df = pd.DataFrame(generations) if generations else pd.DataFrame()
        score_df = pd.DataFrame(scores) if scores else pd.DataFrame()
        
        # Generate charts
        self.generate_charts(trace_df, generation_df, score_df, output_dir)
        
        # Generate PDF
        report_path = self.generate_pdf(trace_df, generation_df, score_df, output_dir, days)
        
        return report_path
    
    def generate_charts(self, trace_df, generation_df, score_df, output_dir):
        """Generate charts for the report"""
        # Trace charts
        if not trace_df.empty and "name" in trace_df.columns:
            # Traces by name
            plt.figure(figsize=(10, 6))
            trace_counts = trace_df["name"].value_counts().head(10)
            trace_counts.plot(kind="bar")
            plt.title("Top 10 Trace Types")
            plt.xlabel("Trace Name")
            plt.ylabel("Count")
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, "traces_by_name.png"))
            
            # Extract tenant information if available
            if not trace_df.empty:
                tenant_ids = []
                for _, row in trace_df.iterrows():
                    if "metadata" in row and row["metadata"] and isinstance(row["metadata"], dict):
                        tenant_id = row["metadata"].get("tenant_id")
                        if tenant_id:
                            tenant_ids.append(tenant_id)
                
                if tenant_ids:
                    plt.figure(figsize=(10, 6))
                    pd.Series(tenant_ids).value_counts().plot(kind="bar")
                    plt.title("Traces by Tenant")
                    plt.xlabel("Tenant")
                    plt.ylabel("Count")
                    plt.tight_layout()
                    plt.savefig(os.path.join(output_dir, "traces_by_tenant.png"))
        
        # Generation charts
        if not generation_df.empty and "model" in generation_df.columns:
            plt.figure(figsize=(10, 6))
            generation_df["model"].value_counts().plot(kind="bar")
            plt.title("Generations by Model")
            plt.xlabel("Model")
            plt.ylabel("Count")
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, "generations_by_model.png"))
        
        # Score charts
        if not score_df.empty and "name" in score_df.columns and "value" in score_df.columns:
            plt.figure(figsize=(10, 6))
            avg_scores = score_df.groupby("name")["value"].mean().sort_values(ascending=False)
            avg_scores.plot(kind="bar")
            plt.title("Average Scores by Name")
            plt.xlabel("Score Name")
            plt.ylabel("Average Value")
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, "avg_scores.png"))
    
    def generate_pdf(self, trace_df, generation_df, score_df, output_dir, days):
        """Generate PDF report"""
        report_date = datetime.now().strftime("%Y-%m-%d")
        filename = os.path.join(output_dir, f"langfuse_report_{report_date}.pdf")
        
        # Create PDF
        pdf = FPDF()
        pdf.add_page()
        
        # Title
        pdf.set_font("Arial", "B", 16)
        pdf.cell(0, 10, "Cloudable.AI Langfuse Metrics Report", 0, 1, "C")
        pdf.set_font("Arial", "", 12)
        pdf.cell(0, 10, f"Generated on {report_date} - Last {days} Days", 0, 1, "C")
        pdf.ln(10)
        
        # Summary section
        pdf.set_font("Arial", "B", 14)
        pdf.cell(0, 10, "Summary", 0, 1)
        pdf.set_font("Arial", "", 12)
        pdf.cell(0, 10, f"Total Traces: {len(trace_df)}", 0, 1)
        pdf.cell(0, 10, f"Total Generations: {len(generation_df)}", 0, 1)
        pdf.cell(0, 10, f"Total Scores: {len(score_df)}", 0, 1)
        pdf.ln(10)
        
        # Add trace chart if available
        if os.path.exists(os.path.join(output_dir, "traces_by_name.png")):
            pdf.set_font("Arial", "B", 14)
            pdf.cell(0, 10, "Traces by Name", 0, 1)
            pdf.image(os.path.join(output_dir, "traces_by_name.png"), x=10, w=190)
            pdf.ln(10)
        
        # Add tenant chart if available
        if os.path.exists(os.path.join(output_dir, "traces_by_tenant.png")):
            pdf.set_font("Arial", "B", 14)
            pdf.cell(0, 10, "Traces by Tenant", 0, 1)
            pdf.image(os.path.join(output_dir, "traces_by_tenant.png"), x=10, w=190)
            pdf.ln(10)
        
        # Add generations chart if available
        if os.path.exists(os.path.join(output_dir, "generations_by_model.png")):
            # Add a new page if needed
            if pdf.get_y() > 200:
                pdf.add_page()
            
            pdf.set_font("Arial", "B", 14)
            pdf.cell(0, 10, "Generations by Model", 0, 1)
            pdf.image(os.path.join(output_dir, "generations_by_model.png"), x=10, w=190)
            pdf.ln(10)
        
        # Add scores chart if available
        if os.path.exists(os.path.join(output_dir, "avg_scores.png")):
            # Add a new page if needed
            if pdf.get_y() > 200:
                pdf.add_page()
            
            pdf.set_font("Arial", "B", 14)
            pdf.cell(0, 10, "Average Scores", 0, 1)
            pdf.image(os.path.join(output_dir, "avg_scores.png"), x=10, w=190)
            pdf.ln(10)
        
        # Score details section
        if not score_df.empty:
            # Add a new page
            pdf.add_page()
            
            pdf.set_font("Arial", "B", 14)
            pdf.cell(0, 10, "Score Details", 0, 1)
            
            if "name" in score_df.columns and "value" in score_df.columns:
                # Calculate average scores by name
                avg_scores = score_df.groupby("name")["value"].agg(["mean", "count", "min", "max"]).reset_index()
                avg_scores["mean"] = avg_scores["mean"].round(2)
                
                # Display in a table
                pdf.set_font("Arial", "B", 12)
                pdf.cell(60, 10, "Score Name", 1)
                pdf.cell(30, 10, "Average", 1)
                pdf.cell(30, 10, "Min", 1)
                pdf.cell(30, 10, "Max", 1)
                pdf.cell(30, 10, "Count", 1)
                pdf.ln()
                
                pdf.set_font("Arial", "", 12)
                for _, row in avg_scores.iterrows():
                    pdf.cell(60, 10, str(row["name"]), 1)
                    pdf.cell(30, 10, str(row["mean"]), 1)
                    pdf.cell(30, 10, str(row["min"]), 1)
                    pdf.cell(30, 10, str(row["max"]), 1)
                    pdf.cell(30, 10, str(row["count"]), 1)
                    pdf.ln()
        
        # Save PDF
        pdf.output(filename)
        print(f"Report saved to {filename}")
        
        return filename

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Generate automated reports from Langfuse metrics")
    parser.add_argument("--public-key", help="Langfuse public API key")
    parser.add_argument("--secret-key", help="Langfuse secret API key")
    parser.add_argument("--host", default="https://cloud.langfuse.com", help="Langfuse API host")
    parser.add_argument("--days", type=int, default=7, help="Number of days to include in report")
    parser.add_argument("--output-dir", default="langfuse_reports", help="Output directory for reports")
    args = parser.parse_args()
    
    # Get API keys from args or environment variables
    public_key = args.public_key or os.environ.get("LANGFUSE_PUBLIC_KEY")
    secret_key = args.secret_key or os.environ.get("LANGFUSE_SECRET_KEY")
    
    if not public_key or not secret_key:
        print("Error: Langfuse API keys not provided.")
        print("Please provide keys using --public-key and --secret-key arguments or")
        print("set LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY environment variables.")
        return 1
    
    # Create report generator
    generator = LangfuseReportGenerator(public_key, secret_key, args.host)
    
    # Generate report
    try:
        report_path = generator.generate_report(args.output_dir, args.days)
        print(f"Report generated successfully: {report_path}")
        return 0
    except Exception as e:
        print(f"Error generating report: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
