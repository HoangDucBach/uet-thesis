use async_trait::async_trait;
use std::time::Instant;

use crate::models::{DetectionResult, DetectionSeverity};

/// Action trait - implement this for custom actions when detections occur
#[async_trait]
pub trait Action: Send + Sync {
    /// Execute the action based on a detection result
    async fn execute(&self, detection: &DetectionResult) -> ActionResult;

    /// Get the action name
    fn action_name(&self) -> &'static str;

    /// Get trigger conditions for this action
    fn trigger_conditions(&self) -> Vec<ActionCondition>;

    /// Whether this action is enabled
    fn is_enabled(&self) -> bool {
        true
    }
}

/// Result of an action execution
#[derive(Debug, Clone)]
pub struct ActionResult {
    pub success: bool,
    pub message: String,
    pub execution_time_ms: u64,
}

impl ActionResult {
    pub fn success(message: String) -> Self {
        Self {
            success: true,
            message,
            execution_time_ms: 0,
        }
    }

    pub fn failure(message: String) -> Self {
        Self {
            success: false,
            message,
            execution_time_ms: 0,
        }
    }
}

/// Conditions for triggering an action
#[derive(Debug, Clone)]
pub struct ActionCondition {
    pub attack_type: Option<String>,
    pub min_confidence: Option<f64>,
    pub min_severity: Option<DetectionSeverity>,
}

impl ActionCondition {
    pub fn new() -> Self {
        Self {
            attack_type: None,
            min_confidence: None,
            min_severity: None,
        }
    }

    pub fn with_attack_type(mut self, attack_type: String) -> Self {
        self.attack_type = Some(attack_type);
        self
    }

    pub fn with_min_confidence(mut self, confidence: f64) -> Self {
        self.min_confidence = Some(confidence);
        self
    }

    pub fn with_min_severity(mut self, severity: DetectionSeverity) -> Self {
        self.min_severity = Some(severity);
        self
    }
}

impl Default for ActionCondition {
    fn default() -> Self {
        Self::new()
    }
}

/// Action manager - orchestrates actions based on detection results
pub struct ActionManager {
    actions: Vec<Box<dyn Action>>,
}

impl ActionManager {
    pub fn new() -> Self {
        Self { actions: vec![] }
    }

    pub fn add_action(mut self, action: Box<dyn Action>) -> Self {
        self.actions.push(action);
        self
    }

    pub fn add_actions(mut self, actions: Vec<Box<dyn Action>>) -> Self {
        self.actions.extend(actions);
        self
    }

    /// Execute all applicable actions for a detection result
    pub async fn execute_actions(&self, detection: &DetectionResult) -> Vec<ActionResult> {
        let mut results = Vec::new();

        for action in &self.actions {
            if !action.is_enabled() {
                continue;
            }

            if self.should_trigger_action(action.as_ref(), detection) {
                let start = Instant::now();
                let mut result = action.execute(detection).await;
                result.execution_time_ms = start.elapsed().as_millis() as u64;
                results.push(result);
            }
        }

        results
    }

    fn should_trigger_action(&self, action: &dyn Action, detection: &DetectionResult) -> bool {
        let conditions = action.trigger_conditions();

        // If no conditions, always trigger
        if conditions.is_empty() {
            return true;
        }

        // Check all conditions (AND logic)
        conditions.iter().all(|condition| {
            // Check attack type
            if let Some(ref attack_type) = condition.attack_type {
                if &detection.attack_type != attack_type {
                    return false;
                }
            }

            // Check confidence threshold
            if let Some(min_confidence) = condition.min_confidence {
                if detection.confidence < min_confidence {
                    return false;
                }
            }

            // Check severity threshold
            if let Some(min_severity) = condition.min_severity {
                if detection.severity < min_severity {
                    return false;
                }
            }

            true
        })
    }

    pub fn actions_count(&self) -> usize {
        self.actions.len()
    }

    pub fn enabled_actions_count(&self) -> usize {
        self.actions.iter().filter(|a| a.is_enabled()).count()
    }
}

