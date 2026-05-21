-- Synthetic data for the SDLC attestation demo.
-- Mirrors the shape of what Lakeflow Connect produces for GitHub + Jira,
-- so 03_control_test.sql runs identically against real or seeded data.
--
-- Run this once. Re-run wipes and re-seeds.

CREATE SCHEMA IF NOT EXISTS gaurav_catalog.docusign_demo;
CREATE table IF NOT EXISTS gaurav_catalog.docusign_demo.controls;

-- ============================================================
-- GitHub: teams + members (who is in code-owners)
-- ============================================================
CREATE OR REPLACE TABLE gaurav_catalog.docusign_demo.raw_github_teams AS
SELECT * FROM VALUES
  (1, 'code-owners', 'Code Owners'),
  (2, 'developers',  'All Developers')
AS t(id, slug, name);

CREATE OR REPLACE TABLE gaurav_catalog.docusign_demo.raw_github_team_members AS
SELECT * FROM VALUES
  (1, 'alice'),  (1, 'bob'),   (1, 'carol'),  (1, 'dave'),
  (2, 'alice'),  (2, 'bob'),   (2, 'carol'),  (2, 'dave'),
  (2, 'erin'),   (2, 'frank'), (2, 'grace'),  (2, 'heidi')
AS t(team_id, user_login);

-- ============================================================
-- GitHub: pull_requests (mix of prod-* and non-prod repos)
-- ============================================================
CREATE OR REPLACE TABLE gaurav_catalog.docusign_demo.raw_github_pull_requests AS
SELECT * FROM VALUES
  -- id, number, repository, title, body, state, merged_at, merged_by, base_ref
  (1001, 42,  'docusign/prod-signing-api',    'Fix signing latency SEC-1001',         'Refs SEC-1001',         'closed', TIMESTAMP'2026-05-10 14:00:00', 'alice', 'main'),
  (1002, 43,  'docusign/prod-signing-api',    'Add new region INFRA-2002',            'Refs INFRA-2002',       'closed', TIMESTAMP'2026-05-11 09:30:00', 'bob',   'main'),
  (1003, 44,  'docusign/prod-billing-svc',    'Patch CVE-2026-1234 SEC-1003',         'Refs SEC-1003',         'closed', TIMESTAMP'2026-05-12 11:15:00', 'carol', 'main'),
  (1004, 45,  'docusign/prod-billing-svc',    'Hotfix billing rounding',              'no ticket',             'closed', TIMESTAMP'2026-05-12 16:45:00', 'dave',  'main'),
  (1005, 46,  'docusign/prod-audit-svc',      'Refactor audit pipeline INFRA-2005',   'Refs INFRA-2005',       'closed', TIMESTAMP'2026-05-13 10:00:00', 'erin',  'main'),
  (1006, 47,  'docusign/prod-audit-svc',      'Update logging PROD-3006',             'Refs PROD-3006',        'closed', TIMESTAMP'2026-05-13 14:20:00', 'frank', 'main'),
  (1007, 48,  'docusign/prod-signing-api',    'Bump deps SEC-1007',                   'Refs SEC-1007',         'closed', TIMESTAMP'2026-05-14 08:00:00', 'grace', 'main'),
  (1008, 49,  'docusign/prod-signing-api',    'Fix flaky test SEC-1008',              'Refs SEC-1008',         'closed', TIMESTAMP'2026-05-14 13:30:00', 'heidi', 'main'),
  (1009, 50,  'docusign/prod-billing-svc',    'Add new pricing tier INFRA-2009',      'Refs INFRA-2009',       'closed', TIMESTAMP'2026-05-15 09:45:00', 'alice', 'main'),
  (1010, 51,  'docusign/prod-billing-svc',    'Refactor invoice gen PROD-3010',       'Refs PROD-3010',        'closed', TIMESTAMP'2026-05-15 15:10:00', 'bob',   'main'),
  (1011, 52,  'docusign/prod-audit-svc',      'Patch null pointer',                   'no ticket attached',    'closed', TIMESTAMP'2026-05-16 10:30:00', 'carol', 'main'),
  (1012, 53,  'docusign/prod-audit-svc',      'Bump go runtime SEC-1012',             'Refs SEC-1012',         'closed', TIMESTAMP'2026-05-16 14:50:00', 'dave',  'main'),
  (1013, 54,  'docusign/internal-dev-tools',  'Internal tweak',                       'internal repo',         'closed', TIMESTAMP'2026-05-17 11:00:00', 'erin',  'main'),
  (1014, 55,  'docusign/prod-signing-api',    'Big refactor INFRA-2014',              'Refs INFRA-2014',       'closed', TIMESTAMP'2026-05-17 16:00:00', 'frank', 'main'),
  (1015, 56,  'docusign/prod-billing-svc',    'Fix integer overflow PROD-3015',       'Refs PROD-3015',        'closed', TIMESTAMP'2026-05-18 08:30:00', 'grace', 'main'),
  (1016, 57,  'docusign/prod-billing-svc',    'Quick fix',                            'PROD-3016',             'closed', TIMESTAMP'2026-05-18 12:15:00', 'heidi', 'main'),
  (1017, 58,  'docusign/prod-audit-svc',      'Deprecate old endpoint SEC-1017',      'Refs SEC-1017',         'closed', TIMESTAMP'2026-05-18 15:40:00', 'alice', 'main'),
  (1018, 59,  'docusign/prod-audit-svc',      'Doc update INFRA-2018',                'Refs INFRA-2018',       'closed', TIMESTAMP'2026-05-19 09:00:00', 'bob',   'main'),
  (1019, 60,  'docusign/prod-signing-api',    'Tighten validation PROD-3019',         'Refs PROD-3019',        'closed', TIMESTAMP'2026-05-19 13:25:00', 'carol', 'main'),
  (1020, 61,  'docusign/prod-signing-api',    'Optimize hot path',                    'no ticket',             'closed', TIMESTAMP'2026-05-19 16:30:00', 'dave',  'main')
