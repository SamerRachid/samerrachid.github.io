-- 2026-10-13 (audit follow-up): listing_photos accepted INSERTs from anyone with the public key, with no
-- ownership check — a row pointing an offensive image at someone else's listing was one REST call away.
-- The app never used that path: photos and videos are written through bk_photo_add (member token + listing
-- ownership + per-listing limits), the bot through the service key. The client's dead direct-insert branch
-- is removed in the same commit.
drop policy if exists p_photo_insert on public.listing_photos;

select count(*) as insert_policies_left from pg_policies where schemaname = 'public' and tablename = 'listing_photos' and cmd = 'INSERT';
