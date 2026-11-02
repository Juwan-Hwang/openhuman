-- Rollback for 010_vector_stores.sql. Run by hand only:
--   psql "$DATABASE_URL" -f server/migrations/010_vector_stores_down.sql
DROP TABLE IF EXISTS vector_objects;
