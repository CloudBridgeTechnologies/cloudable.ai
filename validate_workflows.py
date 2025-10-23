#!/usr/bin/env python3
"""
Workflow Validation Script for Cloudable.AI

This script validates GitHub Actions workflows and ensures they are properly configured.
"""

import os
import sys
import yaml
import re


def validate_workflow_file(file_path):
    """Validate a single workflow file."""
    try:
        with open(file_path, 'r') as f:
            workflow = yaml.safe_load(f)
        
        errors = []
        warnings = []
        
        # Basic structure checks
        if 'name' not in workflow:
            errors.append(f"Missing workflow name in {file_path}")
        
        # Due to YAML parsing, 'on' might be interpreted as True instead of a dict
        if 'on' not in workflow:
            errors.append(f"Missing trigger configuration in {file_path}")
        
        if 'jobs' not in workflow:
            errors.append(f"Missing jobs configuration in {file_path}")
        elif not workflow['jobs']:
            errors.append(f"No jobs defined in {file_path}")
        
        # Check for AWS credentials usage
        if has_aws_credentials_step(workflow):
            if not has_aws_permissions(workflow):
                errors.append(f"Uses AWS credentials but missing id-token permissions in {file_path}")
        
        # Check for GitHub token usage
        if has_github_token_usage(workflow):
            if not has_contents_permissions(workflow):
                warnings.append(f"Uses GitHub token but may not have proper permissions in {file_path}")
        
        # Check for proper Python version
        if has_python_setup(workflow) and not has_valid_python_version(workflow):
            warnings.append(f"Uses Python version 3.12 which might have compatibility issues in {file_path}")
        
        # Check for external action versions
        if has_outdated_actions(workflow):
            warnings.append(f"Uses potentially outdated actions in {file_path}")
        
        return {
            "file": file_path,
            "valid": len(errors) == 0,
            "errors": errors,
            "warnings": warnings
        }
        
    except Exception as e:
        return {
            "file": file_path,
            "valid": False,
            "errors": [f"Failed to parse workflow file: {str(e)}"],
            "warnings": []
        }

def has_aws_credentials_step(workflow):
    """Check if workflow uses AWS credentials steps."""
    for job_name, job in workflow.get('jobs', {}).items():
        for step in job.get('steps', []):
            if 'uses' in step and 'aws-actions/configure-aws-credentials' in step['uses']:
                return True
    return False

def has_aws_permissions(workflow):
    """Check if workflow has AWS permissions."""
    permissions = workflow.get('permissions', {})
    return isinstance(permissions, dict) and permissions.get('id-token') in ['write', True]

def has_github_token_usage(workflow):
    """Check if workflow uses GitHub token."""
    for job_name, job in workflow.get('jobs', {}).items():
        for step in job.get('steps', []):
            if 'uses' in step and ('actions/github-script' in step['uses'] or 'EndBug/add-and-commit' in step['uses']):
                return True
            if 'env' in step and any('GITHUB_TOKEN' in env for env in step['env'].keys()):
                return True
    return False

def has_contents_permissions(workflow):
    """Check if workflow has contents permissions."""
    permissions = workflow.get('permissions', {})
    return isinstance(permissions, dict) and permissions.get('contents') in ['write', 'read', True]

def has_python_setup(workflow):
    """Check if workflow sets up Python."""
    for job_name, job in workflow.get('jobs', {}).items():
        for step in job.get('steps', []):
            if 'uses' in step and 'actions/setup-python' in step['uses']:
                return True
    return False

def has_valid_python_version(workflow):
    """Check if workflow uses a valid Python version."""
    env_python_version = workflow.get('env', {}).get('PYTHON_VERSION')
    if env_python_version and env_python_version == '3.12':
        return False
    
    for job_name, job in workflow.get('jobs', {}).items():
        for step in job.get('steps', []):
            if 'uses' in step and 'actions/setup-python' in step['uses']:
                if 'with' in step and 'python-version' in step['with']:
                    if step['with']['python-version'] == '3.12':
                        return False
    return True

