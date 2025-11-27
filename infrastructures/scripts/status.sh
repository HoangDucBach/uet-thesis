#!/bin/bash

# ===========================================
# Check Infrastructure Services Status
# ===========================================

set -e

echo "📊 Sui Indexer Infrastructure Status"
echo "===================================="
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

# Go to infrastructure directory
cd "$(dirname "$0")/.."

# Show container status
echo "🐳 Container Status:"
$DOCKER_COMPOSE ps
echo ""

# Test PostgreSQL
echo "🔍 Testing PostgreSQL..."
if docker exec sui_postgres pg_isready -U postgres &> /dev/null; then
    echo "   ✅ PostgreSQL is healthy"
else
    echo "   ❌ PostgreSQL is not responding"
fi

# Test Elasticsearch
echo "🔍 Testing Elasticsearch..."
if curl -s http://localhost:9200/_cluster/health &> /dev/null; then
    echo "   ✅ Elasticsearch is healthy"
else
    echo "   ❌ Elasticsearch is not responding"
fi

# Test Redis
echo "🔍 Testing Redis..."
if docker exec sui_redis redis-cli -a Admin2025@ ping &> /dev/null 2>&1; then
    echo "   ✅ Redis is healthy"
else
    echo "   ❌ Redis is not responding"
fi

# Test Kibana
echo "🔍 Testing Kibana..."
if curl -s http://localhost:5601/api/status &> /dev/null; then
    echo "   ✅ Kibana is healthy"
else
    echo "   ❌ Kibana is not responding"
fi

echo ""
echo "===================================="
