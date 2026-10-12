//! Notification Dispatcher — pushes notifications when human is offline.
//!
//! Supports:
//! 1. Google Firebase FCM v1 native push notifications (Android / iOS).
//! 2. Webhook notifications via `NOTIFICATION_WEBHOOK_URL` (Bark, Feishu, DingTalk, etc.).

use serde_json::json;
use std::collections::HashMap;
use std::sync::RwLock;
use std::time::Duration;

static DEVICE_TOKENS: RwLock<Option<HashMap<String, String>>> = RwLock::new(None);

/// Register or update a human's FCM device token.
pub fn register_device_token(human_id: String, device_token: String) {
    if device_token.trim().is_empty() {
        return;
    }
    tracing::info!(human_id = %human_id, "Registered device token for FCM push notification");
    if let Ok(mut lock) = DEVICE_TOKENS.write() {
        let map = lock.get_or_insert_with(HashMap::new);
        map.insert(human_id, device_token);
    }
}

/// Retrieve the active device token for a human.
pub fn get_device_token(human_id: &str) -> Option<String> {
    if let Ok(lock) = DEVICE_TOKENS.read() {
        if let Some(map) = lock.as_ref() {
            if let Some(token) = map.get(human_id) {
                return Some(token.clone());
            }
        }
    }
    std::env::var("DEFAULT_FCM_DEVICE_TOKEN")
        .ok()
        .filter(|s| !s.trim().is_empty())
}

#[derive(serde::Deserialize)]
struct ServiceAccountKey {
    project_id: String,
    private_key: String,
    client_email: String,
    #[serde(default = "default_token_uri")]
    token_uri: String,
}

fn default_token_uri() -> String {
    "https://oauth2.googleapis.com/token".to_string()
}

#[derive(serde::Serialize)]
struct GoogleJwtClaims<'a> {
    iss: &'a str,
    scope: &'a str,
    aud: &'a str,
    exp: usize,
    iat: usize,
}

async fn get_google_access_token(
    sa: &ServiceAccountKey,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let now = chrono::Utc::now().timestamp() as usize;
    let claims = GoogleJwtClaims {
        iss: &sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: &sa.token_uri,
        exp: now + 3600,
        iat: now,
    };

    let header = jsonwebtoken::Header::new(jsonwebtoken::Algorithm::RS256);
    let key = jsonwebtoken::EncodingKey::from_rsa_pem(sa.private_key.as_bytes())?;
    let token = jsonwebtoken::encode(&header, &claims, &key)?;

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()?;

    let params = [
        ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
        ("assertion", &token),
    ];

    let resp = client.post(&sa.token_uri).form(&params).send().await?;
    let json: serde_json::Value = resp.json().await?;
    let access_token = json["access_token"]
        .as_str()
        .ok_or_else(|| format!("No access_token in Google OAuth response: {:?}", json))?
        .to_string();

    Ok(access_token)
}

async fn send_fcm_notification(
    sa: &ServiceAccountKey,
    device_token: &str,
    title: &str,
    body: &str,
    conversation_id: &str,
    agent_name: &str,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let access_token = get_google_access_token(sa).await?;
    let fcm_url = format!(
        "https://fcm.googleapis.com/v1/projects/{}/messages:send",
        sa.project_id
    );

    let message = json!({
        "message": {
            "token": device_token,
            "notification": {
                "title": title,
                "body": body,
            },
            "data": {
                "conversation_id": conversation_id,
                "agent_name": agent_name,
                "click_action": "FLUTTER_NOTIFICATION_CLICK"
            },
            "android": {
                "priority": "high",
                "notification": {
                    "channel_id": "openhuman_high_importance",
                    "sound": "default",
                    "priority": "high",
                    "default_sound": true,
                    "default_vibrate_timings": true
                }
            }
        }
    });

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()?;

    let resp = client
        .post(&fcm_url)
        .bearer_auth(&access_token)
        .json(&message)
        .send()
        .await?;

    if resp.status().is_success() {
        tracing::info!(status = %resp.status(), "FCM push notification sent successfully");
    } else {
        let err_text = resp.text().await.unwrap_or_default();
        tracing::warn!("FCM push notification returned non-success: {}", err_text);
    }

    Ok(())
}

/// Asynchronously dispatch an offline notification.
///
/// Runs in a background Tokio task so it never blocks HTTP request handling.
pub fn dispatch_offline_notification(
    human_id: String,
    agent_name: String,
    conversation_id: String,
    message_preview: String,
) {
    tokio::spawn(async move {
        let title = format!("🔔 [OpenHuman] 来自 {} 的新请求", agent_name);
        let preview_truncated = if message_preview.chars().count() > 200 {
            let s: String = message_preview.chars().take(200).collect();
            format!("{}...", s)
        } else {
            message_preview
        };

        // ── 1. Google Firebase FCM Push ──
        if let Some(device_token) = get_device_token(&human_id) {
            let key_path = std::env::var("FIREBASE_KEY_PATH")
                .unwrap_or_else(|_| "/app/firebase-key.json".to_string());

            if let Ok(key_data) = tokio::fs::read_to_string(&key_path).await {
                match serde_json::from_str::<ServiceAccountKey>(&key_data) {
                    Ok(sa) => {
                        tracing::info!(
                            human_id = %human_id,
                            project_id = %sa.project_id,
                            "Dispatching FCM v1 push notification..."
                        );
                        if let Err(e) = send_fcm_notification(
                            &sa,
                            &device_token,
                            &title,
                            &preview_truncated,
                            &conversation_id,
                            &agent_name,
                        )
                        .await
                        {
                            tracing::warn!("Failed to send FCM notification: {}", e);
                        }
                    }
                    Err(e) => {
                        tracing::warn!("Failed to parse Firebase service account key: {}", e);
                    }
                }
            } else {
                tracing::debug!("No firebase key file found at {}, skipping FCM", key_path);
            }
        }

        // ── 2. Generic Webhook (Bark, Feishu, etc.) ──
        if let Ok(webhook_url) = std::env::var("NOTIFICATION_WEBHOOK_URL") {
            let webhook_url = webhook_url.trim();
            if !webhook_url.is_empty() {
                if let Ok(client) = reqwest::Client::builder()
                    .timeout(Duration::from_secs(5))
                    .build()
                {
                    let mut payload = json!({
                        "title": title,
                        "body": preview_truncated,
                        "human_id": human_id,
                        "agent_name": agent_name,
                        "conversation_id": conversation_id,
                        // Bark compatibility
                        "group": "OpenHuman",
                        // Feishu compatibility
                        "msg_type": "text",
                        "content": {
                            "text": format!("{}\n\n{}", title, preview_truncated)
                        }
                    });

                    // Only append public url if configured
                    if let Ok(public_url) = std::env::var("SERVER_PUBLIC_URL") {
                        if !public_url.trim().is_empty() {
                            payload["url"] = json!(public_url.trim());
                        }
                    }

                    tracing::info!(
                        webhook = %webhook_url,
                        agent = %agent_name,
                        "Dispatching offline notification to external webhook..."
                    );

                    let _ = client.post(webhook_url).json(&payload).send().await;
                }
            }
        }
    });
}
