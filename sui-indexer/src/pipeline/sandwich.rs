use async_trait::async_trait;
use sui_types::full_checkpoint_content::ExecutedTransaction;
use crate::analyzer::SandwichAnalyzer;
use crate::pipeline::RiskDetector;
use crate::risk::{RiskEvent, DetectionContext};

pub struct SandwichDetector {
    analyzer: SandwichAnalyzer,
}

impl SandwichDetector {
    pub fn new() -> Self {
        Self {
            analyzer: SandwichAnalyzer::new(),
        }
    }
}

#[async_trait]
impl RiskDetector for SandwichDetector {
    fn name(&self) -> &'static str {
        "SandwichDetector"
    }

    async fn detect(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Vec<RiskEvent> {
        self.analyzer.analyze(tx, context)
    }
}

impl Default for SandwichDetector {
    fn default() -> Self {
        Self::new()
    }
}
