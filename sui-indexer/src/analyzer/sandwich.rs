use sui_types::full_checkpoint_content::CheckpointTransaction;
use crate::risk::{RiskEvent, RiskLevel, RiskType, DetectionContext};

pub struct SandwichAnalyzer;

impl SandwichAnalyzer {
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
                if event.type_.name.as_str() == "SandwichAttackExecuted" {
                    if let Ok(json) = serde_json::to_value(&event.contents) {
                        let attacker_profit = json
                            .get("attacker_profit")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0);

                        let victim_slippage = json
                            .get("victim_slippage")
                            .and_then(|v| v.as_u64())
                            .unwrap_or(0);

                        let risk_level = if attacker_profit > 1_000_000 || victim_slippage > 100_000 {
                            RiskLevel::Critical
                        } else if attacker_profit > 100_000 {
                            RiskLevel::High
                        } else {
                            RiskLevel::Medium
                        };

                        let event = RiskEvent::new(
                            RiskType::SandwichAttack,
                            risk_level,
                            context.tx_digest.clone(),
                            context.sender.clone(),
                            context.checkpoint,
                            context.timestamp_ms,
                            format!("Sandwich attack executed with profit: {}", attacker_profit),
                        )
                        .with_detail("attacker", json.get("attacker"))
                        .with_detail("victim", json.get("victim"))
                        .with_detail("attacker_profit", attacker_profit)
                        .with_detail("victim_slippage", victim_slippage)
                        .with_detail("front_run_amount", json.get("front_run_amount"))
                        .with_detail("victim_amount", json.get("victim_amount"))
                        .with_detail("pool_id", json.get("pool_id"));

                        return Some(event);
                    }
                }
            }

            let swaps: Vec<_> = events.data.iter()
                .filter(|e| e.type_.name.as_str() == "SwapExecuted")
                .collect();

            if swaps.len() >= 2 {
                if let (Ok(first_swap), Ok(last_swap)) = (
                    serde_json::to_value(&swaps[0].contents),
                    serde_json::to_value(&swaps[swaps.len() - 1].contents),
                ) {
                    let first_price_impact = first_swap
                        .get("price_impact")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    let last_price_impact = last_swap
                        .get("price_impact")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    if first_price_impact > 500 && last_price_impact > 500 {
                        let event = RiskEvent::new(
                            RiskType::SandwichAttack,
                            RiskLevel::Medium,
                            context.tx_digest.clone(),
                            context.sender.clone(),
                            context.checkpoint,
                            context.timestamp_ms,
                            "Potential sandwich pattern: multiple swaps with high impact".to_string(),
                        )
                        .with_detail("swap_count", swaps.len())
                        .with_detail("first_price_impact", first_price_impact)
                        .with_detail("last_price_impact", last_price_impact);

                        return Some(event);
                    }
                }
            }
        }

        None
    }
}

impl Default for SandwichAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}
