//! ObjectRepository contract tests: the same expectations run against
//! the memory store always and the postgres store when DATABASE_URL is
//! set. Covers put/get round trips, owner scoping, kind-filtered
//! listing, in-place update, replacement and the per-owner cap.

use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::postgres::PostgresStore;
use openhuman_server::storage::traits::{ObjectRepository, StoredObject};
use serde_json::json;

fn store_obj(id: &str, name: &str, active: i64) -> StoredObject {
    StoredObject {
        obj: json!({
            "id": id,
            "object": "vector_store",
            "created_at": active,
            "name": name,
            "last_active_at": active,
        }),
        input: vec![json!({"id": "file-1", "object": "vector_store.file"})],
        history: vec![json!({"role": "assistant", "content": "prior step"})],
    }
}

async fn round_trip(repo: &dyn ObjectRepository) {
    let owner = "agt_vs_rt";
    let id = format!("vs_rt_{}", uuid::Uuid::now_v7().simple());
    let want = store_obj(&id, "papers", 10);
    repo.put_object(&id, owner, want.clone()).await;
    let v = repo.get_object(owner, &id).await.expect("stored");
    assert_eq!(v.obj["name"], "papers");
    assert_eq!(v.input, want.input);
    assert_eq!(v.history, want.history);
    // Owner scoping: another owner sees nothing.
    assert!(repo.get_object("agt_someone_else", &id).await.is_none());
    // Replacement: same id overwrites.
    let mut renamed = store_obj(&id, "renamed", 20);
    renamed.input = Vec::new();
    renamed.history = Vec::new();
    repo.put_object(&id, owner, renamed).await;
    let v = repo.get_object(owner, &id).await.expect("replaced");
    assert_eq!(v.obj["name"], "renamed");
    assert!(v.input.is_empty());
}

async fn update_in_place(repo: &dyn ObjectRepository) {
    let owner = "agt_obj_upd";
    let id = format!("thread_{}", uuid::Uuid::now_v7().simple());
    let mut o = store_obj(&id, "t", 5);
    o.obj["object"] = json!("thread");
    repo.put_object(&id, owner, o).await;
    assert!(
        repo.update_object(&id, &|s| {
            s.input.push(json!({"id": "msg_1"}));
            s.history.push(json!({"role": "tool", "content": "42"}));
            s.obj["metadata"] = json!({"k": "v"});
        })
        .await
    );
    let v = repo.get_object(owner, &id).await.expect("updated");
    assert_eq!(v.input.len(), 2);
    assert_eq!(v.history.len(), 2);
    assert_eq!(v.obj["metadata"]["k"], "v");
    assert!(!repo.update_object("no-such-object", &|_| {}).await);
}

async fn list_filters_kind_and_orders_by_activity(repo: &dyn ObjectRepository) {
    let owner = "agt_vs_list";
    let tag = uuid::Uuid::now_v7().simple().to_string();
    let a = format!("vs_la_{tag}");
    let b = format!("vs_lb_{tag}");
    let batch = format!("vsfb_{tag}");
    repo.put_object(&a, owner, store_obj(&a, "a", 100)).await;
    repo.put_object(&b, owner, store_obj(&b, "b", 200)).await;
    let mut bobj = store_obj(&batch, "batch", 300);
    bobj.obj["object"] = json!("vector_store.files_batch");
    repo.put_object(&batch, owner, bobj).await;
    let rows = repo.list_objects(owner, "vector_store").await;
    let names: Vec<&str> = rows
        .iter()
        .filter(|(id, _)| id.ends_with(&tag.to_string()))
        .map(|(_, v)| v.obj["name"].as_str().unwrap_or(""))
        .collect();
    assert_eq!(names, vec!["b", "a"]);
}

async fn delete_is_owner_scoped(repo: &dyn ObjectRepository) {
    let id = format!("vs_del_{}", uuid::Uuid::now_v7().simple());
    repo.put_object(&id, "agt_a", store_obj(&id, "x", 1)).await;
    assert!(!repo.delete_object("agt_b", &id).await);
    assert!(repo.get_object("agt_a", &id).await.is_some());
    assert!(repo.delete_object("agt_a", &id).await);
    assert!(repo.get_object("agt_a", &id).await.is_none());
}

async fn cap_evicts_least_active(repo: &dyn ObjectRepository) {
    // Only meaningful with a tiny cap; the default (2000) makes this a
    // no-op so the full suite stays fast. Run it explicitly with
    // OPENHUMAN_API_OBJECTS_MAX_PER_OWNER=1 to exercise eviction.
    if std::env::var("OPENHUMAN_API_OBJECTS_MAX_PER_OWNER").is_err() {
        return;
    }
    let owner = "agt_vs_cap";
    let tag = uuid::Uuid::now_v7().simple().to_string();
    let old = format!("vs_old_{tag}");
    let new = format!("vs_new_{tag}");
    repo.put_object(&old, owner, store_obj(&old, "old", 1))
        .await;
    repo.put_object(&new, owner, store_obj(&new, "new", 2))
        .await;
    assert!(repo.get_object(owner, &old).await.is_none());
    assert!(repo.get_object(owner, &new).await.is_some());
}

#[tokio::test]
async fn memory_round_trip() {
    round_trip(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_update_in_place() {
    update_in_place(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_list_filters_and_orders() {
    list_filters_kind_and_orders_by_activity(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_delete_owner_scoped() {
    delete_is_owner_scoped(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_cap_evicts() {
    cap_evicts_least_active(&MemoryStore::new()).await;
}

async fn pg_store() -> Option<PostgresStore> {
    let url = std::env::var("DATABASE_URL").ok()?;
    let store = PostgresStore::new(&url).await.ok()?;
    let _ = store.migrate().await;
    Some(store)
}

#[tokio::test]
async fn postgres_round_trip() {
    let Some(store) = pg_store().await else {
        return;
    };
    round_trip(&store).await;
}

#[tokio::test]
async fn postgres_update_in_place() {
    let Some(store) = pg_store().await else {
        return;
    };
    update_in_place(&store).await;
}

#[tokio::test]
async fn postgres_list_filters_and_orders() {
    let Some(store) = pg_store().await else {
        return;
    };
    list_filters_kind_and_orders_by_activity(&store).await;
}

#[tokio::test]
async fn postgres_delete_owner_scoped() {
    let Some(store) = pg_store().await else {
        return;
    };
    delete_is_owner_scoped(&store).await;
}

#[tokio::test]
async fn postgres_cap_evicts() {
    let Some(store) = pg_store().await else {
        return;
    };
    cap_evicts_least_active(&store).await;
}
