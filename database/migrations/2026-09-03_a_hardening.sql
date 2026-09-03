-- Security migration A (2026-09-03): low-risk hardening.
-- Idempotent. Safe to re-run. Apply in the Supabase SQL editor or via the MCP apply_migration tool.

-- 1) covering indexes for every foreign key the advisor flagged
create index if not exists idx_ad_slots_linked_listing on public.ad_slots(linked_listing_id);
create index if not exists idx_admin_sessions_user     on public.admin_sessions(user_id);
create index if not exists idx_contact_events_user     on public.contact_events(user_id);
create index if not exists idx_feedback_user           on public.feedback(user_id);
create index if not exists idx_listing_reports_listing on public.listing_reports(listing_id);
create index if not exists idx_listing_reports_user    on public.listing_reports(user_id);
create index if not exists idx_listings_area           on public.listings(area_id);
create index if not exists idx_listings_user           on public.listings(user_id);
create index if not exists idx_page_views_user         on public.page_views(user_id);
create index if not exists idx_reviews_author          on public.reviews(author_user);
create index if not exists idx_saved_listings_listing  on public.saved_listings(listing_id);
create index if not exists idx_saved_searches_user     on public.saved_searches(user_id);

-- 2) stale overloads the client no longer calls (it uses the 8-arg register and 5-arg update_profile)
drop function if exists public.bk_register(text,text,text,text);
drop function if exists public.bk_update_profile(uuid,text,text);

-- 3) policies: p_listing_own used auth.uid(), which is always null here (dead);
--    p_review_own was "author_user = author_user" = always true, letting anon write/delete any review
drop policy if exists p_listing_own on public.listings;
drop policy if exists p_review_own on public.reviews;

-- 4) views run with the caller's rights so the listings read policy applies (advisor ERROR fix)
alter view public.v_listings set (security_invoker = on);
alter view public.v_area_prices set (security_invoker = on);

-- 5) no direct table writes from the browser: every write goes through a SECURITY DEFINER bk_* function
do $$ declare r record; begin
  for r in select tablename as n from pg_tables where schemaname='public'
           union all select viewname from pg_views where schemaname='public' loop
    execute format('revoke insert, update, delete, truncate, references, trigger on public.%I from anon, authenticated', r.n);
  end loop;
end $$;
-- the post-listing form still inserts directly until migration B replaces it with bk_post_listing
grant insert on public.listings to anon, authenticated;

-- 6) pin search_path on every bk_* function (advisor WARN "Function Search Path Mutable");
--    pgcrypto lives in the extensions schema on Supabase, so it must stay on the path
do $$ declare r record; begin
  for r in select p.oid::regprocedure as sig from pg_proc p
           join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname like 'bk\_%' loop
    execute format('alter function %s set search_path = public, extensions', r.sig);
  end loop;
end $$;
