use async_trait::async_trait;
use anyhow::Result;
use crate::action::ActionHandler;
use crate::risk::{RiskEvent, RiskLevel};

pub struct AlertAction {
    webhook_url: Option<String>,
    min_level: RiskLevel,
}

impl AlertAction {
    pub fn new(webhook_url: Option<String>, min_level: RiskLevel) -> Self {
        Self {
            webhook_url,
            min_level,
        }
    }

    fn should_alert(&self, event: &RiskEvent) -> bool {
        let event_priority = match event.risk_level {
            RiskLevel::Critical => 4,
            RiskLevel::High => 3,
            RiskLevel::Medium => 2,
            RiskLevel::Low => 1,
        };

        let min_priority = match self.min_level {
            RiskLevel::Critical => 4,
            RiskLevel::High => 3,
            RiskLevel::Medium => 2,
            RiskLevel::Low => 1,
        };

        event_priority >= min_priority
    }
}

#[async_trait]
impl ActionHandler for AlertAction {
    async fn handle(&self, event: &RiskEvent) -> Result<()> {
        if !self.should_alert(event) {
            return Ok(());
        }

        if let Some(url) = &self.webhook_url {
            let client = reqwest::Client::new();
            let payload = serde_json::json!({
                "risk_type": format!("{:?}", event.risk_type),
                "risk_level": format!("{:?}", event.risk_level),
                "description": event.description,
                "tx_digest": event.tx_digest,
                "sender": event.sender,
                "checkpoint": event.checkpoint,
                "timestamp_ms": event.timestamp_ms,
                "details": event.details,
            });

            client.post(url)
                .json(&payload)
                .send()
                .await?;
        }

        Ok(())
    }
}

impl Default for AlertAction {
    fn default() -> Self {
        Self::new(None, RiskLevel::High)
    }
}
