-- Clean Data Architecture Migration - Full Schema
-- Drop existing tables (clean slate)
DROP TABLE IF EXISTS transactions CASCADE;
DROP TABLE IF EXISTS transaction_digests CASCADE;

-- =============================================================================
-- CORE TRANSACTIONS TABLE
-- =============================================================================
CREATE TABLE transactions (
    -- Primary identifiers
    id BIGSERIAL PRIMARY KEY,
    tx_digest TEXT UNIQUE NOT NULL,
    checkpoint_sequence_number BIGINT NOT NULL,

    -- Basic transaction metadata
    sender TEXT NOT NULL,
    gas_owner TEXT, -- For sponsored transactions
    gas_budget BIGINT NOT NULL,
    gas_used BIGINT,
    gas_price BIGINT NOT NULL,
    execution_status TEXT NOT NULL, -- 'success', 'failure', 'invalid'
    timestamp_ms BIGINT NOT NULL,

    -- Transaction type classification (from Sui types)
    transaction_kind TEXT NOT NULL, -- 'ProgrammableTransaction', 'SystemTransaction'
    is_system_tx BOOLEAN NOT NULL DEFAULT FALSE,
    is_sponsored_tx BOOLEAN NOT NULL DEFAULT FALSE,
    is_end_of_epoch_tx BOOLEAN NOT NULL DEFAULT FALSE,

    -- Move calls summary (extracted from programmable transaction)
    total_move_calls INTEGER DEFAULT 0,
    total_input_objects INTEGER DEFAULT 0,
    total_shared_objects INTEGER DEFAULT 0,

    -- Gas and execution metrics
    computation_cost BIGINT,
    storage_cost BIGINT,
    storage_rebate BIGINT,

    -- Transaction expiration
    expiration_epoch BIGINT,

    -- Raw transaction data (full Sui transaction structure)
    raw_transaction_data JSONB NOT NULL,

    -- Metadata
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE,

    -- Constraints
    CONSTRAINT valid_gas_budget CHECK (gas_budget > 0),
    CONSTRAINT valid_gas_price CHECK (gas_price > 0),
    CONSTRAINT valid_timestamp CHECK (timestamp_ms > 0)
);

-- Indexes for common queries
CREATE INDEX idx_transactions_checkpoint ON transactions(checkpoint_sequence_number);
CREATE INDEX idx_transactions_sender ON transactions(sender);
CREATE INDEX idx_transactions_timestamp ON transactions(timestamp_ms);
CREATE INDEX idx_transactions_status ON transactions(execution_status);
CREATE INDEX idx_transactions_kind ON transactions(transaction_kind);
CREATE INDEX idx_transactions_system ON transactions(is_system_tx) WHERE is_system_tx = TRUE;
CREATE INDEX idx_transactions_sponsored ON transactions(is_sponsored_tx) WHERE is_sponsored_tx = TRUE;
CREATE INDEX idx_transactions_digest_btree ON transactions(tx_digest);

-- GIN index for JSONB queries
CREATE INDEX idx_transactions_raw_data ON transactions USING GIN (raw_transaction_data);

-- =============================================================================
-- MOVE CALLS TABLE (Normalized)
-- =============================================================================
CREATE TABLE move_calls (
    id BIGSERIAL PRIMARY KEY,
    tx_digest TEXT NOT NULL,
    call_sequence INTEGER NOT NULL, -- Order within transaction

    -- Move call details (from Sui TransactionDataAPI)
    package_id TEXT NOT NULL,
    module_name TEXT NOT NULL,
    function_name TEXT NOT NULL,
    type_arguments TEXT[], -- Array of type parameters

    -- Call metadata
    is_entry_function BOOLEAN DEFAULT FALSE,

    -- Raw arguments (preserved as JSON for exact reconstruction)
    arguments JSONB,

    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tx_digest, call_sequence),
    FOREIGN KEY (tx_digest) REFERENCES transactions(tx_digest) ON DELETE CASCADE
);

CREATE INDEX idx_move_calls_tx ON move_calls(tx_digest);
CREATE INDEX idx_move_calls_package ON move_calls(package_id);
CREATE INDEX idx_move_calls_module ON move_calls(module_name);
CREATE INDEX idx_move_calls_function ON move_calls(package_id, module_name, function_name);
CREATE INDEX idx_move_calls_full_name ON move_calls(package_id, module_name, function_name);

-- =============================================================================
-- TRANSACTION OBJECTS TABLE
-- =============================================================================
CREATE TABLE transaction_objects (
    id BIGSERIAL PRIMARY KEY,
    tx_digest TEXT NOT NULL,
    object_sequence INTEGER NOT NULL,

    -- Object reference details
    object_id TEXT NOT NULL,
    object_version BIGINT,
    object_digest TEXT,

    -- Object type and usage
    object_type TEXT NOT NULL, -- 'input', 'shared', 'receiving'
    object_kind TEXT, -- 'owned', 'shared', 'immutable'

    -- Ownership information
    owner_type TEXT, -- 'address', 'object', 'shared', 'immutable'
    owner_address TEXT,

    UNIQUE(tx_digest, object_sequence),
    FOREIGN KEY (tx_digest) REFERENCES transactions(tx_digest) ON DELETE CASCADE
);

