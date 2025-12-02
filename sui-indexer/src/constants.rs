use once_cell::sync::Lazy;
use std::env;

// Package ID
pub static SIMULATION_PACKAGE_ID: Lazy<String> = Lazy::new(|| {
    env::var("SIMULATION_PACKAGE_ID").unwrap_or_else(|_| "0x0".to_string())
});

// Shared Objects
pub static PRICE_ORACLE: Lazy<String> = Lazy::new(|| {
    env::var("PRICE_ORACLE").unwrap_or_else(|_| "0x0".to_string())
});

// Treasury Caps
pub static USDC_TREASURY_CAP: Lazy<String> = Lazy::new(|| {
    env::var("USDC_TREASURY_CAP").unwrap_or_else(|_| "0x0".to_string())
});

pub static USDT_TREASURY_CAP: Lazy<String> = Lazy::new(|| {
    env::var("USDT_TREASURY_CAP").unwrap_or_else(|_| "0x0".to_string())
});

pub static BTC_TREASURY_CAP: Lazy<String> = Lazy::new(|| {
    env::var("BTC_TREASURY_CAP").unwrap_or_else(|_| "0x0".to_string())
});

pub static WETH_TREASURY_CAP: Lazy<String> = Lazy::new(|| {
    env::var("WETH_TREASURY_CAP").unwrap_or_else(|_| "0x0".to_string())
});

pub static SUI_COIN_TREASURY_CAP: Lazy<String> = Lazy::new(|| {
    env::var("SUI_COIN_TREASURY_CAP").unwrap_or_else(|_| "0x0".to_string())
});

// Upgrade Cap
pub static UPGRADE_CAP: Lazy<String> = Lazy::new(|| {
    env::var("UPGRADE_CAP").unwrap_or_else(|_| "0x0".to_string())
});
