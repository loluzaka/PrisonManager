\set ON_ERROR_STOP on
\echo 'Installing PostgreSQL schema and demo data'
\ir 00_roles.sql
\ir 001_schema.sql
\ir 002_seed.sql
\ir 003_routines_triggers.sql
\ir 004_views.sql
\ir 005_security.sql
\echo 'PostgreSQL install complete'
