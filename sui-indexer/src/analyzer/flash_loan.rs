// Copyright (c) 2024 DeFi Protocol Indexer
// Flash Loan Attack Detection using Multi-Signal Pattern Analysis

use sui_types::full_checkpoint_content::ExecutedTransaction;
use std::collections::HashSet;
use crate::risk::{RiskEvent, RiskLevel, RiskType, DetectionContext};
use crate::events::{FlashLoanTaken, SwapExecuted, EventParser};

/// Flash loan information extracted from events
#[derive(Debug, Clone)]
struct FlashLoanInfo {
    pool_id: String,
    amount: u64,
    fee: u64,
}

/// Swap information extracted from events
#[derive(Debug, Clone)]
struct SwapInfo {
    pool_id: String,
    sender: String,
    token_in_type: String,
    amount_in: u64,
    amount_out: u64,
    price_impact: u64, // in basis points
}

/// Token flow graph node
#[derive(Debug, Clone, Hash, Eq, PartialEq)]
struct TokenType {
    type_name: String,
}

/// Flash loan attack analyzer with sophisticated pattern detection
pub struct FlashLoanAnalyzer {
    // Thresholds for detection
    min_swap_count: usize,
    price_impact_threshold: u64,
    high_price_impact_threshold: u64,
}

impl FlashLoanAnalyzer {
    pub fn new() -> Self {
        Self {
            min_swap_count: 2,                  // Minimum swaps to be suspicious
            price_impact_threshold: 500,        // 5% price impact
            high_price_impact_threshold: 1000,  // 10% high impact
        }
    }

