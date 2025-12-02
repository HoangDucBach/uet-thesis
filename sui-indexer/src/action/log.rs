use async_trait::async_trait;
use anyhow::Result;
use crate::action::ActionHandler;
use crate::risk::RiskEvent;

pub struct LogAction;

impl LogAction {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl ActionHandler for LogAction {
    async fn handle(&self, event: &RiskEvent) -> Result<()> {
        let level_emoji = match event.risk_level {
            crate::risk::RiskLevel::Critical => "🚨",
            crate::risk::RiskLevel::High => "⚠️",
            crate::risk::RiskLevel::Medium => "⚡",
            crate::risk::RiskLevel::Low => "ℹ️",
        };

        println!(
            "{} [{:?}] {:?} detected: {} (tx: {})",
            level_emoji,
            event.risk_level,
            event.risk_type,
            event.description,
            &event.tx_digest[..8]
        );

        Ok(())
    }
}

impl Default for LogAction {
    fn default() -> Self {
        Self::new()
    }
}
