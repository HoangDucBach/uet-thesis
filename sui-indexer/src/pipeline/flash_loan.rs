use async_trait::async_trait;
use sui_types::full_checkpoint_content::ExecutedTransaction;
use crate::analyzer::FlashLoanAnalyzer;
use crate::pipeline::RiskDetector;
use crate::risk::{RiskEvent, DetectionContext};

pub struct FlashLoanDetector {
    analyzer: FlashLoanAnalyzer,
}

impl FlashLoanDetector {
    pub fn new() -> Self {
        Self {
            analyzer: FlashLoanAnalyzer::new(),
        }
    }
}

#[async_trait]
impl RiskDetector for FlashLoanDetector {
    fn name(&self) -> &'static str {
        "FlashLoanDetector"
    }

    async fn detect(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Vec<RiskEvent> {
        self.analyzer.analyze(tx, context).into_iter().collect()
    }
}

impl Default for FlashLoanDetector {
    fn default() -> Self {
        Self::new()
    }
}
