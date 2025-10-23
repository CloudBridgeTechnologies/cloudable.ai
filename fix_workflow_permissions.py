#!/usr/bin/env python3
"""
Fix permissions in GitHub Actions workflow files
"""

import os
import yaml
import sys

# List of workflow files to fix
WORKFLOW_FILES = [
    '.github/workflows/terraform-deploy.yml',
    '.github/workflows/agent-core-monitoring.yml',
    '.github/workflows/aws-setup.yml',
    '.github/workflows/lambda-update.yml',
    '.github/workflows/api-test.yml'
]

def fix_workflow_file(file_path):
    """Fix permissions in a workflow file"""
    try:
        # Read the workflow file
        with open(file_path, 'r') as f:
            content = f.read()
            
        # Parse YAML
        workflow = yaml.safe_load(content)
        
        # Check if permissions exist
        if 'permissions' not in workflow:
            # Add permissions section after the "on" section
            lines = content.splitlines()
            insert_index = None
            
            # Find the line after the "on" section
            for i, line in enumerate(lines):
                if line.startswith('on:'):
                    # Find the end of the "on" section
                    j = i + 1
                    while j < len(lines) and (lines[j].startswith('  ') or not lines[j].strip()):
                        j += 1
                    insert_index = j
                    break
            
            if insert_index is not None:
                # Add permissions section
                permissions_lines = [
                    "",
                    "permissions:",
                    "  id-token: write  # Required for AWS credentials",
                    "  contents: read   # Required for checkout",
                    "  pull-requests: write  # Required for PR comments",
                    ""
                ]
                lines = lines[:insert_index] + permissions_lines + lines[insert_index:]
                
                # Write the updated content back
                with open(file_path, 'w') as f:
                    f.write('\n'.join(lines))
                
                print(f"✅ Fixed permissions in {file_path}")
            else:
                print(f"⚠️ Could not find insertion point in {file_path}")
        else:
            print(f"ℹ️ Permissions already exist in {file_path}")
    
    except Exception as e:
        print(f"❌ Error fixing {file_path}: {str(e)}")

def main():
    """Main function"""
    print("Fixing permissions in GitHub Actions workflow files...")
    
    for file_path in WORKFLOW_FILES:
        if os.path.exists(file_path):
            fix_workflow_file(file_path)
        else:
            print(f"❌ File not found: {file_path}")
    
    print("\nDone! Please run the validation script again to verify fixes.")

if __name__ == "__main__":
    main()
