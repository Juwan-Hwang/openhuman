-- Rollback for 010_api_objects.sql. Run by hand only:
--   psql "$DATABASE_URL" -f server/migrations/010_api_objects_down.sql
DROP TABLE IF EXISTS api_objects;
