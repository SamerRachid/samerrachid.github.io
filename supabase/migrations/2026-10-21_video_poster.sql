-- The owner / an admin picks a video's preview picture (owner, 2026-10-21): a frame of the video (uploaded by the page
-- into the listing's own folder) or one of the listing's photos. Only a file inside photos/listings/<listing id>/ is
-- accepted, never an outside link.
begin;

create or replace function public.bk_video_poster_apply(p_photo bigint, p_url text)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare r listing_photos;
begin
  select * into r from listing_photos where id = p_photo;
  if r.id is null or coalesce(r.kind,'photo') <> 'video' then return json_build_object('error','novideo'); end if;
  if p_url is null or p_url !~ ('^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/photos/photos/listings/' || r.listing_id || '/[A-Za-z0-9._-]+\.(jpe?g|png|webp)$') then
    return json_build_object('error','badurl');
  end if;
  update listing_photos set thumb_url = p_url where id = p_photo;
  return json_build_object('ok', true, 'thumb_url', p_url);
end $fn$;
revoke all on function public.bk_video_poster_apply(bigint, text) from public, anon, authenticated;

create or replace function public.bk_photo_set_poster(p_user uuid, p_photo bigint, p_url text, p_token text default null)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
begin
  perform bk_require_member(p_token, p_user);
  if not exists (select 1 from listing_photos p join listings l on l.id = p.listing_id where p.id = p_photo and l.user_id = p_user) then
    raise exception 'forbidden';
  end if;
  return bk_video_poster_apply(p_photo, p_url);
end $fn$;
revoke all on function public.bk_photo_set_poster(uuid, bigint, text, text) from public;
grant execute on function public.bk_photo_set_poster(uuid, bigint, text, text) to anon, authenticated;

create or replace function public.bk_admin_photo_set_poster(p_token text, p_photo bigint, p_url text)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; lcc text;
begin
  uid := bk_admin_uid(p_token);
  select coalesce(l.country_code,'SY') into lcc from listing_photos p join listings l on l.id = p.listing_id where p.id = p_photo;
  perform public.bk_admin_need(uid, ARRAY['listings_edit']::text[], 'bk_admin_photo_set_poster', lcc, true, left(coalesce(p_photo::text,''),300), lcc);
  return bk_video_poster_apply(p_photo, p_url);
end $fn$;
revoke all on function public.bk_admin_photo_set_poster(text, bigint, text) from public;
grant execute on function public.bk_admin_photo_set_poster(text, bigint, text) to anon, authenticated;
commit;
