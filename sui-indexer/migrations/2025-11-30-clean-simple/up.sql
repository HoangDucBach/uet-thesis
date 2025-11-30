-- Clean 1:1 Sui Transaction Schema
-- No computed fields, no aggregators, pure data storage

-- =============================================================================
-- TRANSACTIONS TABLE (1:1 with Sui Transaction)
-- =============================================================================
CREATE TABLE IF NOT EXISTS transactions (
    -- Identity
    tx_digest TEXT PRIMARY KEY,
    checkpoint_sequence_number BIGINT NOT NULL,

    -- Sender
    sender TEXT NOT NULL,

    -- Gas Data
    gas_owner TEXT,
    gas_budget BIGINT NOT NULL,
    gas_price BIGINT NOT NULL,

    -- Execution
    execution_status TEXT NOT NULL,
    gas_used BIGINT,

    -- Timing
    timestamp_ms BIGINT NOT NULL,

    -- Raw Data (complete Sui transaction)
    raw_transaction JSONB NOT NULL,
    raw_effects JSONB,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    -- Indexes
    CONSTRAINT valid_gas_budget CHECK (gas_budget > 0),
    CONSTRAINT valid_gas_price CHECK (gas_price > 0)
);

CREATE INDEX IF NOT EXISTS idx_tx_checkpoint ON transactions(checkpoint_sequence_number);
CREATE INDEX IF NOT EXISTS idx_tx_sender ON transactions(sender);
CREATE INDEX IF NOT EXISTS idx_tx_timestamp ON transactions(timestamp_ms);
CREATE INDEX IF NOT EXISTS idx_tx_status ON transactions(execution_status);

-- =============================================================================
-- MOVE CALLS TABLE (1:1 with Sui Move Call)
-- =============================================================================
CREATE TABLE IF NOT EXISTS move_calls (
    id BIGSERIAL PRIMARY KEY,
    tx_digest TEXT NOT NULL REFERENCES transactions(tx_digest) ON DELETE CASCADE,

    -- Call identification
    package TEXT NOT NULL,
    module TEXT NOT NULL,
    function TEXT NOT NULL,

    -- Call data
    type_arguments JSONB,
    arguments JSONB,

    -- Index for queries
    UNIQUE(tx_digest, package, module, function, id)
);

CREATE INDEX IF NOT EXISTS idx_move_calls_tx ON move_calls(tx_digest);
CREATE INDEX IF NOT EXISTS idx_move_calls_package ON move_calls(package);
CREATE INDEX IF NOT EXISTS idx_move_calls_function ON move_calls(package, module, function);

-- =============================================================================
-- OBJECTS TABLE (1:1 with Sui Object References)
-- =============================================================================
CREATE TABLE IF NOT EXISTS objects (
    id BIGSERIAL PRIMARY KEY,
    tx_digest TEXT NOT NULL REFERENCES transactions(tx_digest) ON DELETE CASCADE,

    -- Object reference
    object_id TEXT NOT NULL,
    version BIGINT,
    digest TEXT,

    -- Object data
    object_type TEXT NOT NULL,
    owner JSONB,

    -- Raw object data
    raw_object JSONB
);

CREATE INDEX IF NOT EXISTS idx_objects_tx ON objects(tx_digest);
CREATE INDEX IF NOT EXISTS idx_objects_id ON objects(object_id);

-- =============================================================================
-- EVENTS TABLE (1:1 with Sui Events)
-- =============================================================================
CREATE TABLE IF NOT EXISTS events (
    id BIGSERIAL PRIMARY KEY,
    tx_digest TEXT NOT NULL REFERENCES transactions(tx_digest) ON DELETE CASCADE,

    -- Event data
    event_type TEXT NOT NULL,
    package TEXT NOT NULL,
    module TEXT NOT NULL,
    sender TEXT NOT NULL,

    -- Raw event
    raw_event JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_tx ON events(tx_digest);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_sender ON events(sender);
