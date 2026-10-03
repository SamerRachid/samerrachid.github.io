# Intake bot test suite

Two parts, both built from real messages seen in use. Run both before deploying `supabase/functions/bk-intake`
or changing `bk_intake_message()` / `bk_intake_save_read()` / `bk_intake_publish()`.

## 1. State machine (SQL, free, ~1 s)
`sql-scenarios.sql` — one `DO` block that creates a throw-away agency, walks the commands («نعم», «لا», «جديد»,
«رجّع», photos after publish / review, the area question, «نعم» mid-read, 24-hour expiry…) and **always rolls back**
by raising an exception whose message is the report:

```
BOT_SQL_SCENARIOS fails=0
PASS no_without_draft
PASS first_text_opens_draft
...
```

Run it in the Supabase SQL editor (or through the MCP connector). `fails=0` is the pass condition; nothing is written.
Note: `now()` is frozen inside the transaction, so "newest draft" setups use `now() + interval '1 second'`.
First run (2026-10-02) found one real bug: a bare photo sent to a draft under review landed silently — fixed in
`database/migrations/2026-10-02_intake_review_photo_ack.sql`.

The fixed product rules the suite protects are in `docs/bot-rules.md`.

## 2. Reading (Edge Function + Claude, ~0.5¢ per case)
`read-cases.mjs` — sends each message through the bot's own `test_claude` route (same prompt, same code guards) and
checks the fields that matter: type, deal, area vs landmark, price, deed, units.

```bash
node tests/bot/read-cases.mjs <admin-session-token>
```

The token is a panel admin session (`admin_sessions.token`); create a short-lived one for the run. Exit code 1 on any
failure. Add a case every time a real message fools the bot — that is how the suite stays honest.
