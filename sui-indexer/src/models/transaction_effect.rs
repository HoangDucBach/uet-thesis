use diesel::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

use crate::schema::transaction_effects;

/// Transaction execution effects
#[derive(Debug, Clone, Serialize, Deserialize, Queryable, Insertable, AsChangeset)]
#[diesel(table_name = transaction_effects)]
pub struct TransactionEffect {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<i64>,
    pub tx_digest: String,
    pub effect_sequence: i32,

    // Effect type and details
    pub effect_type: String, // 'object_creation', 'object_mutation', 'object_deletion', 'balance_change', 'event_emission'

    // Object-related effects
    pub affected_object_id: Option<String>,
    pub object_type: Option<String>,

    // Balance change effects
    pub coin_type: Option<String>,
    pub balance_change: Option<i64>, // Can be negative
    pub owner_address: Option<String>,

    // Event emission
    pub event_type: Option<String>,
    pub event_data: Option<JsonValue>,
}

/// Insertable transaction effect (without auto-generated fields)
#[derive(Debug, Clone, Serialize, Deserialize, Insertable)]
#[diesel(table_name = transaction_effects)]
pub struct NewTransactionEffect {
    pub tx_digest: String,
    pub effect_sequence: i32,

    pub effect_type: String,

    pub affected_object_id: Option<String>,
    pub object_type: Option<String>,

    pub coin_type: Option<String>,
    pub balance_change: Option<i64>,
    pub owner_address: Option<String>,

    pub event_type: Option<String>,
    pub event_data: Option<JsonValue>,
}

impl NewTransactionEffect {
    pub fn new(tx_digest: String, effect_sequence: i32, effect_type: String) -> Self {
        Self {
            tx_digest,
            effect_sequence,
            effect_type,
            affected_object_id: None,
            object_type: None,
            coin_type: None,
            balance_change: None,
            owner_address: None,
            event_type: None,
            event_data: None,
        }
    }

    pub fn balance_change(
        tx_digest: String,
        effect_sequence: i32,
        coin_type: String,
        balance_change: i64,
        owner_address: String,
    ) -> Self {
        Self {
            tx_digest,
            effect_sequence,
            effect_type: "balance_change".to_string(),
            affected_object_id: None,
            object_type: None,
            coin_type: Some(coin_type),
            balance_change: Some(balance_change),
            owner_address: Some(owner_address),
            event_type: None,
            event_data: None,
        }
    }

    pub fn object_creation(
        tx_digest: String,
        effect_sequence: i32,
        object_id: String,
        object_type: String,
    ) -> Self {
        Self {
            tx_digest,
            effect_sequence,
            effect_type: "object_creation".to_string(),
            affected_object_id: Some(object_id),
            object_type: Some(object_type),
            coin_type: None,
            balance_change: None,
            owner_address: None,
            event_type: None,
            event_data: None,
        }
    }
}

/// Effect type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EffectType {
    ObjectCreation,
    ObjectMutation,
    ObjectDeletion,
    BalanceChange,
    EventEmission,
}

impl EffectType {
    pub fn as_str(&self) -> &'static str {
        match self {
            EffectType::ObjectCreation => "object_creation",
            EffectType::ObjectMutation => "object_mutation",
            EffectType::ObjectDeletion => "object_deletion",
            EffectType::BalanceChange => "balance_change",
            EffectType::EventEmission => "event_emission",
        }
    }
}

impl ToString for EffectType {
    fn to_string(&self) -> String {
        self.as_str().to_string()
    }
}
