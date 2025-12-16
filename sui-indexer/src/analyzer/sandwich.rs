// Copyright (c) 2024 DeFi Protocol Indexer
// Sandwich Attack Detection using Cross-Transaction Pattern Matching

use sui_types::full_checkpoint_content::ExecutedTransaction;
use std::collections::VecDeque;
use std::sync::Mutex;
use crate::risk::{RiskEvent, RiskLevel, RiskType, DetectionContext};
use crate::events::{SwapExecuted, EventParser};

/// Swap transaction pattern for sandwich detection
#[derive(Debug, Clone)]
pub struct SwapPattern {
    pub tx_digest: String,
    pub sender: String,
    pub pool_id: String,
    pub checkpoint: i64,
    pub timestamp_ms: i64,
    pub token_in_direction: bool,  // true = A→B, false = B→A
    pub amount_in: u64,
    pub amount_out: u64,
    pub price_impact: u64,
}

/// Detected sandwich attack pattern
#[derive(Debug, Clone)]
pub struct SandwichMatch {
    pub front_run: SwapPattern,
    pub victim: SwapPattern,
    pub back_run: SwapPattern,
    pub attacker_profit: u64,
    pub victim_loss_bps: u64,
}

/// Sandwich attack analyzer with stateful transaction buffer
pub struct SandwichAnalyzer {
    // Circular buffer for recent transactions (uses interior mutability with Mutex for thread-safety)
    transaction_buffer: Mutex<VecDeque<SwapPattern>>,
    // Maximum buffer size
    max_buffer_size: usize,
    // Maximum checkpoint distance for matching
    max_checkpoint_distance: i64,
    // Minimum price impact to be considered
    min_price_impact: u64,
}

impl SandwichAnalyzer {
    pub fn new() -> Self {
        Self {
            transaction_buffer: Mutex::new(VecDeque::with_capacity(1000)),
            max_buffer_size: 1000,
            max_checkpoint_distance: 100,  // Increased to 100 checkpoints to catch slower attacks/simulations
            min_price_impact: 100,        // 1% minimum impact
        }
    }

