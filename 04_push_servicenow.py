# Databricks notebook source
# MAGIC %md
# MAGIC # 04 — Push control failures to ServiceNow
# MAGIC
# MAGIC Reads `docusign_demo.controls.sdlc_pr_attestation`, picks the `failed` rows that
# MAGIC have not been pushed yet, and creates one ticket per failure in ServiceNow
# MAGIC (`incident` table by default — universally available on every instance,
# MAGIC including PDIs without IRM/GRC installed).
# MAGIC
# MAGIC In a customer prod instance with IRM/GRC activated, change `SN_TABLE` to
# MAGIC `sn_grc_issue` (or whatever the customer's IRM uses) and adjust field names
# MAGIC in `build_payload`.
# MAGIC
# MAGIC **Idempotency:** each PR gets a deterministic `correlation_id` so re-runs upsert
# MAGIC instead of duplicating. ServiceNow rows already created are skipped via lookup.
# MAGIC
# MAGIC **Why this matters:** Databricks computes the truth; ServiceNow gets the
# MAGIC workflow record (owner, SLA, audit trail). Auditors review in ServiceNow,
# MAGIC not in Databricks.
# MAGIC
# MAGIC **Mock mode:** set `MOCK_MODE = True` below to skip the real API calls and
# MAGIC generate synthetic-but-realistic responses. Use this for demos without a
# MAGIC live ServiceNow instance.

# COMMAND ----------

import json
import hashlib
import uuid
from datetime import date, datetime, timedelta, timezone

import requests
from pyspark.sql import functions as F

# COMMAND ----------

# MAGIC %md
# MAGIC ## Config

# COMMAND ----------

MOCK_MODE = False   # flip to False to hit a real ServiceNow instance

SN_TABLE = "incident"         # universal table — works on any PDI without IRM/GRC
                              # swap to "sn_grc_issue" on a real GRC-enabled instance
CONTROL_ID = "SDLC-002"
SLA_DAYS = 7

if not MOCK_MODE:
    SCOPE = "docusign-demo"
    SN_INSTANCE = dbutils.secrets.get(SCOPE, "servicenow-instance")
    SN_USER     = dbutils.secrets.get(SCOPE, "servicenow-user")
    SN_PASS     = dbutils.secrets.get(SCOPE, "servicenow-password")
    SN_BASE = f"https://{SN_INSTANCE}.service-now.com/api/now/table"
else:
    SN_BASE = "https://mock-instance.service-now.com/api/now/table"

# COMMAND ----------

# MAGIC %md
# MAGIC ## Read control failures

# COMMAND ----------

failures = (
    spark.table("gaurav_catalog.docusign_demo.controls_sdlc_pr_attestation")
    .where(F.col("result") == "failed")
    .withColumn(
        "correlation_id",
        F.concat_ws(":", F.lit(CONTROL_ID), F.col("pr_url"))
    )
)

display(failures)

# COMMAND ----------

# MAGIC %md
# MAGIC ## API helpers (real + mock)

# COMMAND ----------

_mock_store = {}     # correlation_id -> existing record (simulates SN persistence)
_mock_counter = {"n": 1000}

def _mock_response(payload: dict) -> dict:
    _mock_counter["n"] += 1
    sys_id = uuid.uuid5(uuid.NAMESPACE_URL, payload["correlation_id"]).hex
    prefix = "INC" if SN_TABLE == "incident" else "GRC"
    number = f"{prefix}{_mock_counter['n']:07d}"
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    record = {
        **payload,
        "sys_id": sys_id,
        "number": number,
        "sys_created_on": now,
        "sys_updated_on": now,
        "sys_created_by": "databricks.integration",
        "opened_at": now,
        "active": "true",
        "sys_class_name": SN_TABLE,
    }
    _mock_store[payload["correlation_id"]] = record
    return record

def sn_get(table: str, query: str):
    if MOCK_MODE:
        cid = query.split("=", 1)[1]
        return [_mock_store[cid]] if cid in _mock_store else []
    r = requests.get(
        f"{SN_BASE}/{table}",
        params={"sysparm_query": query, "sysparm_limit": 1},
        auth=(SN_USER, SN_PASS),
        headers={"Accept": "application/json"},
        timeout=30,
    )
    r.raise_for_status()
    return r.json().get("result", [])

