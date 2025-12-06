use async_trait::async_trait;
use anyhow::Result;
use crate::action::ActionHandler;
use crate::risk::{RiskEvent, RiskLevel};

pub struct MockDefenseAction {
    enabled: bool,
}

impl MockDefenseAction {
    pub fn new(enabled: bool) -> Self {
        Self { enabled }
    }
}

#[async_trait]
impl ActionHandler for MockDefenseAction {
    async fn handle(&self, event: &RiskEvent) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        // Only trigger defense for High or Critical risks
        match event.risk_level {
            RiskLevel::Critical | RiskLevel::High => {
                println!("🛡️ [MOCK DEFENSE] Initiating emergency protocol pause...");
                println!("🛡️ [MOCK DEFENSE] Target Protocol: {}", event.sender); // In real scenario, this would be the protocol package ID
                println!("🛡️ [MOCK DEFENSE] Reason: {:?}", event.risk_type);
                
                // Simulate some latency for the on-chain transaction
                tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                
                println!("✅ [MOCK DEFENSE] Protocol successfully paused. Further transactions will be reverted.");
            }
            _ => {}
        }

        Ok(())
    }
}
