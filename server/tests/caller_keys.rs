//! Caller keys for people (`/v1/seat/caller-keys`): the seat hands each
//! friend a key of their own, that key can ask but never answer, and it
//! is revoked on its own.

use openhuman_server::build_router;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::AppState;
use serde_json::{json, Value};

const SEAT: &str = "ohk_demo_alice_codex";

async fn serve() -> String {
    let app = build_router(AppState::from_store(MemoryStore::seeded()));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    format!("http://{addr}")
}

fn http() -> reqwest::Client {
    reqwest::Client::new()
}

#[tokio::test]
async fn a_friend_gets_a_key_of_their_own_and_loses_it_alone() {
    let base = serve().await;

    // Mint one for 林晓.
    let r = http()
        .post(format!("{base}/v1/seat/caller-keys"))
        .bearer_auth(SEAT)
        .json(&json!({ "name": "  林晓  " }))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), 201);
    let made: Value = r.json().await.unwrap();
    let key = made["api_key"].as_str().unwrap().to_string();
    let id = made["id"].as_str().unwrap().to_string();
    assert!(key.starts_with("ohk_"));
    assert_eq!(made["name"], "林晓");
    assert!(made["model"].as_str().is_some());

    // The seat sees who holds it — never the key itself.
    let list: Value = http()
        .get(format!("{base}/v1/seat/caller-keys"))
        .bearer_auth(SEAT)
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let rows = list["data"].as_array().unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["name"], "林晓");
    assert_eq!(rows[0]["revoked"], false);
    assert!(!list.to_string().contains(&key));

    // The friend's key can ask (models list) but not manage keys.
    let models = http()
        .get(format!("{base}/v1/models"))
        .bearer_auth(&key)
        .send()
        .await
        .unwrap();
    assert_eq!(models.status(), 200);
    let manage = http()
        .get(format!("{base}/v1/seat/caller-keys"))
        .bearer_auth(&key)
        .send()
        .await
        .unwrap();
    assert_eq!(manage.status(), 403);

    // Revoke: the friend is out, the seat is not.
    let r = http()
        .delete(format!("{base}/v1/seat/caller-keys/{id}"))
        .bearer_auth(SEAT)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), 200);
    let after = http()
        .post(format!("{base}/v1/chat/completions"))
        .bearer_auth(&key)
        .json(&json!({ "model": "openhuman-human", "messages": [{ "role": "user", "content": "hi" }] }))
        .send()
        .await
        .unwrap();
    assert!(
        after.status() == 401 || after.status() == 403,
        "a revoked key still asks: {}",
        after.status()
    );
    let seat = http()
        .get(format!("{base}/v1/seat/caller-keys"))
        .bearer_auth(SEAT)
        .send()
        .await
        .unwrap();
    assert_eq!(seat.status(), 200);
    let list: Value = seat.json().await.unwrap();
    assert_eq!(list["data"][0]["revoked"], true);
}

#[tokio::test]
async fn names_are_checked_and_strangers_cannot_revoke() {
    let base = serve().await;
    for bad in ["", "   ", "a\u{0007}b"] {
        let r = http()
            .post(format!("{base}/v1/seat/caller-keys"))
            .bearer_auth(SEAT)
            .json(&json!({ "name": bad }))
            .send()
            .await
            .unwrap();
        assert_eq!(r.status(), 400, "name {bad:?}");
    }
    let r = http()
        .delete(format!("{base}/v1/seat/caller-keys/key_nobody"))
        .bearer_auth(SEAT)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), 404);
}
