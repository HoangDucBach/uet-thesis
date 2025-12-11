// Copyright (c) 2024 DeFi Protocol Indexer
// Price Manipulation Detection using TWAP Deviation Analysis + Trade Impact Scoring

use crate::risk::{DetectionContext, RiskEvent, RiskLevel, RiskType};
use crate::events::{SwapExecuted, TWAPUpdated, EventParser};
use sui_types::full_checkpoint_content::ExecutedTransaction;

/// TWAP information from oracle update events
#[derive(Debug, Clone)]
struct TWAPInfo {
    pool_id: String,
    twap_price: u64,
    spot_price: u64,
    deviation_bps: u64,
}

/// Swap information for price impact analysis
#[derive(Debug, Clone)]
struct SwapImpact {
    pool_id: String,
    amount_in: u64,
    amount_out: u64,
    price_impact: u64, // Basis points
    reserve_a: u64,    // After swap
    reserve_b: u64,    // After swap
}

/// Price manipulation analyzer with TWAP deviation and impact scoring
pub struct PriceAnalyzer {
    // Thresholds for detection
    high_price_impact_threshold: u64,     // 10% (1000 bps)
    critical_price_impact_threshold: u64, // 20% (2000 bps)
    twap_deviation_threshold: u64,        // 5% (500 bps)
    high_twap_deviation_threshold: u64,   // 10% (1000 bps)
    large_trade_ratio: f64,               // 0.15 (15% of pool depth)
}

impl PriceAnalyzer {
    pub fn new() -> Self {
        Self {
            high_price_impact_threshold: 1000,     // 10%
            critical_price_impact_threshold: 2000, // 20%
            twap_deviation_threshold: 500,         // 5%
            high_twap_deviation_threshold: 1000,   // 10%
            large_trade_ratio: 0.15,               // 15% of pool
        }
    }