AS t(id, number, repository, title, body, state, merged_at, merged_by, base_ref);

-- ============================================================
-- GitHub: pull_request_reviews
-- Distribution designed so failures cover each rule:
--   1004 — no Jira ticket
--   1007 — Jira ticket exists but NOT Approved
--   1011 — no Jira ticket
--   1014 — only 1 reviewer
--   1016 — reviewers not from code-owners
--   1020 — no Jira ticket
-- All others pass.
-- ============================================================
CREATE OR REPLACE TABLE gaurav_catalog.docusign_demo.raw_github_pull_request_reviews AS
SELECT * FROM VALUES
  -- pull_request_id, user_login, state, submitted_at
  (1001, 'bob',   'APPROVED', TIMESTAMP'2026-05-10 13:30:00'),
  (1001, 'carol', 'APPROVED', TIMESTAMP'2026-05-10 13:45:00'),
  (1002, 'alice', 'APPROVED', TIMESTAMP'2026-05-11 09:00:00'),
  (1002, 'dave',  'APPROVED', TIMESTAMP'2026-05-11 09:15:00'),
  (1003, 'bob',   'APPROVED', TIMESTAMP'2026-05-12 10:45:00'),
  (1003, 'dave',  'APPROVED', TIMESTAMP'2026-05-12 11:00:00'),
  (1004, 'alice', 'APPROVED', TIMESTAMP'2026-05-12 16:15:00'),
  (1004, 'bob',   'APPROVED', TIMESTAMP'2026-05-12 16:30:00'),
  (1005, 'alice', 'APPROVED', TIMESTAMP'2026-05-13 09:30:00'),
  (1005, 'carol', 'APPROVED', TIMESTAMP'2026-05-13 09:45:00'),
  (1006, 'bob',   'APPROVED', TIMESTAMP'2026-05-13 14:00:00'),
  (1006, 'dave',  'APPROVED', TIMESTAMP'2026-05-13 14:10:00'),
  (1007, 'alice', 'APPROVED', TIMESTAMP'2026-05-14 07:30:00'),
  (1007, 'carol', 'APPROVED', TIMESTAMP'2026-05-14 07:45:00'),
  (1008, 'bob',   'APPROVED', TIMESTAMP'2026-05-14 13:00:00'),
  (1008, 'dave',  'APPROVED', TIMESTAMP'2026-05-14 13:15:00'),
  (1009, 'alice', 'APPROVED', TIMESTAMP'2026-05-15 09:15:00'),
  (1009, 'carol', 'APPROVED', TIMESTAMP'2026-05-15 09:30:00'),
  (1010, 'bob',   'APPROVED', TIMESTAMP'2026-05-15 14:45:00'),
  (1010, 'dave',  'APPROVED', TIMESTAMP'2026-05-15 15:00:00'),
  (1011, 'alice', 'APPROVED', TIMESTAMP'2026-05-16 10:00:00'),
  (1011, 'bob',   'APPROVED', TIMESTAMP'2026-05-16 10:15:00'),
  (1012, 'carol', 'APPROVED', TIMESTAMP'2026-05-16 14:30:00'),
  (1012, 'dave',  'APPROVED', TIMESTAMP'2026-05-16 14:40:00'),
  (1013, 'erin',  'APPROVED', TIMESTAMP'2026-05-17 10:30:00'),
  (1013, 'frank', 'APPROVED', TIMESTAMP'2026-05-17 10:45:00'),
  -- 1014: only one approval (FAIL: reviewer count)
  (1014, 'alice', 'APPROVED', TIMESTAMP'2026-05-17 15:45:00'),
  (1014, 'bob',   'COMMENTED', TIMESTAMP'2026-05-17 15:50:00'),
  (1015, 'carol', 'APPROVED', TIMESTAMP'2026-05-18 08:00:00'),
  (1015, 'dave',  'APPROVED', TIMESTAMP'2026-05-18 08:15:00'),
  -- 1016: reviewers exist but neither is in code-owners (erin/frank are not)
  (1016, 'erin',  'APPROVED', TIMESTAMP'2026-05-18 11:45:00'),
  (1016, 'frank', 'APPROVED', TIMESTAMP'2026-05-18 12:00:00'),
  (1017, 'alice', 'APPROVED', TIMESTAMP'2026-05-18 15:10:00'),
  (1017, 'bob',   'APPROVED', TIMESTAMP'2026-05-18 15:20:00'),
  (1018, 'carol', 'APPROVED', TIMESTAMP'2026-05-19 08:30:00'),
  (1018, 'dave',  'APPROVED', TIMESTAMP'2026-05-19 08:45:00'),
  (1019, 'alice', 'APPROVED', TIMESTAMP'2026-05-19 13:00:00'),
  (1019, 'bob',   'APPROVED', TIMESTAMP'2026-05-19 13:10:00'),
  (1020, 'carol', 'APPROVED', TIMESTAMP'2026-05-19 16:00:00'),
  (1020, 'dave',  'APPROVED', TIMESTAMP'2026-05-19 16:15:00')
