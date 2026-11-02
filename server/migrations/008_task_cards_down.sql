-- Rollback for 008_task_cards.sql. Run by hand only:
--   psql "$DATABASE_URL" -f server/migrations/008_task_cards_down.sql
DROP TABLE IF EXISTS tasks;
