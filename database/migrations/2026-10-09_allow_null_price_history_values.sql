-- 2026-10-09 — found while fixing "member/admin cannot clear a listing's price back to on-request": the
-- keep_price() trigger (BEFORE UPDATE on listings) logs every price_usd change into price_history, whose
-- old_price/new_price columns were NOT NULL. "Price on request" (price_usd null) is a fully supported state
-- everywhere else in the app, but this trigger had never been updated for it, so ANY transition to or from a
-- null price failed with a not-null violation on price_history — even after fixing bk_edit/bk_admin_edit_listing
-- to pass the null through correctly. price_history is purely an internal counter (client only reads
-- count(*) as "price_changes"; no code reads the actual old/new values), so relaxing these columns is safe.
alter table public.price_history alter column old_price drop not null;
alter table public.price_history alter column new_price drop not null;
