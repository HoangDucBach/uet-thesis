use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RiskLevel {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RiskType {
    FlashLoanAttack,
    PriceManipulation,
    SandwichAttack,
    OracleManipulation,  // NEW: Oracle manipulation via lending
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskEvent {
    pub risk_type: RiskType,
    pub risk_level: RiskLevel,
    pub tx_digest: String,
    pub sender: String,
    pub checkpoint: i64,
    pub timestamp_ms: i64,
    pub details: HashMap<String, serde_json::Value>,
    pub description: String,
}

impl RiskEvent {
    pub fn new(
        risk_type: RiskType,
        risk_level: RiskLevel,
        tx_digest: String,
        sender: String,
        checkpoint: i64,
        timestamp_ms: i64,
        description: String,
    ) -> Self {
        Self {
            risk_type,
            risk_level,
            tx_digest,
            sender,
            checkpoint,
            timestamp_ms,
            details: HashMap::new(),
            description,
        }
    }

    pub fn with_detail(mut self, key: impl Into<String>, value: impl Serialize) -> Self {
        if let Ok(json_value) = serde_json::to_value(value) {
            self.details.insert(key.into(), json_value);
        }
        self
    }
}

#[derive(Debug, Clone)]
pub struct DetectionContext {
    pub tx_digest: String,
    pub sender: String,
    pub checkpoint: i64,
    pub timestamp_ms: i64,
}

impl DetectionContext {
    pub fn new(tx_digest: String, sender: String, checkpoint: i64, timestamp_ms: i64) -> Self {
        Self {
            tx_digest,
            sender,
            checkpoint,
            timestamp_ms,
        }
    }
}