    /// Analyze transaction and detect sandwich patterns
    pub fn analyze(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Vec<RiskEvent> {
        // Extract swap patterns from current transaction
        let current_swaps = self.extract_swap_patterns(tx, context);

        let mut detected_events = Vec::new();

        // For each new swap, check if it completes a sandwich pattern
        for new_swap in &current_swaps {
            // Look for potential sandwich patterns in buffer
            if let Some(sandwich) = self.find_sandwich_pattern(new_swap) {
                // Create risk event for detected sandwich
                let risk_event = self.create_sandwich_event(&sandwich);
                detected_events.push(risk_event);
            }
        }

        // Add new swaps to buffer
        for swap in current_swaps {
            self.add_to_buffer(swap);
        }

        // Clean old entries from buffer
        self.cleanup_buffer(context.checkpoint);

        detected_events
    }

    /// Extract swap patterns from transaction events
    fn extract_swap_patterns(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Vec<SwapPattern> {
        let events = match &tx.events {
            Some(e) => e,
            None => return Vec::new(),
        };

        let mut patterns = Vec::new();

        for event in &events.data {
            if event.type_.name.as_str() == "SwapExecuted" {
                if let Some(parsed) = SwapExecuted::from_event(event) {
                    let pool_id = parsed.pool_id.to_string();
                    let sender = parsed.sender.to_string();
                    let token_in = parsed.token_in;
                    let amount_in = parsed.amount_in;
                    let amount_out = parsed.amount_out;
                    let price_impact = parsed.price_impact;

                    // Only track swaps with significant price impact
                    if price_impact >= self.min_price_impact {
                        patterns.push(SwapPattern {
                            tx_digest: context.tx_digest.clone(),
                            sender,
                            pool_id,
                            checkpoint: context.checkpoint,
                            timestamp_ms: context.timestamp_ms,
                            token_in_direction: token_in,
                            amount_in,
                            amount_out,
                            price_impact,
                        });
                    }
                }
            }
        }

        patterns
    }

    /// Find sandwich pattern: Front-run → [Victim] → Back-run (new_swap)
    fn find_sandwich_pattern(&self, back_run: &SwapPattern) -> Option<SandwichMatch> {
        let buffer = self.transaction_buffer.lock().unwrap();
        // Look for front-run candidates (before current transaction)
        let front_run_candidates: Vec<&SwapPattern> = buffer.iter()
            .filter(|s| {
                // Same pool
                s.pool_id == back_run.pool_id &&
                // Before back-run
                s.checkpoint <= back_run.checkpoint &&
                // Same sender as back-run (the attacker)
                s.sender == back_run.sender &&
                // Opposite direction (Front-run buys, Back-run sells)
                s.token_in_direction != back_run.token_in_direction &&
                // Within checkpoint distance
                back_run.checkpoint - s.checkpoint <= self.max_checkpoint_distance
            })
            .collect();

        // For each front-run candidate, look for victim in between
        for front_run in front_run_candidates {
            let victim_candidates: Vec<&SwapPattern> = buffer.iter()
                .filter(|s| {
                    // Same pool
                    s.pool_id == back_run.pool_id &&
                    // Between front-run and back-run
                    s.checkpoint >= front_run.checkpoint &&
                    s.checkpoint <= back_run.checkpoint &&
                    // Timestamp check: must be strictly between
                    // Note: In same checkpoint, timestamps might be identical if not careful
                    // So we relax timestamp check if checkpoints are different
                    (s.checkpoint > front_run.checkpoint || s.timestamp_ms >= front_run.timestamp_ms) &&
                    (s.checkpoint < back_run.checkpoint || s.timestamp_ms <= back_run.timestamp_ms) &&
                    // Different sender (the victim)
                    s.sender != back_run.sender &&
                    // Same direction as front-run (victim buys same token, pushing price further)
                    s.token_in_direction == front_run.token_in_direction
                })
                .collect();

            // If we found a victim, we have a sandwich!
            if let Some(&victim) = victim_candidates.first() {
                // Calculate attacker profit
                let attacker_profit = if back_run.amount_out > front_run.amount_in {
                    back_run.amount_out - front_run.amount_in
                } else {
                    0
                };

                // Calculate victim loss (in basis points)
                // Victim should have gotten better price without sandwich
                let expected_out = self.estimate_expected_output(victim, front_run);
                let victim_loss_bps = if expected_out > victim.amount_out {
                    let loss = expected_out - victim.amount_out;
                    (loss * 10000) / expected_out
                } else {
                    0
                };

                return Some(SandwichMatch {
                    front_run: front_run.clone(),
                    victim: victim.clone(),
                    back_run: back_run.clone(),
                    attacker_profit,
                    victim_loss_bps,
                });
            }
        }

        None
    }



    /// Estimate what the victim should have received without front-running
    fn estimate_expected_output(&self, victim: &SwapPattern, front_run: &SwapPattern) -> u64 {
        // Simple estimation: victim would have gotten proportionally more
        // if the pool wasn't moved by front-run
        // This is approximate - real calculation would need pool reserves

        // If front-run moved price by X%, victim lost roughly X%
        let price_impact_factor = 10000 - front_run.price_impact;
        (victim.amount_out * 10000) / price_impact_factor
    }

    /// Add swap pattern to buffer
    fn add_to_buffer(&self, pattern: SwapPattern) {
        let mut buffer = self.transaction_buffer.lock().unwrap();
        if buffer.len() >= self.max_buffer_size {
            buffer.pop_front(); // Remove oldest
        }
        buffer.push_back(pattern);
    }

    /// Remove old entries from buffer
    fn cleanup_buffer(&self, current_checkpoint: i64) {
        let mut buffer = self.transaction_buffer.lock().unwrap();
        buffer.retain(|pattern| {
            current_checkpoint - pattern.checkpoint <= self.max_checkpoint_distance * 2
        });
    }

    /// Create risk event from detected sandwich match
    fn create_sandwich_event(&self, sandwich: &SandwichMatch) -> RiskEvent {
        // Calculate risk score
        let mut risk_score = 0u32;

        // Attacker profit scoring
        if sandwich.attacker_profit > 1_000_000_000 {  // > 1000 tokens
            risk_score += 40;
        } else if sandwich.attacker_profit > 100_000_000 {  // > 100 tokens
            risk_score += 30;
        } else if sandwich.attacker_profit > 0 {
            risk_score += 20;
        }

        // Victim loss scoring
        if sandwich.victim_loss_bps > 1000 {  // > 10%
            risk_score += 30;
        } else if sandwich.victim_loss_bps > 500 {  // > 5%
            risk_score += 20;
        } else if sandwich.victim_loss_bps > 100 {  // > 1%
            risk_score += 10;
        }

        // Same checkpoint bonus (more certainty)
        if sandwich.front_run.checkpoint == sandwich.back_run.checkpoint {
            risk_score += 10;
        }

        // Quick execution bonus (< 5 seconds)
        let time_diff = sandwich.back_run.timestamp_ms - sandwich.front_run.timestamp_ms;
        if time_diff < 5000 {
            risk_score += 10;
        }

        // Classify risk level
        let risk_level = match risk_score {
            0..=29 => RiskLevel::Low,
            30..=49 => RiskLevel::Medium,
            50..=69 => RiskLevel::High,
            _ => RiskLevel::Critical,
        };

        let description = format!(
            "Sandwich attack: attacker profit {}, victim loss {:.2}%, time span {}ms",
            format_currency(sandwich.attacker_profit),
            sandwich.victim_loss_bps as f64 / 100.0,
            time_diff
        );

        let event = RiskEvent::new(
            RiskType::SandwichAttack,
            risk_level,
            sandwich.back_run.tx_digest.clone(),
            sandwich.back_run.sender.clone(),
            sandwich.back_run.checkpoint,
            sandwich.back_run.timestamp_ms,
            description,
        )
        .with_detail("attacker", serde_json::json!(sandwich.back_run.sender))
        .with_detail("victim", serde_json::json!(sandwich.victim.sender))
        .with_detail("pool_id", serde_json::json!(sandwich.back_run.pool_id))
        .with_detail("front_run_tx", serde_json::json!(sandwich.front_run.tx_digest))
        .with_detail("victim_tx", serde_json::json!(sandwich.victim.tx_digest))
        .with_detail("back_run_tx", serde_json::json!(sandwich.back_run.tx_digest))
        .with_detail("attacker_profit", serde_json::json!(format_currency(sandwich.attacker_profit)))
        .with_detail("victim_loss", serde_json::json!(format_bps(sandwich.victim_loss_bps)))
        .with_detail("time_span_ms", serde_json::json!(time_diff))
        .with_detail("risk_score", serde_json::json!(risk_score));

        event
    }

    /// Get current buffer size (for monitoring)
    pub fn get_buffer_size(&self) -> usize {
        self.transaction_buffer.lock().unwrap().len()
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

impl Default for SandwichAnalyzer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_buffer_management() {
        let analyzer = SandwichAnalyzer::new();

        assert_eq!(analyzer.get_buffer_size(), 0);

        let swap = SwapPattern {
            tx_digest: "test1".to_string(),
            sender: "addr1".to_string(),
            pool_id: "pool1".to_string(),
            checkpoint: 1000,
            timestamp_ms: 1000000,
            token_in_direction: true,
            amount_in: 1000,
            amount_out: 990,
            price_impact: 100,
        };

        analyzer.add_to_buffer(swap);
        assert_eq!(analyzer.get_buffer_size(), 1);
    }

    #[test]
    fn test_buffer_cleanup() {
        let analyzer = SandwichAnalyzer::new();

        // Add old swap
        let old_swap = SwapPattern {
            tx_digest: "old".to_string(),
            sender: "addr1".to_string(),
            pool_id: "pool1".to_string(),
            checkpoint: 1000,
            timestamp_ms: 1000000,
            token_in_direction: true,
            amount_in: 1000,
            amount_out: 990,
            price_impact: 100,
        };

        analyzer.add_to_buffer(old_swap);
        assert_eq!(analyzer.get_buffer_size(), 1);

        // Cleanup with current checkpoint far in future
        analyzer.cleanup_buffer(2000);
        assert_eq!(analyzer.get_buffer_size(), 0);
    }

    #[test]
    fn test_expected_output_estimation() {
        let analyzer = SandwichAnalyzer::new();

        let victim = SwapPattern {
            tx_digest: "victim".to_string(),
            sender: "victim_addr".to_string(),
            pool_id: "pool1".to_string(),
            checkpoint: 1001,
            timestamp_ms: 1001000,
            token_in_direction: true,
            amount_in: 1000,
            amount_out: 900,  // Got 900 tokens
            price_impact: 200,
        };

        let front_run = SwapPattern {
            tx_digest: "front".to_string(),
            sender: "attacker".to_string(),
            pool_id: "pool1".to_string(),
            checkpoint: 1000,
            timestamp_ms: 1000000,
            token_in_direction: true,
            amount_in: 500,
            amount_out: 495,
            price_impact: 500,  // 5% price impact
        };

        let expected = analyzer.estimate_expected_output(&victim, &front_run);
        // Should be more than 900 (what victim actually got)
        assert!(expected > 900);
    }
}
