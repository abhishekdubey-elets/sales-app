# Compliance & Security Notes

This describes what the platform enforces. It is not legal advice: review calling hours, consent wording,
recording disclosures and DND handling with your counsel and telephony provider (TRAI TCCCPR, DPDP Act 2023,
and any sector rules that apply to your prospects).

## Enforced before every call (human and AI)

| Control | Where | Behaviour |
|---|---|---|
| Opt-out / do-not-call list | `opt_outs` table, `services/compliance.py` | Numbers that asked not to be called are blocked for **all** users and agents (`403 opted_out`). Sources: lead request, AI call (`record_opt_out` tool), admin. |
| External DND registry | `compliance.DndChecker` | Extension point for NCPR/DND scrubbing via your provider. Not connected by default — wire it to your provider's DND API before campaigns. |
| Permitted calling hours | Settings → calling hours/days (default 09:00–21:00, Mon–Sat, Asia/Kolkata) | Calls outside the window are refused (`403 outside_calling_hours`). Campaigns also have their own, narrower schedule. |
| AI consent | Settings → *Require consent for AI calls* | When on, AI calls only go to leads whose `consent_status` is `granted`. |
| One live call per lead | `lead_call_locks` | Prevents duplicate simultaneous calls across human and AI calling. |
| Calling credits | Settings → credits | AI calls stop when credits are exhausted; campaigns auto-pause. |

## AI-specific

- **Disclosure first.** The AI agent's first words are the fixed *AI disclosure text* from Settings (plus the
  recording notice when recording is on), spoken before any model-generated speech. The model is also instructed
  to confirm it is an AI if asked and never to claim to be human.
- **Grounded statements.** Agents are instructed to state only facts present in their knowledge base and to defer
  prices/commitments to the sales team.
- **Hand-off on request.** Asking for a person triggers `transfer_to_human`: the lead owner is notified, a
  follow-up is created, and the call is transferred live where the provider supports it.
- **No sensitive data collection.** Agents are instructed never to ask for payment details, passwords or
  government ID numbers.
- **Human review.** Transcripts, summaries and qualification scores are visible to managers/admins; AI suggestions
  never downgrade a lead that a human moved to converted/lost/meeting scheduled.

## Recording

- Org-level switch plus a per-agent switch; when off, the provider is not asked to record.
- The recording disclosure text is played on AI calls. For human calls, salespeople should announce recording, or
  configure a provider-side announcement on your virtual number.
- Recordings are stored at the provider; the platform stores the URL encrypted and serves audio only through
  short-lived signed links after a permission check. Every access is written to `audit_logs`.

## Data protection

- Lead phone numbers, emails and recording URLs are encrypted at rest (Fernet); lookups use HMAC blind indexes.
- Executives see masked numbers by default (calls are placed server-side, so they never need the raw number).
- Role-based access: executives see their own leads and calls, managers their team, admins everything.
- JWT access tokens are short-lived; refresh tokens rotate and are stored hashed per device session; changing a
  password revokes other sessions.
- Provider credentials and API keys live only in server environment variables — never in the Flutter app.
- Audit log covers logins (including failures), user/role changes, lead deletion/opt-out/import/assignment,
  recording access, AI agent and campaign changes, settings changes and exports.

## Retention

Not automated yet. Decide retention periods for call records, transcripts and recordings (and the provider's own
retention), then add a scheduled purge job in `workers/jobs.py`.
