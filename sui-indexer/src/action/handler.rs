use async_trait::async_trait;
use anyhow::Result;
use crate::risk::RiskEvent;

#[async_trait]
pub trait ActionHandler: Send + Sync {
    async fn handle(&self, event: &RiskEvent) -> Result<()>;
}

pub struct ActionPipeline {
    handlers: Vec<Box<dyn ActionHandler>>,
}

impl ActionPipeline {
    pub fn new() -> Self {
        Self {
            handlers: Vec::new(),
        }
    }

    pub fn add_handler<H: ActionHandler + 'static>(mut self, handler: H) -> Self {
        self.handlers.push(Box::new(handler));
        self
    }

    pub async fn run(&self, event: &RiskEvent) {
        for handler in &self.handlers {
            if let Err(e) = handler.handle(event).await {
                eprintln!("⚠ Action handler error: {}", e);
            }
        }
    }
}

impl Default for ActionPipeline {
    fn default() -> Self {
        Self::new()
    }
}
