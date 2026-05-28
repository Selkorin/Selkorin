#!/bin/bash

# 🚀 Quick Start Guide for Remote Support App on macOS
# This script will walk you through the setup process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

clear

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Remote Support Application - macOS Quick Start               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Step 1: Check Node.js
echo -e "${YELLOW}Step 1: Checking Node.js...${NC}"
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js not found${NC}"
    echo ""
    echo "Install Node.js 20.x using Homebrew:"
    echo -e "${BLUE}brew install node@20${NC}"
    echo ""
    echo "Or download from: ${BLUE}https://nodejs.org/${NC}"
    exit 1
fi

NODE_VERSION=$(node --version)
echo -e "${GREEN}✓ Node.js installed: ${NODE_VERSION}${NC}"
echo -e "${GREEN}✓ npm installed: $(npm --version)${NC}"
echo ""

# Step 2: Install dependencies
echo -e "${YELLOW}Step 2: Installing dependencies...${NC}"
if [ -d "node_modules" ]; then
    echo -e "${GREEN}✓ Dependencies already installed${NC}"
else
    echo "Running npm install..."
    npm install --legacy-peer-deps > /dev/null 2>&1
    echo -e "${GREEN}✓ Dependencies installed${NC}"
fi
echo ""

# Step 3: Setup database
echo -e "${YELLOW}Step 3: Setting up database...${NC}"
if [ -f "apps/server/dev.db" ]; then
    echo -e "${GREEN}✓ Database already exists${NC}"
else
    echo "Creating database..."
    npm run db:push --workspace=apps/server > /dev/null 2>&1
    echo -e "${GREEN}✓ Database created${NC}"
fi
echo ""

# Step 4: Show next steps
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}✓ All setup complete! Ready to launch.${NC}"
echo ""
echo -e "${YELLOW}To start the application:${NC}"
echo ""
echo -e "${BLUE}Option 1 - Automatic (Recommended):${NC}"
echo -e "  ${GREEN}./start-macos.sh${NC}"
echo ""
echo -e "${BLUE}Option 2 - Manual:${NC}"
echo "  Terminal 1 (Backend):"
echo -e "    ${GREEN}npm run dev --workspace=apps/server${NC}"
echo ""
echo "  Terminal 2 (Frontend):"
echo -e "    ${GREEN}npm run dev --workspace=apps/web${NC}"
echo ""
echo "  Then open in browser:"
echo -e "    ${GREEN}open http://localhost:5173${NC}"
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}💡 Tips:${NC}"
echo "  • The app will run on:"
echo "    Frontend: http://localhost:5173"
echo "    Backend:  http://localhost:3000"
echo ""
echo "  • To scan QR on mobile, ensure both devices are on same Wi-Fi"
echo ""
echo "  • For more info, see: MACOS_SETUP.md"
echo ""

# Ask if user wants to start now
read -p "Start application now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🚀 Launching application...${NC}"
    ./start-macos.sh
fi