def sn_post(table: str, payload: dict):
    if MOCK_MODE:
        result = _mock_response(payload)
        print(f"[MOCK] POST {SN_BASE}/{table}")
        print(f"[MOCK] request body: {json.dumps(payload, indent=2)}")
        print(f"[MOCK] response: {json.dumps(result, indent=2)}")
        return result
    r = requests.post(
        f"{SN_BASE}/{table}",
        auth=(SN_USER, SN_PASS),
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        data=json.dumps(payload),
        timeout=30,
    )
    r.raise_for_status()
    return r.json()["result"]

def build_payload(row) -> dict:
    reasons = ", ".join(row["failure_reasons"]) if row["failure_reasons"] else "unknown"
    return {
        # `correlation_id` is a built-in field on `task` (parent of `incident`),
        # used here as the idempotency key — re-runs upsert instead of duplicating.
        "correlation_id": row["correlation_id"],
        "short_description": f"{CONTROL_ID} violation: {row['repository']} PR #{row['pr_number']}",
        "description": (
            f"Control: {CONTROL_ID}\n"
            f"PR: {row['pr_url']}\n"
            f"Merged by: {row['merged_by']}\n"
            f"Jira: {row['jira_key'] or 'NONE'} (status: {row['jira_status'] or 'NONE'})\n"
            f"Approvals: {row['approval_count']} (code-owners: {row['code_owner_approval_count']})\n"
            f"Failure reasons: {reasons}"
        ),
        "assigned_to": row["merged_by"],
        "due_date": (date.today() + timedelta(days=SLA_DAYS)).isoformat(),
        "category": "inquiry",
        "urgency": "2",
        "impact": "2",
    }

# COMMAND ----------

# MAGIC %md
# MAGIC ## Push

# COMMAND ----------

rows = failures.collect()
created, skipped = [], []

for row in rows:
    correlation_id = row["correlation_id"]

    existing = sn_get(SN_TABLE, f"correlation_id={correlation_id}")
    if existing:
        skipped.append({"correlation_id": correlation_id, "sys_id": existing[0]["sys_id"]})
        continue

    payload = build_payload(row)
    result = sn_post(SN_TABLE, payload)
    created.append({
        "correlation_id": correlation_id,
        "sys_id": result["sys_id"],
        "number": result.get("number"),
    })

print(f"\nCreated: {len(created)}    Skipped (already existed): {len(skipped)}")
for c in created:
    print(f"  -> {c['number']}  {c['correlation_id']}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Persist the push log
# MAGIC
# MAGIC So the auditor view can show: "violation X was pushed to ServiceNow on Y, ticket Z."

# COMMAND ----------

if created or skipped:
    log_df = spark.createDataFrame(
        [(c["correlation_id"], c.get("sys_id"), c.get("number"), "created") for c in created] +
        [(s["correlation_id"], s.get("sys_id"), None,             "skipped") for s in skipped],
        ["correlation_id", "sn_sys_id", "sn_number", "action"],
    ).withColumn("pushed_at", F.current_timestamp())

    (log_df.write
        .mode("append")
        .saveAsTable("gaurav_catalog.docusign_demo.controls_sdlc_pr_attestation_push_log"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Auditor view — closed-loop attestation
# MAGIC
# MAGIC Join the control results to the push log: "for every violation in Databricks,
# MAGIC here is the ServiceNow ticket where it was remediated or accepted."

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   a.repository,
# MAGIC   a.pr_url,
# MAGIC   a.merged_by,
# MAGIC   a.result,
# MAGIC   a.failure_reasons,
# MAGIC   p.sn_number,
# MAGIC   p.pushed_at
# MAGIC FROM gaurav_catalog.docusign_demo.controls_sdlc_pr_attestation a
# MAGIC LEFT JOIN gaurav_catalog.docusign_demo.controls_sdlc_pr_attestation_push_log p
# MAGIC   ON p.correlation_id = concat('SDLC-001:', a.pr_url)
# MAGIC ORDER BY a.merged_at DESC;

# COMMAND ----------

