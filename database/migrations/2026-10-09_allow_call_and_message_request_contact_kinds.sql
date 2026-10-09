-- 2026-10-09 — contact_events_kind_check allowed only reveal_phone/whatsapp/visit_request, but the client
-- (index.html: the phone/call buttons and the in-site message-to-owner flow) also sends 'call' and
-- 'message_request'. Both inserts violated the check constraint and were silently swallowed client-side
-- (the log() helper is fire-and-forget), so the admin's "contact kinds" analytics has always shown zero
-- calls and zero message requests. GX_T already had full ar/en/de/fr labels for ck_call (an oversight: the
-- label was added but the constraint never was), confirming this was always meant to work.
-- Verified live before this fix (rolled-back transaction): inserting kind='call' raised 23514; after the
-- fix, both 'call' and 'message_request' insert cleanly.
alter table public.contact_events drop constraint contact_events_kind_check;
alter table public.contact_events add constraint contact_events_kind_check
  check (kind = any (array['reveal_phone','whatsapp','visit_request','call','message_request']));
