// Copyright (c) 2024 DeFi Protocol Indexer
// Oracle Manipulation Attack Detection via Lending Protocol Exploitation

use sui_types::full_checkpoint_content::ExecutedTransaction;
use crate::risk::{RiskEvent, RiskLevel, RiskType, DetectionContext};

/// Oracle manipulation analyzer
///
/// Detects attacks that manipulate DEX oracle prices to exploit lending protocols:
/// 1. Flash loan borrowed
/// 2. Large swap to manipulate DEX price
/// 3. Borrow from lending using inflated collateral value
/// 4. Swap back to restore price
/// 5. Repay flash loan with profit
/// 6. Lending protocol has bad debt
pub struct OracleManipulationAnalyzer {
    /// Minimum price deviation to flag (basis points)
    min_price_deviation: u64,
    /// Minimum borrow amount to analyze
    min_borrow_amount: u64,
}

impl OracleManipulationAnalyzer {
    pub fn new() -> Self {
        Self {
            min_price_deviation: 1000,  // 10% price deviation
            min_borrow_amount: 100_000_000,  // 100 tokens minimum
        }
    }

    /// Main analysis function
    pub fn analyze(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Option<RiskEvent> {
        // Step 1: Check for flash loan presence
        let flash_loan_info = self.extract_flash_loan_info(tx)?;

        // Step 2: Extract price-moving swaps
        let large_swaps = self.extract_large_swaps(tx);
        if large_swaps.is_empty() {
            return None;
        }

        // Step 3: Extract lending borrows
        let lending_borrows = self.extract_lending_borrows(tx);
        if lending_borrows.is_empty() {
            return None;
        }

        // Step 4: Temporal correlation analysis
        // Check if borrow happened AFTER price manipulation
        let swap_timestamp = large_swaps[0].timestamp;
        let borrow_timestamp = lending_borrows[0].timestamp;

        if borrow_timestamp <= swap_timestamp {
            return None;  // Borrow before swap, not manipulation
        }

        // Step 5: Price analysis
        let oracle_price = lending_borrows[0].oracle_price;
        let normal_price = self.estimate_normal_price(&large_swaps);

        if oracle_price == 0 || normal_price == 0 {
            return None;
        }

        let price_deviation = if oracle_price > normal_price {
            ((oracle_price - normal_price) as u128 * 10000 / normal_price as u128) as u64
        } else {
            ((normal_price - oracle_price) as u128 * 10000 / oracle_price as u128) as u64
        };

        // Check if price deviation is significant
        if price_deviation < self.min_price_deviation {
            return None;
        }

        // Step 6: Calculate protocol loss risk
        let collateral_value = lending_borrows[0].collateral_value;
        let borrow_amount = lending_borrows[0].borrow_amount;

        // Estimate protocol loss if price returns to normal
        let real_collateral_value = (collateral_value as u128 * normal_price as u128 / oracle_price as u128) as u64;
        let protocol_loss = if borrow_amount > real_collateral_value {
            borrow_amount - real_collateral_value
        } else {
            0
        };

        // Step 7: Risk scoring
        let mut risk_score = 0u32;

        // Flash loan presence
        risk_score += 20;

        // Price deviation scoring
        if price_deviation >= 5000 {  // 50%+
            risk_score += 40;
        } else if price_deviation >= 2000 {  // 20%+
            risk_score += 30;
        } else if price_deviation >= 1000 {  // 10%+
            risk_score += 20;
        }

        // Borrow amount scoring
        if borrow_amount > 10_000_000_000 {  // > 10k tokens
            risk_score += 20;
        } else if borrow_amount > 1_000_000_000 {  // > 1k tokens
            risk_score += 15;
        }

        // Protocol loss scoring
        if protocol_loss > borrow_amount / 2 {  // > 50% loss
            risk_score += 20;
        } else if protocol_loss > 0 {
            risk_score += 10;
        }

        // Health factor analysis
        let health_factor = lending_borrows[0].health_factor;
        if health_factor > 15000 {  // Abnormally high (1.5x)
            risk_score += 10;
        }

        // Classify
        if risk_score < 40 {
            return None;  // Below threshold
        }

        let risk_level = match risk_score {
            40..=59 => RiskLevel::Medium,
            60..=79 => RiskLevel::High,
            _ => RiskLevel::Critical,
        };

        // Step 8: Create event
        let description = format!(
            "Oracle manipulation: {}% price inflation, ${} borrow, ${} potential protocol loss",
            price_deviation / 100,
            borrow_amount / 1_000_000,
            protocol_loss / 1_000_000
        );

        let mut event = RiskEvent::new(
            RiskType::OracleManipulation,
            risk_level,
            context.tx_digest.clone(),
            context.sender.clone(),
            context.checkpoint,
            context.timestamp_ms,
            description,
        );

        // Add details
        event = event
            .with_detail("flash_loan_amount", serde_json::json!(flash_loan_info.amount))
            .with_detail("swap_count", serde_json::json!(large_swaps.len()))
            .with_detail("oracle_price", serde_json::json!(oracle_price))
            .with_detail("normal_price", serde_json::json!(normal_price))
            .with_detail("price_deviation_bps", serde_json::json!(price_deviation))
            .with_detail("borrow_amount", serde_json::json!(borrow_amount))
            .with_detail("collateral_value", serde_json::json!(collateral_value))
            .with_detail("real_collateral_value", serde_json::json!(real_collateral_value))
            .with_detail("protocol_loss", serde_json::json!(protocol_loss))
            .with_detail("health_factor", serde_json::json!(health_factor))
            .with_detail("risk_score", serde_json::json!(risk_score));

        Some(event)
    }

    /// Extract flash loan information
    fn extract_flash_loan_info(&self, tx: &ExecutedTransaction) -> Option<FlashLoanInfo> {
        let events = tx.events.as_ref()?;

        let mut has_taken = false;
        let mut amount = 0u64;

        for event in &events.data {
            let event_name = event.type_.name.as_str();

            if event_name == "FlashLoanTaken" {
                has_taken = true;
                if let Ok(json) = serde_json::to_value(&event.contents) {
                    amount = json.get("amount")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);
                }
            }

            if event_name == "FlashLoanRepaid" {
                if has_taken {
                    return Some(FlashLoanInfo { amount });
                }
            }
        }

        None
    }

