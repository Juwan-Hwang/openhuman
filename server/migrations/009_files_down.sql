-- Rollback for 009_files.sql. Run by hand only:
--   psql "$DATABASE_URL" -f server/migrations/009_files_down.sql
DROP TABLE IF EXISTS files;
