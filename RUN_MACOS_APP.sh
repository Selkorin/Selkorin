#!/bin/bash

# 🍎 Remote Support App - Native macOS Application Launcher

set -e

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Remote Support - Native macOS App                       ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js not found${NC}"
    echo "Install with: brew install node@20"
    exit 1
fi

echo -e "${GREEN}✓ Node.js $(node --version)${NC}"

# Kill old processes
echo ""
echo -e "${YELLOW}Cleaning up ports...${NC}"
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
lsof -ti:5173 | xargs kill -9 2>/dev/null || true
sleep 1

# Install dependencies
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    npm install --legacy-peer-deps > /dev/null 2>&1
fi

# Setup database
if [ ! -f "apps/server/dev.db" ]; then
    echo -e "${YELLOW}Setting up database...${NC}"
    npm run db:push --workspace=apps/server > /dev/null 2>&1
fi

echo ""
echo -e "${BLUE}Building application...${NC}"

# Build backend
echo -e "${YELLOW}Building backend...${NC}"
npm run build:server > /dev/null 2>&1

# Build electron
echo -e "${YELLOW}Building Electron...${NC}"
npm run build --workspace=electron > /dev/null 2>&1

echo ""
echo -e "${GREEN}✓ Build complete!${NC}"
echo ""
echo -e "${BLUE}Launching application...${NC}"
echo ""

# Run electron app
cd electron
npx electron dist/main.js

# Cleanup on exit
trap "kill %1" EXIT