def has_outdated_actions(workflow):
    """Check if workflow uses potentially outdated actions."""
    for job_name, job in workflow.get('jobs', {}).items():
        for step in job.get('steps', []):
            if 'uses' in step:
                # Check if using non-versioned actions
                if not re.search(r'@v\d+', step['uses']):
                    return True
                # Check for very old versions
                match = re.search(r'@v(\d+)', step['uses'])
                if match and int(match.group(1)) < 2:
                    return True
    return False

def validate_all_workflows(workflows_dir='.github/workflows'):
    """Validate all workflow files in the given directory."""
    workflow_files = []
    for file in os.listdir(workflows_dir):
        if file.endswith('.yml') or file.endswith('.yaml'):
            workflow_files.append(os.path.join(workflows_dir, file))
    
    results = []
    for file in workflow_files:
        results.append(validate_workflow_file(file))
    
    return results

def print_validation_results(results):
    """Print validation results in a readable format."""
    print("=== GitHub Actions Workflow Validation ===\n")
    
    valid_count = len([r for r in results if r['valid']])
    total_count = len(results)
    
    print(f"Validated {total_count} workflow files, {valid_count} valid, {total_count - valid_count} with errors\n")
    
    for result in results:
        file_name = os.path.basename(result['file'])
        status = "✅ VALID" if result['valid'] else "❌ INVALID"
        print(f"{status} - {file_name}")
        
        if result['errors']:
            print("  Errors:")
            for error in result['errors']:
                print(f"  - {error}")
        
        if result['warnings']:
            print("  Warnings:")
            for warning in result['warnings']:
                print(f"  - {warning}")
        
        print("")
    
    if valid_count == total_count:
        print("All workflows are valid! 🎉")
    else:
        print(f"{total_count - valid_count} workflows have errors that need to be fixed.")

def check_workflow_dependencies(workflows_dir='.github/workflows'):
    """Check dependencies between workflows."""
    workflow_mapping = {}
    dependent_workflows = {}
    
    # First pass: gather workflow names
    for file in os.listdir(workflows_dir):
        if file.endswith('.yml') or file.endswith('.yaml'):
            try:
                with open(os.path.join(workflows_dir, file), 'r') as f:
                    workflow = yaml.safe_load(f)
                    if 'name' in workflow:
                        workflow_mapping[workflow['name']] = file
            except Exception:
                pass
    
    # Second pass: check for dependencies
    for file in os.listdir(workflows_dir):
        if file.endswith('.yml') or file.endswith('.yaml'):
            try:
                with open(os.path.join(workflows_dir, file), 'r') as f:
                    workflow = yaml.safe_load(f)
                    workflow_name = workflow.get('name', file)
                    
                    # Check workflow_run triggers
                    workflow_run = workflow.get('on', {}).get('workflow_run', {})
                    if workflow_run:
                        workflows = workflow_run.get('workflows', [])
                        if not isinstance(workflows, list):
                            workflows = [workflows]
                        
                        for dependent in workflows:
                            if dependent not in dependent_workflows:
                                dependent_workflows[dependent] = []
                            dependent_workflows[dependent].append(workflow_name)
            except Exception:
                pass
    
    print("\n=== Workflow Dependencies ===\n")
    
    for workflow_name, dependents in dependent_workflows.items():
        if workflow_name in workflow_mapping:
            print(f"Workflow '{workflow_name}' ({workflow_mapping[workflow_name]}):")
            print(f"  Triggers workflows: {', '.join(dependents)}")
        else:
            print(f"❌ WARNING: Workflow '{workflow_name}' is referenced but not found!")
    
    print("")

if __name__ == "__main__":
    workflows_dir = '.github/workflows'
    if not os.path.exists(workflows_dir):
        print(f"Workflows directory '{workflows_dir}' not found!")
        sys.exit(1)
    
    results = validate_all_workflows(workflows_dir)
    print_validation_results(results)
    check_workflow_dependencies(workflows_dir)
    
    # Exit with non-zero code if any workflow has errors
    if any(not result['valid'] for result in results):
        sys.exit(1)
