use sui_types::full_checkpoint_content::CheckpointTransaction;
use crate::risk::{RiskEvent, RiskLevel, RiskType, DetectionContext};

const CRITICAL_PRICE_CHANGE_THRESHOLD: u64 = 2000; // 20%
const HIGH_PRICE_CHANGE_THRESHOLD: u64 = 1000; // 10%

pub struct PriceAnalyzer;

impl PriceAnalyzer {
    pub fn new() -> Self {
        Self
    }

    pub fn analyze(
        &self,
        tx: &CheckpointTransaction,
        context: &DetectionContext,
    ) -> Option<RiskEvent> {
        if let Some(events) = &tx.events {
            for event in &events.data {
                if event.type_.name.as_str() == "PriceManipulationDetected" {
                    if let Ok(json) = serde_json::to_value(&event.contents) {
                        let price_change_pct = json
                            .get("price_change_pct")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0);

                        let risk_level = if price_change_pct >= CRITICAL_PRICE_CHANGE_THRESHOLD {
                            RiskLevel::Critical
                        } else if price_change_pct >= HIGH_PRICE_CHANGE_THRESHOLD {
                            RiskLevel::High
                        } else {
                            RiskLevel::Medium
                        };

                        let event = RiskEvent::new(
                            RiskType::PriceManipulation,
                            risk_level,
                            context.tx_digest.clone(),
                            context.sender.clone(),
                            context.checkpoint,
                            context.timestamp_ms,
                            format!("Price manipulation detected: {}% change", price_change_pct / 100),
                        )
                        .with_detail("price_change_pct", price_change_pct)
                        .with_detail("manipulator", json.get("manipulator"))
                        .with_detail("token_type", json.get("token_type"));

                        return Some(event);
                    }
                }

                if event.type_.name.as_str() == "PriceUpdated" {
                    if let Ok(json) = serde_json::to_value(&event.contents) {
                        let price_change_pct = json
                            .get("price_change_pct")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0);

                        if price_change_pct >= HIGH_PRICE_CHANGE_THRESHOLD {
                            let risk_level = if price_change_pct >= CRITICAL_PRICE_CHANGE_THRESHOLD {
                                RiskLevel::High
                            } else {
                                RiskLevel::Medium
                            };

                            let event = RiskEvent::new(
                                RiskType::PriceManipulation,
                                risk_level,
                                context.tx_digest.clone(),
                                context.sender.clone(),
                                context.checkpoint,
                                context.timestamp_ms,
                                format!("Large price update: {}% change", price_change_pct / 100),
                            )
                            .with_detail("price_change_pct", price_change_pct)
                            .with_detail("old_price", json.get("old_price"))
                            .with_detail("new_price", json.get("new_price"));

                            return Some(event);
                        }
                    }
                }
            }
        }

        None
    }
}

impl Default for PriceAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}
