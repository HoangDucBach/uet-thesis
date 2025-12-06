// Copyright (c) 2024 DeFi Protocol Indexer
// Strongly-typed event structures matching Move contract events

use serde::{Deserialize, Serialize};
use sui_types::base_types::{ObjectID, SuiAddress};

// ============================================================================
// DEX Events (simple_dex.move)
// ============================================================================

/// Pool creation event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolCreated {
    pub pool_id: ObjectID,
    pub initial_a: u64,
    pub initial_b: u64,
    pub creator: SuiAddress,
}

/// Swap execution event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapExecuted {
    pub pool_id: ObjectID,
    pub sender: SuiAddress,
    #[serde(rename = "token_in")]
    pub token_in: bool,  // true = TokenA in, false = TokenB in
    pub amount_in: u64,
    pub amount_out: u64,
    pub fee_amount: u64,
    pub reserve_a: u64,  // After swap
    pub reserve_b: u64,  // After swap
    pub price_impact: u64,  // Basis points
}

/// Liquidity addition event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiquidityAdded {
    pub pool_id: ObjectID,
    pub provider: SuiAddress,
    pub amount_a: u64,
    pub amount_b: u64,
    pub liquidity_minted: u64,
}

// ============================================================================
// Flash Loan Events (flash_loan_pool.move)
// ============================================================================

/// Flash loan borrowed event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlashLoanTaken {
    pub pool_id: ObjectID,
    pub borrower: SuiAddress,
    pub amount: u64,
    pub fee: u64,
}

/// Flash loan repayment event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlashLoanRepaid {
    pub pool_id: ObjectID,
    pub borrower: SuiAddress,
    pub amount: u64,
    pub fee: u64,
}

// ============================================================================
// TWAP Oracle Events (twap_oracle.move)
// ============================================================================

/// TWAP update event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TWAPUpdated {
    pub pool_id: ObjectID,
    #[serde(rename = "token_a")]
    pub token_a: String,  // TypeName
    #[serde(rename = "token_b")]
    pub token_b: String,  // TypeName
    pub twap_price_a: u64,  // Scaled by 1e9
    pub twap_price_b: u64,
    pub spot_price_a: u64,
    pub spot_price_b: u64,
    pub price_deviation: u64,  // Basis points
    pub timestamp: u64,
}

/// Price deviation detected event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PriceDeviationDetected {
    pub pool_id: ObjectID,
    #[serde(rename = "token_a")]
    pub token_a: String,
    #[serde(rename = "token_b")]
    pub token_b: String,
    pub twap_price: u64,
    pub spot_price: u64,
    pub deviation_bps: u64,  // Basis points (10000 = 100%)
    pub timestamp: u64,
}

// ============================================================================
// Lending Events (compound_market.move)
// ============================================================================

/// Supply to lending market event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SupplyEvent {
    pub market_id: ObjectID,
    pub supplier: SuiAddress,
    pub amount: u64,
    pub c_tokens_minted: u64,
    pub exchange_rate: u64,
    pub timestamp: u64,
}

/// Borrow from lending market event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BorrowEvent {
    pub market_id: ObjectID,
    pub borrower: SuiAddress,
    pub position_id: ObjectID,
    pub borrow_amount: u64,
    pub collateral_value: u64,
    pub oracle_price: u64,       // Price used from DEX oracle
    pub health_factor: u64,      // Risk metric
    pub total_borrows: u64,
    pub timestamp: u64,
}

/// Repay lending debt event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepayEvent {
    pub market_id: ObjectID,
    pub borrower: SuiAddress,
    pub position_id: ObjectID,
    pub repay_amount: u64,
    pub remaining_debt: u64,
    pub timestamp: u64,
}

/// Liquidation event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiquidationEvent {
    pub market_id: ObjectID,
    pub liquidator: SuiAddress,
    pub borrower: SuiAddress,
    pub position_id: ObjectID,
    pub debt_repaid: u64,
    pub collateral_seized: u64,
    pub liquidation_incentive: u64,
    pub health_factor_before: u64,
    pub protocol_loss: u64,  // Bad debt if any
    pub timestamp: u64,
}

/// Interest accrual event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccrueInterestEvent {
    pub market_id: ObjectID,
    pub borrow_rate: u64,
    pub supply_rate: u64,
    pub total_borrows: u64,
    pub total_reserves: u64,
    pub borrow_index: u64,
    pub timestamp: u64,
}

// ============================================================================
// Event Parsing Utilities
// ============================================================================

use sui_types::event::Event;

/// Parse event content to strongly-typed struct
pub trait EventParser: Sized {
    /// Event type name in Move (e.g., "SwapExecuted")
    fn event_name() -> &'static str;

    /// Parse from Sui Event
    fn from_event(event: &Event) -> Option<Self>;
}

macro_rules! impl_event_parser {
    ($struct_name:ident, $event_name:expr) => {
        impl EventParser for $struct_name {
            fn event_name() -> &'static str {
                $event_name
            }

            fn from_event(event: &Event) -> Option<Self> {
                if event.type_.name.as_str() != Self::event_name() {
                    return None;
                }

                match bcs::from_bytes(&event.contents) {
                    Ok(parsed) => Some(parsed),
                    Err(e) => {
                        eprintln!("Failed to parse event {}: {}", Self::event_name(), e);
                        None
                    }
                }
            }
        }
    };
}

