use chrono::{DateTime, Utc};
use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use crate::schema::transactions;

/// Core transaction model - comprehensive Sui transaction data
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable, AsChangeset)]
#[diesel(table_name = transactions)]
pub struct Transaction {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<i64>,
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,

    // Basic metadata
    pub sender: String,
    pub gas_owner: Option<String>,
    pub gas_budget: i64,
    pub gas_used: Option<i64>,
    pub gas_price: i64,
    pub execution_status: String,
    pub timestamp_ms: i64,

    // Transaction type (from Sui API)
    pub transaction_kind: String,
    pub is_system_tx: bool,
    pub is_sponsored_tx: bool,
    pub is_end_of_epoch_tx: bool,

    // Summary metrics
    pub total_move_calls: i32,
    pub total_input_objects: i32,
    pub total_shared_objects: i32,

    // Gas details
    pub computation_cost: Option<i64>,
    pub storage_cost: Option<i64>,
    pub storage_rebate: Option<i64>,

    // Expiration
    pub expiration_epoch: Option<i64>,

    // Raw data
    pub raw_transaction_data: JsonValue,

    // Metadata
    pub processed_at: DateTime<Utc>,
    pub updated_at: Option<DateTime<Utc>>,
}

/// Insertable transaction (without auto-generated fields)
#[derive(Debug, Clone, Serialize, Deserialize, Insertable)]
#[diesel(table_name = transactions)]
pub struct NewTransaction {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,

    pub sender: String,
    pub gas_owner: Option<String>,
    pub gas_budget: i64,
    pub gas_used: Option<i64>,
    pub gas_price: i64,
    pub execution_status: String,
    pub timestamp_ms: i64,

    pub transaction_kind: String,
    pub is_system_tx: bool,
    pub is_sponsored_tx: bool,
    pub is_end_of_epoch_tx: bool,

    pub total_move_calls: i32,
    pub total_input_objects: i32,
    pub total_shared_objects: i32,

    pub computation_cost: Option<i64>,
    pub storage_cost: Option<i64>,
    pub storage_rebate: Option<i64>,

    pub expiration_epoch: Option<i64>,

    pub raw_transaction_data: JsonValue,
}

impl Default for NewTransaction {
    fn default() -> Self {
        Self {
            tx_digest: String::new(),
            checkpoint_sequence_number: 0,
            sender: String::new(),
            gas_owner: None,
            gas_budget: 0,
            gas_used: None,
            gas_price: 0,
            execution_status: "pending".to_string(),
            timestamp_ms: 0,
            transaction_kind: "ProgrammableTransaction".to_string(),
            is_system_tx: false,
            is_sponsored_tx: false,
            is_end_of_epoch_tx: false,
            total_move_calls: 0,
            total_input_objects: 0,
            total_shared_objects: 0,
            computation_cost: None,
            storage_cost: None,
            storage_rebate: None,
            expiration_epoch: None,
            raw_transaction_data: JsonValue::Null,
        }
    }
}

/// Transaction execution status
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ExecutionStatus {
    Success,
    Failure,
    Invalid,
    Pending,
}

impl ExecutionStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            ExecutionStatus::Success => "success",
            ExecutionStatus::Failure => "failure",
            ExecutionStatus::Invalid => "invalid",
            ExecutionStatus::Pending => "pending",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s {
            "success" => ExecutionStatus::Success,
            "failure" => ExecutionStatus::Failure,
            "invalid" => ExecutionStatus::Invalid,
            _ => ExecutionStatus::Pending,
        }
    }
}

impl ToString for ExecutionStatus {
    fn to_string(&self) -> String {
        self.as_str().to_string()
    }
}