    /// Extract large swaps that could manipulate price
    fn extract_large_swaps(&self, tx: &ExecutedTransaction) -> Vec<SwapInfo> {
        let events = match &tx.events {
            Some(e) => e,
            None => return Vec::new(),
        };

        let mut swaps = Vec::new();

        for event in &events.data {
            if event.type_.name.as_str() == "SwapExecuted" {
                if let Ok(json) = serde_json::to_value(&event.contents) {
                    let amount_in = json.get("amount_in")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    let price_impact = json.get("price_impact")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    let reserve_a = json.get("reserve_a")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    let reserve_b = json.get("reserve_b")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    // Only track swaps with significant impact
                    if price_impact >= 500 {  // >= 5%
                        swaps.push(SwapInfo {
                            amount_in,
                            price_impact,
                            reserve_a_before: 0,  // Would need to track
                            reserve_a_after: reserve_a,
                            reserve_b_after: reserve_b,
                            timestamp: 0,  // Would come from event
                        });
                    }
                }
            }
        }

        swaps
    }

    /// Extract lending borrow events
    fn extract_lending_borrows(&self, tx: &ExecutedTransaction) -> Vec<BorrowInfo> {
        let events = match &tx.events {
            Some(e) => e,
            None => return Vec::new(),
        };

        let mut borrows = Vec::new();

        for event in &events.data {
            if event.type_.name.as_str() == "BorrowEvent" {
                if let Ok(json) = serde_json::to_value(&event.contents) {
                    let borrow_amount = json.get("borrow_amount")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    let collateral_value = json.get("collateral_value")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    let oracle_price = json.get("oracle_price")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    let health_factor = json.get("health_factor")
                        .and_then(|v| v.as_u64())
                        .unwrap_or(0);

                    if borrow_amount >= self.min_borrow_amount {
                        borrows.push(BorrowInfo {
                            borrow_amount,
                            collateral_value,
                            oracle_price,
                            health_factor,
                            timestamp: 0,  // Would come from event
                        });
                    }
                }
            }
        }

        borrows
    }

    /// Estimate normal price from swap reserves before manipulation
    fn estimate_normal_price(&self, swaps: &[SwapInfo]) -> u64 {
        if swaps.is_empty() {
            return 0;
        }

        // Use the first swap's post-state as baseline
        // In reality, would track pre-swap state
        let swap = &swaps[0];

        // Simple heuristic: reverse the price impact
        // normal_price = current_price / (1 + impact)
        let current_price = if swap.reserve_a_after > 0 {
            (swap.reserve_b_after as u128 * 1_000_000_000 / swap.reserve_a_after as u128) as u64
        } else {
            0
        };

        if current_price == 0 {
            return 0;
        }

        // Reverse impact
        let impact_factor = 10000 + swap.price_impact;
        ((current_price as u128 * 10000 / impact_factor as u128) as u64)
    }
}

impl Default for OracleManipulationAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Helper Structs
// ============================================================================

#[derive(Debug, Clone)]
struct FlashLoanInfo {
    amount: u64,
}

#[derive(Debug, Clone)]
struct SwapInfo {
    amount_in: u64,
    price_impact: u64,
    reserve_a_before: u64,
    reserve_a_after: u64,
    reserve_b_after: u64,
    timestamp: u64,
}

#[derive(Debug, Clone)]
struct BorrowInfo {
    borrow_amount: u64,
    collateral_value: u64,
    oracle_price: u64,
    health_factor: u64,
    timestamp: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_analyzer_creation() {
        let analyzer = OracleManipulationAnalyzer::new();
        assert_eq!(analyzer.min_price_deviation, 1000);
        assert_eq!(analyzer.min_borrow_amount, 100_000_000);
    }

    #[test]
    fn test_normal_price_estimation() {
        let analyzer = OracleManipulationAnalyzer::new();

        let swaps = vec![SwapInfo {
            amount_in: 1000000,
            price_impact: 2000,  // 20%
            reserve_a_before: 0,
            reserve_a_after: 100_000_000,
            reserve_b_after: 240_000_000_000,  // Price: 2400
            timestamp: 0,
        }];

        let normal_price = analyzer.estimate_normal_price(&swaps);

        // Should be ~2000 (2400 / 1.2)
        assert!(normal_price > 1900_000_000 && normal_price < 2100_000_000);
    }
}
