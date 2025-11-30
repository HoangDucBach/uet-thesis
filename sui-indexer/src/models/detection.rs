use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

/// Detection results from a detection engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectionResults {
    pub engine_name: String,
    pub tx_digest: String,
    pub results: Vec<DetectionResult>,
    pub processing_time_ms: u64,
}

/// Individual detection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetectionResult {
    pub detection_id: String,
    pub attack_type: String,
    pub confidence: f64,
    pub severity: DetectionSeverity,
    pub evidence: Vec<String>,
    pub metadata: JsonValue,
}

/// Detection severity levels
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum DetectionSeverity {
    Info,
    Low,
    Medium,
    High,
    Critical,
}

impl DetectionSeverity {
    pub fn as_str(&self) -> &'static str {
        match self {
            DetectionSeverity::Info => "info",
            DetectionSeverity::Low => "low",
            DetectionSeverity::Medium => "medium",
            DetectionSeverity::High => "high",
            DetectionSeverity::Critical => "critical",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "info" => DetectionSeverity::Info,
            "low" => DetectionSeverity::Low,
            "medium" => DetectionSeverity::Medium,
            "high" => DetectionSeverity::High,
            "critical" => DetectionSeverity::Critical,
            _ => DetectionSeverity::Info,
        }
    }
}

impl ToString for DetectionSeverity {
    fn to_string(&self) -> String {
        self.as_str().to_string()
    }
}

impl DetectionResult {
    pub fn new(
        detection_id: String,
        attack_type: String,
        confidence: f64,
        severity: DetectionSeverity,
    ) -> Self {
        Self {
            detection_id,
            attack_type,
            confidence,
            severity,
            evidence: vec![],
            metadata: JsonValue::Null,
        }
    }

    pub fn add_evidence(&mut self, evidence: String) {
        self.evidence.push(evidence);
    }

    pub fn set_metadata(&mut self, metadata: JsonValue) {
        self.metadata = metadata;
    }
}

impl DetectionResults {
    pub fn new(engine_name: String, tx_digest: String) -> Self {
        Self {
            engine_name,
            tx_digest,
            results: vec![],
            processing_time_ms: 0,
        }
    }

    pub fn add_result(&mut self, result: DetectionResult) {
        self.results.push(result);
    }

    pub fn has_detections(&self) -> bool {
        !self.results.is_empty()
    }

    pub fn highest_severity(&self) -> Option<DetectionSeverity> {
        self.results.iter().map(|r| r.severity).max()
    }

    pub fn highest_confidence(&self) -> Option<f64> {
        self.results.iter().map(|r| r.confidence).max_by(|a, b| a.partial_cmp(b).unwrap())
    }
}
