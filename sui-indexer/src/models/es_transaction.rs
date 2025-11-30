use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Elasticsearch document - flattened for search/aggregation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsTransaction {
    pub tx_digest: String,
    pub checkpoint_sequence_number: i64,
    pub timestamp_ms: DateTime<Utc>,

    pub sender: String,
    pub execution_status: String,
    
    // Transaction type information
    pub kind: String,
    pub is_system_tx: bool,
    pub is_sponsored_tx: bool,
    pub is_end_of_epoch_tx: bool,

    pub gas: EsGas,
    pub move_calls: Vec<EsMoveCall>,
    pub objects: Vec<EsObject>,
    pub effects: EsEffects,
    pub events: Vec<EsEvent>,

    // Flattened for aggregation
    pub packages: Vec<String>,
    pub modules: Vec<String>,
    pub functions: Vec<String>,
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
    pub all_changed_objects: Vec<EsChangedObject>,
    pub all_removed_objects: Vec<EsRemovedObject>,
}

/// Changed object with full state information from transaction effects
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsChangedObject {
    pub object_id: String,
    // Input state (before transaction) - from old_object_metadata or V2 input_state
    pub input_version: Option<u64>,
    pub input_digest: Option<String>,
    pub input_owner: Option<String>,
    pub input_state_type: String, // "Exist", "NotExist"
    // Output state (after transaction) - from all_changed_objects
    pub output_version: Option<u64>,
    pub output_digest: Option<String>,
    pub output_owner: Option<String>,
    pub output_state_type: String, // "Mutate", "Create", "Unwrap"
    // ID operation
    pub id_operation: String, // "None", "Created", "Mutated"
}

/// Removed object information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsRemovedObject {
    pub object_id: String,
    pub version: u64,
    pub digest: String,
    pub remove_kind: String, // "Wrap", "Delete"
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EsEvent {
    #[serde(rename = "type")]
    pub event_type: String,
    pub package: String,
    pub module: String,
    pub sender: String,
}