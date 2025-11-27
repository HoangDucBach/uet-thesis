#!/bin/bash

# ===========================================
# Start Infrastructure Services
# ===========================================

set -e

echo "🚀 Starting Sui Indexer Infrastructure..."
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is available
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
elif docker-compose version &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
else
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Check .env file
if [ ! -f .env ]; then
    echo "❌ .env file not found. Please create it from .env.example"
    exit 1
fi

echo "📋 Using: $DOCKER_COMPOSE"
echo ""

# Set vm.max_map_count for Elasticsearch (if needed)
if [ "$(uname)" == "Linux" ]; then
    CURRENT_MAP_COUNT=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
    if [ "$CURRENT_MAP_COUNT" -lt 262144 ]; then
        echo "⚙️  Setting vm.max_map_count for Elasticsearch..."
        sudo sysctl -w vm.max_map_count=262144 || true
    fi
fi

# Start services
echo "🐳 Starting Docker containers..."
$DOCKER_COMPOSE up -d

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 5

# Show status
echo ""
echo "📊 Services Status:"
$DOCKER_COMPOSE ps

echo ""
echo "✅ Infrastructure started successfully!"
echo ""
echo "🌐 Access Points:"
echo "   - PostgreSQL:     localhost:5432"
echo "   - Elasticsearch:  http://localhost:9200"
echo "   - Kibana:         http://localhost:5601"
echo "   - Redis:          localhost:6379"
echo ""
echo "📝 View logs: $DOCKER_COMPOSE logs -f"
echo "🛑 Stop services: $DOCKER_COMPOSE down"
