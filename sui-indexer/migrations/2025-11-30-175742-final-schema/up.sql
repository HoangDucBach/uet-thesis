-- Final Schema Migration - Sync with schema.rs
-- This migration creates the transactions table matching the current schema.rs

-- Drop existing tables if they exist (clean slate)
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS transaction_digests CASCADE;
DROP TABLE IF EXISTS move_calls CASCADE;
DROP TABLE IF EXISTS transaction_objects CASCADE;
DROP TABLE IF EXISTS objects CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS transaction_effects CASCADE;
DROP TABLE IF EXISTS detection_results CASCADE;

-- Drop views if they exist
DROP VIEW IF EXISTS v_transaction_full CASCADE;
DROP VIEW IF EXISTS v_move_calls_enriched CASCADE;
DROP VIEW IF EXISTS v_balance_changes_summary CASCADE;

-- =============================================================================
-- TRANSACTIONS TABLE - Matches schema.rs exactly
-- =============================================================================
CREATE TABLE transactions (
    -- Primary key (matches schema.rs: id -> Int8)
    id BIGSERIAL PRIMARY KEY,
    
    -- Transaction digest (unique, matches schema.rs: tx_digest -> Text)
    tx_digest TEXT UNIQUE NOT NULL,
    
    -- Checkpoint info (matches schema.rs: checkpoint_sequence_number -> Int8)
    checkpoint_sequence_number BIGINT NOT NULL,
    
    -- Sender (matches schema.rs: sender -> Text)
    sender TEXT NOT NULL,
    
    -- Timestamp (matches schema.rs: timestamp_ms -> Int8)
    timestamp_ms BIGINT NOT NULL,
    
    -- Execution status (matches schema.rs: execution_status -> Text)
    execution_status TEXT NOT NULL,
    
    -- Raw transaction data (matches schema.rs: raw_transaction -> Jsonb)
    raw_transaction JSONB NOT NULL,
    
    -- Raw effects (matches schema.rs: raw_effects -> Nullable<Jsonb>)
    raw_effects JSONB,
    
    -- Created timestamp (matches schema.rs: created_at -> Timestamptz)
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for common queries
CREATE INDEX idx_transactions_checkpoint ON transactions(checkpoint_sequence_number);
CREATE INDEX idx_transactions_sender ON transactions(sender);
CREATE INDEX idx_transactions_timestamp ON transactions(timestamp_ms);
CREATE INDEX idx_transactions_status ON transactions(execution_status);
CREATE INDEX idx_transactions_digest ON transactions(tx_digest);

-- GIN indexes for JSONB queries
CREATE INDEX idx_transactions_raw_transaction_gin ON transactions USING GIN (raw_transaction);
CREATE INDEX idx_transactions_raw_effects_gin ON transactions USING GIN (raw_effects);

