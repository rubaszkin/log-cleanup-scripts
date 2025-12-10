#!/bin/bash

#############################################
# GitHub Setup Automation Script
# Automatically creates and pushes to GitHub
#############################################

set -e  # Exit on any error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_NAME="log-cleanup-scripts"
REPO_DESCRIPTION="Intelligent log cleanup scripts with automatic Force Mode for critical disk usage"
REPO_VISIBILITY="public"  # Change to "private" if you want

echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    GitHub Repository Setup Automation           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "clean_logs_advanced.sh" ]; then
    echo -e "${RED}Error: clean_logs_advanced.sh not found!${NC}"
    echo "Please run this script from the directory containing your log cleanup scripts."
    exit 1
fi

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command_exists git; then
    echo -e "${RED}Error: git is not installed${NC}"
    echo "Install with: sudo apt install git"
    exit 1
fi

if ! command_exists gh; then
    echo -e "${YELLOW}GitHub CLI (gh) not found. Installing...${NC}"
    echo -e "${BLUE}Choose your installation method:${NC}"
    echo "1) Install GitHub CLI now (requires sudo)"
    echo "2) Manual setup without GitHub CLI"
    echo "3) Exit and install manually"
    read -p "Choice [1/2/3]: " install_choice
    
    case $install_choice in
        1)
            if command_exists apt; then
                sudo apt update && sudo apt install -y gh
            elif command_exists dnf; then
                sudo dnf install -y gh
            elif command_exists yum; then
                sudo yum install -y gh
            else
                echo -e "${RED}Cannot auto-install. Please install manually.${NC}"
                exit 1
            fi
            ;;
        2)
            USE_MANUAL_METHOD=true
            ;;
        3)
            echo "Exiting. Install gh with:"
            echo "  Ubuntu/Debian: sudo apt install gh"
            echo "  Fedora: sudo dnf install gh"
            exit 0
            ;;
    esac
fi

echo -e "${GREEN}✓ Prerequisites checked${NC}"
echo ""

# Get user information
echo -e "${YELLOW}Setting up Git configuration...${NC}"

# Check if git is configured
if [ -z "$(git config --global user.name)" ]; then
    read -p "Enter your name: " user_name
    git config --global user.name "$user_name"
else
    echo "Git user.name: $(git config --global user.name)"
fi

if [ -z "$(git config --global user.email)" ]; then
    read -p "Enter your email: " user_email
    git config --global user.email "$user_email"
else
    echo "Git user.email: $(git config --global user.email)"
fi

echo -e "${GREEN}✓ Git configured${NC}"
echo ""

# Initialize git repository
echo -e "${YELLOW}Initializing Git repository...${NC}"

if [ -d ".git" ]; then
    echo -e "${YELLOW}Git repository already exists${NC}"
else
    git init
    echo -e "${GREEN}✓ Git repository initialized${NC}"
fi
echo ""

# Create .gitignore
echo -e "${YELLOW}Creating .gitignore...${NC}"
cat > .gitignore << 'EOF'
# Log files
*.log

# Temporary files
*.tmp
*.swp
*~
.*.swp

# OS files
.DS_Store
Thumbs.db

# Editor files
.vscode/
.idea/
*.sublime-*

# Backup files
*.bak
*.backup
EOF

echo -e "${GREEN}✓ .gitignore created${NC}"
echo ""

# Add all files
echo -e "${YELLOW}Adding files to git...${NC}"
git add .

# Show what will be committed
echo ""
echo -e "${BLUE}Files to be committed:${NC}"
git status --short
echo ""

# Create commit
echo -e "${YELLOW}Creating commit...${NC}"
git commit -m "Initial commit: Log cleanup scripts with Force Mode v2.0

Features:
- Basic log cleanup script
- Advanced script with Force Mode for 95-100% disk usage
- Automatic escalation and emergency cleanup
- Large file truncation
- Package cache cleaning
- Comprehensive documentation suite

Includes:
- clean_logs.sh - Basic version
- clean_logs_advanced.sh - Advanced with Force Mode
- Complete documentation (README, FORCE_MODE, QUICK_REFERENCE)
- Usage examples and flowcharts
- GitHub setup guide"

echo -e "${GREEN}✓ Initial commit created${NC}"
echo ""

# Push to GitHub
if [ "$USE_MANUAL_METHOD" = true ]; then
    echo -e "${YELLOW}Manual GitHub Setup Required${NC}"
    echo ""
    echo "1. Go to: https://github.com/new"
    echo "2. Repository name: $REPO_NAME"
    echo "3. Description: $REPO_DESCRIPTION"
    echo "4. Choose Public or Private"
    echo "5. Do NOT initialize with README"
    echo "6. Click 'Create repository'"
    echo ""
    read -p "Press Enter after creating the repository on GitHub..."
    echo ""
    
    read -p "Enter your GitHub username: " github_username
    
    echo -e "${YELLOW}Adding remote and pushing...${NC}"
    git branch -M main
    git remote add origin "https://github.com/${github_username}/${REPO_NAME}.git"
    
    echo ""
    echo -e "${BLUE}Pushing to GitHub...${NC}"
    echo "You may be prompted for credentials."
    echo "Use Personal Access Token (not password):"
    echo "https://github.com/settings/tokens"
    echo ""
    
    git push -u origin main
    
else
    # Using GitHub CLI
    echo -e "${YELLOW}Authenticating with GitHub...${NC}"
    
    if ! gh auth status >/dev/null 2>&1; then
        echo "Please authenticate with GitHub:"
        gh auth login
    else
        echo -e "${GREEN}✓ Already authenticated${NC}"
    fi
    echo ""
    
    # Get GitHub username
    GITHUB_USER=$(gh api user --jq '.login')
    echo -e "${BLUE}GitHub user: ${GITHUB_USER}${NC}"
    echo ""
    
    # Create repository
    echo -e "${YELLOW}Creating GitHub repository...${NC}"
    
    if [ "$REPO_VISIBILITY" = "private" ]; then
        gh repo create "$REPO_NAME" --description "$REPO_DESCRIPTION" --private --source=. --remote=origin --push
    else
        gh repo create "$REPO_NAME" --description "$REPO_DESCRIPTION" --public --source=. --remote=origin --push
    fi
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Setup Complete! ✓                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# Get repository URL
if [ "$USE_MANUAL_METHOD" = true ]; then
    REPO_URL="https://github.com/${github_username}/${REPO_NAME}"
else
    REPO_URL=$(gh repo view --json url --jq '.url')
fi

echo -e "${BLUE}Your repository is now live!${NC}"
echo ""
echo -e "${YELLOW}Repository URL:${NC}"
echo "  $REPO_URL"
echo ""
echo -e "${YELLOW}Clone command:${NC}"
echo "  git clone $REPO_URL"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Visit: $REPO_URL"
echo "  2. Add topics: bash, log-management, devops, linux, automation"
echo "  3. Add a description if not set"
echo "  4. Create a release (optional): gh release create v2.0"
echo ""
echo -e "${YELLOW}Future updates:${NC}"
echo "  git add ."
echo "  git commit -m 'Your message'"
echo "  git push"
echo ""
echo -e "${GREEN}Happy coding! 🚀${NC}"
