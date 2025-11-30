use chrono::{DateTime, Utc};
use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use crate::schema::transactions;

/// Transaction - PostgreSQL model (minimal + raw JSONB)
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable, AsChangeset)]
#[diesel(table_name = transactions)]
pub struct Transaction {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
    pub sender: String,
    pub timestamp_ms: i64,
    pub execution_status: String,
    pub raw_transaction: JsonValue,
    pub raw_effects: Option<JsonValue>,
    pub created_at: DateTime<Utc>,
}

impl Transaction {
    pub fn new(
        tx_digest: String,
        checkpoint_sequence_number: i64,
        sender: String,
        timestamp_ms: i64,
        raw_transaction: JsonValue,
    ) -> Self {
        Self {
            tx_digest,
            checkpoint_sequence_number,
            sender,
            timestamp_ms,
            execution_status: "pending".to_string(),
            raw_transaction,
            raw_effects: None,
            created_at: Utc::now(),
        }
    }
}