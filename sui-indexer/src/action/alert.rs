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

    fn get_color(&self, level: &RiskLevel) -> u32 {
        match level {
            RiskLevel::Critical => 0xFF0000, // Red
            RiskLevel::High => 0xE67E22,     // Orange
            RiskLevel::Medium => 0xF1C40F,   // Yellow
            RiskLevel::Low => 0x3498DB,      // Blue
        }
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
            
            // Format details as fields
            let mut fields = vec![
                serde_json::json!({
                    "name": "Transaction",
                    "value": format!("[View on Explorer](https://suiscan.xyz/testnet/tx/{})", event.tx_digest),
                    "inline": true
                }),
                serde_json::json!({
                    "name": "Sender",
                    "value": format!("`{}`", event.sender),
                    "inline": true
                }),
                serde_json::json!({
                    "name": "Checkpoint",
                    "value": event.checkpoint.to_string(),
                    "inline": true
                }),
            ];

            // Add specific details if available
            for (key, value) in &event.details {
                fields.push(serde_json::json!({
                    "name": key,
                    "value": format!("`{}`", value),
                    "inline": false
                }));
            }

            let payload = serde_json::json!({
                "username": "Sui Security Bot",
                "avatar_url": "https://cryptologos.cc/logos/sui-sui-logo.png",
                "embeds": [{
                    "title": format!("🚨 {:?} Security Alert Detected!", event.risk_type),
                    "description": event.description,
                    "color": self.get_color(&event.risk_level),
                    "fields": fields,
                    "footer": {
                        "text": format!("Risk Level: {:?}", event.risk_level)
                    },
                    "timestamp": chrono::Utc::now().to_rfc3339()
                }]
            });

            match client.post(url).json(&payload).send().await {
                Ok(_) => println!("✅ Alert sent to Discord"),
                Err(e) => println!("❌ Failed to send alert to Discord: {}", e),
            }
        }

        Ok(())
    }
}

impl Default for AlertAction {
    fn default() -> Self {
        Self::new(None, RiskLevel::High)
    }
}
