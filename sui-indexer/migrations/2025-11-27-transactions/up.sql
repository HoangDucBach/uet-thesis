CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    tx_digest TEXT UNIQUE NOT NULL,
    checkpoint_sequence_number BIGINT NOT NULL,

    sender TEXT,
    gas_budget BIGINT,
    gas_used BIGINT,
    execution_status TEXT NOT NULL,
    timestamp_ms BIGINT,

    transaction_data JSONB,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT transactions_tx_digest_key UNIQUE (tx_digest)
);

CREATE INDEX IF NOT EXISTS idx_transactions_checkpoint ON transactions (checkpoint_sequence_number);
CREATE INDEX IF NOT EXISTS idx_transactions_sender ON transactions (sender);
CREATE INDEX IF NOT EXISTS idx_transactions_timestamp ON transactions (timestamp_ms);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions (execution_status);
CREATE INDEX IF NOT EXISTS idx_transactions_data_gin ON transactions USING GIN (transaction_data);
