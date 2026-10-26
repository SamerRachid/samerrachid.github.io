-- «المشاهدات» = every time the listing page is opened, the same visitor again included (owner, 2026-10-26:
-- «it's viewing count, not visitor count»). Crawlers and a page left within 3 seconds are still not counted.
create or replace function public.bk_log_view2(p_path text, p_view text, p_user uuid, p_country text, p_token text DEFAULT NULL::text, p_visitor text DEFAULT NULL::text, p_device text DEFAULT NULL::text, p_referrer text DEFAULT NULL::text, p_site_country text DEFAULT NULL::text)
 returns void language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare lid bigint;
begin
  perform bk_require_member(p_token, p_user);
  lid := nullif(substring(coalesce(p_path,'') from '/listing/(\d+)'), '')::bigint;
  insert into page_views (path, view, user_id, country, visitor_id, device, referrer, listing_id, site_country)
  values (left(p_path,300), left(p_view,40), p_user, left(p_country,8), left(p_visitor,40), left(p_device,10), left(p_referrer,200), lid, coalesce(nullif(upper(left(p_site_country,2)),''),'SY'));
  if lid is not null then update listings set views = views + 1 where id = lid; end if;
end $function$;

drop index if exists page_views_listing_visitor_idx;

update listings l set views = coalesce((select count(*) from page_views v where v.listing_id = l.id), 0);
