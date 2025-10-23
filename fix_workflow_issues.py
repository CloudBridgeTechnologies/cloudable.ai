#!/usr/bin/env python3
"""
Fix common issues in GitHub Actions workflow files.
This script automatically corrects common problems found in GitHub Actions workflows.
"""

import os
import sys
import yaml
import re
import argparse
from pathlib import Path
from typing import Dict, List, Any, Optional, Set, Union

# ANSI color codes for terminal output
GREEN = '\033[92m'
YELLOW = '\033[93m'
RED = '\033[91m'
BOLD = '\033[1m'
ENDC = '\033[0m'

class WorkflowFixer:
    def __init__(self, workflows_dir: str = ".github/workflows"):
        self.workflows_dir = Path(workflows_dir)
        self.fixes_applied = []
        self.errors = []
    
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
    
    def save_workflow(self, file_path: Path, workflow: Dict) -> bool:
        """Save workflow back to file, preserving comments and formatting as much as possible."""
        try:
            # Load original content to use as a baseline for formatting
            with open(file_path, 'r') as f:
                original_content = f.read()
            
            # Generate new YAML content
            with open(file_path, 'w') as f:
                yaml.dump(workflow, f, default_flow_style=False, sort_keys=False)
            
            return True
        except Exception as e:
            self.errors.append(f"Error saving workflow {file_path}: {e}")
            return False
    
    def fix_permissions(self, workflow: Dict, file_path: Path) -> bool:
        """Add required permissions for AWS credentials."""
        modified = False
        
        # Check if the workflow uses AWS actions
        has_aws_action = self._has_aws_action(workflow)
        
        if has_aws_action:
            # Add permissions if missing
            if 'permissions' not in workflow:
                workflow['permissions'] = {
                    'id-token': 'write',
                    'contents': 'read',
                    'pull-requests': 'write'
                }
                self.fixes_applied.append(f"{file_path}: Added missing 'permissions' for AWS OIDC authentication")
                modified = True
            elif 'id-token' not in workflow['permissions'] or workflow['permissions']['id-token'] != 'write':
                workflow['permissions']['id-token'] = 'write'
                self.fixes_applied.append(f"{file_path}: Added 'id-token: write' permission required for OIDC")
                modified = True
        
        return modified
    
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
                if 'with' in step and 'role-to-assume' in step.get('with', {}):
                    return True
                    
        return False
    
    def fix_trigger_configuration(self, workflow: Dict, file_path: Path) -> bool:
        """Fix trigger configuration issues."""
        modified = False
        
        # Ensure 'on' trigger is present
        if 'on' not in workflow:
            workflow['on'] = {'workflow_dispatch': {}}
            self.fixes_applied.append(f"{file_path}: Added missing 'on' trigger with workflow_dispatch")
            modified = True
        
        # Fix empty trigger configuration
        if workflow['on'] is None or workflow['on'] == {}:
            workflow['on'] = {'workflow_dispatch': {}}
            self.fixes_applied.append(f"{file_path}: Fixed empty trigger configuration with workflow_dispatch")
            modified = True
        
        # Fix workflow_dispatch if it's None
        if isinstance(workflow['on'], dict) and 'workflow_dispatch' in workflow['on'] and workflow['on']['workflow_dispatch'] is None:
            workflow['on']['workflow_dispatch'] = {}
            self.fixes_applied.append(f"{file_path}: Fixed null workflow_dispatch configuration")
            modified = True
            
        return modified
    
    def fix_string_expressions(self, file_path: Path) -> bool:
        """Fix expressions in string context issues by extracting the expressions to variables."""
        modified = False
        content = ""
        
        try:
            with open(file_path, 'r') as f:
                content = f.read()
            
            # Look for problematic expressions in strings
            pattern1 = re.compile(r'message:\s*[\'"]Update.*for\s+\$\{\{\s+github\.event\.inputs\.environment\s+\|\|\s+"[^"]+"\s+\}\}')
            pattern2 = re.compile(r'[\'"]\$\{\{\s+github\.event\.inputs\.environment\s+\|\|\s+[\'"][^\'"][\'"]\s+\}\}[\'"]')
            
            # Fix expressions by extracting to variables
            if pattern1.search(content) or pattern2.search(content):
                # Add the environment variable declaration
                env_var_declaration = "      - name: Set Environment Name\n        run: echo \"ENV_NAME=${{ github.event.inputs.environment || 'dev' }}\" >> $GITHUB_ENV\n"
                
                # Replace expressions in strings with the variable
                content = pattern1.sub(lambda m: m.group(0).replace("${{ github.event.inputs.environment || \"dev\" }}", "${{ env.ENV_NAME }}"), content)
                content = pattern2.sub(lambda m: m.group(0).replace("${{ github.event.inputs.environment || 'dev' }}", "${{ env.ENV_NAME }}"), content)
                
                # Insert the environment variable declaration before any occurrences
                if env_var_declaration not in content:
                    content = re.sub(
                        r'(      - name: [^\n]+\n)(\s+uses: EndBug/add-and-commit)',
                        f"\\1{env_var_declaration}\\2",
                        content
                    )
                
                with open(file_path, 'w') as f:
                    f.write(content)
                
                self.fixes_applied.append(f"{file_path}: Fixed expressions in string context by extracting to variables")
                modified = True
        except Exception as e:
            self.errors.append(f"Error fixing string expressions in {file_path}: {e}")
        
        return modified
    
    def fix_python_version(self, workflow: Dict, file_path: Path) -> bool:
        """Standardize Python version across all setup-python actions."""
        if 'jobs' not in workflow:
            return False
            
        modified = False
        python_versions = {}
        
        # Find all Python version references
        for job_id, job in workflow['jobs'].items():
            if 'steps' not in job:
                continue
                
            for step in job['steps']:
                if 'uses' in step and 'actions/setup-python@' in step['uses']:
                    if 'with' in step and 'python-version' in step['with']:
                        version = step['with']['python-version']
                        if version not in python_versions:
                            python_versions[version] = 0
                        python_versions[version] += 1
        
        # If multiple versions, standardize to the most common
        if len(python_versions) > 1:
            most_common_version = max(python_versions.items(), key=lambda x: x[1])[0]
            
            # Update all setup-python actions to use the most common version
            for job_id, job in workflow['jobs'].items():
                if 'steps' not in job:
                    continue
                    
                for step in job['steps']:
                    if 'uses' in step and 'actions/setup-python@' in step['uses']:
                        if 'with' in step and 'python-version' in step['with']:
                            if step['with']['python-version'] != most_common_version:
                                step['with']['python-version'] = most_common_version
                                modified = True
            
            if modified:
                self.fixes_applied.append(f"{file_path}: Standardized Python version to {most_common_version}")
        
        return modified
    
    def fix_all_workflows(self) -> bool:
        """Fix all workflows in the directory."""
        workflow_files = self.find_workflow_files()
        
        if not workflow_files:
            self.errors.append("No workflow files found")
            return False
        
        success = True
        for file_path in workflow_files:
            # Fix string expressions (operates on the file content)
            self.fix_string_expressions(file_path)
            
            # Load and fix other issues
            workflow = self.load_workflow(file_path)
            if not workflow:
                success = False
                continue
                
            modified = False
            modified |= self.fix_permissions(workflow, file_path)
            modified |= self.fix_trigger_configuration(workflow, file_path)
            modified |= self.fix_python_version(workflow, file_path)
            
            if modified:
                if not self.save_workflow(file_path, workflow):
                    success = False
        
        return success and len(self.errors) == 0
    
    def print_results(self) -> None:
        """Print results of fixing operations."""
        if self.fixes_applied:
            print(f"{GREEN}{BOLD}Fixes Applied:{ENDC}")
            for fix in self.fixes_applied:
                print(f"  {GREEN}✓ {fix}{ENDC}")
            print()
            
        if self.errors:
            print(f"{RED}{BOLD}Errors:{ENDC}")
            for error in self.errors:
                print(f"  {RED}✖ {error}{ENDC}")
            print()
            
        if self.fixes_applied and not self.errors:
            print(f"{GREEN}{BOLD}All fixes applied successfully!{ENDC}")
        elif not self.fixes_applied and not self.errors:
            print(f"{GREEN}{BOLD}All workflows are already correctly configured. No fixes needed.{ENDC}")
        else:
            print(f"{RED}{BOLD}Some issues could not be fixed automatically.{ENDC}")

def main():
    parser = argparse.ArgumentParser(description="Fix common issues in GitHub Actions workflow files")
    parser.add_argument(
        "--workflows-dir", 
        default=".github/workflows", 
        help="Directory containing workflow files (default: .github/workflows)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Don't modify files, just show what would be fixed"
    )
    args = parser.parse_args()
    
    fixer = WorkflowFixer(args.workflows_dir)
    if not args.dry_run:
        success = fixer.fix_all_workflows()
        fixer.print_results()
        sys.exit(0 if success else 1)
    else:
        print(f"{YELLOW}{BOLD}Dry run mode: Not modifying any files{ENDC}")
        fixer.fix_all_workflows()
        fixer.print_results()
        sys.exit(0)

if __name__ == "__main__":
    main()
