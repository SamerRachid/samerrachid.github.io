-- 2026-10-09 — three functions each had two overloads (an older short signature left behind when a newer
-- signature with one extra DEFAULT-valued parameter was added via a new CREATE FUNCTION instead of replacing
-- the old one). Every extra parameter has a DEFAULT, so PostgREST sees both candidates as equally valid for any
-- call that only provides the shorter parameter set and returns PGRST203 "Could not choose the best candidate
-- function" (HTTP 300) instead of calling either. Confirmed live call sites that hit this:
--   bk_verify_start(p_phone,p_purpose,p_country) <- index.html:4624 (resend/reset flow, no p_email)
--   bk_agency_save(p_token,p_name,p_phone,p_whatsapp,p_country) <- index.html:8828 (account-page agency autocreate)
--   bk_admin_set_permissions(p_token,p_admin,p_permissions,p_countries) <- admin.js:1892 (the main "save admin
--     permissions" form in the panel)
-- In each pair the longer signature is a strict, verified superset (bk_verify_start: adds email verification;
-- bk_agency_save: adds contact_person auto-fill; bk_admin_set_permissions: preserves permissions instead of
-- wiping them to '{}' on a null, uses the bk_admin_is_super() helper, and additionally guards against editing a
-- super admin's own row) — so dropping the short one is a strict improvement, not just a disambiguation.
-- Applied via the Supabase SQL editor directly (owner ran it) since apply_migration auto-declines "drop".
-- Verified live via the real REST/RPC layer after the drop: bk_verify_start with the short 3-key set returns
-- a full normal response (no PGRST203); bk_agency_save and bk_admin_set_permissions with their short key sets
-- reach real application logic ("not signed in" / "unauthorised") instead of an ambiguity error.
drop function public.bk_verify_start(text, text, text);
drop function public.bk_agency_save(text, text, text, text, text, text, text, text, text[], text[], text[], text);
drop function public.bk_admin_set_permissions(text, uuid, text[], text[]);
