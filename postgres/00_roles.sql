\set ON_ERROR_STOP on

SELECT format('CREATE ROLE %I LOGIN', role_name)
FROM (VALUES ('prison_u_admin'), ('prison_u_warden'), ('prison_u_warden2'),
             ('prison_u_frontdesk'), ('prison_u_auditor')) AS roles(role_name)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name)
\gexec

ALTER ROLE prison_u_admin WITH LOGIN PASSWORD :'demo_password';
ALTER ROLE prison_u_warden WITH LOGIN PASSWORD :'demo_password';
ALTER ROLE prison_u_warden2 WITH LOGIN PASSWORD :'demo_password';
ALTER ROLE prison_u_frontdesk WITH LOGIN PASSWORD :'demo_password';
ALTER ROLE prison_u_auditor WITH LOGIN PASSWORD :'demo_password';
