use chrono::{DateTime, Utc};
use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use crate::schema::move_calls;

/// Detailed move call information extracted from transactions
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable, AsChangeset)]
#[diesel(table_name = move_calls)]
pub struct MoveCall {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<i64>,
    pub tx_digest: String,
    pub call_sequence: i32,

    // Move call details (from Sui TransactionDataAPI)
    pub package_id: String,
    pub module_name: String,
    pub function_name: String,
    pub type_arguments: Vec<String>,

    // Call metadata
    pub is_entry_function: bool,

    // Raw arguments (preserved as JSON for exact reconstruction)
    pub arguments: Option<JsonValue>,

    // Timestamps
    pub created_at: DateTime<Utc>,
}

/// Insertable move call (without auto-generated fields)
#[derive(Debug, Clone, Serialize, Deserialize, Insertable)]
#[diesel(table_name = move_calls)]
pub struct NewMoveCall {
    pub tx_digest: String,
    pub call_sequence: i32,

    pub package_id: String,
    pub module_name: String,
    pub function_name: String,
    pub type_arguments: Vec<String>,

    pub is_entry_function: bool,
    pub arguments: Option<JsonValue>,
}

impl NewMoveCall {
    pub fn new(
        tx_digest: String,
        call_sequence: i32,
        package_id: String,
        module_name: String,
        function_name: String,
    ) -> Self {
        Self {
            tx_digest,
            call_sequence,
            package_id,
            module_name,
            function_name,
            type_arguments: vec![],
            is_entry_function: false,
            arguments: None,
        }
    }

    /// Get full function identifier: package::module::function
    pub fn full_name(&self) -> String {
        format!("{}::{}::{}", self.package_id, self.module_name, self.function_name)
    }
}

impl MoveCall {
    /// Get full function identifier: package::module::function
    pub fn full_name(&self) -> String {
        format!("{}::{}::{}", self.package_id, self.module_name, self.function_name)
    }
}
