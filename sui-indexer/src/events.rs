use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct SwapExecutedEvent {
    pub pool_id: [u8; 32],
    pub sender: [u8; 32],
    pub token_in: bool,
    pub amount_in: u64,
    pub amount_out: u64,
    pub fee_amount: u64,
    pub reserve_a: u64,
    pub reserve_b: u64,
    pub price_impact: u64,
}

#[derive(Debug, Deserialize)]
pub struct FlashLoanTakenEvent {
    pub pool_id: [u8; 32],
    pub borrower: [u8; 32],
    pub amount: u64,
    pub fee: u64,
}

#[derive(Debug, Deserialize)]
pub struct FlashLoanRepaidEvent {
    pub pool_id: [u8; 32],
    pub borrower: [u8; 32],
    pub amount: u64,
    pub fee: u64,
}

#[derive(Debug, Deserialize)]
pub struct TWAPUpdatedEvent {
    pub pool_id: [u8; 32],
    pub token_a: Vec<u8>,
    pub token_b: Vec<u8>,
    pub twap_price_a: u64,
    pub twap_price_b: u64,
    pub spot_price_a: u64,
    pub spot_price_b: u64,
    pub price_deviation: u64,
    pub timestamp: u64,
}

#[derive(Debug, Deserialize)]
pub struct PriceDeviationDetectedEvent {
    pub pool_id: [u8; 32],
    pub token_a: Vec<u8>,
    pub token_b: Vec<u8>,
    pub twap_price: u64,
    pub spot_price: u64,
    pub deviation_bps: u64,
    pub timestamp: u64,
}

