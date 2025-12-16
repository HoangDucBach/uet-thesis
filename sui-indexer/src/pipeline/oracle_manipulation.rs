// Copyright (c) 2024 DeFi Protocol Indexer
// Oracle Manipulation Detector - Pipeline Integration

use async_trait::async_trait;
use sui_types::full_checkpoint_content::ExecutedTransaction;
use crate::analyzer::OracleManipulationAnalyzer;
use crate::pipeline::detector::RiskDetector;
use crate::risk::{RiskEvent, DetectionContext};

/// Oracle manipulation detector for pipeline
pub struct OracleManipulationDetector {
    analyzer: OracleManipulationAnalyzer,
}

impl OracleManipulationDetector {
    pub fn new() -> Self {
        Self {
            analyzer: OracleManipulationAnalyzer::new(),
        }
    }
}

#[async_trait]
impl RiskDetector for OracleManipulationDetector {
    fn name(&self) -> &'static str {
        "OracleManipulation"
    }

    async fn detect(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Vec<RiskEvent> {
        if let Some(event) = self.analyzer.analyze(tx, context) {
            vec![event]
        } else {
            Vec::new()
        }
    }
}

impl Default for OracleManipulationDetector {
    fn default() -> Self {
        Self::new()
    }
}
