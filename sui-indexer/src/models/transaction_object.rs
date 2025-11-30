use diesel::prelude::*;
use serde::{Deserialize, Serialize};

use crate::schema::transaction_objects;

/// Objects involved in transactions
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable, AsChangeset)]
#[diesel(table_name = transaction_objects)]
pub struct TransactionObject {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<i64>,
    pub tx_digest: String,
    pub object_sequence: i32,

    // Object reference details
    pub object_id: String,
    pub object_version: Option<i64>,
    pub object_digest: Option<String>,

    // Object type and usage
    pub object_type: String, // 'input', 'shared', 'receiving'
    pub object_kind: Option<String>, // 'owned', 'shared', 'immutable'

    // Ownership information
    pub owner_type: Option<String>, // 'address', 'object', 'shared', 'immutable'
    pub owner_address: Option<String>,
}

/// Insertable transaction object (without auto-generated fields)
#[derive(Debug, Clone, Serialize, Deserialize, Insertable)]
#[diesel(table_name = transaction_objects)]
pub struct NewTransactionObject {
    pub tx_digest: String,
    pub object_sequence: i32,

    pub object_id: String,
    pub object_version: Option<i64>,
    pub object_digest: Option<String>,

    pub object_type: String,
    pub object_kind: Option<String>,

    pub owner_type: Option<String>,
    pub owner_address: Option<String>,
}

impl NewTransactionObject {
    pub fn new(tx_digest: String, object_sequence: i32, object_id: String, object_type: String) -> Self {
        Self {
            tx_digest,
            object_sequence,
            object_id,
            object_version: None,
            object_digest: None,
            object_type,
            object_kind: None,
            owner_type: None,
            owner_address: None,
        }
    }
}

/// Object type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ObjectType {
    Input,
    Shared,
    Receiving,
}

impl ObjectType {
    pub fn as_str(&self) -> &'static str {
        match self {
            ObjectType::Input => "input",
            ObjectType::Shared => "shared",
            ObjectType::Receiving => "receiving",
        }
    }
}

impl ToString for ObjectType {
    fn to_string(&self) -> String {
        self.as_str().to_string()
    }
}

/// Object kind classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ObjectKind {
    Owned,
    Shared,
    Immutable,
}

impl ObjectKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            ObjectKind::Owned => "owned",
            ObjectKind::Shared => "shared",
            ObjectKind::Immutable => "immutable",
        }
    }
}

impl ToString for ObjectKind {
    fn to_string(&self) -> String {
        self.as_str().to_string()
    }
}