    /// Main analysis function implementing TWAP deviation + trade impact scoring
    pub fn analyze(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Option<RiskEvent> {
        // Step 1: Check for TWAP deviation signals (from oracle)
        let twap_info = self.extract_twap_info(tx);

        // Step 2: Extract swap events for direct price impact analysis
        let swaps = self.extract_swap_impacts(tx);

        // Need at least one signal to proceed
        if twap_info.is_none() && swaps.is_empty() {
            return None;
        }

        // Step 3: Calculate risk score using multiple signals
        let mut risk_score = 0u32;
        let mut max_price_impact = 0u64;
        let mut max_swap_to_depth_ratio = 0.0f64;
        let mut twap_deviation = 0u64;

        // Signal 1: Direct price impact from swaps
        if !swaps.is_empty() {
            max_price_impact = swaps.iter().map(|s| s.price_impact).max().unwrap_or(0);

            // Calculate swap-to-depth ratio
            for swap in &swaps {
                let pool_depth = swap.reserve_a.min(swap.reserve_b);
                if pool_depth > 0 {
                    let ratio = swap.amount_in as f64 / pool_depth as f64;
                    max_swap_to_depth_ratio = max_swap_to_depth_ratio.max(ratio);
                }
            }

            // Score based on price impact
            if max_price_impact >= self.critical_price_impact_threshold {
                risk_score += 40;
            } else if max_price_impact >= self.high_price_impact_threshold {
                risk_score += 30;
            } else if max_price_impact >= 500 {
                risk_score += 15;
            }

            // Score based on trade size relative to pool
            if max_swap_to_depth_ratio > 0.3 {
                risk_score += 25;
            } else if max_swap_to_depth_ratio > self.large_trade_ratio {
                risk_score += 15;
            }
        }

        // Signal 2: TWAP deviation (if oracle exists)
        if let Some(twap) = &twap_info {
            twap_deviation = twap.deviation_bps;

            if twap_deviation >= self.critical_price_impact_threshold {
                risk_score += 25;
            } else if twap_deviation >= self.high_twap_deviation_threshold {
                risk_score += 15;
            } else if twap_deviation >= self.twap_deviation_threshold {
                risk_score += 5;
            }
        }

        // Signal 3: Check for explicit deviation detection from oracle
        if self.has_deviation_detected_event(tx) {
            risk_score += 10;
        }

        // Signal 4: Multiple large swaps in same direction (pump pattern)
        if swaps.len() >= 2 && self.is_pump_pattern(&swaps) {
            risk_score += 10;
        }

        // Step 4: Classify risk level
        if risk_score < 25 {
            // Below threshold, likely normal volatility
            return None;
        }

        let risk_level = match risk_score {
            25..=49 => RiskLevel::Low,
            50..=69 => RiskLevel::Medium,
            70..=84 => RiskLevel::High,
            _ => RiskLevel::Critical,
        };

        // Step 5: Create detailed risk event
        let description = if twap_info.is_some() {
            format!(
                "Price manipulation: {:.2}% price impact, {:.2}% TWAP deviation (ratio: {:.2}% of pool)",
                max_price_impact as f64 / 100.0,
                twap_deviation as f64 / 100.0,
                max_swap_to_depth_ratio * 100.0
            )
        } else {
            format!(
                "High price impact: {:.2}% in single swap (ratio: {:.2}% of pool depth)",
                max_price_impact as f64 / 100.0,
                max_swap_to_depth_ratio * 100.0
            )
        };

        let mut event = RiskEvent::new(
            RiskType::PriceManipulation,
            risk_level,
            context.tx_digest.clone(),
            context.sender.clone(),
            context.checkpoint,
            context.timestamp_ms,
            description,
        );

        // Add detailed metrics
        event = event
            .with_detail("max_price_impact", serde_json::json!(format_bps(max_price_impact)))
            .with_detail("swap_count", serde_json::json!(swaps.len()))
            .with_detail(
                "swap_to_depth_ratio",
                serde_json::json!(format!("{:.2}%", max_swap_to_depth_ratio * 100.0)),
            )
            .with_detail("risk_score", serde_json::json!(risk_score));

        if let Some(twap) = twap_info {
            event = event
                .with_detail("twap_deviation", serde_json::json!(format_bps(twap.deviation_bps)))
                .with_detail("spot_price", serde_json::json!(format_currency(twap.spot_price)))
                .with_detail("twap_price", serde_json::json!(format_currency(twap.twap_price)))
                .with_detail("pool_id", serde_json::json!(twap.pool_id));
        }

        Some(event)
    }

    /// Extract TWAP information from oracle update events
    fn extract_twap_info(&self, tx: &ExecutedTransaction) -> Option<TWAPInfo> {
        let events = tx.events.as_ref()?;

        for event in &events.data {
            if event.type_.name.as_str() == "TWAPUpdated" {
                if let Some(parsed) = TWAPUpdated::from_event(event) {
                    return Some(TWAPInfo {
                        pool_id: parsed.pool_id.to_string(),
                        twap_price: parsed.twap_price_a,
                        spot_price: parsed.spot_price_a,
                        deviation_bps: parsed.price_deviation,
                    });
                }
            }
        }

        None
    }

    /// Extract swap impacts from swap events
    fn extract_swap_impacts(&self, tx: &ExecutedTransaction) -> Vec<SwapImpact> {
        let events = match &tx.events {
            Some(e) => e,
            None => return Vec::new(),
        };

        let mut swaps = Vec::new();

        for event in &events.data {
            if event.type_.name.as_str() == "SwapExecuted" {
                if let Some(parsed) = SwapExecuted::from_event(event) {
                    swaps.push(SwapImpact {
                        pool_id: parsed.pool_id.to_string(),
                        amount_in: parsed.amount_in,
                        amount_out: parsed.amount_out,
                        price_impact: parsed.price_impact,
                        reserve_a: parsed.reserve_a,
                        reserve_b: parsed.reserve_b,
                    });
                }
            }
        }

        swaps
    }

    /// Check if transaction has explicit PriceDeviationDetected event from oracle
    fn has_deviation_detected_event(&self, tx: &ExecutedTransaction) -> bool {
        if let Some(events) = &tx.events {
            return events
                .data
                .iter()
                .any(|e| e.type_.name.as_str() == "PriceDeviationDetected");
        }
        false
    }

    /// Detect pump pattern: multiple swaps in same direction
    fn is_pump_pattern(&self, swaps: &[SwapImpact]) -> bool {
        if swaps.len() < 2 {
            return false;
        }

        // Check if all swaps are on same pool and in same direction
        let first_pool = &swaps[0].pool_id;

        // Simple heuristic: if all swaps have high price impact on same pool
        swaps
            .iter()
            .all(|s| s.pool_id == *first_pool && s.price_impact >= 100)
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

impl Default for PriceAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_thresholds() {
        let analyzer = PriceAnalyzer::new();

        assert_eq!(analyzer.high_price_impact_threshold, 1000);
        assert_eq!(analyzer.critical_price_impact_threshold, 2000);
        assert_eq!(analyzer.twap_deviation_threshold, 500);
    }

    #[test]
    fn test_pump_pattern_detection() {
        let analyzer = PriceAnalyzer::new();

        let swaps = vec![
            SwapImpact {
                pool_id: "pool1".to_string(),
                amount_in: 1000,
                amount_out: 900,
                price_impact: 500,
                reserve_a: 10000,
                reserve_b: 10000,
            },
            SwapImpact {
                pool_id: "pool1".to_string(),
                amount_in: 1000,
                amount_out: 850,
                price_impact: 600,
                reserve_a: 11000,
                reserve_b: 9150,
            },
        ];

        assert!(analyzer.is_pump_pattern(&swaps));
    }

    #[test]
    fn test_not_pump_pattern_different_pools() {
        let analyzer = PriceAnalyzer::new();

        let swaps = vec![
            SwapImpact {
                pool_id: "pool1".to_string(),
                amount_in: 1000,
                amount_out: 900,
                price_impact: 500,
                reserve_a: 10000,
                reserve_b: 10000,
            },
            SwapImpact {
                pool_id: "pool2".to_string(), // Different pool
                amount_in: 1000,
                amount_out: 850,
                price_impact: 600,
                reserve_a: 11000,
                reserve_b: 9150,
            },
        ];

        assert!(!analyzer.is_pump_pattern(&swaps));
    }
}
