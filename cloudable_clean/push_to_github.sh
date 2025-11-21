#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if GitHub repo URL is provided
if [ -z "$1" ]; then
  echo -e "${RED}Error: GitHub repository URL is required.${NC}"
  echo -e "${YELLOW}Usage: ./push_to_github.sh <github-repo-url>${NC}"
  exit 1
fi

GITHUB_REPO_URL=$1

# Run cleanup script first
echo -e "${YELLOW}Running repository cleanup...${NC}"
chmod +x prepare_for_github.sh
./prepare_for_github.sh

# Navigate to the cleaned directory
echo -e "${YELLOW}Navigating to cleaned repository directory...${NC}"
cd cloudable_clean

# Initialize git repository
echo -e "${YELLOW}Initializing git repository...${NC}"
git init

# Add all files
echo -e "${YELLOW}Adding files to git...${NC}"
git add .

# Commit changes
echo -e "${YELLOW}Committing files...${NC}"
git commit -m "Initial commit of Cloudable.AI project"

# Add remote origin
echo -e "${YELLOW}Adding remote origin...${NC}"
git remote add origin $GITHUB_REPO_URL

# Push to GitHub
echo -e "${YELLOW}Pushing to GitHub...${NC}"
git push -u origin main || git push -u origin master

echo -e "${GREEN}Successfully pushed to GitHub!${NC}"
