//! TaskRepository contract tests: the same expectations run against the
//! memory store always and the postgres store when DATABASE_URL is set
//! (OPENHUMAN_BACKEND=postgres). Covers lifecycle, owner scoping, quotas
//! and the boot-time in-flight sweep.

use openhuman_server::model::task::{TaskRecord, TaskStatus};
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::postgres::PostgresStore;
use openhuman_server::storage::traits::TaskRepository;

/// Unique id/owner prefix per test run: the postgres table persists
/// across runs and test binaries run in parallel against it.
fn tag() -> String {
    uuid::Uuid::now_v7().simple().to_string()
}

fn rec(id: &str, owner: &str, status: TaskStatus) -> TaskRecord {
    TaskRecord {
        id: id.to_string(),
        owner: owner.to_string(),
        api: "images".to_string(),
        status,
        conversation_id: None,
        request: serde_json::json!({"prompt_head": "a cat"}),
        answer: None,
        error: None,
        created_at: 0,
        updated_at: 0,
    }
}

async fn lifecycle(repo: &dyn TaskRepository) {
    let tag = tag();
    let owner = format!("agt_lifecycle_{tag}");
    let id1 = format!("task_lc1_{tag}");
    let owner = owner.as_str();
    let id1 = id1.as_str();
    repo.create_task(rec(id1, owner, TaskStatus::Running)).await;
    let t = repo.get_task(owner, id1).await.expect("created");
    assert_eq!(t.status, TaskStatus::Running);
    repo.bind_task_conversation(id1, "cnv_1").await;
    let t = repo.get_task(owner, id1).await.unwrap();
    assert_eq!(t.conversation_id.as_deref(), Some("cnv_1"));
    repo.finish_task(id1, Some(serde_json::json!({"text": "done"})), None)
        .await;
    let t = repo.get_task(owner, id1).await.unwrap();
    assert_eq!(t.status, TaskStatus::Completed);
    // Owner scoping: another owner cannot see it.
    assert!(repo.get_task("agt_other", id1).await.is_none());
    // A late duplicate finish never reopens a completed task.
    repo.finish_task(id1, None, Some("late error".into())).await;
    let t = repo.get_task(owner, id1).await.unwrap();
    assert_eq!(t.status, TaskStatus::Completed);
    assert!(t.error.is_none());
}

async fn in_flight_sweep(repo: &dyn TaskRepository) {
    let tag = tag();
    let owner = format!("agt_sweep_{tag}");
    let owner = owner.as_str();
    let sw1 = format!("task_sw1_{tag}");
    let sw3 = format!("task_sw3_{tag}");
    repo.create_task(rec(&sw1, owner, TaskStatus::Queued)).await;
    repo.create_task(rec(&format!("task_sw2_{tag}"), owner, TaskStatus::Running))
        .await;
    repo.create_task(rec(&sw3, owner, TaskStatus::Completed))
        .await;
    let n = repo.fail_in_flight_tasks("server restarted").await;
    assert!(n >= 2, "queued+running failed, got {n}");
    let t = repo.get_task(owner, &sw1).await.unwrap();
    assert_eq!(t.status, TaskStatus::Failed);
    assert_eq!(t.error.as_deref(), Some("server restarted"));
    let t = repo.get_task(owner, &sw3).await.unwrap();
    assert_eq!(t.status, TaskStatus::Completed, "finished rows untouched");
}

async fn quota_prunes_finished_only(repo: &dyn TaskRepository) {
    std::env::set_var("OPENHUMAN_TASKS_MAX_PER_OWNER", "5");
    let tag = tag();
    let owner = format!("agt_quota_{tag}");
    let owner = owner.as_str();
    for i in 0..8 {
        repo.create_task(rec(
            &format!("task_q{i}_{tag}"),
            owner,
            TaskStatus::Completed,
        ))
        .await;
    }
    let active = format!("task_q_active_{tag}");
    repo.create_task(rec(&active, owner, TaskStatus::Running))
        .await;
    let listed = repo.list_tasks(owner, 100).await;
    assert!(
        listed.len() <= 6,
        "pruned to the cap, {} left",
        listed.len()
    );
    assert!(
        listed.iter().any(|t| t.id == active),
        "the active task is never pruned"
    );
    std::env::remove_var("OPENHUMAN_TASKS_MAX_PER_OWNER");
}

#[tokio::test]
async fn memory_lifecycle() {
    lifecycle(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_in_flight_sweep() {
    in_flight_sweep(&MemoryStore::new()).await;
}

#[tokio::test]
async fn memory_quota_prunes_finished_only() {
    quota_prunes_finished_only(&MemoryStore::new()).await;
}

async fn pg_store() -> Option<PostgresStore> {
    let url = std::env::var("DATABASE_URL").ok()?;
    let store = PostgresStore::new(&url).await.ok()?;
    let _ = store.migrate().await;
    Some(store)
}

#[tokio::test]
async fn postgres_lifecycle() {
    let Some(store) = pg_store().await else {
        return;
    };
    lifecycle(&store).await;
}

#[tokio::test]
async fn postgres_in_flight_sweep() {
    let Some(store) = pg_store().await else {
        return;
    };
    in_flight_sweep(&store).await;
}

#[tokio::test]
async fn postgres_quota_prunes_finished_only() {
    let Some(store) = pg_store().await else {
        return;
    };
    quota_prunes_finished_only(&store).await;
}
