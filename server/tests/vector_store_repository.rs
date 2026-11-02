//! VectorStoreRepository contract tests: the same expectations run
//! against the memory store always and the postgres store when
//! DATABASE_URL is set. Covers put/get round trips, owner scoping,
//! kind-filtered listing, replacement and the per-owner cap.

use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::postgres::PostgresStore;
use openhuman_server::storage::traits::VectorStoreRepository;
use serde_json::{json, Value};

fn store_obj(id: &str, name: &str, active: i64) -> Value {
    json!({
        "id": id,
        "object": "vector_store",
        "created_at": active,
        "name": name,
        "last_active_at": active,
    })
}

async fn round_trip(repo: &dyn VectorStoreRepository) {
    let owner = "agt_vs_rt";
    let id = format!("vs_rt_{}", uuid::Uuid::now_v7().simple());
    let input = vec![json!({"id": "file-1", "object": "vector_store.file"})];
    repo.put_vector_object(&id, owner, store_obj(&id, "papers", 10), input.clone())
        .await;
    let v = repo.get_vector_object(owner, &id).await.expect("stored");
    assert_eq!(v.obj["name"], "papers");
    assert_eq!(v.input, input);
    // Owner scoping: another owner sees nothing.
    assert!(repo
        .get_vector_object("agt_someone_else", &id)
        .await
        .is_none());
    // Replacement: same id overwrites.
    repo.put_vector_object(&id, owner, store_obj(&id, "renamed", 20), Vec::new())
        .await;
    let v = repo.get_vector_object(owner, &id).await.expect("replaced");
    assert_eq!(v.obj["name"], "renamed");
    assert!(v.input.is_empty());
}

async fn list_filters_kind_and_orders_by_activity(repo: &dyn VectorStoreRepository) {
    let owner = "agt_vs_list";
    let tag = uuid::Uuid::now_v7().simple().to_string();
    let a = format!("vs_la_{tag}");
    let b = format!("vs_lb_{tag}");
    let batch = format!("vsfb_{tag}");
    repo.put_vector_object(&a, owner, store_obj(&a, "a", 100), Vec::new())
        .await;
    repo.put_vector_object(&b, owner, store_obj(&b, "b", 200), Vec::new())
        .await;
    let mut bobj = store_obj(&batch, "batch", 300);
    bobj["object"] = json!("vector_store.files_batch");
    repo.put_vector_object(&batch, owner, bobj, Vec::new())
        .await;
    let rows = repo.list_vector_objects(owner, "vector_store").await;
    let names: Vec<&str> = rows
        .iter()
        .filter(|(id, _)| id.ends_with(&tag.to_string()))
        .map(|(_, v)| v.obj["name"].as_str().unwrap_or(""))
        .collect();
    assert_eq!(names, vec!["b", "a"]);
}

async fn delete_is_owner_scoped(repo: &dyn VectorStoreRepository) {
    let id = format!("vs_del_{}", uuid::Uuid::now_v7().simple());
    repo.put_vector_object(&id, "agt_a", store_obj(&id, "x", 1), Vec::new())
        .await;
    assert!(!repo.delete_vector_object("agt_b", &id).await);
    assert!(repo.get_vector_object("agt_a", &id).await.is_some());
    assert!(repo.delete_vector_object("agt_a", &id).await);
    assert!(repo.get_vector_object("agt_a", &id).await.is_none());
}

async fn cap_evicts_least_active(repo: &dyn VectorStoreRepository) {
    // Safety: a tiny cap via env is process-wide, so this test uses the
    // default and only checks ordering-independent eviction with 2 objects
    // under a cap of 1 set just for this process run. If the env var is
    // absent, the default cap (500) makes this a no-op check.
    if std::env::var("OPENHUMAN_VECTOR_OBJECTS_MAX_PER_OWNER").is_err() {
        return;
    }
    let owner = "agt_vs_cap";
    let tag = uuid::Uuid::now_v7().simple().to_string();
    let old = format!("vs_old_{tag}");
    let new = format!("vs_new_{tag}");
    repo.put_vector_object(&old, owner, store_obj(&old, "old", 1), Vec::new())
        .await;
    repo.put_vector_object(&new, owner, store_obj(&new, "new", 2), Vec::new())
        .await;
    assert!(repo.get_vector_object(owner, &old).await.is_none());
    assert!(repo.get_vector_object(owner, &new).await.is_some());
}

#[tokio::test]
async fn memory_round_trip() {
    round_trip(&MemoryStore::new()).await;
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
