-- 2026-10-31: the panel replaces blurry video posters (the tiny preview WhatsApp sends, ~500 bytes) with the sharpest frame of
-- the video itself. The browser does the frame work; this lists the videos it may look at (the admin's own countries only).
begin;
create or replace function public.bk_admin_video_list(p_token text)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['listings_edit']::text[], 'bk_admin_video_list', null, false, '', null);
  return coalesce((
    select json_agg(json_build_object('id', p.id, 'listing_id', p.listing_id, 'url', p.url, 'thumb_url', p.thumb_url) order by p.id desc)
    from listing_photos p join listings l on l.id = p.listing_id
    where p.kind = 'video' and l.status in ('live','pending','sold','rented')
      and bk_admin_country_ok(uid, coalesce(l.country_code,'SY'))), '[]'::json);
end $fn$;
revoke all on function public.bk_admin_video_list(text) from public;
grant execute on function public.bk_admin_video_list(text) to anon, authenticated;
commit;
