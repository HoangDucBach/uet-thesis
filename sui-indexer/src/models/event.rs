use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use crate::schema::events;

/// Event - 1:1 mapping with Sui Event
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable)]
#[diesel(table_name = events)]
pub struct Event {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<i64>,
    pub tx_digest: String,
    pub event_type: String,
    pub package: String,
    pub module: String,
    pub sender: String,
    pub raw_event: JsonValue,
}

impl Event {
    pub fn new(
        tx_digest: String,
        event_type: String,
        package: String,
        module: String,
        sender: String,
        raw_event: JsonValue,
    ) -> Self {
        Self {
            id: None,
            tx_digest,
            event_type,
            package,
            module,
            sender,
            raw_event,
        }
    }
}
