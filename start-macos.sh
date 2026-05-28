#!/bin/bash

# Remote Support Application Launcher for macOS

echo "🚀 Starting Remote Support Application..."
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js 20.x or later."
    exit 1
fi

echo "${BLUE}✓ Node.js version:${NC} $(node --version)"
echo "${BLUE}✓ npm version:${NC} $(npm --version)"
echo ""

# Kill any existing processes on port 3000 and 5173
echo "🔧 Cleaning up ports..."
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
lsof -ti:5173 | xargs kill -9 2>/dev/null || true
sleep 1

echo ""
echo "${GREEN}Starting both servers...${NC}"
echo ""
echo "${YELLOW}📦 Backend server${NC} will run on: http://localhost:3000"
echo "${YELLOW}🌐 Frontend server${NC} will run on: http://localhost:5173"
echo ""

# Start backend and frontend in parallel
npm run dev &

# Wait for services to start
echo "⏳ Waiting for servers to start..."
sleep 10

# Check if backend is running
if nc -z localhost 3000 2>/dev/null; then
    echo "${GREEN}✓ Backend is running on http://localhost:3000${NC}"
else
    echo "${YELLOW}⚠ Backend might still be starting...${NC}"
fi

# Check if frontend is running
if nc -z localhost 5173 2>/dev/null; then
    echo "${GREEN}✓ Frontend is running on http://localhost:5173${NC}"
    # Open frontend in default browser
    echo ""
    echo "${BLUE}Opening application in browser...${NC}"
    open http://localhost:5173
else
    echo "${YELLOW}⚠ Frontend might still be starting...${NC}"
fi

echo ""
echo "${GREEN}✅ Application is ready!${NC}"
echo ""
echo "📱 To join from a mobile device:"
echo "   1. Open the app in your browser at http://localhost:5173"
echo "   2. Click 'Create QR' button"
echo "   3. Scan the QR code from your phone"
echo "   4. Confirm on your device"
echo ""
echo "Press Ctrl+C to stop all servers"
echo ""

wait
