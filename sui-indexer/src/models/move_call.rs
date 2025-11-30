use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use crate::schema::move_calls;

/// MoveCall - 1:1 mapping with Sui Move Call
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable)]
#[diesel(table_name = move_calls)]
pub struct MoveCall {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<i64>,
    pub tx_digest: String,
    pub package: String,
    pub module: String,
    pub function: String,
    pub type_arguments: Option<JsonValue>,
    pub arguments: Option<JsonValue>,
}

impl MoveCall {
    pub fn new(tx_digest: String, package: String, module: String, function: String) -> Self {
        Self {
            id: None,
            tx_digest,
            package,
            module,
            function,
            type_arguments: None,
            arguments: None,
        }
    }

    /// Full function path: package::module::function
    pub fn full_name(&self) -> String {
        format!("{}::{}::{}", self.package, self.module, self.function)
    }
}
