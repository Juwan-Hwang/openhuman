//! Webhook `/test` result shape: every failure mode (refused connection,
//! blocked name, a non-2xx answer) returns the identical body so /test is
//! no port/host oracle; only a 2xx answer carries its status code.

use openhuman_server::api::stored::{self, Stored};
use openhuman_server::build_router;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::AppState;
use serde_json::{json, Value};

const KEY: &str = "ohk_demo_alice_codex";
const OWNER: &str = "agt_demo_codex";

async fn app() -> String {
    let app = build_router(AppState::from_store(MemoryStore::seeded()));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    addr
}

async fn post(addr: &str, path: &str, body: Value) -> (u16, Value) {
    let r = reqwest::Client::new()
        .post(format!("http://{addr}{path}"))
        .header("Authorization", format!("Bearer {KEY}"))
        .json(&body)
        .send()
        .await
        .unwrap();
    let s = r.status().as_u16();
    (s, r.json().await.unwrap_or(json!(null)))
}

/// A tiny receiver on loopback that answers every POST with `status`.
async fn hook_server(status: axum::http::StatusCode) -> String {
    let app =
        axum::Router::new().route("/hook", axum::routing::post(move || async move { status }));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap().to_string();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    addr
}

fn put_endpoint(id: &str, url: String) {
    stored::put(
        id,
        Stored {
            owner: OWNER.to_string(),
            obj: json!({"id": id, "object": "webhook_endpoint", "url": url,
                        "event_types": ["response.completed"], "status": "enabled"}),
            input: Vec::new(),
            history: Vec::new(),
        },
    );
}

#[tokio::test]
async fn webhook_test_result_is_uniform() {
    let addr = app().await;
    // a loopback literal (connection refused) and a loopback name (the
    // blocking DNS resolver refuses it). Registered straight into the
    // store, since create would reject these URLs on sight.
    // A third endpoint answers 401: a non-2xx must look the same as a
    // refused connection and a blocked name.
    let rejecting = hook_server(axum::http::StatusCode::UNAUTHORIZED).await;
    let uid = uuid::Uuid::new_v4().simple().to_string();
    let ids = [
        format!("whep_uniform_a_{uid}"),
        format!("whep_uniform_b_{uid}"),
        format!("whep_uniform_c_{uid}"),
    ];
    for (id, url) in [
        (&ids[0], "http://127.0.0.1:9/hook".to_string()),
        (&ids[1], "http://localhost:9/hook".to_string()),
        (&ids[2], format!("http://{rejecting}/hook")),
    ] {
        put_endpoint(id, url);
    }
    let mut bodies = Vec::new();
    for id in &ids {
        let (s, v) = post(
            &addr,
            &format!("/v1/webhook_endpoints/{id}/test"),
            json!({"event_type": "response.completed"}),
        )
        .await;
        assert_eq!(s, 200, "{v}");
        bodies.push(v);
    }
    for b in &mut bodies {
        b.as_object_mut().unwrap().remove("webhook_endpoint_id");
    }
    assert_eq!(
        bodies[0], bodies[1],
        "every failure mode returns the identical result"
    );
    assert_eq!(
        bodies[0], bodies[2],
        "a non-2xx answer returns the identical result"
    );
    assert!(bodies[0].get("status_code").is_none(), "{}", bodies[0]);
}

#[tokio::test]
async fn webhook_test_success_carries_status_code() {
    let addr = app().await;
    let ok = hook_server(axum::http::StatusCode::NO_CONTENT).await;
    let id = format!("whep_success_{}", uuid::Uuid::new_v4().simple());
    put_endpoint(&id, format!("http://{ok}/hook"));
    let (s, v) = post(
        &addr,
        &format!("/v1/webhook_endpoints/{id}/test"),
        json!({"event_type": "response.completed"}),
    )
    .await;
    assert_eq!(s, 200, "{v}");
    assert_eq!(v["success"], json!(true), "{v}");
    assert_eq!(v["status_code"], json!(204), "{v}");
}
