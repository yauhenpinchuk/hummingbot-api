-- Safety net for PostgreSQL initialization
-- PostgreSQL auto-creates user/db from POSTGRES_USER, POSTGRES_DB env vars
-- This script only runs on first container initialization

-- Native Hummingbot trade/fill tables (MarketsRecorder, SQLAlchemy) live here.
-- hummingbot-api ORM uses POSTGRES_DB (e.g. hummingbot_api). Same Postgres instance, two databases.
-- Bot containers use network_mode: host → db_host 127.0.0.1, db_port 55432 (host-mapped), db_name hummingbot.
CREATE DATABASE hummingbot OWNER hbot;

-- Ensure proper permissions on public schema
GRANT ALL ON SCHEMA public TO hbot;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO hbot;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO hbot;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO hbot;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO hbot;
