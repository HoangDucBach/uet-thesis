use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Elasticsearch document - flattened for search/aggregation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsTransaction {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
    #[serde(with = "chrono::serde::ts_milliseconds")]
    pub timestamp: DateTime<Utc>,

    pub sender: String,
    pub execution_status: String,

    pub gas: EsGas,
    pub move_calls: Vec<EsMoveCall>,
    pub objects: Vec<EsObject>,
    pub effects: EsEffects,
    pub events: Vec<EsEvent>,

    // Flattened for aggregation
    pub packages: Vec<String>,
    pub modules: Vec<String>,
    pub functions: Vec<String>,
    pub coin_types: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsGas {
    pub owner: String,
    pub budget: i64,
    pub price: i64,
    pub used: Option<i64>,
    pub computation_cost: Option<i64>,
    pub storage_cost: Option<i64>,
    pub storage_rebate: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsMoveCall {
    pub package: String,
    pub module: String,
    pub function: String,
    pub full_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsObject {
    pub object_id: String,
    #[serde(rename = "type")]
    pub object_type: String,
    pub owner: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsEffects {
    pub created_count: i32,
    pub mutated_count: i32,
    pub deleted_count: i32,
    pub balance_changes: Vec<EsBalanceChange>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsBalanceChange {
    pub coin_type: String,
    pub amount: i64,
    pub owner: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsEvent {
    #[serde(rename = "type")]
    pub event_type: String,
    pub package: String,
    pub module: String,
    pub sender: String,
}
