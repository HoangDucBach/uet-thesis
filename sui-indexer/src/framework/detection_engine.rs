use async_trait::async_trait;
use std::time::Instant;

use crate::models::{Transaction, DetectionResults, DetectionResult};

/// Detection engine trait - implement this for custom detection logic
#[async_trait]
pub trait DetectionEngine: Send + Sync {
    /// Run detection on a transaction
    async fn detect(&self, transaction: &Transaction) -> DetectionResults;

    /// Get the engine name
    fn engine_name(&self) -> &'static str;

    /// Get supported attack types that this engine can detect
    fn supported_attack_types(&self) -> Vec<&'static str>;

    /// Get engine version
    fn version(&self) -> &'static str {
        "1.0.0"
    }

    /// Whether this engine is enabled
    fn is_enabled(&self) -> bool {
        true
    }
}

/// Detection pipeline orchestrator - manages multiple detection engines
pub struct DetectionPipeline {
    engines: Vec<Box<dyn DetectionEngine>>,
    max_parallel: usize,
}

impl DetectionPipeline {
    pub fn new() -> Self {
        Self {
            engines: vec![],
            max_parallel: 4,
        }
    }

    pub fn with_max_parallel(mut self, max_parallel: usize) -> Self {
        self.max_parallel = max_parallel;
        self
    }

    pub fn add_engine(mut self, engine: Box<dyn DetectionEngine>) -> Self {
        self.engines.push(engine);
        self
    }

    pub fn add_engines(mut self, engines: Vec<Box<dyn DetectionEngine>>) -> Self {
        self.engines.extend(engines);
        self
    }

    /// Process a transaction through all detection engines
    pub async fn process_transaction(&self, tx: &Transaction) -> Vec<DetectionResults> {
        let mut all_results = Vec::new();

        for engine in &self.engines {
            if !engine.is_enabled() {
                continue;
            }

            let start = Instant::now();
            let mut results = engine.detect(tx).await;
            results.processing_time_ms = start.elapsed().as_millis() as u64;

            all_results.push(results);
        }

        all_results
    }

    /// Get all registered engines
    pub fn engines(&self) -> &[Box<dyn DetectionEngine>] {
        &self.engines
    }

    /// Get enabled engines count
    pub fn enabled_engines_count(&self) -> usize {
        self.engines.iter().filter(|e| e.is_enabled()).count()
    }
}

impl Default for DetectionPipeline {
    fn default() -> Self {
        Self::new()
    }
}

/// Example dummy detection engine for testing
pub struct DummyDetectionEngine {
    enabled: bool,
}

impl DummyDetectionEngine {
    pub fn new() -> Self {
        Self { enabled: true }
    }

    pub fn disabled() -> Self {
        Self { enabled: false }
    }
}

#[async_trait]
impl DetectionEngine for DummyDetectionEngine {
    async fn detect(&self, transaction: &Transaction) -> DetectionResults {
        DetectionResults {
            engine_name: self.engine_name().to_string(),
            tx_digest: transaction.tx_digest.clone(),
            results: vec![],
            processing_time_ms: 0,
        }
    }

    fn engine_name(&self) -> &'static str {
        "dummy_engine"
    }

    fn supported_attack_types(&self) -> Vec<&'static str> {
        vec!["test_attack"]
    }

    fn is_enabled(&self) -> bool {
        self.enabled
    }
}

impl Default for DummyDetectionEngine {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::NewTransaction;
    use chrono::Utc;
    use serde_json::json;

    #[tokio::test]
    async fn test_detection_pipeline() {
        let pipeline = DetectionPipeline::new()
            .add_engine(Box::new(DummyDetectionEngine::new()))
            .add_engine(Box::new(DummyDetectionEngine::disabled()));

        assert_eq!(pipeline.engines().len(), 2);
        assert_eq!(pipeline.enabled_engines_count(), 1);

        let tx = Transaction {
            id: Some(1),
            tx_digest: "test".to_string(),
            checkpoint_sequence_number: 1,
            sender: "0x123".to_string(),
            gas_owner: None,
            gas_budget: 1000000,
            gas_used: None,
            gas_price: 1000,
            execution_status: "success".to_string(),
            timestamp_ms: 1234567890,
            transaction_kind: "ProgrammableTransaction".to_string(),
            is_system_tx: false,
            is_sponsored_tx: false,
            is_end_of_epoch_tx: false,
            total_move_calls: 0,
            total_input_objects: 0,
            total_shared_objects: 0,
            computation_cost: None,
            storage_cost: None,
            storage_rebate: None,
            expiration_epoch: None,
            raw_transaction_data: json!({}),
            processed_at: Utc::now(),
            updated_at: None,
        };

        let results = pipeline.process_transaction(&tx).await;
        assert_eq!(results.len(), 1); // Only enabled engine should run
    }
}
