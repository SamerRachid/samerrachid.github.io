-- undo of 2026-11-11_user_follows.sql (the follow notifications already delivered stay in members' bells)
drop trigger if exists trg_listing_live_follows on public.listings;
drop function if exists public.bk_trg_listing_live_follows();
drop function if exists public.bk_my_follows(text);
drop function if exists public.bk_follow_user(text, uuid, boolean);
drop table if exists public.user_follows;
