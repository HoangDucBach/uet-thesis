use async_trait::async_trait;
use sui_types::full_checkpoint_content::ExecutedTransaction;
use crate::analyzer::PriceAnalyzer;
use crate::pipeline::RiskDetector;
use crate::risk::{RiskEvent, DetectionContext};

pub struct PriceManipulationDetector {
    analyzer: PriceAnalyzer,
}

impl PriceManipulationDetector {
    pub fn new() -> Self {
        Self {
            analyzer: PriceAnalyzer::new(),
        }
    }
}

#[async_trait]
impl RiskDetector for PriceManipulationDetector {
    fn name(&self) -> &'static str {
        "PriceManipulationDetector"
    }

    async fn detect(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Vec<RiskEvent> {
        self.analyzer.analyze(tx, context).into_iter().collect()
    }
}

impl Default for PriceManipulationDetector {
    fn default() -> Self {
        Self::new()
    }
}