AS t(pull_request_id, user_login, state, submitted_at);

-- ============================================================
-- Jira: issues
-- 1007's ticket (SEC-1007) deliberately In Progress at merge time.
-- ============================================================
CREATE OR REPLACE TABLE gaurav_catalog.docusign_demo.raw_jira_issues AS
SELECT * FROM VALUES
  -- key, project_key, status_name, status_category, summary, issue_type, assignee, created, updated
  ('SEC-1001',   'SEC',   'Done',        'Complete',    'Signing latency root cause', 'Task',  'alice', TIMESTAMP'2026-05-01', TIMESTAMP'2026-05-10'),
  ('INFRA-2002', 'INFRA', 'Approved',    'In Progress', 'New region launch',          'Story', 'bob',   TIMESTAMP'2026-05-02', TIMESTAMP'2026-05-11'),
  ('SEC-1003',   'SEC',   'Done',        'Complete',    'CVE-2026-1234 patch',        'Bug',   'carol', TIMESTAMP'2026-05-02', TIMESTAMP'2026-05-12'),
  ('INFRA-2005', 'INFRA', 'Approved',    'In Progress', 'Audit pipeline refactor',    'Story', 'erin',  TIMESTAMP'2026-05-03', TIMESTAMP'2026-05-13'),
  ('PROD-3006',  'PROD',  'Done',        'Complete',    'Logging update',             'Task',  'frank', TIMESTAMP'2026-05-04', TIMESTAMP'2026-05-13'),
  ('SEC-1007',   'SEC',   'In Progress', 'In Progress', 'Bump deps',                  'Task',  'grace', TIMESTAMP'2026-05-05', TIMESTAMP'2026-05-14'),  -- FAIL: not approved
  ('SEC-1008',   'SEC',   'Done',        'Complete',    'Fix flaky test',             'Bug',   'heidi', TIMESTAMP'2026-05-06', TIMESTAMP'2026-05-14'),
  ('INFRA-2009', 'INFRA', 'Approved',    'In Progress','New pricing tier',           'Story', 'alice', TIMESTAMP'2026-05-07', TIMESTAMP'2026-05-15'),
  ('PROD-3010',  'PROD',  'Done',        'Complete',    'Invoice gen refactor',       'Task',  'bob',   TIMESTAMP'2026-05-07', TIMESTAMP'2026-05-15'),
  ('SEC-1012',   'SEC',   'Approved',    'In Progress', 'Bump go runtime',            'Task',  'dave',  TIMESTAMP'2026-05-08', TIMESTAMP'2026-05-16'),
  ('INFRA-2014', 'INFRA', 'Approved',    'In Progress', 'Big refactor',               'Story', 'frank', TIMESTAMP'2026-05-09', TIMESTAMP'2026-05-17'),
  ('PROD-3015',  'PROD',  'Done',        'Complete',    'Integer overflow fix',       'Bug',   'grace', TIMESTAMP'2026-05-10', TIMESTAMP'2026-05-18'),
  ('PROD-3016',  'PROD',  'Done',        'Complete',    'Quick fix',                  'Task',  'heidi', TIMESTAMP'2026-05-10', TIMESTAMP'2026-05-18'),
  ('SEC-1017',   'SEC',   'Done',        'Complete',    'Deprecate old endpoint',     'Task',  'alice', TIMESTAMP'2026-05-11', TIMESTAMP'2026-05-18'),
  ('INFRA-2018', 'INFRA', 'Approved',    'In Progress', 'Doc update',                 'Task',  'bob',   TIMESTAMP'2026-05-12', TIMESTAMP'2026-05-19'),
  ('PROD-3019',  'PROD',  'Done',        'Complete',    'Tighten validation',         'Task',  'carol', TIMESTAMP'2026-05-12', TIMESTAMP'2026-05-19')
AS t(key, project_key, status_name, status_category, summary, issue_type, assignee, created, updated);
