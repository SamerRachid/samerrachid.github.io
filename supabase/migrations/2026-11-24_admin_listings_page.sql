-- 2026-11-24 «كل الإعلانات» in the panel reads page by page from the database (owner: the page said 500 while
-- the site has 863). Step 2 (same day): the panel's pickers (featured, home-page ad link, social, placements,
-- engagements), type counts and «delete all» read through it too. Read only: no listing is changed here.
-- p_f: {status, gov, type, who, src: bot|site, q, user: uuid, sort: new|views|contacts|price|livefirst,
--       ids: [listing ids], statuses: [..], ref: exact listing number or id, nofacets: true} — the last four for the panel's pickers
create or replace function public.bk_admin_listings_page(p_token text, p_country text default null, p_f jsonb default '{}'::jsonb,
                                                         p_offset integer default 0, p_limit integer default 25, p_days integer default 7)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; sc text; al text[]; f jsonb := coalesce(p_f,'{}'::jsonb); w text[]; uf uuid; t0 timestamptz; srt text; res json;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, array['listings_view','listings_edit','listings_delete']::text[], 'bk_admin_listings_page', null, false, left(coalesce(f::text,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  w := bk_kw_words(coalesce(f->>'q','')); if cardinality(w) = 0 then w := null; end if;
  uf := nullif(f->>'user','')::uuid;
  srt := coalesce(nullif(f->>'sort',''),'new');
  t0 := now() - (greatest(1, least(coalesce(p_days,7), 3650)) || ' days')::interval;
  with base as (
    select l.id, l.ref, l.status, l.deal, l.property_type, l.price_usd, l.area_m2, l.tabu, l.condition, l.contact_name, l.contact_phone,
           l.created_at, l.is_featured, l.country_code, g.name_ar as gov, a.name_ar as area,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name, u.phone as poster_phone, u.id as poster_id,
           (select ag.name from agencies ag where ag.user_id = l.user_id and ag.status = 'approved' limit 1) as agency_name,
           (select d.source from intake_drafts d where d.listing_id=l.id order by d.id desc limit 1) as via
      from listings l join governorates g on g.id=l.governorate_id left join areas a on a.id=l.area_id left join users u on u.id=l.user_id
     where bk_scope_ok(l.country_code,sc,al) and (uf is null or l.user_id = uf)
       and (jsonb_typeof(f->'ids') is distinct from 'array' or l.id in (select (x #>> '{}')::bigint from jsonb_array_elements(f->'ids') x where (x #>> '{}') ~ '^\d+$'))
       and (jsonb_typeof(f->'statuses') is distinct from 'array' or l.status in (select x #>> '{}' from jsonb_array_elements(f->'statuses') x))
       and (coalesce(f->>'ref','') = '' or upper(l.ref) = upper(trim(f->>'ref')) or l.id::text = trim(f->>'ref'))
  ), b2 as (
    select b.*, coalesce(nullif(b.agency_name,''), nullif(b.poster_name,''), '') as who from base b
  ), filt as (
    select * from b2 b
     where (coalesce(f->>'status','') = '' or b.status = f->>'status')
       and (coalesce(f->>'gov','') = '' or coalesce(b.gov,'') = f->>'gov')
       and (coalesce(f->>'type','') = '' or b.property_type = f->>'type')
       and (coalesce(f->>'who','') = '' or b.who = f->>'who')
       and (coalesce(f->>'src','') <> 'bot' or b.via is not null)
       and (coalesce(f->>'src','') <> 'site' or b.via is null)
       and (w is null or bk_kw_hit(bk_kw_norm(concat_ws(' ', b.ref, b.id::text, b.gov, b.area, b.poster_name, b.agency_name, b.poster_phone, b.contact_phone,
              b.price_usd::text, b.property_type, b.status,
              case b.property_type when 'apartment' then 'شقة' when 'shop' then 'محل' when 'plot' then 'ارض' when 'house' then 'بيت منزل'
                when 'farm' then 'مزرعة' when 'arab' then 'بيت عربي' when 'villa' then 'فيلا' when 'office' then 'مكتب'
                when 'agri' then 'ارض زراعية' when 'building' then 'بناء كامل' when 'showroom' then 'صالة عرض' when 'restaurant' then 'مطعم'
                when 'warehouse' then 'مستودع' when 'resid' then 'ارض سكنية' when 'comm' then 'ارض تجارية' when 'duplex' then 'دوبلكس'
                when 'factory' then 'معمل' when 'tourist' then 'ارض سياحية' when 'mahdar' then 'محضر' when 'hotel' then 'فندق' else '' end,
              case b.status when 'live' then 'منشور' when 'pending' then 'بانتظار المراجعة' when 'hidden' then 'مخفي' when 'rejected' then 'مرفوض'
                when 'sold' then 'مباع' when 'rented' then 'مؤجر' when 'expired' then 'منتهي' when 'removed' then 'محذوف' else '' end,
              case b.deal when 'rent' then 'ايجار للايجار' else 'بيع للبيع' end)), w))
  ), ranked as (
    select fl.*,
           case when srt = 'views' then (select count(*) from page_views v where v.listing_id=fl.id and v.created_at >= t0) else 0 end as s_views,
           case when srt = 'contacts' then (select count(*) from contact_events c where c.listing_id=fl.id and c.created_at >= t0) else 0 end as s_contacts
      from filt fl
  ), page as (
    select r.* from ranked r
     order by case when srt='livefirst' and r.status <> 'live' then 1 else 0 end,
              case when srt='views' then r.s_views when srt='contacts' then r.s_contacts else 0 end desc,
              case when srt='price' then coalesce(r.price_usd,0) else 0 end desc,
              r.created_at desc, r.id desc
     offset greatest(0, coalesce(p_offset,0)) limit greatest(1, least(coalesce(p_limit,25), 500))
  )
  select json_build_object(
    'total', (select count(*) from filt),
    'scope_total', (select count(*) from b2),
    'pending', (select count(*) from b2 where status = 'pending'),
    'facets', case when coalesce((f->>'nofacets')::boolean,false) then '{}'::json else json_build_object(
       'status', coalesce((select json_object_agg(k, n) from (select status k, count(*) n from b2 group by 1) x), '{}'::json),
       'gov',    coalesce((select json_agg(json_build_array(k, n) order by n desc, k) from (select gov k, count(*) n from b2 where coalesce(gov,'') <> '' group by 1) x), '[]'::json),
       'type',   coalesce((select json_agg(json_build_array(k, n) order by n desc, k) from (select property_type k, count(*) n from b2 where coalesce(property_type,'') <> '' group by 1) x), '[]'::json),
       'who',    coalesce((select json_agg(json_build_array(k, n) order by n desc, k) from (select who k, count(*) n from b2 where who <> '' group by 1) x), '[]'::json),
       'bot',    (select count(*) from b2 where via is not null),
       'site',   (select count(*) from b2 where via is null)) end,
    'rows', coalesce((select json_agg(json_build_object(
        'id',p.id,'ref',p.ref,'status',p.status,'deal',p.deal,'property_type',p.property_type,'price_usd',p.price_usd,'area_m2',p.area_m2,
        'tabu',p.tabu,'condition',p.condition,'contact_name',p.contact_name,'contact_phone',p.contact_phone,'created_at',p.created_at,
        'is_featured',p.is_featured,'country_code',p.country_code,'gov',p.gov,'area',p.area,'poster_name',p.poster_name,'poster_phone',p.poster_phone,
        'poster_id',p.poster_id,'agency_name',p.agency_name,'via',p.via,
        'photos',(select count(*) from listing_photos ph where ph.listing_id=p.id),
        'cover',coalesce((select coalesce(nullif(ph.thumb_url,''), ph.url) from listing_photos ph where ph.listing_id=p.id and coalesce(ph.kind,'photo')='photo' order by ph.sort_order, ph.id limit 1),
                         (select nullif(ph.thumb_url,'') from listing_photos ph where ph.listing_id=p.id and ph.kind='video' and coalesce(ph.thumb_url,'') <> '' order by ph.sort_order, ph.id limit 1)))
        order by case when srt='livefirst' and p.status <> 'live' then 1 else 0 end, case when srt='views' then p.s_views when srt='contacts' then p.s_contacts else 0 end desc,
                 case when srt='price' then coalesce(p.price_usd,0) else 0 end desc, p.created_at desc, p.id desc) from page p), '[]'::json)
  ) into res;
  return res;
end $function$;
revoke all on function public.bk_admin_listings_page(text,text,jsonb,integer,integer,integer) from public;
grant execute on function public.bk_admin_listings_page(text,text,jsonb,integer,integer,integer) to anon, authenticated, service_role;
