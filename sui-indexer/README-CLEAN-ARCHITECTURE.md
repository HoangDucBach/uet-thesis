# Clean Data Architecture - Implementation Guide

## Overview

This implementation provides a comprehensive, clean data architecture for Sui blockchain transaction analysis with **NO detection logic** - only pure data modeling and framework structure.

## Architecture Components

### 1. PostgreSQL Schema (Source of Truth)

#### Core Tables:
- **transactions**: Main transaction data with comprehensive metadata
- **move_calls**: Detailed Move function calls (normalized)
- **transaction_objects**: Objects involved in transactions
- **transaction_effects**: Transaction execution effects (balance changes, object mutations, events)
- **detection_results**: Storage for future detection engine results

#### Database Features:
- Full JSONB support for raw transaction data preservation
- Comprehensive indexing for performance
- Foreign key relationships with CASCADE delete
- Views for common query patterns
- Time-series optimizations ready

### 2. Rust Models

#### Domain Models (`src/models/`):
- `transaction.rs`: Core transaction model
- `move_call.rs`: Move function call data
- `transaction_object.rs`: Object interaction data
- `transaction_effect.rs`: Transaction effects data
- `elasticsearch.rs`: ES-optimized document structures
- `detection.rs`: Detection result models

#### Key Features:
- Full type safety with Diesel ORM
- Serde serialization support
- Builder patterns for complex structures
- Comprehensive validation

### 3. Data Services (`src/services/`)

#### Transaction Extractor:
Extracts structured data from Sui RPC JSON responses:
```rust
use crate::services::SuiTransactionExtractor;

let transaction = SuiTransactionExtractor::extract_transaction(&tx_data, checkpoint, timestamp)?;
let move_calls = SuiTransactionExtractor::extract_move_calls(&tx_data)?;
let objects = SuiTransactionExtractor::extract_transaction_objects(&tx_data)?;
let effects = SuiTransactionExtractor::extract_transaction_effects(&tx_data)?;
```

#### Elasticsearch Transformer:
Transforms PostgreSQL data to Elasticsearch-optimized documents:
```rust
use crate::services::ElasticsearchTransformer;

let es_doc = ElasticsearchTransformer::transform_transaction(
    &transaction,
    &move_calls,
    &objects,
    &effects,
)?;
```

### 4. Detection Framework (`src/framework/`)

#### Detection Engine Interface:
```rust
use crate::framework::{DetectionEngine, DetectionPipeline};

#[async_trait]
impl DetectionEngine for MyDetector {
    async fn detect(&self, transaction: &Transaction) -> DetectionResults {
        // Your detection logic here
    }

    fn engine_name(&self) -> &'static str {
        "my_detector"
    }

    fn supported_attack_types(&self) -> Vec<&'static str> {
        vec!["flash_loan_attack", "reentrancy"]
    }
}

// Use in pipeline
let pipeline = DetectionPipeline::new()
    .add_engine(Box::new(MyDetector::new()));

let results = pipeline.process_transaction(&tx).await;
```

#### Action Manager:
```rust
use crate::framework::{Action, ActionManager, ActionCondition, DetectionSeverity};

#[async_trait]
impl Action for MyAction {
    async fn execute(&self, detection: &DetectionResult) -> ActionResult {
        // Your action logic here
    }

    fn action_name(&self) -> &'static str {
        "my_action"
    }

    fn trigger_conditions(&self) -> Vec<ActionCondition> {
        vec![
            ActionCondition::new()
                .with_min_severity(DetectionSeverity::High)
                .with_min_confidence(0.8)
        ]
    }
}
```

### 5. Elasticsearch Index Mapping

See `elasticsearch-mapping.json` for the complete index configuration.

#### Key Features:
- Flattened arrays for fast searching
- Nested objects for complex queries
- Time-based fields for aggregations
- Keyword + text dual indexing for addresses
- Optimized field limits and result windows

## Database Migration

Run migrations to set up the database schema:

```bash
# Using diesel CLI
diesel migration run

# Or manually apply
psql -U postgres -d sui_indexer < migrations/2025-11-30-clean-architecture/up.sql
```

## Elasticsearch Setup

Create the index with proper mapping:

```bash
curl -X PUT "localhost:9200/sui_transactions" \
  -H 'Content-Type: application/json' \
  -d @elasticsearch-mapping.json
```

## Usage Examples

### 1. Extract and Store Transaction

