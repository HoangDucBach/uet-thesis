use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
use sui_indexer_alt_framework::FieldCount;
use crate::schema::{transaction_digests, transactions};

#[derive(Insertable, Debug, Clone, FieldCount)]
#[diesel(table_name = transaction_digests)]
pub struct StoredTransactionDigest {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
}

#[derive(Insertable, Queryable, Serialize, Deserialize, Debug, Clone, FieldCount)]
#[diesel(table_name = transactions)]
pub struct Transaction {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
    pub sender: Option<String>,
    pub gas_budget: Option<i64>,
    pub gas_used: Option<i64>,
    pub execution_status: String,
    pub timestamp_ms: Option<i64>,
    pub transaction_data: Option<JsonValue>,
}
