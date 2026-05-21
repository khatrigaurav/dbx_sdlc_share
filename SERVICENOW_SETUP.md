# ServiceNow setup for the SDLC attestation demo

The push notebook (`04_push_servicenow.py`) writes to the **`incident`** table by default. `incident` exists on every ServiceNow instance — no plugins, no store apps, no extra columns. That makes it the right choice for a demo on a fresh Personal Developer Instance (PDI).

If/when you demo against a customer instance that has IRM/GRC installed, switch `SN_TABLE` to `sn_grc_issue` and adjust `build_payload` (see "Switching to a real GRC table" at the bottom).

---

## 1. Get a Personal Developer Instance (PDI)

1. Sign up at https://developer.servicenow.com/ (free, work email).
2. In the dev portal: profile menu → **Request Instance**.
3. Pick the latest release. Wait 2–3 minutes.
4. You'll get:
   - Instance URL: `https://devXXXXXX.service-now.com`
   - Admin username (`admin`) and a generated password — shown in the portal **once**, copy it now.
5. Log in to confirm it's live.

> ⚠️ PDIs **hibernate after 10 days idle** and get reclaimed after ~60 days. Wake from the developer portal before your demo.

## 2. Verify the `incident` table is reachable

Open `https://devXXXXXX.service-now.com/incident_list.do` — you'll see the standard incident list (might be empty or have a few sample tickets). Nothing to install.


## 3. Create the Databricks secret scope

From your laptop with the Databricks CLI configured to the demo workspace:

```bash
databricks secrets create-scope docusign-demo

databricks secrets put-secret docusign-demo servicenow-instance \
  --string-value "devXXXXXX"      # just the subdomain, no https://
databricks secrets put-secret docusign-demo servicenow-user \
  --string-value "admin"
databricks secrets put-secret docusign-demo servicenow-password \
  --string-value "<password from step 1>"
```

## 4. Flip the notebook to live mode

In `04_push_servicenow.py`:

```python
MOCK_MODE = False
```

Run it. You should see new `INCxxxxxxx` tickets appear at `https://devXXXXXX.service-now.com/incident_list.do`.



## Switching to a real GRC table (customer prod or GRC-enabled sandbox)

If you later get access to an instance that has Policy and Compliance Management installed:

1. Confirm the table — usually `sn_grc_issue`. List view at `/sn_grc_issue_list.do`.
2. Add a custom column `u_correlation_id` (String, 255) under **All → System Definition → Tables → sn_grc_issue → Columns → New**. (The GRC table doesn't have a built-in `correlation_id` field, unlike `task`/`incident`.)
3. In `04_push_servicenow.py`:
   - Set `SN_TABLE = "sn_grc_issue"`.
   - In `build_payload`, rename the key `"correlation_id"` → `"u_correlation_id"` and add back `"u_control_id": CONTROL_ID`.
   - In the dedupe lookup near the bottom, change `f"correlation_id={correlation_id}"` → `f"u_correlation_id={correlation_id}"`.
   - Update the mock-store key in `_mock_response` and `_mock_store[...]` to match (only matters if you keep mock mode around for slides).
4. Service account: needs the `sn_grc_user` role and write on `sn_grc_issue`.

## Fallback — stay in `MOCK_MODE`

`MOCK_MODE = True` (the default in the file as shipped) prints request/response pairs that look like real ServiceNow output. For a 15-minute talk to a non-technical audience it sells the story fine and you skip PDI hibernation roulette entirely.

**Rule of thumb:**
- Technical buyer, hands-on demo → live PDI against `incident`.
- Exec or risk-org audience → `MOCK_MODE = True`, use `sample_servicenow_responses.md` for slide screenshots.
