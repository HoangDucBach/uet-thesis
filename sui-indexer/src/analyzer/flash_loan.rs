use sui_types::full_checkpoint_content::CheckpointTransaction;
use sui_types::base_types::ObjectID;
use crate::risk::{RiskEvent, RiskLevel, RiskType, DetectionContext};

pub struct FlashLoanAnalyzer;

impl FlashLoanAnalyzer {
    pub fn new() -> Self {
        Self
    }

    pub fn analyze(
        &self,
        tx: &CheckpointTransaction,
        context: &DetectionContext,
    ) -> Option<RiskEvent> {
        if let Some(events) = &tx.events {
            let has_flash_loan = events.data.iter().any(|event| {
                event.type_.name.as_str() == "FlashLoanTaken"
            });

            let has_flash_repay = events.data.iter().any(|event| {
                event.type_.name.as_str() == "FlashLoanRepaid"
            });

            let has_attack_executed = events.data.iter().any(|event| {
                event.type_.name.as_str() == "FlashLoanAttackExecuted"
            });

            if has_flash_loan && has_flash_repay {
                let risk_level = if has_attack_executed {
                    RiskLevel::Critical
                } else {
                    RiskLevel::Medium
                };

                let mut event = RiskEvent::new(
                    RiskType::FlashLoanAttack,
                    risk_level,
                    context.tx_digest.clone(),
                    context.sender.clone(),
                    context.checkpoint,
                    context.timestamp_ms,
                    format!("Flash loan usage detected"),
                );

                if let Some(attack_event) = events.data.iter().find(|e| {
                    e.type_.name.as_str() == "FlashLoanAttackExecuted"
                }) {
                    if let Ok(json) = serde_json::to_value(&attack_event.contents) {
                        event = event
                            .with_detail("borrowed_amount", json.get("borrowed_amount"))
                            .with_detail("profit_amount", json.get("profit_amount"))
                            .with_detail("attack_type", "arbitrage");
                    }
                }

                return Some(event);
            }
        }

        None
    }
}

impl Default for FlashLoanAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}
