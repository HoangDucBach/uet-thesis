// Copyright (c) 2024 DeFi Protocol Indexer
// Oracle Manipulation Attack Detection via Lending Protocol Exploitation

use crate::events::{BorrowEvent, EventParser, FlashLoanTaken, SwapExecuted};
use crate::risk::{DetectionContext, RiskEvent, RiskLevel, RiskType};
use sui_types::full_checkpoint_content::ExecutedTransaction;

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
            min_price_deviation: 1000,      // 10% price deviation
            min_borrow_amount: 100_000_000, // 100 tokens minimum
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
        // let swap_timestamp = large_swaps[0].timestamp;
        // let borrow_timestamp = lending_borrows[0].timestamp;

        // if borrow_timestamp <= swap_timestamp {
        //     return None;  // Borrow before swap, not manipulation
        // }

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
        let real_collateral_value =
            (collateral_value as u128 * normal_price as u128 / oracle_price as u128) as u64;
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
        if price_deviation >= 5000 {
            // 50%+
            risk_score += 40;
        } else if price_deviation >= 2000 {
            // 20%+
            risk_score += 30;
        } else if price_deviation >= 1000 {
            // 10%+
            risk_score += 20;
        }

        // Borrow amount scoring
        if borrow_amount > 10_000_000_000 {
            // > 10k tokens
            risk_score += 20;
        } else if borrow_amount > 1_000_000_000 {
            // > 1k tokens
            risk_score += 15;
        }

        // Protocol loss scoring
        if protocol_loss > borrow_amount / 2 {
            // > 50% loss
            risk_score += 20;
        } else if protocol_loss > 0 {
            risk_score += 10;
        }

        // Health factor analysis
        let health_factor = lending_borrows[0].health_factor;
        if health_factor > 15000 {
            // Abnormally high (1.5x)
            risk_score += 10;
        }

        // Classify
        if risk_score < 40 {
            return None; // Below threshold
        }

        let risk_level = match risk_score {
            40..=59 => RiskLevel::Medium,
            60..=79 => RiskLevel::High,
            _ => RiskLevel::Critical,
        };

        // Step 8: Create event
        let description = format!(
            "Oracle manipulation: {:.2}% price inflation, ${} borrow, ${} potential protocol loss",
            price_deviation as f64 / 100.0,
            format_currency(borrow_amount / 1_000_000),
            format_currency(protocol_loss / 1_000_000)
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
            .with_detail(
                "flash_loan_amount",
                serde_json::json!(format_currency(flash_loan_info.amount)),
            )
            .with_detail("swap_count", serde_json::json!(large_swaps.len()))
            .with_detail("oracle_price", serde_json::json!(format_currency(oracle_price)))
            .with_detail("normal_price", serde_json::json!(format_currency(normal_price)))
            .with_detail("price_deviation", serde_json::json!(format_bps(price_deviation)))
            .with_detail("borrow_amount", serde_json::json!(format_currency(borrow_amount)))
            .with_detail("collateral_value", serde_json::json!(format_currency(collateral_value)))
            .with_detail(
                "real_collateral_value",
                serde_json::json!(format_currency(real_collateral_value)),
            )
            .with_detail("protocol_loss", serde_json::json!(format_currency(protocol_loss)))
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
                if let Some(parsed) = FlashLoanTaken::from_event(event) {
                    amount = parsed.amount;
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
                if let Some(parsed) = SwapExecuted::from_event(event) {
                    let amount_in = parsed.amount_in;
                    let amount_out = parsed.amount_out;
                    let token_in = parsed.token_in;
                    let price_impact = parsed.price_impact;
                    let reserve_a = parsed.reserve_a;
                    let reserve_b = parsed.reserve_b;

                    // Only track swaps with significant impact
                    if price_impact >= 500 {
                        // >= 5%
                        swaps.push(SwapInfo {
                            token_in,
                            amount_in,
                            amount_out,
                            price_impact,
                            reserve_a_before: 0, // Would need to track
                            reserve_a_after: reserve_a,
                            reserve_b_after: reserve_b,
                            timestamp: 0, // Would come from event
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
                if let Some(parsed) = BorrowEvent::from_event(event) {
                    let borrow_amount = parsed.borrow_amount;
                    let collateral_value = parsed.collateral_value;
                    let oracle_price = parsed.oracle_price;
                    let health_factor = parsed.health_factor;

                    if borrow_amount >= self.min_borrow_amount {
                        borrows.push(BorrowInfo {
                            borrow_amount,
                            collateral_value,
                            oracle_price,
                            health_factor,
                            timestamp: 0, // Would come from event
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

        // Lấy swap đầu tiên làm căn cứ
        let swap = &swaps[0];

        let (reserve_a_pre, reserve_b_pre) = if swap.token_in {
            (
                swap.reserve_a_after
                    .checked_sub(swap.amount_in)
                    .unwrap_or(0),
                swap.reserve_b_after
                    .checked_add(swap.amount_out)
                    .unwrap_or(0),
            )
        } else {
            // B -> A
            (
                swap.reserve_a_after
                    .checked_add(swap.amount_out)
                    .unwrap_or(0),
                swap.reserve_b_after
                    .checked_sub(swap.amount_in)
                    .unwrap_or(0),
            )
        };

        if reserve_a_pre == 0 {
            return 0;
        }

        (reserve_b_pre as u128 * 1_000_000_000 / reserve_a_pre as u128) as u64
    }
}

fn format_currency(amount: u64) -> String {
    let s = amount.to_string();
    let mut res = String::new();
    for (i, c) in s.chars().rev().enumerate() {
        if i > 0 && i % 3 == 0 {
            res.insert(0, ',');
        }
        res.insert(0, c);
    }
    res
}

fn format_bps(bps: u64) -> String {
    format!("{:.2}%", bps as f64 / 100.0)
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
    token_in: bool,
    amount_in: u64,
    amount_out: u64,
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
            token_in: false,           // B -> A (Price increases)
            amount_in: 40_000_000_000, // Input B
            amount_out: 20_000_000,    // Output A
            price_impact: 2000,        // 20%
            reserve_a_before: 0,
            reserve_a_after: 100_000_000,
            reserve_b_after: 240_000_000_000, // Price: 2400
            timestamp: 0,
        }];

        // Pre-swap state:
        // Reserve A = 100M + 20M = 120M
        // Reserve B = 240B - 40B = 200B
        // Normal Price = 200B / 120M = 1666.66

        let normal_price = analyzer.estimate_normal_price(&swaps);

        // Should be around 1666
        assert!(normal_price > 1600_000_000 && normal_price < 1700_000_000);
    }
}
