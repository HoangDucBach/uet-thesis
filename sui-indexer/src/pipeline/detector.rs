use async_trait::async_trait;
use sui_types::full_checkpoint_content::ExecutedTransaction;
use crate::risk::{RiskEvent, DetectionContext};

#[async_trait]
pub trait RiskDetector: Send + Sync {
    fn name(&self) -> &'static str;

    async fn detect(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Vec<RiskEvent>;
}

pub struct DetectionPipeline {
    detectors: Vec<Box<dyn RiskDetector>>,
}

impl DetectionPipeline {
    pub fn new() -> Self {
        Self {
            detectors: Vec::new(),
        }
    }

    pub fn add_detector<D: RiskDetector + 'static>(mut self, detector: D) -> Self {
        self.detectors.push(Box::new(detector));
        self
    }

    pub async fn run(
        &self,
        tx: &ExecutedTransaction,
        context: &DetectionContext,
    ) -> Vec<RiskEvent> {
        let mut events = Vec::new();

        for detector in &self.detectors {
            let detector_events = detector.detect(tx, context).await;
            events.extend(detector_events);
        }

        events
    }
}

impl Default for DetectionPipeline {
    fn default() -> Self {
        Self::new()
    }
}
