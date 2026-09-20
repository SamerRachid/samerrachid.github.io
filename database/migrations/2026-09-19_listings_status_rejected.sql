-- Balkoun · 2026-09-19 · the panel's "Reject" sets listings.status = 'rejected' (reject_reason / rejected_at, owner notified by
-- bk_admin_set_status) but the check constraint predated that status → "violates check constraint listings_status_check".
alter table public.listings drop constraint if exists listings_status_check;
alter table public.listings add constraint listings_status_check check (status in ('draft','pending','live','hidden','sold','rented','expired','removed','rejected'));
