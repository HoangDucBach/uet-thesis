-- PostgreSQL: Source of Truth - Minimal + Raw JSONB
-- Rust queries JSONB directly for complex detection

-- =============================================================================
-- TRANSACTIONS - Source of Truth
-- =============================================================================
CREATE TABLE IF NOT EXISTS transactions (
    -- Identity
    tx_digest TEXT PRIMARY KEY,
    checkpoint_sequence_number BIGINT NOT NULL,

    -- Basic metadata (for quick filters)
    sender TEXT NOT NULL,
    timestamp_ms BIGINT NOT NULL,
    execution_status TEXT NOT NULL,

    -- Raw Sui data (complete transaction)
    raw_transaction JSONB NOT NULL,
    raw_effects JSONB,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Minimal indexes
    CONSTRAINT valid_timestamp CHECK (timestamp_ms > 0)
);

CREATE INDEX idx_tx_checkpoint ON transactions(checkpoint_sequence_number);
CREATE INDEX idx_tx_sender ON transactions(sender);
CREATE INDEX idx_tx_timestamp ON transactions(timestamp_ms);
CREATE INDEX idx_tx_status ON transactions(execution_status);

-- GIN index for JSONB queries (Rust detection)
CREATE INDEX idx_tx_raw_transaction ON transactions USING GIN (raw_transaction);
CREATE INDEX idx_tx_raw_effects ON transactions USING GIN (raw_effects);

-- Example JSONB queries for Rust detection:
-- SELECT * FROM transactions WHERE raw_transaction @> '{"transaction":{"data":{"gasData":{"price": 1000}}}}';
-- SELECT * FROM transactions WHERE raw_effects @> '{"status":"failure"}';
