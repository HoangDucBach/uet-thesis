use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use crate::schema::objects;

/// Object - 1:1 mapping with Sui Object
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable)]
#[diesel(table_name = objects)]
pub struct Object {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<i64>,
    pub tx_digest: String,
    pub object_id: String,
    pub version: Option<i64>,
    pub digest: Option<String>,
    pub object_type: String,
    pub owner: Option<JsonValue>,
    pub raw_object: Option<JsonValue>,
}

impl Object {
    pub fn new(tx_digest: String, object_id: String, object_type: String) -> Self {
        Self {
            id: None,
            tx_digest,
            object_id,
            version: None,
            digest: None,
            object_type,
            owner: None,
            raw_object: None,
        }
    }
}
