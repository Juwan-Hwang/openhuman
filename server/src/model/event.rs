//! Event model — realtime notification envelope.
//!
//! See: `protocol/internal-model/event.md`

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Common envelope for all events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    pub event_id: String,
    pub event_type: String,
    pub conversation_id: String,
    pub timestamp: DateTime<Utc>,
    pub data: Value,
}

impl Event {
    pub fn new(
        event_type: impl Into<String>,
        conversation_id: impl Into<String>,
        data: Value,
    ) -> Self {
        Self {
            event_id: format!("evt_{}", uuid::Uuid::now_v7().simple()),
            event_type: event_type.into(),
            conversation_id: conversation_id.into(),
            timestamp: Utc::now(),
            data,
        }
    }
}
