-- SDLC-001 attestation: every prod-* PR must reference an approved Jira ticket
-- and have >=2 approvals, one of whom is in the code-owners team.
--
-- Output: docusign_demo.controls_sdlc_pr_attestation
-- One row per merged prod-* PR with passed/failed and a human-readable reason.

CREATE OR REPLACE TABLE gaurav_catalog.docusign_demo.controls_sdlc_pr_attestation AS
WITH

-- 1. Scope: merged PRs into prod-* repos
prod_prs AS (
  SELECT
    id              AS pr_id,
    number          AS pr_number,
    repository,
    title,
    body,
    merged_at,
    merged_by,
    concat('https://github.com/', repository, '/pull/', number) AS pr_url
  FROM gaurav_catalog.docusign_demo.raw_github_pull_requests
  WHERE state = 'closed'
    AND merged_at IS NOT NULL
    AND repository LIKE 'docusign/prod-%'
),

-- 2. Extract the Jira key from title or body
pr_with_jira_key AS (
  SELECT
    pr.*,
    regexp_extract(coalesce(pr.title, '') || ' ' || coalesce(pr.body, ''),
                   '([A-Z]+-[0-9]+)', 1) AS jira_key
  FROM prod_prs pr
),

-- 3. Lookup the Jira ticket
pr_with_jira AS (
  SELECT
    pr.*,
    j.status_name      AS jira_status,
    j.status_category  AS jira_status_category,
    j.summary          AS jira_summary,
    j.assignee         AS jira_assignee
  FROM pr_with_jira_key pr
  LEFT JOIN gaurav_catalog.docusign_demo.raw_jira_issues j
    ON pr.jira_key = j.key
),

-- 4. Reviewer aggregation
code_owners AS (
  SELECT tm.user_login
  FROM gaurav_catalog.docusign_demo.raw_github_team_members tm
  JOIN gaurav_catalog.docusign_demo.raw_github_teams t ON t.id = tm.team_id
  WHERE t.slug = 'code-owners'
),
approvals AS (
  SELECT
    r.pull_request_id,
    count(*)                                              AS approval_count,
    count(*) FILTER (WHERE co.user_login IS NOT NULL)     AS code_owner_approval_count,
    collect_set(r.user_login)                             AS approvers
  FROM gaurav_catalog.docusign_demo.raw_github_pull_request_reviews r
  LEFT JOIN code_owners co ON co.user_login = r.user_login
  WHERE r.state = 'APPROVED'
  GROUP BY r.pull_request_id
),

-- 5. Final assembly + per-rule evaluation
evaluated AS (
  SELECT
    pr.pr_id,
    pr.pr_number,
    pr.repository,
    pr.pr_url,
    pr.merged_at,
    pr.merged_by,
    pr.jira_key,
    pr.jira_status,
    pr.jira_summary,
    coalesce(a.approval_count, 0)            AS approval_count,
    coalesce(a.code_owner_approval_count, 0) AS code_owner_approval_count,
    a.approvers,

    -- rule predicates
    (pr.jira_key != '')                                     AS rule_has_jira_ref,
    (pr.jira_status IN ('Approved', 'Done'))                AS rule_jira_approved,
    (coalesce(a.approval_count, 0) >= 2)                    AS rule_two_approvals,
    (coalesce(a.code_owner_approval_count, 0) >= 1)         AS rule_code_owner_approved
  FROM pr_with_jira pr
  LEFT JOIN approvals a ON a.pull_request_id = pr.pr_id
)

SELECT
  pr_id,
  pr_number,
  repository,
  pr_url,
  merged_at,
  merged_by,
  jira_key,
  jira_status,
  jira_summary,
  approval_count,
  code_owner_approval_count,
  approvers,
  CASE
    WHEN rule_has_jira_ref
     AND rule_jira_approved
     AND rule_two_approvals
     AND rule_code_owner_approved THEN 'passed'
    ELSE 'failed'
  END AS result,
  array_remove(array(
    CASE WHEN NOT rule_has_jira_ref       THEN 'no Jira ticket referenced'          END,
    CASE WHEN NOT rule_jira_approved      THEN concat('Jira ticket not approved at merge (status=', coalesce(jira_status, 'NOT FOUND'), ')') END,
    CASE WHEN NOT rule_two_approvals      THEN concat('fewer than 2 approvals (got ', approval_count, ')') END,
    CASE WHEN NOT rule_code_owner_approved THEN 'no approval from code-owners team' END
  ), NULL) AS failure_reasons,
  current_timestamp() AS evaluated_at
FROM evaluated;

-- ============================================================
-- Quick views to drive the demo narrative
-- ============================================================

-- Overall result counts
SELECT result, count(*) AS prs
FROM gaurav_catalog.docusign_demo.controls_sdlc_pr_attestation
GROUP BY result;

-- The failures with reasons (this is what gets pushed to ServiceNow)
SELECT pr_url, merged_by, jira_key, failure_reasons
FROM gaurav_catalog.docusign_demo.controls_sdlc_pr_attestation
WHERE result = 'failed'
ORDER BY merged_at DESC;
