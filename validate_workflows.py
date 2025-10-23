#!/usr/bin/env python3
"""
Comprehensive GitHub Actions workflow validator script.
This script checks for common errors in GitHub Actions workflow files.
"""

import os
import sys
import yaml
import re
from pathlib import Path
import argparse
from typing import Dict, List, Any, Optional, Set

# ANSI color codes for terminal output
GREEN = '\033[92m'
YELLOW = '\033[93m'
RED = '\033[91m'
BOLD = '\033[1m'
ENDC = '\033[0m'

class WorkflowValidator:
    def __init__(self, workflows_dir: str = ".github/workflows"):
        self.workflows_dir = Path(workflows_dir)
        self.errors = []
        self.warnings = []
        self.info = []
        self.all_job_ids = set()
        self.all_workflow_ids = set()
        self.active_workflows = set()
    
    def load_workflow(self, file_path: Path) -> Dict:
        """Load a YAML workflow file."""
        with open(file_path, 'r') as f:
            try:
                return yaml.safe_load(f)
            except yaml.YAMLError as e:
                self.errors.append(f"Error parsing YAML in {file_path}: {e}")
                return {}
    
    def find_workflow_files(self) -> List[Path]:
        """Find all YAML workflow files in the workflows directory."""
        if not self.workflows_dir.exists():
            self.errors.append(f"Workflows directory {self.workflows_dir} does not exist")
            return []
        
        return list(self.workflows_dir.glob("*.yml")) + list(self.workflows_dir.glob("*.yaml"))
    
    def validate_trigger_configuration(self, workflow: Dict, file_path: Path) -> None:
        """Check if workflow has proper trigger configuration."""
        if 'on' not in workflow:
            self.errors.append(f"{file_path}: Missing 'on' trigger configuration")
            return
        
        # Empty trigger configuration
        if workflow['on'] is None or workflow['on'] == {}:
            self.errors.append(f"{file_path}: Empty trigger configuration")
        
        # Check if workflow_dispatch is properly configured for manual triggers
        if isinstance(workflow['on'], dict) and 'workflow_dispatch' in workflow['on']:
            if workflow['on']['workflow_dispatch'] is None:
                workflow['on']['workflow_dispatch'] = {}  # Default empty object is valid
            elif not isinstance(workflow['on']['workflow_dispatch'], dict):
                self.errors.append(f"{file_path}: Invalid 'workflow_dispatch' configuration")
    
    def validate_permissions(self, workflow: Dict, file_path: Path) -> None:
        """Check if workflow has proper permissions configuration."""
        if 'permissions' not in workflow:
            self.warnings.append(f"{file_path}: Missing 'permissions' configuration. Consider adding explicitly.")
            return
            
        # Check for required permissions for AWS credentials
        has_aws_action = self._has_aws_action(workflow)
        if has_aws_action and ('permissions' not in workflow or 
                              'id-token' not in workflow['permissions'] or 
                              workflow['permissions']['id-token'] != 'write'):
            self.errors.append(f"{file_path}: Uses AWS actions but missing 'id-token: write' permission required for OIDC")
    
    def _has_aws_action(self, workflow: Dict) -> bool:
        """Check if workflow uses AWS actions that need OIDC auth."""
        if 'jobs' not in workflow:
            return False
            
        for job_id, job in workflow['jobs'].items():
            if 'steps' not in job:
                continue
                
            for step in job['steps']:
                if 'uses' in step and 'aws-actions/configure-aws-credentials' in step['uses']:
                    return True
                if 'with' in step and 'role-to-assume' in step['with']:
                    return True
                    
        return False
    
    def validate_jobs(self, workflow: Dict, file_path: Path) -> None:
        """Validate jobs configuration."""
        if 'jobs' not in workflow or not workflow['jobs']:
            self.errors.append(f"{file_path}: Missing or empty 'jobs' configuration")
            return
            
        # Add all job IDs to the set for dependency checking
        workflow_name = Path(file_path).stem
        for job_id in workflow['jobs'].keys():
            self.all_job_ids.add(f"{workflow_name}.{job_id}")
        
        # Check each job
        for job_id, job in workflow['jobs'].items():
            # Check if job has runs-on
            if 'runs-on' not in job:
                self.errors.append(f"{file_path}, job '{job_id}': Missing 'runs-on' configuration")
            
            # Check job dependencies
            if 'needs' in job:
                needs = job['needs']
                if isinstance(needs, str):
                    if needs not in workflow['jobs']:
                        self.errors.append(f"{file_path}, job '{job_id}': Depends on non-existent job '{needs}'")
                elif isinstance(needs, list):
                    for need in needs:
                        if need not in workflow['jobs']:
                            self.errors.append(f"{file_path}, job '{job_id}': Depends on non-existent job '{need}'")
            
            # Check steps
            if 'steps' not in job or not job['steps']:
                self.errors.append(f"{file_path}, job '{job_id}': Missing or empty 'steps' configuration")
                continue
                
            self._validate_steps(job['steps'], file_path, job_id)
    
    def _validate_steps(self, steps: List[Dict], file_path: Path, job_id: str) -> None:
        """Validate workflow steps."""
        has_checkout = False
        
        for i, step in enumerate(steps):
            # Check if step has a name
            if 'name' not in step:
                self.warnings.append(f"{file_path}, job '{job_id}', step #{i+1}: Missing 'name' property")
            
            # Check for checkout action
            if 'uses' in step and 'actions/checkout@' in step['uses']:
                has_checkout = True
            
            # Check for string interpolation in expressions
            if 'run' in step:
                self._check_expression_in_string(step['run'], file_path, job_id, i)
                
            if 'with' in step:
                for key, value in step['with'].items():
                    if isinstance(value, str):
                        self._check_expression_in_string(value, file_path, job_id, i)
        
        # Warn if no checkout action is used
        if not has_checkout:
            self.warnings.append(f"{file_path}, job '{job_id}': No checkout action found. Most workflows need to checkout the code.")
    
    def _check_expression_in_string(self, text: str, file_path: Path, job_id: str, step_index: int) -> None:
        """Check for potential problems with expressions inside strings."""
        if not isinstance(text, str):
            return
            
        # Look for expressions with logical operators inside double quotes
        matches = re.findall(r'"[^"]*\$\{\{[^}]*\|\|[^}]*\}\}[^"]*"', text)
        if matches:
            self.errors.append(
                f"{file_path}, job '{job_id}', step #{step_index+1}: "
                f"Expression with logical operator found inside double quotes: {matches[0]}"
            )
            
        # Look for expressions with ternary operators inside double quotes
        matches = re.findall(r'"[^"]*\$\{\{[^}]*\?[^}]*:[^}]*\}\}[^"]*"', text)
        if matches:
            self.errors.append(
                f"{file_path}, job '{job_id}', step #{step_index+1}: "
                f"Expression with ternary operator found inside double quotes: {matches[0]}"
            )
    
    def validate_workflow_dependencies(self) -> None:
        """Validate dependencies between workflows."""
        for workflow_file in self.find_workflow_files():
            workflow = self.load_workflow(workflow_file)
            if not workflow:
                continue
                
            # Check workflow_run triggers
            if 'on' in workflow and isinstance(workflow['on'], dict) and 'workflow_run' in workflow['on']:
                workflow_run = workflow['on']['workflow_run']
                if isinstance(workflow_run, dict) and 'workflows' in workflow_run:
                    workflows = workflow_run['workflows']
                    for wf in workflows:
                        if wf not in self.all_workflow_ids:
                            self.warnings.append(f"{workflow_file}: Depends on workflow '{wf}' that may not exist")
    
    def check_python_version(self, workflow: Dict, file_path: Path) -> None:
        """Check if Python version is consistent across jobs."""
        python_versions = set()
        
        if 'jobs' not in workflow:
            return
            
        for job_id, job in workflow['jobs'].items():
            if 'steps' not in job:
                continue
                
            for step in job['steps']:
                if 'uses' in step and 'actions/setup-python@' in step['uses']:
                    if 'with' in step and 'python-version' in step['with']:
                        python_version = step['with']['python-version']
                        python_versions.add(python_version)
        
        if len(python_versions) > 1:
            self.warnings.append(f"{file_path}: Multiple Python versions used across jobs: {', '.join(python_versions)}")
    
    def validate_all_workflows(self) -> bool:
        """Validate all workflows in the directory."""
        workflow_files = self.find_workflow_files()
        
        if not workflow_files:
            self.errors.append("No workflow files found")
            return False
        
        # First pass: collect all workflow and job IDs
        for file_path in workflow_files:
            workflow_name = file_path.stem
            self.all_workflow_ids.add(workflow_name)
            
            workflow = self.load_workflow(file_path)
            if not workflow:
                continue
                
            # Check if workflow is active
            if 'on' in workflow and workflow['on']:
                self.active_workflows.add(workflow_name)
        
        # Second pass: validate each workflow
        for file_path in workflow_files:
            workflow = self.load_workflow(file_path)
            if not workflow:
                continue
                
            self.validate_trigger_configuration(workflow, file_path)
            self.validate_permissions(workflow, file_path)
            self.validate_jobs(workflow, file_path)
            self.check_python_version(workflow, file_path)
        
        # Third pass: validate inter-workflow dependencies
        self.validate_workflow_dependencies()
        
        # Check if any workflows are inactive
        inactive_workflows = self.all_workflow_ids - self.active_workflows
        for wf in inactive_workflows:
            self.warnings.append(f"Workflow '{wf}' appears to be inactive (no triggers configured)")
        
        return len(self.errors) == 0
    
    def print_results(self) -> None:
        """Print validation results."""
        if self.info:
            print(f"{BOLD}Info:{ENDC}")
            for item in self.info:
                print(f"  {item}")
            print()
            
        if self.warnings:
            print(f"{YELLOW}{BOLD}Warnings:{ENDC}")
            for warning in self.warnings:
                print(f"  {YELLOW}⚠ {warning}{ENDC}")
            print()
            
        if self.errors:
            print(f"{RED}{BOLD}Errors:{ENDC}")
            for error in self.errors:
                print(f"  {RED}✖ {error}{ENDC}")
            print()
            
        if not self.errors and not self.warnings:
            print(f"{GREEN}{BOLD}All workflows are valid! No issues found.{ENDC}")
        elif not self.errors:
            print(f"{YELLOW}{BOLD}Workflows have warnings but no critical errors.{ENDC}")
        else:
            print(f"{RED}{BOLD}Workflows have errors that need to be fixed.{ENDC}")

def main():
    parser = argparse.ArgumentParser(description="Validate GitHub Actions workflow files")
    parser.add_argument(
        "--workflows-dir", 
        default=".github/workflows", 
        help="Directory containing workflow files (default: .github/workflows)"
    )
    args = parser.parse_args()
    
    validator = WorkflowValidator(args.workflows_dir)
    success = validator.validate_all_workflows()
    validator.print_results()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()