impl Default for ActionManager {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Example Action Implementations
// ============================================================================

/// Log action - simply logs the detection
pub struct LogAction;

#[async_trait]
impl Action for LogAction {
    async fn execute(&self, detection: &DetectionResult) -> ActionResult {
        println!(
            "[LOG] Detection: {} - {} (confidence: {:.2}, severity: {:?})",
            detection.detection_id,
            detection.attack_type,
            detection.confidence,
            detection.severity
        );

        ActionResult::success("Detection logged".to_string())
    }

    fn action_name(&self) -> &'static str {
        "log_action"
    }

    fn trigger_conditions(&self) -> Vec<ActionCondition> {
        vec![]
    }
}

/// Slack notification action (placeholder)
pub struct SlackNotificationAction {
    webhook_url: String,
    min_severity: DetectionSeverity,
}

impl SlackNotificationAction {
    pub fn new(webhook_url: String, min_severity: DetectionSeverity) -> Self {
        Self {
            webhook_url,
            min_severity,
        }
    }
}

#[async_trait]
impl Action for SlackNotificationAction {
    async fn execute(&self, detection: &DetectionResult) -> ActionResult {
        // TODO: Implement actual Slack notification
        println!(
            "[SLACK] Would send to {}: {} - {}",
            self.webhook_url, detection.attack_type, detection.detection_id
        );

        ActionResult::success("Slack notification sent".to_string())
    }

    fn action_name(&self) -> &'static str {
        "slack_notification"
    }

    fn trigger_conditions(&self) -> Vec<ActionCondition> {
        vec![ActionCondition::new().with_min_severity(self.min_severity)]
    }
}

/// Email notification action (placeholder)
pub struct EmailNotificationAction {
    recipients: Vec<String>,
    min_confidence: f64,
}

impl EmailNotificationAction {
    pub fn new(recipients: Vec<String>, min_confidence: f64) -> Self {
        Self {
            recipients,
            min_confidence,
        }
    }
}

#[async_trait]
impl Action for EmailNotificationAction {
    async fn execute(&self, detection: &DetectionResult) -> ActionResult {
        // TODO: Implement actual email notification
        println!(
            "[EMAIL] Would send to {:?}: {} - {}",
            self.recipients, detection.attack_type, detection.detection_id
        );

        ActionResult::success("Email notification sent".to_string())
    }

    fn action_name(&self) -> &'static str {
        "email_notification"
    }

    fn trigger_conditions(&self) -> Vec<ActionCondition> {
        vec![ActionCondition::new().with_min_confidence(self.min_confidence)]
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn test_action_manager() {
        let manager = ActionManager::new()
            .add_action(Box::new(LogAction))
            .add_action(Box::new(SlackNotificationAction::new(
                "https://hooks.slack.com/test".to_string(),
                DetectionSeverity::High,
            )));

        assert_eq!(manager.actions_count(), 2);

        let detection = DetectionResult {
            detection_id: "test-1".to_string(),
            attack_type: "test_attack".to_string(),
            confidence: 0.95,
            severity: DetectionSeverity::High,
            evidence: vec!["Evidence 1".to_string()],
            metadata: json!({}),
        };

        let results = manager.execute_actions(&detection).await;
        assert_eq!(results.len(), 2);
        assert!(results.iter().all(|r| r.success));
    }

    #[tokio::test]
    async fn test_action_conditions() {
        let manager = ActionManager::new()
            .add_action(Box::new(SlackNotificationAction::new(
                "https://hooks.slack.com/test".to_string(),
                DetectionSeverity::Critical, // Only critical
            )));

        // High severity - should not trigger
        let detection_high = DetectionResult {
            detection_id: "test-1".to_string(),
            attack_type: "test_attack".to_string(),
            confidence: 0.95,
            severity: DetectionSeverity::High,
            evidence: vec![],
            metadata: json!({}),
        };

        let results = manager.execute_actions(&detection_high).await;
        assert_eq!(results.len(), 0);

        // Critical severity - should trigger
        let detection_critical = DetectionResult {
            detection_id: "test-2".to_string(),
            attack_type: "test_attack".to_string(),
            confidence: 0.95,
            severity: DetectionSeverity::Critical,
            evidence: vec![],
            metadata: json!({}),
        };

        let results = manager.execute_actions(&detection_critical).await;
        assert_eq!(results.len(), 1);
    }
}
