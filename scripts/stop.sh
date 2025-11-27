#!/bin/bash

# ===========================================
# Stop Infrastructure Services
# ===========================================

set -e

echo "🛑 Stopping Sui Indexer Infrastructure..."
echo ""

# Check if Docker Compose is available
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif docker-compose version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "❌ Docker Compose is not installed."
    exit 1
fi

# Stop services
$DOCKER_COMPOSE down

echo ""
echo "✅ All services stopped successfully!"
echo ""
echo "💡 Tips:"
echo "   - To remove volumes: $DOCKER_COMPOSE down -v"
echo "   - To restart: ./scripts/start.sh"
