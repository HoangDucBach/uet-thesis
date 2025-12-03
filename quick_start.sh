#!/bin/bash
# Quick Start Script for DeFi Attack Detection System
set -e

echo "🚀 DeFi Attack Detection System - Quick Start"
echo "=============================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running in correct directory
if [ ! -d "sui-indexer" ] || [ ! -d "contracts" ]; then
    echo -e "${RED}❌ Error: Must run from project root directory${NC}"
    exit 1
fi

echo "📋 Checking prerequisites..."

# Check PostgreSQL
if command -v psql &> /dev/null; then
    echo -e "${GREEN}✓${NC} PostgreSQL installed"
else
    echo -e "${YELLOW}⚠${NC}  PostgreSQL not found. Install: sudo apt install postgresql"
fi

# Check Elasticsearch
if curl -s http://localhost:9200 &> /dev/null; then
    echo -e "${GREEN}✓${NC} Elasticsearch running"
else
    echo -e "${YELLOW}⚠${NC}  Elasticsearch not running. Starting with Docker..."
    docker run --name sui-elasticsearch \
      -e "discovery.type=single-node" \
      -e "xpack.security.enabled=false" \
      -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
      -p 9200:9200 \
      -p 9300:9300 \
      -d elasticsearch:8.11.0 2>/dev/null || echo "Docker not available"
fi

# Check Sui CLI
if command -v sui &> /dev/null; then
    echo -e "${GREEN}✓${NC} Sui CLI installed"
else
    echo -e "${RED}❌${NC} Sui CLI not found. Install from: https://docs.sui.io/build/install"
    exit 1
fi

# Check Rust/Cargo
if command -v cargo &> /dev/null; then
    echo -e "${GREEN}✓${NC} Rust/Cargo installed"
else
    echo -e "${RED}❌${NC} Rust not found. Install from: https://rustup.rs"
    exit 1
fi

echo ""
echo "📦 Setting up environment..."

# Create .env for sui-indexer if not exists
if [ ! -f "sui-indexer/.env" ]; then
    echo "Creating sui-indexer/.env..."
    cat > sui-indexer/.env << 'EOF'
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/sui_indexer
ELASTICSEARCH_URL=http://localhost:9200
ELASTICSEARCH_INDEX=sui-transactions
SIMULATION_PACKAGE_ID=0x18f41d08c00001b0295bcbd810e600354a84eb48bc534fbea47fa318257af7e2
SUI_RPC_URL=https://fullnode.testnet.sui.io:443
RUST_LOG=info
EOF
    echo -e "${GREEN}✓${NC} Created sui-indexer/.env"
else
    echo -e "${GREEN}✓${NC} sui-indexer/.env already exists"
fi

# Setup PostgreSQL database
echo ""
echo "🗄️  Setting up PostgreSQL..."
echo "Enter PostgreSQL password (default: postgres):"
read -s PG_PASSWORD
PG_PASSWORD=${PG_PASSWORD:-postgres}

# Try to create database
PGPASSWORD=$PG_PASSWORD psql -U postgres -h localhost -c "CREATE DATABASE sui_indexer;" 2>/dev/null || echo "Database may already exist"
echo -e "${GREEN}✓${NC} PostgreSQL database ready"

# Update .env with correct password
sed -i "s|postgres:postgres@|postgres:${PG_PASSWORD}@|g" sui-indexer/.env

# Run migrations
echo ""
echo "🔧 Running database migrations..."
cd sui-indexer
diesel migration run || cargo install diesel_cli --no-default-features --features postgres && diesel migration run
cd ..
echo -e "${GREEN}✓${NC} Migrations complete"

# Build indexer
echo ""
echo "🏗️  Building sui-indexer..."
cd sui-indexer
cargo build --release
cd ..
echo -e "${GREEN}✓${NC} Build complete"

echo ""
echo "=============================================="
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "📝 Next steps:"
echo ""
echo "1. Start the indexer:"
echo "   cd sui-indexer"
echo "   cargo run --release"
echo ""
echo "2. In another terminal, run test scenarios:"
echo "   cd contracts/scripts"
echo "   ./test_flash_loan_attack.sh"
echo ""
echo "3. View detection results in the indexer terminal"
echo ""
echo "📚 Full guide: SETUP_GUIDE.md"
echo "📊 Detection docs: sui-indexer/DETECTION.md"
echo ""
