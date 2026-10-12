//! Message content block — text, structured, multipart.
//!
//! See: `protocol/internal-model/message.md` §3

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// The payload of a Message. Exactly one variant per message.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ContentBlock {
    #[serde(rename = "text")]
    Text { text: String },

    #[serde(rename = "structured")]
    Structured { schema: Value, data: Value },

    #[serde(rename = "multipart")]
    Multipart { parts: Vec<ContentBlock> },
}

impl ContentBlock {
    /// Convenience: create a text content block.
    pub fn text(text: impl Into<String>) -> Self {
        ContentBlock::Text { text: text.into() }
    }

    /// Extract plain text if this is a Text block; otherwise None.
    pub fn as_text(&self) -> Option<&str> {
        match self {
            ContentBlock::Text { text } => Some(text),
            _ => None,
        }
    }
}

/// An attachment reference (file, image, etc.).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attachment {
    pub id: String,
    pub filename: String,
    pub content_type: String,
    pub size_bytes: u64,
    pub url: String,
}
