-- 2026-10-11: bk_admin_storage_report extended, two additions the owner asked for after the storage investigation.
--   1. "stale_og" is now its own kind: the og-share.png.stale/.stale2/.stale3/.stale4 leftovers from the regen-via-
--      rename trick used while fixing the share-card (2026-10-05..10) were silently counted as ordinary listing
--      photos ("k_listings"), so the admin had no visibility into ~1.85 GB of pure waste. They get their own
--      row in the by-kind table (red, like orphans) and their own delete-all button, same pattern as trash/orphans.
--   2. "by_listing": the top 30 listings by storage (photo + video bytes, stale excluded since that's cleaned
--      separately), always available in the admin's Storage tab — not a one-off report.

CREATE OR REPLACE FUNCTION public.bk_admin_storage_report(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return (
    with o as (
      select name, (metadata->>'size')::bigint as bytes, created_at,
             split_part(name,'/',1) as f1, split_part(name,'/',2) as f2, split_part(name,'/',3) as f3
        from storage.objects where bucket_id = 'photos'
    ), k as (
      select *,
        case
          when f1 = 'trash' then 'trash'
          when name ~ 'og-share\.png\.stale' then 'stale_og'
          when f1 = 'ads' or (f1 = 'videos' and f2 = 'ads') then (case when name ~* '\.(mp4|webm|mov|m4v)$' then 'ad_videos' else 'ad_photos' end)
          when f1 in ('banners','banner') or (f1 = 'videos' and f2 in ('banners','banner')) then 'banners'
          when f1 in ('background','hero') or (f1 = 'videos' and f2 in ('background','hero')) then 'background'
          when f1 = 'avatars' then 'avatars'
          when f1 ~ '^[0-9]+$' and exists (select 1 from listings l where l.id::text = f1) then 'listings'
          when f1 in ('photos','videos') and f2 = 'listings' and exists (select 1 from listings l where l.id::text = f3) then 'listings'
          when f1 ~ '^[0-9]+$' or (f1 in ('photos','videos') and f2 = 'listings') then 'orphans'
          else 'other'
        end as kind,
        case when f1 in ('photos','videos') and f2 = 'listings' then f1||'/listings/'||f3 else f1 end as folder
      from o
    ), kl as (
      select (case when f1 in ('photos','videos') and f2 = 'listings' then f3 else f1 end)::bigint as lid,
             bytes, (f1 = 'videos' or name ~* '\.(mp4|webm|mov|m4v)$') as is_video
        from k where kind = 'listings'
    ), bl as (
      select lid,
             coalesce(sum(bytes) filter (where not is_video), 0) as photo_bytes, count(*) filter (where not is_video) as n_photo,
             coalesce(sum(bytes) filter (where is_video), 0) as video_bytes, count(*) filter (where is_video) as n_video,
             sum(bytes) as total_bytes
        from kl group by lid
    )
    select json_build_object(
      'total_bytes', coalesce((select sum(bytes) from k),0),
      'files', (select count(*) from k),
      'groups', coalesce((select json_agg(g order by g.bytes desc) from (select kind, count(*) as files, sum(bytes) as bytes from k group by kind) g), '[]'::json),
      'orphans', coalesce((select json_agg(x order by x.bytes desc) from (select folder, count(*) as files, sum(bytes) as bytes from k where kind='orphans' group by folder) x), '[]'::json),
      'orphan_items', coalesce((select json_agg(t) from (select name, folder, bytes, created_at::date as created from k where kind='orphans' order by folder, name limit 300) t), '[]'::json),
      'trash_paths', coalesce((select json_agg(name) from k where kind='trash'), '[]'::json),
      'trash_bytes', coalesce((select sum(bytes) from k where kind='trash'),0),
      'trash_items', coalesce((select json_agg(t) from (select name, bytes, created_at::date as created from k where kind='trash' order by created_at desc, name limit 300) t), '[]'::json),
      'stale_paths', coalesce((select json_agg(name) from k where kind='stale_og'), '[]'::json),
      'stale_bytes', coalesce((select sum(bytes) from k where kind='stale_og'),0),
      'stale_items', coalesce((select json_agg(t) from (select name, bytes, created_at::date as created from k where kind='stale_og' order by bytes desc, name limit 300) t), '[]'::json),
      'top', coalesce((select json_agg(t) from (select name, bytes, created_at::date as created, kind from k order by bytes desc limit 10) t), '[]'::json),
      'by_listing', coalesce((select json_agg(x order by x.total_bytes desc) from (
          select bl.lid as id, l.ref, l.status, l.country_code,
                 bl.photo_bytes, bl.n_photo, bl.video_bytes, bl.n_video, bl.total_bytes
            from bl join listings l on l.id = bl.lid
           order by bl.total_bytes desc limit 30) x), '[]'::json)
    )
  );
end $function$;