CREATE INDEX idx_tx_objects_tx ON transaction_objects(tx_digest);
CREATE INDEX idx_tx_objects_id ON transaction_objects(object_id);
CREATE INDEX idx_tx_objects_type ON transaction_objects(object_type);
CREATE INDEX idx_tx_objects_kind ON transaction_objects(object_kind);
CREATE INDEX idx_tx_objects_owner ON transaction_objects(owner_address);

-- =============================================================================
-- TRANSACTION EFFECTS TABLE
-- =============================================================================
CREATE TABLE transaction_effects (
    id BIGSERIAL PRIMARY KEY,
    tx_digest TEXT NOT NULL,
    effect_sequence INTEGER NOT NULL,

    -- Effect type and details
    effect_type TEXT NOT NULL, -- 'object_creation', 'object_mutation', 'object_deletion', 'balance_change', 'event_emission'

    -- Object-related effects
    affected_object_id TEXT,
    object_type TEXT,

    -- Balance change effects
    coin_type TEXT,
    balance_change BIGINT, -- Can be negative
    owner_address TEXT,

    -- Event emission
    event_type TEXT,
    event_data JSONB,

    UNIQUE(tx_digest, effect_sequence),
    FOREIGN KEY (tx_digest) REFERENCES transactions(tx_digest) ON DELETE CASCADE
);

CREATE INDEX idx_tx_effects_tx ON transaction_effects(tx_digest);
CREATE INDEX idx_tx_effects_type ON transaction_effects(effect_type);
CREATE INDEX idx_tx_effects_object ON transaction_effects(affected_object_id);
CREATE INDEX idx_tx_effects_coin ON transaction_effects(coin_type);
CREATE INDEX idx_tx_effects_balance ON transaction_effects(balance_change) WHERE ABS(balance_change) > 1000000000;
CREATE INDEX idx_tx_effects_owner ON transaction_effects(owner_address);

-- =============================================================================
-- DETECTION RESULTS TABLE (for future use)
-- =============================================================================
CREATE TABLE detection_results (
    id BIGSERIAL PRIMARY KEY,
    tx_digest TEXT NOT NULL,
    engine_name TEXT NOT NULL,
    detection_id TEXT NOT NULL,

    -- Detection details
    attack_type TEXT NOT NULL,
    confidence DOUBLE PRECISION NOT NULL,
    severity TEXT NOT NULL, -- 'info', 'low', 'medium', 'high', 'critical'

    -- Evidence and metadata
    evidence TEXT[],
    metadata JSONB,

    -- Timestamps
    detected_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tx_digest) REFERENCES transactions(tx_digest) ON DELETE CASCADE
);

CREATE INDEX idx_detection_results_tx ON detection_results(tx_digest);
CREATE INDEX idx_detection_results_engine ON detection_results(engine_name);
CREATE INDEX idx_detection_results_attack_type ON detection_results(attack_type);
CREATE INDEX idx_detection_results_severity ON detection_results(severity);
CREATE INDEX idx_detection_results_confidence ON detection_results(confidence);
CREATE INDEX idx_detection_results_detected_at ON detection_results(detected_at);

-- =============================================================================
-- VIEWS FOR COMMON QUERIES
-- =============================================================================

-- Full transaction details view
CREATE VIEW v_transaction_full AS
SELECT
    t.*,
    COUNT(DISTINCT mc.id) as move_call_count,
    COUNT(DISTINCT to2.id) as object_count,
    COUNT(DISTINCT te.id) as effect_count
FROM transactions t
LEFT JOIN move_calls mc ON t.tx_digest = mc.tx_digest
LEFT JOIN transaction_objects to2 ON t.tx_digest = to2.tx_digest
LEFT JOIN transaction_effects te ON t.tx_digest = te.tx_digest
GROUP BY t.id;

-- Move calls with transaction context
CREATE VIEW v_move_calls_enriched AS
SELECT
    mc.*,
    t.sender,
    t.execution_status,
    t.timestamp_ms,
    t.checkpoint_sequence_number
FROM move_calls mc
JOIN transactions t ON mc.tx_digest = t.tx_digest;

-- Balance changes summary
CREATE VIEW v_balance_changes_summary AS
SELECT
    te.tx_digest,
    te.coin_type,
    te.owner_address,
    SUM(te.balance_change) as total_change,
    COUNT(*) as change_count,
    t.timestamp_ms,
    t.sender
FROM transaction_effects te
JOIN transactions t ON te.tx_digest = t.tx_digest
WHERE te.effect_type = 'balance_change'
GROUP BY te.tx_digest, te.coin_type, te.owner_address, t.timestamp_ms, t.sender;