    /// Main analysis function implementing the multi-signal algorithm
    pub fn analyze(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Option<RiskEvent> {
        // Step 1: Extract flash loan events
        let flash_loan_info = self.extract_flash_loan_info(tx)?;

        // Flash loan must be borrowed and repaid in same tx
        if flash_loan_info.is_empty() {
            return None;
        }

        // Step 2: Extract swap events
        let swaps = self.extract_swap_events(tx);

        // If no swaps, it's just a flash loan (not an attack)
        if swaps.is_empty() {
            return None;
        }

        // Step 3: Analyze patterns
        let circular_trading = self.detect_circular_trading(&swaps);
        let unique_pools = self.count_unique_pools(&swaps);
        let total_price_impact = self.calculate_total_price_impact(&swaps);
        let max_single_impact = self.calculate_max_price_impact(&swaps);

        // Step 4: Calculate risk score using weighted multi-signal approach
        let mut risk_score = 0u32;

        // Circular trading is highly suspicious
        if circular_trading {
            risk_score += 30;
        }

        // Multiple swaps indicate complex arbitrage
        if swaps.len() >= 3 {
            risk_score += 20;
        } else if swaps.len() >= 2 {
            risk_score += 10;
        }

        // High cumulative price impact
        if total_price_impact > self.high_price_impact_threshold * 2 {
            risk_score += 25;
        } else if total_price_impact > self.high_price_impact_threshold {
            risk_score += 15;
        }

        // Single high-impact swap
        if max_single_impact > self.price_impact_threshold {
            risk_score += 15;
        }

        // Multi-pool arbitrage
        if unique_pools >= 3 {
            risk_score += 15;
        } else if unique_pools >= 2 {
            risk_score += 10;
        }

        // Large flash loan amount (relative)
        if flash_loan_info.iter().any(|fl| fl.amount > 1_000_000_000) {
            risk_score += 10;
        }

        // Step 5: Classify risk level based on score
        if risk_score < 30 {
            // Below threshold, likely legitimate
            return None;
        }

        let risk_level = match risk_score {
            30..=49 => RiskLevel::Low,
            50..=69 => RiskLevel::Medium,
            70..=84 => RiskLevel::High,
            _ => RiskLevel::Critical,
        };

        // Step 6: Create detailed risk event
        let description = format!(
            "Flash loan arbitrage detected: {} swaps across {} pools, {:.2}% total price impact{}",
            swaps.len(),
            unique_pools,
            total_price_impact as f64 / 100.0,
            if circular_trading {
                ", circular trading pattern"
            } else {
                ""
            }
        );

        let mut event = RiskEvent::new(
            RiskType::FlashLoanAttack,
            risk_level,
            context.tx_digest.clone(),
            context.sender.clone(),
            context.checkpoint,
            context.timestamp_ms,
            description,
        );

        // Add detailed metrics
        event = event
            .with_detail("flash_loan_count", serde_json::json!(flash_loan_info.len()))
            .with_detail("total_borrowed", serde_json::json!(
                format_currency(flash_loan_info.iter().map(|fl| fl.amount).sum::<u64>())
            ))
            .with_detail("swap_count", serde_json::json!(swaps.len()))
            .with_detail("unique_pools", serde_json::json!(unique_pools))
            .with_detail("circular_trading", serde_json::json!(circular_trading))
            .with_detail("total_price_impact", serde_json::json!(format_bps(total_price_impact)))
            .with_detail("max_price_impact", serde_json::json!(format_bps(max_single_impact)))
            .with_detail("risk_score", serde_json::json!(risk_score));

        Some(event)
    }

    /// Extract flash loan information from events
    fn extract_flash_loan_info(&self, tx: &ExecutedTransaction) -> Option<Vec<FlashLoanInfo>> {
        let events = tx.events.as_ref()?;

        let mut taken_loans: Vec<FlashLoanInfo> = Vec::new();
        let mut repaid_count = 0;

        for event in &events.data {
            let event_name = event.type_.name.as_str();

            if event_name == "FlashLoanTaken" {
                if let Some(parsed) = FlashLoanTaken::from_event(event) {
                    taken_loans.push(FlashLoanInfo {
                        pool_id: parsed.pool_id.to_string(),
                        amount: parsed.amount,
                        fee: parsed.fee,
                    });
                }
            } else if event_name == "FlashLoanRepaid" {
                repaid_count += 1;
            }
        }

        // Flash loan attack requires both borrow and repay
        if !taken_loans.is_empty() && repaid_count > 0 {
            Some(taken_loans)
        } else {
            None
        }
    }

    /// Extract swap events from transaction
    fn extract_swap_events(&self, tx: &ExecutedTransaction) -> Vec<SwapInfo> {
        let events = match &tx.events {
            Some(e) => e,
            None => return Vec::new(),
        };

        let mut swaps = Vec::new();

        for event in &events.data {
            if event.type_.name.as_str() == "SwapExecuted" {
                if let Some(parsed) = SwapExecuted::from_event(event) {
                    let token_in_type = event.type_.type_params.get(0)
                        .map(|t| format!("{:?}", t))
                        .unwrap_or_default();

                    swaps.push(SwapInfo {
                        pool_id: parsed.pool_id.to_string(),
                        sender: parsed.sender.to_string(),
                        token_in_type,
                        amount_in: parsed.amount_in,
                        amount_out: parsed.amount_out,
                        price_impact: parsed.price_impact,
                    });
                }
            }
        }

        swaps
    }

    /// Detect circular trading pattern (A → B → A)
    fn detect_circular_trading(&self, swaps: &[SwapInfo]) -> bool {
        if swaps.len() < 2 {
            return false;
        }

        // Build token flow graph
        let mut token_flow: Vec<String> = Vec::new();

        for swap in swaps {
            // Extract token types from pool swaps
            // This is a simplified version - in reality you'd track actual token types
            token_flow.push(swap.token_in_type.clone());
        }

        // Check if start token appears again (circular)
        if token_flow.is_empty() {
            return false;
        }

        let start_token = &token_flow[0];
        token_flow[1..].contains(start_token)
    }

    /// Count unique pools touched
    fn count_unique_pools(&self, swaps: &[SwapInfo]) -> usize {
        let unique_pools: HashSet<&String> = swaps.iter()
            .map(|swap| &swap.pool_id)
            .collect();

        unique_pools.len()
    }

    /// Calculate total price impact across all swaps
    fn calculate_total_price_impact(&self, swaps: &[SwapInfo]) -> u64 {
        swaps.iter()
            .map(|swap| swap.price_impact)
            .sum()
    }

    /// Calculate maximum single swap price impact
    fn calculate_max_price_impact(&self, swaps: &[SwapInfo]) -> u64 {
        swaps.iter()
            .map(|swap| swap.price_impact)
            .max()
            .unwrap_or(0)
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

impl Default for FlashLoanAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_risk_scoring() {
        let analyzer = FlashLoanAnalyzer::new();

        // Test that thresholds are set correctly
        assert_eq!(analyzer.min_swap_count, 2);
        assert_eq!(analyzer.price_impact_threshold, 500);
        assert_eq!(analyzer.high_price_impact_threshold, 1000);
    }

    #[test]
    fn test_circular_trading_detection() {
        let analyzer = FlashLoanAnalyzer::new();

        let swaps = vec![
            SwapInfo {
                pool_id: "pool1".to_string(),
                sender: "addr1".to_string(),
                token_in_type: "USDC".to_string(),
                amount_in: 1000,
                amount_out: 1000,
                price_impact: 100,
            },
            SwapInfo {
                pool_id: "pool2".to_string(),
                sender: "addr1".to_string(),
                token_in_type: "USDT".to_string(),
                amount_in: 1000,
                amount_out: 1000,
                price_impact: 100,
            },
            SwapInfo {
                pool_id: "pool1".to_string(),
                sender: "addr1".to_string(),
                token_in_type: "USDC".to_string(), // Back to USDC - circular!
                amount_in: 1000,
                amount_out: 1000,
                price_impact: 100,
            },
        ];

        assert!(analyzer.detect_circular_trading(&swaps));
    }

    #[test]
    fn test_unique_pool_counting() {
        let analyzer = FlashLoanAnalyzer::new();

        let swaps = vec![
            SwapInfo {
                pool_id: "pool1".to_string(),
                sender: "addr1".to_string(),
                token_in_type: "USDC".to_string(),
                amount_in: 1000,
                amount_out: 1000,
                price_impact: 100,
            },
            SwapInfo {
                pool_id: "pool2".to_string(),
                sender: "addr1".to_string(),
                token_in_type: "USDT".to_string(),
                amount_in: 1000,
                amount_out: 1000,
                price_impact: 100,
            },
            SwapInfo {
                pool_id: "pool1".to_string(), // Duplicate pool
                sender: "addr1".to_string(),
                token_in_type: "USDC".to_string(),
                amount_in: 1000,
                amount_out: 1000,
                price_impact: 100,
            },
        ];

        assert_eq!(analyzer.count_unique_pools(&swaps), 2);
    }
}