// Implement EventParser for all event types
impl_event_parser!(PoolCreated, "PoolCreated");
impl_event_parser!(SwapExecuted, "SwapExecuted");
impl_event_parser!(LiquidityAdded, "LiquidityAdded");
impl_event_parser!(FlashLoanTaken, "FlashLoanTaken");
impl_event_parser!(FlashLoanRepaid, "FlashLoanRepaid");
impl_event_parser!(TWAPUpdated, "TWAPUpdated");
impl_event_parser!(PriceDeviationDetected, "PriceDeviationDetected");
impl_event_parser!(SupplyEvent, "SupplyEvent");
impl_event_parser!(BorrowEvent, "BorrowEvent");
impl_event_parser!(RepayEvent, "RepayEvent");
impl_event_parser!(LiquidationEvent, "LiquidationEvent");
impl_event_parser!(AccrueInterestEvent, "AccrueInterestEvent");

// ============================================================================
// Multi-Event Parser
// ============================================================================

use sui_types::full_checkpoint_content::ExecutedTransaction;

/// Collection of parsed events from a transaction
#[derive(Debug, Default)]
pub struct ParsedEvents {
    pub flash_loan_taken: Vec<FlashLoanTaken>,
    pub flash_loan_repaid: Vec<FlashLoanRepaid>,
    pub swaps: Vec<SwapExecuted>,
    pub twap_updates: Vec<TWAPUpdated>,
    pub price_deviations: Vec<PriceDeviationDetected>,
    pub borrows: Vec<BorrowEvent>,
    pub repays: Vec<RepayEvent>,
    pub liquidations: Vec<LiquidationEvent>,
    pub supplies: Vec<SupplyEvent>,
}

impl ParsedEvents {
    /// Parse all events from a transaction
    pub fn from_transaction(tx: &ExecutedTransaction) -> Self {
        let mut parsed = Self::default();

        let events = match &tx.events {
            Some(e) => e,
            None => return parsed,
        };

        for event in &events.data {
            let event_name = event.type_.name.as_str();

            match event_name {
                "FlashLoanTaken" => {
                    if let Some(e) = FlashLoanTaken::from_event(event) {
                        parsed.flash_loan_taken.push(e);
                    }
                }
                "FlashLoanRepaid" => {
                    if let Some(e) = FlashLoanRepaid::from_event(event) {
                        parsed.flash_loan_repaid.push(e);
                    }
                }
                "SwapExecuted" => {
                    if let Some(e) = SwapExecuted::from_event(event) {
                        parsed.swaps.push(e);
                    }
                }
                "TWAPUpdated" => {
                    if let Some(e) = TWAPUpdated::from_event(event) {
                        parsed.twap_updates.push(e);
                    }
                }
                "PriceDeviationDetected" => {
                    if let Some(e) = PriceDeviationDetected::from_event(event) {
                        parsed.price_deviations.push(e);
                    }
                }
                "BorrowEvent" => {
                    if let Some(e) = BorrowEvent::from_event(event) {
                        parsed.borrows.push(e);
                    }
                }
                "RepayEvent" => {
                    if let Some(e) = RepayEvent::from_event(event) {
                        parsed.repays.push(e);
                    }
                }
                "LiquidationEvent" => {
                    if let Some(e) = LiquidationEvent::from_event(event) {
                        parsed.liquidations.push(e);
                    }
                }
                "SupplyEvent" => {
                    if let Some(e) = SupplyEvent::from_event(event) {
                        parsed.supplies.push(e);
                    }
                }
                _ => {}  // Ignore unknown events
            }
        }

        parsed
    }

    /// Check if flash loan was taken and repaid in same tx
    pub fn has_complete_flash_loan(&self) -> bool {
        !self.flash_loan_taken.is_empty() && !self.flash_loan_repaid.is_empty()
    }

    /// Check if transaction has swaps
    pub fn has_swaps(&self) -> bool {
        !self.swaps.is_empty()
    }

    /// Check if transaction has lending borrows
    pub fn has_borrows(&self) -> bool {
        !self.borrows.is_empty()
    }

    /// Get total flash loan amount
    pub fn total_flash_loan_amount(&self) -> u64 {
        self.flash_loan_taken.iter().map(|fl| fl.amount).sum()
    }

    /// Get total price impact from swaps
    pub fn total_swap_price_impact(&self) -> u64 {
        self.swaps.iter().map(|s| s.price_impact).sum()
    }

    /// Get max single swap price impact
    pub fn max_swap_price_impact(&self) -> u64 {
        self.swaps.iter().map(|s| s.price_impact).max().unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_parser_names() {
        assert_eq!(SwapExecuted::event_name(), "SwapExecuted");
        assert_eq!(FlashLoanTaken::event_name(), "FlashLoanTaken");
        assert_eq!(BorrowEvent::event_name(), "BorrowEvent");
    }

    #[test]
    fn test_parsed_events_helpers() {
        use std::str::FromStr;
        let mut parsed = ParsedEvents::default();
        assert!(!parsed.has_complete_flash_loan());
        assert!(!parsed.has_swaps());

        parsed.flash_loan_taken.push(FlashLoanTaken {
            pool_id: ObjectID::from_str("0x1").unwrap(),
            borrower: SuiAddress::from_str("0x2").unwrap(),
            amount: 1000,
            fee: 10,
        });
        parsed.flash_loan_repaid.push(FlashLoanRepaid {
            pool_id: ObjectID::from_str("0x1").unwrap(),
            borrower: SuiAddress::from_str("0x2").unwrap(),
            amount: 1000,
            fee: 10,
        });

        assert!(parsed.has_complete_flash_loan());
        assert_eq!(parsed.total_flash_loan_amount(), 1000);
    }
}
