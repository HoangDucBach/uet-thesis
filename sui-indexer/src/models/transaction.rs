use chrono::{DateTime, Utc};
use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use crate::schema::transactions;

/// Transaction - 1:1 mapping with Sui Transaction
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable, AsChangeset)]
#[diesel(table_name = transactions)]
pub struct Transaction {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
    pub sender: String,
    pub gas_owner: Option<String>,
    pub gas_budget: i64,
    pub gas_price: i64,
    pub execution_status: String,
    pub gas_used: Option<i64>,
    pub timestamp_ms: i64,
    pub raw_transaction: JsonValue,
    pub raw_effects: Option<JsonValue>,
    pub created_at: DateTime<Utc>,
}

impl Transaction {
    pub fn new(tx_digest: String, checkpoint_sequence_number: i64, sender: String) -> Self {
        Self {
            tx_digest,
            checkpoint_sequence_number,
            sender,
            gas_owner: None,
            gas_budget: 0,
            gas_price: 0,
            execution_status: "pending".to_string(),
            gas_used: None,
            timestamp_ms: 0,
            raw_transaction: JsonValue::Null,
            raw_effects: None,
            created_at: Utc::now(),
        }
    }
}
