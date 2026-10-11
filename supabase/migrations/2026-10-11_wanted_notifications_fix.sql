-- 2026-10-11: the "wanted" (مطلوب) feature was broken end to end since whoever added it — not a "too many required
-- fields" problem, a real server crash. bk_wanted_save() calls bk_wanted_notify(), which inserts a notification
-- with type='wanted_match' to alert any owner of a matching live listing; and the trigger bk_trg_listing_live_wanted
-- (fires whenever a listing goes live) inserts type='wanted_listing' to alert the wanted-poster back. Neither value
-- was ever added to notifications_type_check, so:
--   - posting a wanted request crashed as soon as ANY matching live listing existed (near-guaranteed on a live site)
--   - publishing a listing crashed too, whenever an open wanted request happened to match it
-- Confirmed by reproducing bk_wanted_save in a rolled-back transaction: ERROR 23514, notifications_type_check.
-- Fix: widen the constraint to the two values the app already writes; nothing else changes.

alter table public.notifications drop constraint notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type = any (array['reply','price','admin_msg','admin_alert','system','wanted_match','wanted_listing']));
