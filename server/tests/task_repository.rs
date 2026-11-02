//! TaskRepository contract tests: the same expectations run against the
//! memory store always and the postgres store when DATABASE_URL is set
//! (OPENHUMAN_BACKEND=postgres). Covers lifecycle, owner scoping, quotas
//! and the boot-time in-flight sweep.

use openhuman_server::model::task::{TaskRecord, TaskStatus};
use openhuman_server::storage::memory::MemoryStore;
use openhuman_server::storage::postgres::PostgresStore;
use openhuman_server::storage::traits::TaskRepository;

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
    let owner = "agt_lifecycle";
    repo.create_task(rec("task_lc1", owner, TaskStatus::Running))
        .await;
    let t = repo.get_task(owner, "task_lc1").await.expect("created");
    assert_eq!(t.status, TaskStatus::Running);
    repo.bind_task_conversation("task_lc1", "cnv_1").await;
    let t = repo.get_task(owner, "task_lc1").await.unwrap();
    assert_eq!(t.conversation_id.as_deref(), Some("cnv_1"));
    repo.finish_task("task_lc1", Some(serde_json::json!({"text": "done"})), None)
        .await;
    let t = repo.get_task(owner, "task_lc1").await.unwrap();
    assert_eq!(t.status, TaskStatus::Completed);
    // Owner scoping: another owner cannot see it.
    assert!(repo.get_task("agt_other", "task_lc1").await.is_none());
    // A late duplicate finish never reopens a completed task.
    repo.finish_task("task_lc1", None, Some("late error".into()))
        .await;
    let t = repo.get_task(owner, "task_lc1").await.unwrap();
    assert_eq!(t.status, TaskStatus::Completed);
    assert!(t.error.is_none());
}

async fn in_flight_sweep(repo: &dyn TaskRepository) {
    let owner = "agt_sweep";
    repo.create_task(rec("task_sw1", owner, TaskStatus::Queued))
        .await;
    repo.create_task(rec("task_sw2", owner, TaskStatus::Running))
        .await;
    repo.create_task(rec("task_sw3", owner, TaskStatus::Completed))
        .await;
    let n = repo.fail_in_flight_tasks("server restarted").await;
    assert!(n >= 2, "queued+running failed, got {n}");
    let t = repo.get_task(owner, "task_sw1").await.unwrap();
    assert_eq!(t.status, TaskStatus::Failed);
    assert_eq!(t.error.as_deref(), Some("server restarted"));
    let t = repo.get_task(owner, "task_sw3").await.unwrap();
    assert_eq!(t.status, TaskStatus::Completed, "finished rows untouched");
}

async fn quota_prunes_finished_only(repo: &dyn TaskRepository) {
    std::env::set_var("OPENHUMAN_TASKS_MAX_PER_OWNER", "5");
    let owner = "agt_quota";
    for i in 0..8 {
        repo.create_task(rec(&format!("task_q{i}"), owner, TaskStatus::Completed))
            .await;
    }
    repo.create_task(rec("task_q_active", owner, TaskStatus::Running))
        .await;
    let listed = repo.list_tasks(owner, 100).await;
    assert!(
        listed.len() <= 6,
        "pruned to the cap, {} left",
        listed.len()
    );
    assert!(
        listed.iter().any(|t| t.id == "task_q_active"),
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
    let _ = sqlx::query("DELETE FROM tasks").execute(store.pool()).await;
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
