//! Connection Registry — manages online human WebSocket connections.
//!
//! Phase 6: Realtime message routing layer.
//!
//! # Multi-Device Support
//!
//! A single human can have multiple simultaneous connections
//! (phone + desktop + web). The registry maps:
//!
//! ```text
//!   human_id → { device_id_1 → tx, device_id_2 → tx, ... }
//! ```
//!
//! When a message arrives for a human, it is fanned out to **all**
//! connected devices. Each device independently ACKs receipt.
//!
//! # Offline Handling
//!
//! If no connections exist for a human, `send_to_human` returns `false`.
//! The caller (message service) is responsible for persisting the
//! message — it is already stored in `MessageRepository` before the
//! push attempt. When the human reconnects, pending messages are
//! delivered from the `MessageRepository` (see `drain_pending`).

use std::collections::HashMap;
use std::sync::Arc;

use tokio::sync::mpsc;
use tokio::sync::Mutex;

/// A unique device identifier for a WebSocket connection.
///
/// Generated server-side as a UUIDv7 to ensure uniqueness
/// even across reconnections.
pub type DeviceId = String;

/// The sender side of a per-connection mpsc channel.
///
/// The WebSocket sender task drains this channel and writes
/// each `String` (a serialized JSON event) to the socket.
pub type ConnectionTx = mpsc::UnboundedSender<String>;

/// Internal map state: human_id → (device_id → tx).
#[derive(Default)]
struct RegistryInner {
    /// human_id → map of device_id → tx channel.
    connections: HashMap<String, HashMap<DeviceId, ConnectionTx>>,
}

/// Thread-safe, multi-device connection registry.
///
/// Shared via `Arc` inside `AppState`. Clone is cheap.
///
/// # Lifecycle
///
/// ```text
/// WS connect → authenticate → register(human_id, device_id, tx)
///                                     ↓
/// Agent sends message → send_to_human(human_id, event_json)
///                                     ↓
/// Fan-out to ALL devices of that human
///                                     ↓
/// WS disconnect → unregister(human_id, device_id)
/// ```
#[derive(Clone)]
pub struct ConnectionRegistry {
    inner: Arc<Mutex<RegistryInner>>,
}

impl ConnectionRegistry {
    /// Create an empty registry.
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(RegistryInner::default())),
        }
    }

    /// Register a new device connection for a human.
    ///
    /// If the human already has other device connections, the new
    /// device is added to the set. All devices will receive
    /// subsequent `send_to_human` calls.
    pub async fn register(&self, human_id: &str, device_id: &str, tx: ConnectionTx) {
        let mut inner = self.inner.lock().await;
        inner
            .connections
            .entry(human_id.to_string())
            .or_default()
            .insert(device_id.to_string(), tx);
        tracing::info!(
            "WS registered: human_id={}, device_id={}",
            human_id,
            device_id
        );
    }

    /// Remove a specific device connection for a human.
    ///
    /// If this was the last device for the human, the human entry
    /// is removed entirely (they are now "offline").
    pub async fn unregister(&self, human_id: &str, device_id: &str) {
        let mut inner = self.inner.lock().await;
        if let Some(devices) = inner.connections.get_mut(human_id) {
            devices.remove(device_id);
            if devices.is_empty() {
                inner.connections.remove(human_id);
            }
        }
        tracing::info!(
            "WS unregistered: human_id={}, device_id={}",
            human_id,
            device_id
        );
    }

    /// Send a JSON event to **all** connected devices of a human.
    ///
    /// Returns `true` if at least one device received the event.
    /// Returns `false` if the human has no active connections (offline).
    ///
    /// Dead channels (receiver dropped) are silently cleaned up.
    pub async fn send_to_human(&self, human_id: &str, event_json: &str) -> bool {
        let mut inner = self.inner.lock().await;
        let Some(devices) = inner.connections.get_mut(human_id) else {
            return false;
        };

        let mut delivered_count = 0;
        let mut dead_devices = Vec::new();

        for (device_id, tx) in devices.iter() {
            match tx.send(event_json.to_string()) {
                Ok(()) => delivered_count += 1,
                Err(_) => {
                    tracing::warn!(
                        "Dead WS channel: human_id={}, device_id={}",
                        human_id,
                        device_id
                    );
                    dead_devices.push(device_id.clone());
                }
            }
        }

        // Cleanup dead channels.
        for device_id in dead_devices {
            devices.remove(&device_id);
        }
        if devices.is_empty() {
            inner.connections.remove(human_id);
        }

        delivered_count > 0
    }

    /// Check if a human has any active connections (is online).
    pub async fn is_online(&self, human_id: &str) -> bool {
        let inner = self.inner.lock().await;
        inner
            .connections
            .get(human_id)
            .map(|d| !d.is_empty())
            .unwrap_or(false)
    }

    /// Get the number of active connections for a human.
    pub async fn connection_count(&self, human_id: &str) -> usize {
        let inner = self.inner.lock().await;
        inner
            .connections
            .get(human_id)
            .map(|d| d.len())
            .unwrap_or(0)
    }
}

