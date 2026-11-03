//! FileRepository contract tests: the same expectations run against the
//! memory store always and the postgres store when DATABASE_URL is set.
//! Covers put/get round trips, owner-scoped delete, list ordering and
//! output-content lookup.

use openhuman_server::api::files::StoredFile;
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::postgres::PostgresStore;
use openhuman_server::storage::traits::FileRepository;

fn file(owner: &str, name: &str, purpose: &str, bytes: &[u8], created_at: i64) -> StoredFile {
    StoredFile {
        owner: owner.to_string(),
        filename: name.to_string(),
        mime: "application/octet-stream".to_string(),
        purpose: purpose.to_string(),
        bytes: bytes.to_vec(),
        created_at,
    }
}

async fn round_trip(repo: &dyn FileRepository) {
    let owner = "agt_files_rt";
    repo.put_file("file-rt1", file(owner, "a.bin", "user_data", b"hello", 10))
        .await;
    let f = repo.get_file("file-rt1").await.expect("stored");
    assert_eq!(f.owner, owner);
    assert_eq!(f.filename, "a.bin");
    assert_eq!(f.bytes, b"hello");
    // Re-putting the same id is idempotent (deterministic ids dedupe content).
    repo.put_file("file-rt1", file(owner, "a.bin", "user_data", b"hello", 10))
        .await;
    let f = repo.get_file("file-rt1").await.expect("still there");
    assert_eq!(f.filename, "a.bin");
    assert_eq!(f.bytes, b"hello");
    assert!(repo.get_file("file-does-not-exist").await.is_none());
}

async fn delete_is_owner_scoped(repo: &dyn FileRepository) {
    repo.put_file("file-del1", file("agt_a", "a.bin", "user_data", b"x", 1))
        .await;
    assert!(!repo.delete_file("agt_b", "file-del1").await);
    assert!(repo.get_file("file-del1").await.is_some());
    assert!(repo.delete_file("agt_a", "file-del1").await);
    assert!(repo.get_file("file-del1").await.is_none());
}

async fn list_is_owner_scoped_and_newest_first(repo: &dyn FileRepository) {
    let owner = "agt_files_list";
    repo.put_file("file-l1", file(owner, "one", "user_data", b"1", 100))
        .await;
    repo.put_file("file-l2", file(owner, "two", "user_data", b"2", 200))
        .await;
    repo.put_file(
        "file-l3",
        file("agt_other", "three", "user_data", b"3", 300),
    )
    .await;
    let rows = repo.list_files(owner).await;
    let names: Vec<&str> = rows.iter().map(|(_, f)| f.filename.as_str()).collect();
    assert_eq!(names, vec!["two", "one"]);
}

async fn find_output_by_bytes_only_matches_outputs(repo: &dyn FileRepository) {
    let owner = "agt_files_out";
    // Unique payloads keep the shared postgres database from leaking
    // between runs (the table persists across test runs).
    let tag = uuid::Uuid::now_v7().simple().to_string();
    let uid = format!("file-u{tag}");
    let oid = format!("file-o{tag}");
    let payload = format!("payload-{tag}").into_bytes();
    repo.put_file(&uid, file(owner, "in.bin", "user_data", &payload, 1))
        .await;
    assert!(repo.find_output_by_bytes(&payload).await.is_none());
    repo.put_file(&oid, file(owner, "out.png", "output", &payload, 2))
        .await;
    let (id, _) = repo
        .find_output_by_bytes(&payload)
        .await
        .expect("output hit");
    assert_eq!(id, oid);
    assert!(repo.find_output_by_bytes(b"never-stored").await.is_none());
}

#[tokio::test]
async fn memory_round_trip() {
    round_trip(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_delete_owner_scoped() {
    delete_is_owner_scoped(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_list_newest_first() {
    list_is_owner_scoped_and_newest_first(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_find_output_by_bytes() {
    find_output_by_bytes_only_matches_outputs(&MemoryStore::new()).await;
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
async fn postgres_delete_owner_scoped() {
    let Some(store) = pg_store().await else {
        return;
    };
    delete_is_owner_scoped(&store).await;
}

#[tokio::test]
async fn postgres_list_newest_first() {
    let Some(store) = pg_store().await else {
        return;
    };
    list_is_owner_scoped_and_newest_first(&store).await;
}

#[tokio::test]
async fn postgres_find_output_by_bytes() {
    let Some(store) = pg_store().await else {
        return;
    };
    find_output_by_bytes_only_matches_outputs(&store).await;
}