```rust
use sui_indexer::services::SuiTransactionExtractor;
use diesel::prelude::*;

// Get transaction from Sui RPC
let tx_json = sui_client.get_transaction(&digest).await?;

// Extract structured data
let transaction = SuiTransactionExtractor::extract_transaction(
    &tx_json,
    checkpoint,
    timestamp_ms,
)?;

let move_calls = SuiTransactionExtractor::extract_move_calls(&tx_json)?;
let objects = SuiTransactionExtractor::extract_transaction_objects(&tx_json)?;
let effects = SuiTransactionExtractor::extract_transaction_effects(&tx_json)?;

// Store in PostgreSQL
diesel::insert_into(transactions::table)
    .values(&transaction)
    .execute(&mut conn)?;

diesel::insert_into(move_calls::table)
    .values(&move_calls)
    .execute(&mut conn)?;

// ... store other data
```

### 2. Transform to Elasticsearch

```rust
use sui_indexer::services::ElasticsearchTransformer;

// Load from PostgreSQL
let transaction = transactions::table
    .filter(transactions::tx_digest.eq(&digest))
    .first::<Transaction>(&mut conn)?;

let move_calls = move_calls::table
    .filter(move_calls::tx_digest.eq(&digest))
    .load::<MoveCall>(&mut conn)?;

// Transform to ES document
let es_doc = ElasticsearchTransformer::transform_transaction(
    &transaction,
    &move_calls,
    &objects,
    &effects,
)?;

// Index in Elasticsearch
let response = es_client
    .index(IndexParts::IndexId("sui_transactions", &digest))
    .body(es_doc)
    .send()
    .await?;
```

### 3. Build Detection Pipeline

```rust
use sui_indexer::framework::{
    DetectionPipeline,
    ActionManager,
    LogAction,
    SlackNotificationAction,
    DetectionSeverity,
};

// Create detection pipeline
let pipeline = DetectionPipeline::new()
    .add_engine(Box::new(MyFlashLoanDetector::new()))
    .add_engine(Box::new(MyReentrancyDetector::new()));

// Create action manager
let actions = ActionManager::new()
    .add_action(Box::new(LogAction))
    .add_action(Box::new(SlackNotificationAction::new(
        webhook_url,
        DetectionSeverity::High,
    )));

// Process transaction
let detection_results = pipeline.process_transaction(&tx).await;

for results in detection_results {
    for detection in results.results {
        let action_results = actions.execute_actions(&detection).await;
        // Handle action results...
    }
}
```

## Data Flow

```
Sui RPC JSON
     ↓
SuiTransactionExtractor
     ↓
PostgreSQL (transactions + related tables)
     ↓
ElasticsearchTransformer
     ↓
Elasticsearch (search-optimized documents)
     ↓
DetectionPipeline
     ↓
ActionManager
```

## Performance Considerations

### PostgreSQL:
- Indexes on all foreign keys
- GIN indexes for JSONB queries
- Partitioning ready for time-series data
- Connection pooling with bb8

### Elasticsearch:
- 3 shards for horizontal scaling
- 10s refresh interval for near real-time
- Keyword fields for exact matching
- Text fields for full-text search
- Nested objects for complex queries

### Detection Framework:
- Async/await throughout
- Parallel engine execution ready
- Conditional action triggering
- Performance metrics tracking

## Testing

Run the comprehensive test suite:

```bash
cargo test
```

Tests cover:
- Model serialization/deserialization
- Data extraction from Sui JSON
- Elasticsearch transformation
- Detection pipeline
- Action manager
- Condition triggering

## Next Steps

1. **Implement Detection Engines**: Create concrete detection engines by implementing the `DetectionEngine` trait
2. **Add Custom Actions**: Implement custom actions (Slack, email, database alerts) by implementing the `Action` trait
3. **Scale Elasticsearch**: Configure sharding and replication based on data volume
4. **Optimize Queries**: Add application-specific indexes based on query patterns
5. **Monitor Performance**: Add metrics collection and monitoring

## Benefits of This Architecture

✅ **Clean Separation**: Data modeling separate from detection logic
✅ **Type Safety**: Full Rust type system enforcement
✅ **Extensible**: Easy to add new detection engines and actions
✅ **Testable**: Comprehensive test coverage
✅ **Performant**: Optimized for both PostgreSQL and Elasticsearch
✅ **Production Ready**: Error handling, logging, and monitoring hooks
✅ **Framework Ready**: Interfaces for detection engines and actions

## License

[Your License Here]