impl Default for ConnectionRegistry {
    fn default() -> Self {
        Self::new()
    }
}

// ── Tests ──

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_register_and_send() {
        let registry = ConnectionRegistry::new();
        let (tx, mut rx) = mpsc::unbounded_channel();

        registry.register("hum_001", "dev_mobile", tx).await;

        assert!(registry.is_online("hum_001").await);
        assert_eq!(registry.connection_count("hum_001").await, 1);

        let delivered = registry.send_to_human("hum_001", "hello").await;
        assert!(delivered);

        let msg = rx.recv().await.unwrap();
        assert_eq!(msg, "hello");
    }

    #[tokio::test]
    async fn test_multi_device() {
        let registry = ConnectionRegistry::new();
        let (tx1, mut rx1) = mpsc::unbounded_channel();
        let (tx2, mut rx2) = mpsc::unbounded_channel();

        registry.register("hum_001", "dev_mobile", tx1).await;
        registry.register("hum_001", "dev_desktop", tx2).await;

        assert_eq!(registry.connection_count("hum_001").await, 2);

        let delivered = registry.send_to_human("hum_001", "fanout").await;
        assert!(delivered);

        assert_eq!(rx1.recv().await.unwrap(), "fanout");
        assert_eq!(rx2.recv().await.unwrap(), "fanout");
    }

    #[tokio::test]
    async fn test_unregister_last_device() {
        let registry = ConnectionRegistry::new();
        let (tx, _rx) = mpsc::unbounded_channel();

        registry.register("hum_001", "dev_mobile", tx).await;
        assert!(registry.is_online("hum_001").await);

        registry.unregister("hum_001", "dev_mobile").await;
        assert!(!registry.is_online("hum_001").await);
    }

    #[tokio::test]
    async fn test_send_to_offline_human() {
        let registry = ConnectionRegistry::new();
        let delivered = registry.send_to_human("hum_nonexistent", "hello").await;
        assert!(!delivered);
    }

    #[tokio::test]
    async fn test_unregister_one_of_multi() {
        let registry = ConnectionRegistry::new();
        let (tx1, _rx1) = mpsc::unbounded_channel();
        let (tx2, mut rx2) = mpsc::unbounded_channel();

        registry.register("hum_001", "dev_mobile", tx1).await;
        registry.register("hum_001", "dev_desktop", tx2).await;

        registry.unregister("hum_001", "dev_mobile").await;
        assert_eq!(registry.connection_count("hum_001").await, 1);
        assert!(registry.is_online("hum_001").await);

        // Desktop should still receive.
        let delivered = registry.send_to_human("hum_001", "still here").await;
        assert!(delivered);
        assert_eq!(rx2.recv().await.unwrap(), "still here");
    }
}
