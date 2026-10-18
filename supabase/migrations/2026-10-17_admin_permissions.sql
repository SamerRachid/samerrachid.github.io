begin;
-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- Admin permissions enforced in the database (owner, 2026-10-17). Before this, permissions only hid pages in the
-- panel; every admin function accepted any admin. Now each one calls bk_admin_need(): the admin must hold one of the
-- listed permissions (super admins hold all), the item must belong to a country the admin may manage, and every
-- change is written to admin_audit. Refusals are logged by the panel through bk_admin_audit_denied (a refused call
-- is rolled back, so it cannot log itself).
-- ════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.admin_audit (
  id bigserial primary key,
  at timestamptz not null default now(),
  admin_id uuid,
  admin_name text,
  action text not null,
  target text,
  country text,
  ok boolean not null default true,
  reason text
);
create index if not exists admin_audit_at_idx on public.admin_audit (at desc);
create index if not exists admin_audit_admin_idx on public.admin_audit (admin_id, at desc);
alter table public.admin_audit enable row level security;
revoke all on public.admin_audit from anon, authenticated, public;

create or replace function public.bk_admin_need(p_uid uuid, p_perms text[], p_action text, p_cc text, p_write boolean, p_target text, p_audit_cc text)
 returns void language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare su boolean; pm text[]; nm text;
begin
  select coalesce(is_super_admin,false), coalesce(permissions,'{}'::text[]), trim(coalesce(name,'')||' '||coalesce(family_name,''))
    into su, pm, nm from users where id = p_uid;
  if p_perms is not null and cardinality(p_perms) > 0 then
    if p_perms = array['__super__']::text[] then
      if not coalesce(su,false) then raise exception 'forbidden: super admin only'; end if;
    elsif not coalesce(su,false) and not (pm && p_perms) then
      raise exception 'forbidden: missing permission %', array_to_string(p_perms,'|');
    end if;
  end if;
  if p_cc is not null and not bk_admin_country_ok(p_uid, p_cc) then raise exception 'forbidden: other country'; end if;
  if p_write then
    insert into admin_audit (admin_id, admin_name, action, target, country, ok) values (p_uid, nm, p_action, p_target, coalesce(p_cc, p_audit_cc), true);
  end if;
end $fn$;
revoke all on function public.bk_admin_need(uuid,text[],text,text,boolean,text,text) from public, anon, authenticated;

-- the panel logs a refused action (who is taken from the token, never from the caller)
create or replace function public.bk_admin_audit_denied(p_token text, p_action text, p_reason text, p_country text default null)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; nm text;
begin
  begin uid := bk_admin_uid(p_token); exception when others then return json_build_object('ok', false); end;
  select trim(coalesce(name,'')||' '||coalesce(family_name,'')) into nm from users where id = uid;
  insert into admin_audit (admin_id, admin_name, action, country, ok, reason)
    values (uid, nm, left(coalesce(p_action,''),80), nullif(upper(left(coalesce(p_country,''),3)),''), false, left(coalesce(p_reason,''),300));
  return json_build_object('ok', true);
end $fn$;

-- edge functions ask whether an admin token holds a permission
create or replace function public.bk_admin_can(p_token text, p_perms text[])
 returns boolean language plpgsql stable security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; su boolean; pm text[];
begin
  begin uid := bk_admin_uid(p_token); exception when others then return false; end;
  select coalesce(is_super_admin,false), coalesce(permissions,'{}'::text[]) into su, pm from users where id = uid;
  return su or pm && p_perms;
end $fn$;

-- the activity log (permission «audit»; super admins see everything); follows the panel's country
create or replace function public.bk_admin_audit(p_token text, p_country text default null, p_admin uuid default null, p_limit integer default 300)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, array['audit']::text[], 'bk_admin_audit', null, false, null, null);
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x order by x.at desc) from (
    select a.id, a.at, a.admin_id, a.admin_name, a.action, a.target, a.country, a.ok, a.reason
      from admin_audit a
     where (p_admin is null or a.admin_id = p_admin)
       and ((a.country is null and sc is null and al is null) or (a.country is not null and bk_scope_ok(a.country, sc, al)))
     order by a.at desc limit greatest(1, least(coalesce(p_limit,300), 2000))) x), '[]'::json);
end $fn$;

-- bk_admin_ad_country
CREATE OR REPLACE FUNCTION public.bk_admin_ad_country(p_token text, p_id bigint, p_country text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['ads']::text[], 'bk_admin_ad_country', (select coalesce(country_code,'SY') from ad_slots where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from ad_slots where id=p_id)); perform bk_admin_guard(uid, (select country_code from ad_slots where id = p_id)); perform bk_admin_guard(uid, p_country); update ad_slots set country_code=p_country where id=p_id; update engagements set country_code=p_country where kind='ad' and ref_id=p_id; return json_build_object('ok',true); end $function$;

-- bk_admin_agencies
CREATE OR REPLACE FUNCTION public.bk_admin_agencies(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_agencies', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by (x.status='pending') desc, x.created_at desc) from (
    select a.*, u.avatar_url as logo_url, u.phone as user_phone, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as user_name, u.blocked,
           (select count(*) from listings l where l.user_id=a.user_id and l.status='live') as live
      from agencies a join users u on u.id=a.user_id where bk_scope_ok(coalesce(a.country_code,'SY'),sc,al)) x), '[]'::json);
end $function$;

-- bk_admin_agency_get
CREATE OR REPLACE FUNCTION public.bk_admin_agency_get(p_token text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_agency_get', (select coalesce(country,'SY') from users where id=p_user), false, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user));
  return coalesce((select row_to_json(a) from agencies a where a.user_id = p_user), (select json_build_object('user_id', u.id, 'phone', u.phone, 'whatsapp', u.phone, 'avatar_url', u.avatar_url, 'country_code', u.country) from users u where u.id = p_user));
end $function$;

-- bk_admin_agency_save
CREATE OR REPLACE FUNCTION public.bk_admin_agency_save(p_token text, p_user uuid, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; u users; r agencies;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_agency_save', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user));
  select * into u from users where id = p_user; if u.id is null then return json_build_object('error', 'nouser'); end if;
  perform bk_admin_guard(uid, u.country);
  if coalesce(trim(p_patch->>'name'), '') = '' then return json_build_object('error', 'noname'); end if;
  if p_patch ? 'avatar_url' then update users set avatar_url = nullif(p_patch->>'avatar_url', '') where id = u.id; end if;
  insert into agencies (user_id, name, description, phone, whatsapp, email, website, address, gov_names, area_names, specialties, status, country_code, contact_person)
    values (u.id, left(trim(p_patch->>'name'), 120), nullif(p_patch->>'description',''), nullif(p_patch->>'phone',''), nullif(p_patch->>'whatsapp',''), nullif(p_patch->>'email',''), nullif(p_patch->>'website',''), nullif(p_patch->>'address',''),
            coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_patch->'gov_names','[]'::jsonb)) x), '{}'),
            coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_patch->'area_names','[]'::jsonb)) x), '{}'),
            coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_patch->'specialties','[]'::jsonb)) x), '{}'),
            coalesce(nullif(p_patch->>'status',''), 'approved'), coalesce(nullif(u.country,''), 'SY'), nullif(p_patch->>'contact_person',''))
  on conflict (user_id) do update set name = excluded.name, description = excluded.description, phone = excluded.phone, whatsapp = excluded.whatsapp, email = excluded.email,
    website = excluded.website, address = excluded.address, gov_names = excluded.gov_names, area_names = excluded.area_names, specialties = excluded.specialties,
    contact_person = excluded.contact_person, status = coalesce(nullif(p_patch->>'status',''), agencies.status), updated_at = now()
  returning * into r;
  update users set account_type = 'agency' where id = u.id and account_type <> 'agency';
  return row_to_json(r);
end $function$;

-- bk_admin_agency_set
CREATE OR REPLACE FUNCTION public.bk_admin_agency_set(p_token text, p_id bigint, p_status text DEFAULT NULL::text, p_verified boolean DEFAULT NULL::boolean, p_intake boolean DEFAULT NULL::boolean, p_trusted boolean DEFAULT NULL::boolean, p_intake_phone text DEFAULT NULL::text, p_unpair boolean DEFAULT NULL::boolean, p_newcode boolean DEFAULT NULL::boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; a agencies;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_agency_set', (select coalesce(country_code,'SY') from agencies where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from agencies where id=p_id));
  select * into a from agencies where id = p_id;
  if a.id is null then return json_build_object('error','noagency'); end if;
  if not bk_admin_country_ok(uid, a.country_code) then raise exception 'unauthorised'; end if;
  update agencies set status = coalesce(p_status, status), verified = coalesce(p_verified, verified),
         intake_enabled = coalesce(p_intake, intake_enabled), intake_trusted = coalesce(p_trusted, intake_trusted),
         intake_phone = case when p_intake_phone is null then intake_phone when trim(p_intake_phone) = '' then null else bk_intake_norm_phone(p_intake_phone) end,
         intake_telegram = case when coalesce(p_unpair,false) then null else intake_telegram end,
         intake_telegram_name = case when coalesce(p_unpair,false) then null else intake_telegram_name end,
         intake_code = case when coalesce(p_newcode,false) or (coalesce(p_intake,false) and intake_code is null) then upper(substr(encode(gen_random_bytes(6),'hex'),1,8)) else intake_code end,
         updated_at = now()
   where id = p_id returning * into a;
  if p_status = 'approved' then update users set card_logo = true where id = a.user_id; end if;
  if coalesce(p_newcode,false) then insert into intake_log (chat_id, event, detail) values (null, 'agency_new_code', jsonb_build_object('agency_id', a.id, 'by', uid)); end if;
  return json_build_object('ok', true, 'intake_enabled', a.intake_enabled, 'intake_trusted', a.intake_trusted, 'intake_code', a.intake_code);
end $function$;

-- bk_admin_analytics
CREATE OR REPLACE FUNCTION public.bk_admin_analytics(p_token text, p_days integer DEFAULT 7, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; d int; t0 timestamptz; t1 timestamptz; tp0 timestamptz; hourly boolean; sc text; al text[]; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_analytics', null, false, left(coalesce(p_days::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid); d := greatest(1, least(coalesce(p_days,7), 3650)); t1 := now(); t0 := now() - (d || ' days')::interval; tp0 := t0 - (d || ' days')::interval; hourly := d <= 2; return json_build_object( 'days', d, 'from', t0, 'to', t1, 'bucket', case when hourly then 'hour' else 'day' end, 'scope', sc, 'kpi', json_build_object( 'views', (select count(*) from page_views where bk_scope_ok(site_country,sc,al) and created_at >= t0), 'views_prev', (select count(*) from page_views where bk_scope_ok(site_country,sc,al) and created_at >= tp0 and created_at < t0), 'visitors', (select count(distinct coalesce(visitor_id, user_id::text, country||path)) from page_views where bk_scope_ok(site_country,sc,al) and created_at >= t0), 'visitors_prev',(select count(distinct coalesce(visitor_id, user_id::text, country||path)) from page_views where bk_scope_ok(site_country,sc,al) and created_at >= tp0 and created_at < t0), 'new_users', (select count(*) from users where role<>'admin' and bk_scope_ok(country,sc,al) and created_at >= t0), 'new_users_prev',(select count(*) from users where role<>'admin' and bk_scope_ok(country,sc,al) and created_at >= tp0 and created_at < t0), 'new_listings',(select count(*) from listings where bk_scope_ok(country_code,sc,al) and created_at >= t0), 'new_listings_prev',(select count(*) from listings where bk_scope_ok(country_code,sc,al) and created_at >= tp0 and created_at < t0), 'contacts', (select count(*) from contact_events c join listings l on l.id=c.listing_id where bk_scope_ok(l.country_code,sc,al) and c.created_at >= t0), 'contacts_prev',(select count(*) from contact_events c join listings l on l.id=c.listing_id where bk_scope_ok(l.country_code,sc,al) and c.created_at >= tp0 and c.created_at < t0), 'listing_views',(select count(*) from page_views where bk_scope_ok(site_country,sc,al) and created_at >= t0 and listing_id is not null), 'listing_views_prev',(select count(*) from page_views where bk_scope_ok(site_country,sc,al) and created_at >= tp0 and created_at < t0 and listing_id is not null), 'ad_clicks', (select count(*) from ad_events a join ad_slots s on s.id=a.slot_id where bk_scope_ok(s.country_code,sc,al) and a.kind='click' and a.created_at >= t0), 'ad_clicks_prev',(select count(*) from ad_events a join ad_slots s on s.id=a.slot_id where bk_scope_ok(s.country_code,sc,al) and a.kind='click' and a.created_at >= tp0 and a.created_at < t0), 'ad_views', (select count(*) from ad_events a join ad_slots s on s.id=a.slot_id where bk_scope_ok(s.country_code,sc,al) and a.kind='view' and a.created_at >= t0), 'saves', (select count(*) from saved_listings sv join listings l on l.id=sv.listing_id where bk_scope_ok(l.country_code,sc,al) and sv.created_at >= t0), 'active_users',(select count(*) from users where role<>'admin' and bk_scope_ok(country,sc,al) and last_seen_at >= t0), 'online_now', (select count(*) from online_presence op join users ou on ou.id = op.user_id where op.last_seen > now() - interval '5 minutes' and bk_scope_ok(ou.country,sc,al)) ), 'series', coalesce((select json_agg(x order by x.b) from ( select b, (select count(*) from page_views v where bk_scope_ok(v.site_country,sc,al) and v.created_at >= b and v.created_at < b + step) as views, (select count(distinct coalesce(visitor_id, user_id::text, country||path)) from page_views v where bk_scope_ok(v.site_country,sc,al) and v.created_at >= b and v.created_at < b + step) as visitors, (select count(*) from users u where u.role<>'admin' and bk_scope_ok(u.country,sc,al) and u.created_at >= b and u.created_at < b + step) as new_users, (select count(*) from listings l where bk_scope_ok(l.country_code,sc,al) and l.created_at >= b and l.created_at < b + step) as new_listings, (select count(*) from contact_events c join listings l on l.id=c.listing_id where bk_scope_ok(l.country_code,sc,al) and c.created_at >= b and c.created_at < b + step) as contacts, (select count(*) from ad_events a join ad_slots s on s.id=a.slot_id where bk_scope_ok(s.country_code,sc,al) and a.kind='click' and a.created_at >= b and a.created_at < b + step) as ad_clicks from (select case when hourly then date_trunc('hour', g) else date_trunc('day', g) end as b, case when hourly then interval '1 hour' else interval '1 day' end as step from generate_series(case when hourly then date_trunc('hour', t0) else date_trunc('day', t0) end, t1, case when hourly then interval '1 hour' else interval '1 day' end) g) s ) x), '[]'::json), 'top_listings', coalesce((select json_agg(x order by x.views desc) from ( select l.id, l.ref, l.price_usd, l.deal, l.property_type, l.status, l.country_code, g.name_ar as gov, a.name_ar as area, (select count(*) from page_views v where v.listing_id = l.id and v.created_at >= t0) as views, (select count(*) from contact_events c where c.listing_id = l.id and c.created_at >= t0) as contacts, (select count(*) from saved_listings sv where sv.listing_id = l.id and sv.created_at >= t0) as saves, l.views as views_total from listings l join governorates g on g.id=l.governorate_id left join areas a on a.id=l.area_id where bk_scope_ok(l.country_code,sc,al) order by (select count(*) from page_views v where v.listing_id = l.id and v.created_at >= t0) desc limit 15) x), '[]'::json), 'ads', coalesce((select json_agg(x order by x.clicks desc, x.position) from ( select s.id, s.position, s.label, s.sponsor_name, s.enabled, s.media_type, s.linked_listing_id, s.country_code, case when s.media_type = 'video' then null else s.image_url end as image_url, (select l.ref from listings l where l.id = s.linked_listing_id) as listing_ref, (select count(*) from ad_events a where a.slot_id=s.id and a.kind='view' and a.created_at >= t0) as views, (select count(*) from ad_events a where a.slot_id=s.id and a.kind='click' and a.created_at >= t0) as clicks, coalesce((select json_object_agg(page, n) from (select coalesce(page,'home') page, count(*) n from ad_events a where a.slot_id=s.id and a.kind='click' and a.created_at >= t0 group by 1 order by 2 desc limit 6) p), '{}'::json) as click_pages, coalesce((select json_object_agg(country, n) from (select coalesce(country,'?') country, count(*) n from ad_events a where a.slot_id=s.id and a.kind='click' and a.created_at >= t0 group by 1 order by 2 desc limit 6) c), '{}'::json) as click_countries from ad_slots s where bk_scope_ok(s.country_code,sc,al)) x), '[]'::json), 'pages', coalesce((select json_agg(x order by x.n desc) from (select coalesce(view,'home') view, count(*) n from page_views where bk_scope_ok(site_country,sc,al) and created_at >= t0 group by 1 order by 2 desc limit 12) x), '[]'::json), 'countries', coalesce((select json_agg(x order by x.n desc) from (select coalesce(country,'?') country, count(*) n from page_views where bk_scope_ok(site_country,sc,al) and created_at >= t0 group by 1 order by 2 desc limit 12) x), '[]'::json), 'sites', coalesce((select json_agg(x order by x.n desc) from (select coalesce(site_country,'SY') site, count(*) n from page_views where bk_scope_ok(site_country,sc,al) and created_at >= t0 group by 1 order by 2 desc limit 30) x), '[]'::json), 'devices', coalesce((select json_agg(x order by x.n desc) from (select coalesce(device,'?') device, count(*) n from page_views where bk_scope_ok(site_country,sc,al) and created_at >= t0 group by 1) x), '[]'::json), 'referrers', coalesce((select json_agg(x order by x.n desc) from (select coalesce(nullif(referrer,''),'direct') referrer, count(*) n from page_views where bk_scope_ok(site_country,sc,al) and created_at >= t0 group by 1 order by 2 desc limit 10) x), '[]'::json), 'contact_kinds', coalesce((select json_agg(x order by x.n desc) from (select c.kind, count(*) n from contact_events c join listings l on l.id=c.listing_id where bk_scope_ok(l.country_code,sc,al) and c.created_at >= t0 group by 1) x), '[]'::json), 'users_activity', json_build_object( 'last_24h', (select count(*) from users where role<>'admin' and bk_scope_ok(country,sc,al) and last_seen_at >= now()-interval '1 day'), 'last_7d', (select count(*) from users where role<>'admin' and bk_scope_ok(country,sc,al) and last_seen_at >= now()-interval '7 days'), 'last_30d', (select count(*) from users where role<>'admin' and bk_scope_ok(country,sc,al) and last_seen_at >= now()-interval '30 days'), 'older', (select count(*) from users where role<>'admin' and bk_scope_ok(country,sc,al) and (last_seen_at < now()-interval '30 days' or last_seen_at is null)), 'total', (select count(*) from users where role<>'admin' and bk_scope_ok(country,sc,al))), 'listings_status', coalesce((select json_object_agg(status, n) from (select status, count(*) n from listings where bk_scope_ok(country_code,sc,al) group by 1) x), '{}'::json), 'health', json_build_object( 'pending', (select count(*) from listings where bk_scope_ok(country_code,sc,al) and status='pending'), 'open_reports', (select count(*) from listing_reports r left join listings l on l.id=r.listing_id where not r.resolved and ((l.id is null and sc is null) or bk_scope_ok(l.country_code,sc,al))), 'open_feedback', (select count(*) from feedback where not handled and ((country_code is null and sc is null) or bk_scope_ok(country_code,sc,al))), 'last_view_at', (select max(created_at) from page_views where bk_scope_ok(site_country,sc,al)), 'storage_mb', (select round(coalesce(sum((metadata->>'size')::bigint),0)/1048576.0,1) from storage.objects where bucket_id='photos'), 'expiring_featured', (select count(*) from listings where bk_scope_ok(country_code,sc,al) and is_featured and featured_until between now() and now()+interval '3 days'), 'listings_without_photos', (select count(*) from listings l where bk_scope_ok(l.country_code,sc,al) and l.status='live' and not exists (select 1 from listing_photos p where p.listing_id=l.id)), 'blocked_users', (select count(*) from users where blocked and bk_scope_ok(country,sc,al)) ) ); end $function$;

-- bk_admin_area_delete
CREATE OR REPLACE FUNCTION public.bk_admin_area_delete(p_token text, p_id integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare uid uuid; n int; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_area_delete', (select g.country_code from areas a join governorates g on g.id=a.governorate_id where a.id=p_id), true, left(coalesce(p_id::text,''),300), (select g.country_code from areas a join governorates g on g.id=a.governorate_id where a.id=p_id)); perform bk_admin_guard(uid, (select g.country_code from areas a join governorates g on g.id = a.governorate_id where a.id = p_id)); select count(*) into n from listings l where l.area_id = p_id; if n > 0 then raise exception 'has_listings'; end if; delete from areas where id = p_id; return json_build_object('ok', true); end $function$;

-- bk_admin_area_save
CREATE OR REPLACE FUNCTION public.bk_admin_area_save(p_token text, p_row jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare uid uuid; v_id int; v_slug text; r areas; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_area_save', (select country_code from governorates where id=coalesce(nullif(p_row->>'governorate_id','')::bigint,(select governorate_id from areas where id=nullif(p_row->>'id','')::bigint))), true, left(coalesce(p_row::text,''),300), (select country_code from governorates where id=coalesce(nullif(p_row->>'governorate_id','')::bigint,(select governorate_id from areas where id=nullif(p_row->>'id','')::bigint)))); perform bk_admin_guard(uid, (select country_code from governorates where id = (p_row->>'governorate_id')::int)); v_id := nullif(p_row->>'id','')::int; v_slug := nullif(trim(coalesce(p_row->>'slug','')),''); if v_slug is null then v_slug := ar_slug(p_row->>'name_ar'); end if; v_slug := lower(regexp_replace(regexp_replace(v_slug, '[^a-z0-9-]+', '-', 'g'), '(^-+|-+$)', '', 'g')); if v_slug is null or v_slug = '' then v_slug := 'area'; end if; if exists (select 1 from areas a where a.governorate_id = (p_row->>'governorate_id')::int and a.slug = v_slug and (v_id is null or a.id <> v_id)) then raise exception 'slug_taken'; end if; if v_id is null then insert into areas (governorate_id, name_ar, name_en, slug, kind, enabled, sort_order, lat, lng) values ((p_row->>'governorate_id')::int, trim(p_row->>'name_ar'), nullif(trim(coalesce(p_row->>'name_en','')),''), v_slug, coalesce(nullif(p_row->>'kind',''),'area'), coalesce((p_row->>'enabled')::boolean, true), coalesce((p_row->>'sort_order')::int, 100), nullif(p_row->>'lat','')::numeric, nullif(p_row->>'lng','')::numeric) returning * into r; else update areas set governorate_id = coalesce((p_row->>'governorate_id')::int, governorate_id), name_ar = coalesce(nullif(trim(p_row->>'name_ar'),''), name_ar), name_en = nullif(trim(coalesce(p_row->>'name_en','')),''), slug = v_slug, kind = coalesce(nullif(p_row->>'kind',''), kind), enabled = coalesce((p_row->>'enabled')::boolean, enabled), sort_order = coalesce((p_row->>'sort_order')::int, sort_order), lat = nullif(p_row->>'lat','')::numeric, lng = nullif(p_row->>'lng','')::numeric where id = v_id returning * into r; end if; return row_to_json(r); end $function$;

-- bk_admin_area_set_coords
CREATE OR REPLACE FUNCTION public.bk_admin_area_set_coords(p_token text, p_area_id integer, p_lat numeric, p_lng numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_area_set_coords', (select g.country_code from areas a join governorates g on g.id=a.governorate_id where a.id=p_area_id), true, left(coalesce(p_area_id::text,''),300), (select g.country_code from areas a join governorates g on g.id=a.governorate_id where a.id=p_area_id)); if uid is null then raise exception 'not admin'; end if;
  update areas set lat=p_lat, lng=p_lng where id=p_area_id;
  return true;
end $function$;

-- bk_admin_area_suggest_apply
CREATE OR REPLACE FUNCTION public.bk_admin_area_suggest_apply(p_token text, p_ids bigint[], p_action text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid; s area_suggestions; n_ok int := 0; n_skip int := 0; v_slug text; new_id int; i int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_area_suggest_apply', null, true, left(coalesce(p_ids::text,''),300), null);
  if p_action not in ('approve','reject') then return json_build_object('error','badaction'); end if;
  for s in select * from area_suggestions where id = any(p_ids) and status = 'pending' loop
    perform bk_admin_guard(uid, (select country_code from governorates where id = s.governorate_id));
    if p_action = 'reject' then
      update area_suggestions set status = 'rejected', updated_at = now() where id = s.id; n_ok := n_ok + 1; continue;
    end if;
    if s.kind = 'geo' then
      if s.area_id is not null and s.lat is not null then
        update areas set lat = s.lat, lng = s.lng where id = s.area_id;
        update area_suggestions set status = 'approved', updated_at = now() where id = s.id; n_ok := n_ok + 1;
      else update area_suggestions set status = 'rejected', updated_at = now() where id = s.id; n_skip := n_skip + 1; end if;
      continue;
    end if;
    if exists (select 1 from areas a where a.governorate_id = s.governorate_id and bk_area_norm(a.name_ar) = bk_area_norm(s.name_ar)) then
      update area_suggestions set status = 'rejected', updated_at = now() where id = s.id; n_skip := n_skip + 1; continue;
    end if;
    v_slug := lower(regexp_replace(regexp_replace(coalesce(nullif(trim(s.name_en),''), ar_slug(s.name_ar), ''), '[^a-z0-9-]+', '-', 'g'), '(^-+|-+$)', '', 'g'));
    if v_slug is null or v_slug = '' then v_slug := 'area'; end if;
    i := 0;
    while exists (select 1 from areas a where a.governorate_id = s.governorate_id and a.slug = v_slug || case when i > 0 then '-' || i else '' end) loop i := i + 1; end loop;
    if i > 0 then v_slug := v_slug || '-' || i; end if;
    insert into areas (governorate_id, name_ar, name_en, slug, kind, enabled, sort_order, lat, lng)
      values (s.governorate_id, trim(s.name_ar), nullif(trim(coalesce(s.name_en,'')),''), v_slug, case when s.place in ('village','hamlet') then 'village' when s.place = 'town' then 'city' else 'area' end, true, 100, s.lat, s.lng)
      returning id into new_id;
    update area_suggestions set status = 'approved', area_id = new_id, updated_at = now() where id = s.id; n_ok := n_ok + 1;
    -- listings published meanwhile with this place written as the landmark now get the area
    update listings set area_id = new_id where governorate_id = s.governorate_id and area_id is null and landmark is not null and position(bk_area_norm(s.name_ar) in bk_area_norm(landmark)) > 0;
  end loop;
  return json_build_object('ok', true, 'done', n_ok, 'skipped', n_skip);
end $function$;

-- bk_admin_area_suggestions
CREATE OR REPLACE FUNCTION public.bk_admin_area_suggestions(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid; al text[]; cc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_area_suggestions', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); al := bk_admin_allowed(uid);
  cc := nullif(upper(trim(coalesce(p_country,''))),''); if cc = 'ALL' then cc := null; end if;
  if cc is not null and al is not null and not (cc = any(al)) then cc := al[1]; end if;
  return json_build_object(
    'items', (select coalesce(json_agg(json_build_object('id', s.id, 'governorate_id', s.governorate_id, 'name_ar', s.name_ar, 'name_en', s.name_en, 'lat', s.lat, 'lng', s.lng,
                'kind', s.kind, 'area_id', s.area_id, 'area_name', a.name_ar, 'source', s.source, 'place', s.place, 'mentions', s.mentions, 'sample', s.sample, 'created_at', s.created_at)
              order by s.governorate_id, s.kind, s.mentions desc, s.name_ar), '[]'::json)
       from area_suggestions s join governorates g on g.id = s.governorate_id left join areas a on a.id = s.area_id
       where s.status = 'pending' and (cc is null or g.country_code = cc) and (al is null or g.country_code = any(al))),
    'counts', (select coalesce(json_object_agg(governorate_id, n), '{}'::json) from (
       select s.governorate_id, count(*) n from area_suggestions s join governorates g on g.id = s.governorate_id
        where s.status = 'pending' and (cc is null or g.country_code = cc) and (al is null or g.country_code = any(al)) group by s.governorate_id) x));
end $function$;

-- bk_admin_areas_map
CREATE OR REPLACE FUNCTION public.bk_admin_areas_map(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo','listings_view']::text[], 'bk_admin_areas_map', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x order by x.live desc, x.area) from (
    select a.id, a.name_ar as area, g.name_ar as gov, a.lat, a.lng, g.lat as gov_lat, g.lng as gov_lng,
           count(*) filter (where l.status='live') as live,
           count(*) filter (where l.status='live' and l.lat is not null and l.lng is not null) as pinned
      from listings l
      join areas a on a.id = l.area_id
      join governorates g on g.id = a.governorate_id
     where bk_scope_ok(l.country_code, sc, al)
     group by a.id, a.name_ar, g.name_ar, a.lat, a.lng, g.lat, g.lng
    ) x), '[]'::json);
end $function$;

-- bk_admin_backup
CREATE OR REPLACE FUNCTION public.bk_admin_backup(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_data jsonb;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_backup', null, true, null, null);
  select jsonb_build_object(
    'exported_at', now(),
    'listings', (select coalesce(jsonb_agg(l), '[]'::jsonb) from listings l),
    'listing_photos', (select coalesce(jsonb_agg(p), '[]'::jsonb) from listing_photos p),
    'site_content', (select coalesce(jsonb_agg(s), '[]'::jsonb) from site_content s),
    'ad_slots', (select coalesce(jsonb_agg(a), '[]'::jsonb) from ad_slots a)
  ) into v_data;
  return v_data::json;
end $function$;

-- bk_admin_block_user
CREATE OR REPLACE FUNCTION public.bk_admin_block_user(p_token text, p_user uuid, p_blocked boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_block_user', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user)); update users set blocked = p_blocked where id = p_user and role <> 'admin'; return json_build_object('ok',true); end $function$;

-- bk_admin_campaign_audience_count
CREATE OR REPLACE FUNCTION public.bk_admin_campaign_audience_count(p_token text, p_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; row_cc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_campaign_audience_count', (select coalesce(country_code,'SY') from campaigns where id=p_id), false, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from campaigns where id=p_id));
  select country_code into row_cc from campaigns where id = p_id;
  if row_cc is null then return json_build_object('error', 'notfound'); end if;
  perform bk_admin_guard(uid, row_cc);
  return coalesce((select json_object_agg(channel, n) from (
    select channel, count(*) as n from bk_campaign_audience(p_id) group by channel) x), '{}'::json);
end $function$;

-- bk_admin_campaign_delete
CREATE OR REPLACE FUNCTION public.bk_admin_campaign_delete(p_token text, p_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; row_cc text; row_status text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_campaign_delete', (select coalesce(country_code,'SY') from campaigns where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from campaigns where id=p_id));
  select country_code, status into row_cc, row_status from campaigns where id = p_id;
  if row_cc is null then return json_build_object('ok', true); end if;
  if row_status not in ('draft', 'scheduled') then return json_build_object('error', 'not_deletable'); end if;
  perform bk_admin_guard(uid, row_cc);
  delete from campaigns where id = p_id;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_campaign_save
CREATE OR REPLACE FUNCTION public.bk_admin_campaign_save(p_token text, p_id uuid, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; row_cc text; row_status text; new_cc text; c campaigns;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_campaign_save', (case when p_id is null then nullif(upper(p_patch->>'country_code'),'') else (select coalesce(country_code,'SY') from campaigns where id=p_id) end), true, left(coalesce(p_id::text,''),300), (case when p_id is null then nullif(upper(p_patch->>'country_code'),'') else (select coalesce(country_code,'SY') from campaigns where id=p_id) end));
  new_cc := nullif(upper(p_patch->>'country_code'), '');
  perform bk_admin_guard(uid, coalesce(new_cc, 'SY'));
  if p_id is not null then
    select country_code, status into row_cc, row_status from campaigns where id = p_id;
    if row_cc is null then return json_build_object('error', 'notfound'); end if;
    if row_status not in ('draft', 'scheduled') then
      return json_build_object('error', 'not_editable');
    end if;
    perform bk_admin_guard(uid, row_cc);
    update campaigns set
      title = coalesce(p_patch->>'title', title),
      channels = case when p_patch ? 'channels' then (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(p_patch->'channels')) else channels end,
      subject = coalesce(p_patch->>'subject', subject),
      body_ar = coalesce(p_patch->>'body_ar', body_ar),
      body_en = coalesce(p_patch->>'body_en', body_en),
      country_code = coalesce(new_cc, country_code),
      governorate_id = case when p_patch ? 'governorate_id' then (p_patch->>'governorate_id')::int else governorate_id end,
      area_id = case when p_patch ? 'area_id' then (p_patch->>'area_id')::int else area_id end,
      tag_filter = case when p_patch ? 'tag_filter' then (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(p_patch->'tag_filter')) else tag_filter end,
      consent_required = coalesce((p_patch->>'consent_required')::boolean, consent_required),
      scheduled_at = case when p_patch ? 'scheduled_at' then (p_patch->>'scheduled_at')::timestamptz else scheduled_at end,
      status = case when p_patch ? 'scheduled_at' and (p_patch->>'scheduled_at') is not null then 'scheduled' else status end
    where id = p_id returning * into c;
  else
    insert into campaigns (title, kind, channels, subject, body_ar, body_en, country_code, governorate_id, area_id, tag_filter, consent_required, created_by)
      values (coalesce(p_patch->>'title', 'بدون عنوان'), 'manual',
        (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(coalesce(p_patch->'channels', '[]'::jsonb))),
        p_patch->>'subject', p_patch->>'body_ar', p_patch->>'body_en', coalesce(new_cc, 'SY'),
        (p_patch->>'governorate_id')::int, (p_patch->>'area_id')::int,
        (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(coalesce(p_patch->'tag_filter', '[]'::jsonb))),
        coalesce((p_patch->>'consent_required')::boolean, true), uid)
      returning * into c;
  end if;
  return row_to_json(c);
end $function$;

-- bk_admin_campaign_send
CREATE OR REPLACE FUNCTION public.bk_admin_campaign_send(p_token text, p_id uuid, p_test boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; row_cc text; row_status text; n int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_campaign_send', (select coalesce(country_code,'SY') from campaigns where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from campaigns where id=p_id));
  select country_code, status into row_cc, row_status from campaigns where id = p_id;
  if row_cc is null then return json_build_object('error', 'notfound'); end if;
  if row_status not in ('draft', 'scheduled') then return json_build_object('error', 'already_sent'); end if;
  perform bk_admin_guard(uid, row_cc);
  if p_test then
    insert into campaign_sends (campaign_id, contact_id, channel)
    select p_id, c.id, ch.channel from contacts c
      cross join unnest((select channels from campaigns where id = p_id)) as ch(channel)
     where c.user_id = uid
       and ((ch.channel = 'telegram' and c.tg_chat_id is not null)
         or (ch.channel = 'whatsapp' and c.phone is not null)
         or (ch.channel = 'email' and c.email is not null));
    get diagnostics n = row_count;
    if n = 0 then return json_build_object('error', 'no_test_contact'); end if;
    return json_build_object('ok', true, 'queued', n, 'test', true);
  end if;
  insert into campaign_sends (campaign_id, contact_id, channel)
    select p_id, contact_id, channel from bk_campaign_audience(p_id);
  get diagnostics n = row_count;
  update campaigns set status = 'sending', sent_at = now() where id = p_id;
  return json_build_object('ok', true, 'queued', n);
end $function$;

-- bk_admin_campaign_stats
CREATE OR REPLACE FUNCTION public.bk_admin_campaign_stats(p_token text, p_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; row_cc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_campaign_stats', (select coalesce(country_code,'SY') from campaigns where id=p_id), false, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from campaigns where id=p_id));
  select country_code into row_cc from campaigns where id = p_id;
  if row_cc is null then return json_build_object('error', 'notfound'); end if;
  perform bk_admin_guard(uid, row_cc);
  return coalesce((select json_object_agg(status, n) from (
    select status, count(*) as n from campaign_sends where campaign_id = p_id group by status) x), '{}'::json);
end $function$;

-- bk_admin_campaigns
CREATE OR REPLACE FUNCTION public.bk_admin_campaigns(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_campaigns', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by x.created_at desc) from (
    select * from campaigns c where bk_scope_ok(c.country_code, sc, al) limit 500) x), '[]'::json);
end $function$;

-- bk_admin_card_logos
CREATE OR REPLACE FUNCTION public.bk_admin_card_logos(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_view','listings_view']::text[], 'bk_admin_card_logos', null, false, null, null);
  return coalesce((select json_agg(id) from users where card_logo), '[]'::json);
end $function$;

-- bk_admin_change_own_password
CREATE OR REPLACE FUNCTION public.bk_admin_change_own_password(p_token text, p_old text, p_new text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; u users;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_change_own_password', null, true, null, null);
  select * into u from users where id = uid;
  if u.pass_hash is null or u.pass_hash <> crypt(p_old, u.pass_hash) then
    return json_build_object('error','badpass');
  end if;
  if length(p_new) < 6 then raise exception 'password too short'; end if;
  update users set pass_hash = crypt(encode(digest('balkoun:'||p_new,'sha256'),'hex'), gen_salt('bf'))
  where id = uid;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_clear_avatar
CREATE OR REPLACE FUNCTION public.bk_admin_clear_avatar(p_token text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_clear_avatar', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user)); update users set avatar_url = null where id = p_user; return json_build_object('ok', true); end $function$;

-- bk_admin_clear_bio
CREATE OR REPLACE FUNCTION public.bk_admin_clear_bio(p_token text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_clear_bio', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user)); update users set bio = null where id = p_user; return json_build_object('ok', true); end $function$;

-- bk_admin_contact_channels
CREATE OR REPLACE FUNCTION public.bk_admin_contact_channels(p_token text, p_contact_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; c contacts; utg text;
begin
  begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns','users_view']::text[], 'bk_admin_contact_channels', coalesce((select coalesce(country_code,'SY') from contacts where id=p_contact_id),(select coalesce(country,'SY') from users where id=p_user_id)), false, left(coalesce(p_contact_id::text,''),300), coalesce((select coalesce(country_code,'SY') from contacts where id=p_contact_id),(select coalesce(country,'SY') from users where id=p_user_id))); exception when others then uid := null; end;
  if uid is null then return json_build_object('error','unauthorised'); end if;
  select * into c from contacts where (p_contact_id is not null and id = p_contact_id) or (p_user_id is not null and user_id = p_user_id) order by created_at limit 1;
  if c.id is null then return json_build_object('error','nocontact'); end if;
  if c.tg_chat_id is null and c.user_id is not null then
    select tg_chat_id into utg from users where id = c.user_id;
    if utg is not null then update contacts set tg_chat_id = utg, updated_at = now() where id = c.id; c.tg_chat_id := utg; end if;
  end if;
  return json_build_object('id', c.id, 'name', c.name, 'phone', c.phone, 'email', c.email, 'tg', c.tg_chat_id is not null,
    'wa_consent', c.wa_consent, 'tg_consent', c.tg_consent, 'email_consent', c.email_consent);
end $function$;

-- bk_admin_contact_delete
CREATE OR REPLACE FUNCTION public.bk_admin_contact_delete(p_token text, p_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; row_cc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_contact_delete', (select coalesce(country_code,'SY') from contacts where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from contacts where id=p_id));
  select country_code into row_cc from contacts where id = p_id;
  if row_cc is null then return json_build_object('ok', true); end if;
  perform bk_admin_guard(uid, row_cc);
  delete from contacts where id = p_id;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_contact_save
CREATE OR REPLACE FUNCTION public.bk_admin_contact_save(p_token text, p_id uuid, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; row_cc text; new_cc text; c contacts;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_contact_save', (case when p_id is null then nullif(upper(p_patch->>'country_code'),'') else (select coalesce(country_code,'SY') from contacts where id=p_id) end), true, left(coalesce(p_id::text,''),300), (case when p_id is null then nullif(upper(p_patch->>'country_code'),'') else (select coalesce(country_code,'SY') from contacts where id=p_id) end));
  new_cc := coalesce(upper(p_patch->>'country_code'), 'SY');
  if p_id is not null then
    select country_code into row_cc from contacts where id = p_id;
    if row_cc is null then return json_build_object('error', 'notfound'); end if;
    perform bk_admin_guard(uid, row_cc); perform bk_admin_guard(uid, new_cc);
    update contacts set
      phone = nullif(trim(coalesce(p_patch->>'phone', phone)), ''),
      email = nullif(lower(trim(coalesce(p_patch->>'email', email))), ''),
      name = coalesce(p_patch->>'name', name),
      country_code = new_cc,
      governorate_id = case when p_patch ? 'governorate_id' then (p_patch->>'governorate_id')::int else governorate_id end,
      area_id = case when p_patch ? 'area_id' then (p_patch->>'area_id')::int else area_id end,
      city_text = coalesce(p_patch->>'city_text', city_text),
      tags = case when p_patch ? 'tags' then (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(p_patch->'tags')) else tags end,
      wa_consent = coalesce(p_patch->>'wa_consent', wa_consent),
      tg_consent = coalesce(p_patch->>'tg_consent', tg_consent),
      email_consent = coalesce(p_patch->>'email_consent', email_consent),
      notes = coalesce(p_patch->>'notes', notes),
      updated_at = now()
    where id = p_id returning * into c;
  else
    perform bk_admin_guard(uid, new_cc);
    insert into contacts (phone, email, name, country_code, governorate_id, area_id, city_text, tags, source,
        wa_consent, tg_consent, email_consent, notes)
      values (nullif(trim(p_patch->>'phone'), ''), nullif(lower(trim(p_patch->>'email')), ''), p_patch->>'name', new_cc,
        (p_patch->>'governorate_id')::int, (p_patch->>'area_id')::int, p_patch->>'city_text',
        (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(coalesce(p_patch->'tags', '[]'::jsonb))),
        'manual', coalesce(p_patch->>'wa_consent', 'pending'), coalesce(p_patch->>'tg_consent', 'pending'),
        coalesce(p_patch->>'email_consent', 'pending'), p_patch->>'notes')
      returning * into c;
  end if;
  return row_to_json(c);
exception when check_violation then return json_build_object('error', 'need_phone_or_email');
end $function$;

-- bk_admin_contacts
CREATE OR REPLACE FUNCTION public.bk_admin_contacts(p_token text, p_country text DEFAULT NULL::text, p_q text DEFAULT NULL::text, p_consent text DEFAULT NULL::text, p_source text DEFAULT NULL::text, p_tag text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_contacts', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by x.created_at desc) from (
    select c.* from contacts c
     where bk_scope_ok(c.country_code, sc, al)
       and (p_q is null or c.phone ilike '%'||p_q||'%' or c.email ilike '%'||p_q||'%' or c.name ilike '%'||p_q||'%')
       and (p_consent is null or c.wa_consent = p_consent or c.tg_consent = p_consent or c.email_consent = p_consent)
       and (p_source is null or c.source = p_source)
       and (p_tag is null or p_tag = any(c.tags))
     limit 2000) x), '[]'::json);
end $function$;

-- bk_admin_contacts_import
CREATE OR REPLACE FUNCTION public.bk_admin_contacts_import(p_token text, p_country text, p_rows jsonb, p_assume_consent boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; cc text; r jsonb; n_ins int := 0; n_skip int := 0;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_contacts_import', nullif(upper(p_country),''), true, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); cc := coalesce(upper(p_country), 'SY'); perform bk_admin_guard(uid, cc);
  if jsonb_array_length(p_rows) > 5000 then raise exception 'too many rows (max 5000 per import)'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(trim(r->>'phone'), '') = '' and coalesce(trim(r->>'email'), '') = '' then
      n_skip := n_skip + 1; continue;
    end if;
    insert into contacts (phone, email, name, country_code, city_text, tags, source, wa_consent, tg_consent, email_consent)
      values (nullif(trim(r->>'phone'), ''), nullif(lower(trim(r->>'email')), ''), r->>'name', cc, r->>'city_text',
        (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(coalesce(r->'tags', '[]'::jsonb))),
        'import',
        case when p_assume_consent and coalesce(trim(r->>'phone'),'')<>'' then 'subscribed' else 'pending' end,
        'pending',
        case when p_assume_consent and coalesce(trim(r->>'email'),'')<>'' then 'subscribed' else 'pending' end);
    n_ins := n_ins + 1;
  end loop;
  return json_build_object('ok', true, 'inserted', n_ins, 'skipped', n_skip);
end $function$;

-- bk_admin_countries
CREATE OR REPLACE FUNCTION public.bk_admin_countries(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_countries', null, false, null, null); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(json_build_object(
    'code',c.code,'name_ar',c.name_ar,'name_en',c.name_en,'name_de',c.name_de,'name_fr',c.name_fr,'name_tr',c.name_tr,
    'enabled',c.enabled,'is_default',c.is_default,'currencies',c.currencies,'rates',c.rates,'phone_code',c.phone_code,
    'tz',c.tz,'lat',c.lat,'lng',c.lng,'zoom',c.zoom,'sort_order',c.sort_order,'languages',c.languages,'notes',c.notes,'types',c.types,
    'govs',(select count(*) from governorates g where g.country_code=c.code),
    'areas',(select count(*) from areas a join governorates g on g.id=a.governorate_id where g.country_code=c.code),
    'listings',(select count(*) from listings l where l.country_code=c.code and l.status='live'),
    'wanted',(select count(*) from wanted w where w.country_code=c.code and w.status='open'),
    'agencies',(select count(*) from agencies a where a.country_code=c.code),
    'ads',(select count(*) from ad_slots a where a.country_code=c.code and a.enabled),
    'featured',(select count(*) from listings l where l.country_code=c.code and l.status='live' and l.is_featured),
    'bg',(select s.hero_bg_type from site_content s where s.country_code=c.code limit 1),
    'bg_photo',(select s.hero_bg_photo_url from site_content s where s.country_code=c.code limit 1),
    'banners',(select case when s.banner_items is null or s.banner_items='' then 0 else coalesce(jsonb_array_length(s.banner_items::jsonb),0) end from site_content s where s.country_code=c.code limit 1),
    'banner_on',(select s.banner_enabled from site_content s where s.country_code=c.code limit 1),
    'deeds',(select coalesce(json_agg(json_build_object('code',d.code,'ar',d.name_ar,'en',d.name_en,'de',d.name_de,'fr',d.name_fr,'strong',d.is_strong,'enabled',d.enabled) order by d.sort_order),'[]'::json) from deed_types d where d.country_code=c.code),
    'verify',coalesce((select (select jsonb_object_agg(key,value) from jsonb_each(coalesce(extras,'{}'::jsonb)) where key in ('verify_telegram_on','verify_wa_code_on','verify_email_on')) from site_content s where s.country_code=c.code), '{}'::jsonb),
    'campaign_cfg',coalesce((select (select jsonb_object_agg(key,value) from jsonb_each(coalesce(extras,'{}'::jsonb)) where key in ('auto_notify_new_listing_on','auto_notify_ch_telegram','auto_notify_ch_whatsapp','auto_notify_ch_email')) from site_content s where s.country_code=c.code), '{}'::jsonb),
    'contacts',(select count(*) from contacts ct where ct.country_code=c.code)
  ) order by c.sort_order) from countries c where al is null or c.code = any(al)), '[]'::json);
end $function$;

-- bk_admin_country_set
CREATE OR REPLACE FUNCTION public.bk_admin_country_set(p_token text, p_code text, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid; r countries;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_country_set', null, true, left(coalesce(p_code::text,''),300), null);
  if not (select is_super_admin from users where id=uid) then raise exception 'super admin only'; end if;
  if (p_patch->>'is_default')::boolean is true then update countries set is_default=false where code<>p_code; end if;
  update countries set
    name_ar=coalesce(p_patch->>'name_ar',name_ar), name_en=coalesce(p_patch->>'name_en',name_en), name_de=coalesce(p_patch->>'name_de',name_de), name_fr=coalesce(p_patch->>'name_fr',name_fr), name_tr=coalesce(p_patch->>'name_tr',name_tr),
    enabled=coalesce((p_patch->>'enabled')::boolean,enabled), is_default=coalesce((p_patch->>'is_default')::boolean,is_default),
    currencies=coalesce((select array_agg(x) from jsonb_array_elements_text(p_patch->'currencies') x),currencies),
    rates=coalesce(p_patch->'rates',rates), phone_code=coalesce(p_patch->>'phone_code',phone_code),
    tz=coalesce((select array_agg(x) from jsonb_array_elements_text(p_patch->'tz') x),tz),
    lat=coalesce((p_patch->>'lat')::numeric,lat), lng=coalesce((p_patch->>'lng')::numeric,lng), zoom=coalesce((p_patch->>'zoom')::int,zoom),
    sort_order=coalesce((p_patch->>'sort_order')::int,sort_order), languages=coalesce((select array_agg(x) from jsonb_array_elements_text(p_patch->'languages') x),languages),
    types=case when p_patch ? 'types' then p_patch->'types' else types end,
    notes=coalesce(p_patch->>'notes',notes), updated_at=now()
  where code=p_code returning * into r;
  if r.code is null then raise exception 'unknown country'; end if;
  if not exists (select 1 from countries where is_default) then update countries set is_default=true where code='SY'; end if;
  return row_to_json(r);
end $function$;

-- bk_admin_create_admin
CREATE OR REPLACE FUNCTION public.bk_admin_create_admin(p_token text, p_phone text, p_name text, p_family text, p_pass text, p_permissions text[], p_countries text[] DEFAULT NULL::text[])
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_super boolean; new_id uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_create_admin', null, true, left(coalesce(p_phone::text,''),300), null);
  select is_super_admin into v_super from users where id = uid;
  if not coalesce(v_super,false) then raise exception 'super admin only'; end if;
  if length(p_pass) < 6 then raise exception 'password too short'; end if;
  if exists (select 1 from users where phone = p_phone) then raise exception 'phone already registered'; end if;
  insert into users (phone, name, family_name, role, permissions, pass_hash, phone_verified, admin_countries)
  values (p_phone, p_name, p_family, 'admin', coalesce(p_permissions,'{}'), crypt(encode(digest('balkoun:'||p_pass,'sha256'),'hex'), gen_salt('bf')), true,
          case when p_countries is null or cardinality(p_countries)=0 then null else (select array_agg(upper(c)) from unnest(p_countries) c) end)
  returning id into new_id;
  return json_build_object('ok', true, 'id', new_id);
end $function$;

-- bk_admin_create_member
CREATE OR REPLACE FUNCTION public.bk_admin_create_member(p_token text, p_phone text, p_name text, p_family text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_country text DEFAULT 'SY'::text, p_hash text DEFAULT NULL::text, p_agency_name text DEFAULT NULL::text, p_password_plain text DEFAULT NULL::text, p_send boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; u users; ph text; cc text; ag_id bigint; c_id uuid; msg text; nm text; contact_ph text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_create_member', nullif(upper(p_country),''), true, left(coalesce(p_phone::text,''),300), nullif(upper(p_country),''));
  cc := upper(coalesce(nullif(trim(p_country), ''), 'SY'));
  perform bk_admin_guard(uid, cc);
  ph := '+' || regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  if length(ph) < 9 then return json_build_object('error', 'badphone'); end if;
  if coalesce(trim(p_name), '') = '' then return json_build_object('error', 'noname'); end if;
  if length(coalesce(p_hash, '')) < 32 then return json_build_object('error', 'badhash'); end if;
  if exists (select 1 from users where phone = ph) then return json_build_object('error', 'exists'); end if;
  if p_email is not null and trim(p_email) <> '' and exists (select 1 from users where lower(email) = lower(trim(p_email))) then return json_build_object('error', 'emailexists'); end if;
  insert into users (phone, name, family_name, pass_hash, phone_verified, lang, country, email, email_verified)
    values (ph, left(trim(p_name), 60), left(trim(coalesce(p_family, '')), 60), crypt(p_hash, gen_salt('bf')), true, 'ar', cc, nullif(trim(coalesce(p_email, '')), ''), false)
    returning * into u;
  if coalesce(trim(p_agency_name), '') <> '' then
    insert into agencies (user_id, name, phone, whatsapp, status, country_code) values (u.id, left(trim(p_agency_name), 120), ph, ph, 'approved', cc) returning id into ag_id;
  end if;
  insert into notifications (user_id, type, title, body, link, is_read) values (u.id, 'system', 'welcome', null, '/#/post', false);
  select id into c_id from contacts where user_id = u.id order by created_at limit 1;
  if c_id is not null then
    update contacts set tags = array_append(coalesce(tags, '{}'), 'admin_added'), notes = coalesce(nullif(notes, ''), 'أُضيف من لوحة الإدارة'), updated_at = now() where id = c_id;
  end if;
  nm := coalesce(nullif(trim(u.name || ' ' || coalesce(u.family_name, '')), ''), ph);
  select extras->>'intake_contact_phone' into contact_ph from site_content where id = 1;
  if p_send and coalesce(p_password_plain, '') <> '' and c_id is not null then
    msg := 'أهلاً ' || nm || ' 👋 أنشأنا لك حساباً على بلكون.' || E'\n'
        || 'رقم الدخول: ' || E'‎' || ph || E'‎' || E'\n'
        || 'كلمة المرور المؤقتة: ' || E'‎' || p_password_plain || E'‎' || E'\n'
        || 'رقم عضويتك: ' || E'‎' || coalesce(u.member_no, '') || E'‎' || E'\n\n'
        || 'ادخل من https://balkoun.com ثم غيّر كلمة المرور من «حسابي» ← «الأمان».' || E'\n' || E'\n'
        || '📩 لنشر إعلان عقارك: أرسل تفاصيله وصوره هنا مباشرة وأنشره لك وأرسل لك رابطه، أو انشره بنفسك من https://balkoun.com/post'
        || coalesce(E'\n' || 'للتواصل مع الإدارة: ' || nullif(trim(contact_ph), ''), '');
    perform bk_admin_message_contact(p_token, c_id, null, 'whatsapp', msg, null);
    -- (2026-10-16) this message is the welcome too: the separate WhatsApp welcome queued by trg_welcome_member is dropped
    delete from campaign_sends where contact_id = c_id and trigger_type = 'welcome' and channel = 'whatsapp' and status = 'queued' and claimed_at is null;
  end if;
  return json_build_object('ok', true, 'id', u.id, 'member_no', u.member_no, 'phone', ph, 'agency_id', ag_id, 'contact_id', c_id);
end $function$;

-- bk_admin_data
CREATE OR REPLACE FUNCTION public.bk_admin_data(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; sc text; al text[]; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_data', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid); return json_build_object( 'me', (select json_build_object('id',id,'name',name,'family_name',family_name, 'permissions',coalesce(to_jsonb(permissions),'[]'::jsonb), 'is_super_admin',is_super_admin, 'admin_countries',coalesce(to_jsonb(admin_countries),'[]'::jsonb)) from users where id = uid), 'scope', sc, 'gx', (select coalesce((select jsonb_object_agg(key, value) from jsonb_each(coalesce(extras,'{}'::jsonb)) where key like 'notify\_%' or key like 'verify\_%' or key = 'intake_bot' or key like 'maintenance\_%'), '{}'::jsonb) from site_content where id = 1), 'stats', (select json_build_object( 'listings', (select count(*) from listings where bk_scope_ok(country_code,sc,al)), 'live', (select count(*) from listings where bk_scope_ok(country_code,sc,al) and status='live'), 'pending', (select count(*) from listings where bk_scope_ok(country_code,sc,al) and status='pending'), 'sold', (select count(*) from listings where bk_scope_ok(country_code,sc,al) and status in ('sold','rented')), 'expired', (select count(*) from listings where bk_scope_ok(country_code,sc,al) and status='expired'), 'green', (select count(*) from listings l where bk_scope_ok(l.country_code,sc,al) and (l.tabu='green' or exists (select 1 from deed_types d where d.country_code=l.country_code and d.code=l.tabu and d.is_strong))), 'users', (select count(*) from users where role <> 'admin' and not coalesce(is_house,false) and bk_scope_ok(country,sc,al)), 'photos', (select count(*) from listing_photos p join listings l on l.id=p.listing_id where bk_scope_ok(l.country_code,sc,al)), 'reviews', (select count(*) from reviews rv join users tu on tu.id = rv.target_user where bk_scope_ok(tu.country,sc,al)), 'openReports', (select count(*) from listing_reports r left join listings l on l.id=r.listing_id where not r.resolved and ((l.id is null and sc is null) or bk_scope_ok(l.country_code,sc,al))), 'openFeedback', (select count(*) from feedback where not handled and ((country_code is null and sc is null) or bk_scope_ok(country_code,sc,al))), 'week', (select count(*) from listings where bk_scope_ok(country_code,sc,al) and created_at > now() - interval '7 days'), 'value', (select coalesce(sum(price_usd),0) from listings where bk_scope_ok(country_code,sc,al) and status='live' and deal='sale'), 'by_country', coalesce((select json_object_agg(country_code, n) from (select coalesce(country_code,'SY') country_code, count(*) n from listings where bk_scope_ok(country_code,sc,al) group by 1) x), '{}'::json))), 'listings', coalesce((select json_agg(x) from ( select l.id, l.ref, l.status, l.deal, l.property_type, l.price_usd, l.area_m2, l.tabu, l.condition, l.contact_name, l.contact_phone, l.created_at, l.is_featured, l.country_code, g.name_ar as gov, a.name_ar as area, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name, u.phone as poster_phone, u.id as poster_id, (select ag.name from agencies ag where ag.user_id = l.user_id and ag.status = 'approved' limit 1) as agency_name, (select count(*) from listing_photos p where p.listing_id=l.id) as photos, coalesce((select coalesce(nullif(p.thumb_url,''), p.url) from listing_photos p where p.listing_id=l.id and coalesce(p.kind,'photo')='photo' order by p.sort_order, p.id limit 1), (select nullif(p.thumb_url,'') from listing_photos p where p.listing_id=l.id and p.kind='video' and coalesce(p.thumb_url,'') <> '' order by p.sort_order, p.id limit 1)) as cover, (select d.source from intake_drafts d where d.listing_id=l.id order by d.id desc limit 1) as via from listings l join governorates g on g.id=l.governorate_id left join areas a on a.id=l.area_id left join users u on u.id=l.user_id where bk_scope_ok(l.country_code,sc,al) order by l.created_at desc limit 500) x), '[]'::json), 'users', coalesce((select json_agg(x) from ( select u.id, u.member_no, u.phone_verified, u.name, u.family_name, u.phone, u.role, u.account_type, u.level, u.blocked, u.skip_review, u.avatar_url, u.bio, u.created_at, u.country, coalesce(u.is_house,false) as is_house, coalesce(u.hide_phone,false) as hide_phone, (select count(*) from listings l where l.user_id=u.id) as listings, (select string_agg(distinct coalesce(l.country_code,'SY'), ',') from listings l where l.user_id=u.id) as countries, (select round(avg(stars)::numeric,1) from reviews where target_user=u.id) as rating from users u where u.role <> 'admin' and bk_scope_ok(u.country,sc,al) order by u.created_at desc limit 500) x), '[]'::json), 'reports', coalesce((select json_agg(x) from ( select r.id, r.listing_id, r.reason, r.note, r.resolved, r.admin_reply, r.priority, r.replied_at, r.created_at, l.ref as listing_ref, l.country_code, trim(coalesce(ru.name,'')||' '||coalesce(ru.family_name,'')) as reporter_name, ru.phone as reporter_phone, ru.id as reporter_id, coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at) from message_followups m where m.kind='report' and m.ref_id=r.id), '[]'::json) as thread from listing_reports r left join listings l on l.id = r.listing_id left join users ru on ru.id = r.user_id where (l.id is null and sc is null) or bk_scope_ok(l.country_code,sc,al) order by r.created_at desc limit 500) x), '[]'::json), 'feedback', coalesce((select json_agg(x) from ( select f.id, f.kind, f.body, f.handled, f.admin_reply, f.priority, f.replied_at, f.created_at, coalesce(trim(coalesce(fu.name,'')||' '||coalesce(fu.family_name,'')), f.name) as sender_name, coalesce(fu.phone, f.contact) as sender_contact, fu.id as sender_id, coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at) from message_followups m where m.kind='feedback' and m.ref_id=f.id), '[]'::json) as thread, f.country_code from feedback f left join users fu on fu.id = f.user_id where (f.country_code is null and sc is null) or bk_scope_ok(f.country_code,sc,al) order by f.created_at desc limit 500) x), '[]'::json)); end $function$;

-- bk_admin_deed_save
CREATE OR REPLACE FUNCTION public.bk_admin_deed_save(p_token text, p_country text, p_code text, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['types']::text[], 'bk_admin_deed_save', nullif(upper(p_country),''), true, left(coalesce(p_code::text,''),300), nullif(upper(p_country),'')); perform bk_admin_guard(uid, p_country); insert into deed_types (country_code, code, name_ar, name_en, name_de, name_fr, sort_order, enabled, is_strong) values (p_country, p_code, coalesce(p_patch->>'ar','?'), coalesce(p_patch->>'en','?'), p_patch->>'de', p_patch->>'fr', coalesce((p_patch->>'sort_order')::int,100), coalesce((p_patch->>'enabled')::boolean,true), coalesce((p_patch->>'strong')::boolean,false)) on conflict (country_code, code) do update set name_ar=coalesce(p_patch->>'ar',deed_types.name_ar), name_en=coalesce(p_patch->>'en',deed_types.name_en), name_de=coalesce(p_patch->>'de',deed_types.name_de), name_fr=coalesce(p_patch->>'fr',deed_types.name_fr), sort_order=coalesce((p_patch->>'sort_order')::int,deed_types.sort_order), enabled=coalesce((p_patch->>'enabled')::boolean,deed_types.enabled), is_strong=coalesce((p_patch->>'strong')::boolean,deed_types.is_strong); return json_build_object('ok',true); end $function$;

-- bk_admin_delete_ad
CREATE OR REPLACE FUNCTION public.bk_admin_delete_ad(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['ads']::text[], 'bk_admin_delete_ad', (select coalesce(country_code,'SY') from ad_slots where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from ad_slots where id=p_id)); perform bk_admin_guard(uid, (select country_code from ad_slots where id = p_id)); perform public.bk_engage_end('ad', p_id, null, 'ended'); delete from ad_slots where id = p_id; return json_build_object('ok', true); end $function$;

-- bk_admin_delete_alert
CREATE OR REPLACE FUNCTION public.bk_admin_delete_alert(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_delete_alert', null, false, left(coalesce(p_id::text,''),300), null);
  delete from notifications where id=p_id and user_id=uid;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_delete_feedback
CREATE OR REPLACE FUNCTION public.bk_admin_delete_feedback(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['feedback']::text[], 'bk_admin_delete_feedback', (select coalesce(country_code,'SY') from feedback where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from feedback where id=p_id)); perform bk_admin_guard_opt(uid, (select country_code from feedback where id = p_id)); delete from message_followups where kind='feedback' and ref_id=p_id; delete from feedback where id=p_id; return json_build_object('ok', true); end $function$;

-- bk_admin_delete_listing
CREATE OR REPLACE FUNCTION public.bk_admin_delete_listing(p_token text, p_listing bigint, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_delete']::text[], 'bk_admin_delete_listing', (select coalesce(country_code,'SY') from listings where id=p_listing), true, left(coalesce(p_listing::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing));
  perform bk_admin_guard(uid, (select country_code from listings where id = p_listing));
  perform set_config('bk.ldel_by', 'admin', true);
  perform set_config('bk.ldel_admin', uid::text, true);
  perform set_config('bk.ldel_reason', '', true);
  perform set_config('bk.ldel_note', coalesce(p_reason, ''), true);
  delete from listings where id = p_listing;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_delete_report
CREATE OR REPLACE FUNCTION public.bk_admin_delete_report(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['reports']::text[], 'bk_admin_delete_report', (select coalesce(l.country_code,'SY') from listing_reports rr left join listings l on l.id=rr.listing_id where rr.id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(l.country_code,'SY') from listing_reports rr left join listings l on l.id=rr.listing_id where rr.id=p_id)); perform bk_admin_guard_opt(uid, (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id)); delete from message_followups where kind='report' and ref_id=p_id; delete from listing_reports where id=p_id; return json_build_object('ok', true); end $function$;

-- bk_admin_delete_review
CREATE OR REPLACE FUNCTION public.bk_admin_delete_review(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['reviews']::text[], 'bk_admin_delete_review', (select coalesce(u.country,'SY') from reviews rv join users u on u.id=rv.target_user where rv.id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(u.country,'SY') from reviews rv join users u on u.id=rv.target_user where rv.id=p_id)); perform bk_admin_guard(uid, (select u.country from reviews rv join users u on u.id = rv.target_user where rv.id = p_id)); delete from reviews where id = p_id; return json_build_object('ok', true); end $function$;

-- bk_admin_delete_user
CREATE OR REPLACE FUNCTION public.bk_admin_delete_user(p_token text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; u users;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_delete']::text[], 'bk_admin_delete_user', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user));
  if not bk_admin_is_super(uid) then return json_build_object('error', 'super admin only'); end if;
  if p_user = uid then return json_build_object('error', 'self'); end if;
  select * into u from users where id = p_user;
  if u.id is null then return json_build_object('error', 'nouser'); end if;
  if u.role = 'admin' then return json_build_object('error', 'isadmin'); end if;
  perform bk_admin_guard(uid, u.country);
  return bk_user_purge(p_user, 'admin', uid);
end $function$;

-- bk_admin_deleted_listings
CREATE OR REPLACE FUNCTION public.bk_admin_deleted_listings(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_view']::text[], 'bk_admin_deleted_listings', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select d.id, d.listing_id, d.ref, d.user_id, d.poster_name, d.poster_phone, d.country_code, d.gov, d.area, d.property_type, d.deal,
           d.price_usd, d.area_m2, d.rooms, d.status, d.views, d.saves, d.posted_at, d.deleted_at, d.deleted_by, d.admin_id, d.admin_name, d.reason, d.note
      from deleted_listings d
     where bk_scope_ok(coalesce(d.country_code, 'SY'), sc, al)
     order by d.deleted_at desc
     limit 500
  ) x), '[]'::json);
end $function$;

-- bk_admin_deleted_users
CREATE OR REPLACE FUNCTION public.bk_admin_deleted_users(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_view']::text[], 'bk_admin_deleted_users', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select d.id, d.user_id, d.member_no, d.name, d.family_name, d.phone, d.email, d.country, d.city, d.account_type, d.level, d.is_house,
           d.joined_at, d.last_seen_at, d.listings_count, d.deleted_at, d.deleted_by, d.admin_id, d.admin_name
      from deleted_users d
     where bk_scope_ok(coalesce(d.country, 'SY'), sc, al)
     order by d.deleted_at desc
     limit 500
  ) x), '[]'::json);
end $function$;

-- bk_admin_direct_messages
CREATE OR REPLACE FUNCTION public.bk_admin_direct_messages(p_token text, p_contact_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; cid uuid;
begin
  begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns','users_view']::text[], 'bk_admin_direct_messages', coalesce((select coalesce(country_code,'SY') from contacts where id=p_contact_id),(select coalesce(country,'SY') from users where id=p_user_id)), false, left(coalesce(p_contact_id::text,''),300), coalesce((select coalesce(country_code,'SY') from contacts where id=p_contact_id),(select coalesce(country,'SY') from users where id=p_user_id))); exception when others then uid := null; end;
  if uid is null then return json_build_object('error','unauthorised'); end if;
  select id into cid from contacts where (p_contact_id is not null and id = p_contact_id) or (p_user_id is not null and user_id = p_user_id) order by created_at limit 1;
  return coalesce((select json_agg(json_build_object('id', s.id, 'channel', s.channel, 'status', s.status, 'error', s.error, 'text', left(coalesce(k.body_ar, ''), 400), 'at', s.created_at, 'sent_at', s.sent_at) order by s.created_at desc)
    from campaign_sends s join campaigns k on k.id = s.campaign_id where s.contact_id = cid and k.title like 'direct: %' ), '[]'::json);
end $function$;

-- bk_admin_draft_get
CREATE OR REPLACE FUNCTION public.bk_admin_draft_get(p_token text, p_country text DEFAULT 'SY'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; r record; begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['homepage','design','contact','ads']::text[], 'bk_admin_draft_get', nullif(upper(p_country),''), false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); perform bk_admin_guard(uid, coalesce(p_country,'SY'));
  select d.draft, d.updated_at, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as who
    into r from site_drafts d left join users u on u.id=d.updated_by where d.country_code=coalesce(p_country,'SY');
  if not found then return json_build_object('draft','{}'::jsonb); end if;
  return json_build_object('draft',r.draft,'updated_at',r.updated_at,'who',r.who);
end $function$;

-- bk_admin_draft_put
CREATE OR REPLACE FUNCTION public.bk_admin_draft_put(p_token text, p_country text, p_draft jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; cc text := coalesce(p_country,'SY'); d jsonb := coalesce(p_draft,'{}'::jsonb); begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['homepage','design','contact','ads']::text[], 'bk_admin_draft_put', nullif(upper(p_country),''), false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); perform bk_admin_guard(uid, cc);
  if jsonb_typeof(d)<>'object' then raise exception 'bad draft'; end if;
  if pg_column_size(d) > 400000 then raise exception 'draft too large'; end if;
  d := jsonb_build_object('site',coalesce(d->'site','{}'::jsonb),'extras',coalesce(d->'extras','{}'::jsonb));
  if d->'site' = '{}'::jsonb and d->'extras' = '{}'::jsonb then delete from site_drafts where country_code=cc; return json_build_object('ok',true,'empty',true); end if;
  insert into site_drafts(country_code,draft,updated_at,updated_by) values (cc,d,now(),uid)
    on conflict (country_code) do update set draft=excluded.draft, updated_at=excluded.updated_at, updated_by=excluded.updated_by;
  return json_build_object('ok',true);
end $function$;

-- bk_admin_duplicate_listings
CREATE OR REPLACE FUNCTION public.bk_admin_duplicate_listings(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_view']::text[], 'bk_admin_duplicate_listings', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    with L as (
      select l.id, coalesce(l.user_id::text, nullif(l.contact_phone, ''), '') as who, coalesce(l.property_type,'') as pt, coalesce(l.deal,'') as dl,
             coalesce(l.area_id::text, '') as ar, l.price_usd, l.area_m2, l.rooms,
             lower(regexp_replace(coalesce(l.description, ''), '\s+', ' ', 'g')) as dsc
        from listings l
       where l.status in ('live','pending','hidden') and bk_scope_ok(coalesce(l.country_code, 'SY'), sc, al)),
    K as (
      select id, 'poster' as kind, who||'|'||pt||'|'||dl||'|'||ar||'|p'||price_usd::text as key from L where who <> '' and price_usd is not null
      union all
      select id, 'poster', who||'|'||pt||'|'||dl||'|'||ar||'|m'||area_m2::text||'r'||coalesce(rooms::text, '') from L where who <> '' and area_m2 is not null
      union all
      select id, 'text', 'txt:'||md5(left(dsc, 160)) from L where length(dsc) >= 40)
    select k.id as listing_id, k.kind, k.key
      from K k
     where k.key in (select key from K group by key having count(distinct id) > 1)
     order by k.key, k.id
  ) x), '[]'::json);
end $function$;

-- bk_admin_edit_listing
CREATE OR REPLACE FUNCTION public.bk_admin_edit_listing(p_token text, p_id bigint, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; l listings; v_old_price int; v_new_price int; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_edit']::text[], 'bk_admin_edit_listing', (select coalesce(country_code,'SY') from listings where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_id)); perform bk_admin_guard(uid, (select country_code from listings where id = p_id)); select * into l from listings where id = p_id; if l.id is null then return json_build_object('error','nolisting'); end if; v_old_price := l.price_usd; v_new_price := case when p_patch ? 'price_usd' then nullif(p_patch->>'price_usd','')::int else l.price_usd end; update listings set price_usd = v_new_price, price_local = case when p_patch ? 'price_local' then nullif(p_patch->>'price_local','')::numeric else price_local end, price_cur = case when p_patch ? 'price_cur' then nullif(p_patch->>'price_cur','') else price_cur end, area_m2 = coalesce((p_patch->>'area_m2')::int, area_m2), rooms = case when p_patch ? 'rooms' then (p_patch->>'rooms')::int else rooms end, baths = case when p_patch ? 'baths' then (p_patch->>'baths')::int else baths end, living_rooms = case when p_patch ? 'living_rooms' then (p_patch->>'living_rooms')::int else living_rooms end, floor = case when p_patch ? 'floor' then (p_patch->>'floor')::int else floor end, year_built = case when p_patch ? 'year_built' then (p_patch->>'year_built')::int else year_built end, power_hours = case when p_patch ? 'power_hours' then (p_patch->>'power_hours')::int else power_hours end, tabu = coalesce(p_patch->>'tabu', tabu), condition = coalesce(p_patch->>'condition', condition), description = coalesce(p_patch->>'description', description), landmark = case when p_patch ? 'landmark' then p_patch->>'landmark' else landmark end, lat = case when p_patch ? 'lat' then (p_patch->>'lat')::numeric else lat end, lng = case when p_patch ? 'lng' then (p_patch->>'lng')::numeric else lng end, lease_months = case when p_patch ? 'lease_months' then (p_patch->>'lease_months')::int else lease_months end, advance_months = case when p_patch ? 'advance_months' then (p_patch->>'advance_months')::int else advance_months end, deposit_usd = case when p_patch ? 'deposit_usd' then (p_patch->>'deposit_usd')::int else deposit_usd end, bills_included = case when p_patch ? 'bills_included' then (p_patch->>'bills_included')::boolean else bills_included end, furnished = case when p_patch ? 'furnished' then (p_patch->>'furnished')::boolean else furnished end, direction = case when p_patch ? 'direction' then nullif(p_patch->>'direction','') else direction end, rental_period = case when p_patch ? 'rental_period' then nullif(p_patch->>'rental_period','') else rental_period end, amenities = case when p_patch ? 'amenities' then (select coalesce(array_agg(x), '{}') from jsonb_array_elements_text(p_patch->'amenities') x) else amenities end, contact_phone = coalesce(p_patch->>'contact_phone', contact_phone),
    deal = case when p_patch->>'deal' in ('sale','rent') then p_patch->>'deal' else deal end,
    property_type = case when coalesce(p_patch->>'property_type','') <> '' then p_patch->>'property_type' else property_type end,
    section = case when coalesce(p_patch->>'property_type','') <> '' then (case when p_patch->>'property_type' in ('plot','resid','agri','comm','indust','tourist') then 'land' when p_patch->>'property_type' in ('shop','office','factory','warehouse','clinic','hotel','hall','showroom','station','workshop') then 'commercial' else 'homes' end) else section end,
    governorate_id = case when p_patch ? 'governorate_id' then (p_patch->>'governorate_id')::int else governorate_id end,
    area_id = case when p_patch ? 'area_id' then nullif(p_patch->>'area_id','')::int else area_id end,
    user_id = case when p_patch ? 'user_id' and exists (select 1 from users u2 where u2.id = (p_patch->>'user_id')::uuid) then (p_patch->>'user_id')::uuid else user_id end,
    contact_name = case when p_patch ? 'user_id' then coalesce((select ag.name from agencies ag where ag.user_id = (p_patch->>'user_id')::uuid and ag.status = 'approved' limit 1), (select trim(coalesce(u3.name,'')||' '||coalesce(u3.family_name,'')) from users u3 where u3.id = (p_patch->>'user_id')::uuid), contact_name) else contact_name end
  where id = p_id; if v_new_price is distinct from v_old_price then insert into notifications (user_id, type, title, body, link) select sl.user_id, 'price', 'price_change', l.ref, '/#/listing/'||p_id from saved_listings sl where sl.listing_id = p_id; end if; return json_build_object('ok', true); end $function$;

-- bk_admin_edit_user
CREATE OR REPLACE FUNCTION public.bk_admin_edit_user(p_token text, p_user uuid, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_role text; v_phone text; v_cc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_edit_user', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user));
  perform bk_admin_guard(uid, (select country from users where id = p_user));
  select role into v_role from users where id = p_user;
  if v_role is null then return json_build_object('error','nouser'); end if;
  if v_role = 'admin' and uid <> p_user then return json_build_object('error','isadmin'); end if;
  if p_patch ? 'phone' then
    v_phone := regexp_replace(coalesce(p_patch->>'phone',''), '[^0-9+]', '', 'g');
    if v_phone <> '' and left(v_phone,1) <> '+' then v_phone := '+' || v_phone; end if;
    if v_phone = '' then return json_build_object('error','phone_required'); end if;
    if exists (select 1 from users where phone = v_phone and id <> p_user) then return json_build_object('error','phone_taken'); end if;
  end if;
  if p_patch ? 'country' then
    v_cc := upper(nullif(trim(p_patch->>'country'),''));
    if v_cc is not null and v_cc !~ '^[A-Z]{2}$' then return json_build_object('error','bad_country'); end if;
    if v_cc is not null and not bk_admin_country_ok(uid, v_cc) then return json_build_object('error','unauthorised'); end if;
  end if;
  update users set
    name        = case when p_patch ? 'name' then nullif(trim(p_patch->>'name'),'') else name end,
    family_name = case when p_patch ? 'family_name' then nullif(trim(p_patch->>'family_name'),'') else family_name end,
    phone       = case when p_patch ? 'phone' then v_phone else phone end,
    email       = case when p_patch ? 'email' then nullif(lower(trim(p_patch->>'email')),'') else email end,
    city        = case when p_patch ? 'city' then nullif(trim(p_patch->>'city'),'') else city end,
    country     = case when p_patch ? 'country' and v_cc is not null then v_cc else country end,
    bio         = case when p_patch ? 'bio' then nullif(trim(p_patch->>'bio'),'') else bio end
  where id = p_user;
  return json_build_object('ok', true);
exception when unique_violation then return json_build_object('error','phone_taken');
end $function$;

-- bk_admin_engage
CREATE OR REPLACE FUNCTION public.bk_admin_engage(p_token text, p_kind text, p_ref_id bigint, p_ref_text text, p_title text, p_client text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_starts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ends timestamp with time zone DEFAULT NULL::timestamp with time zone, p_notes text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; r public.engagements; v_cc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['engage']::text[], 'bk_admin_engage', nullif(upper(p_country),''), true, left(coalesce(p_kind::text,''),300), nullif(upper(p_country),''));
  v_cc := upper(nullif(nullif(trim(coalesce(p_country,'')),''),'ALL'));
  if p_kind = 'featured' and p_ref_id is not null then perform bk_admin_guard(uid, (select country_code from listings where id = p_ref_id));
  elsif p_kind = 'ad' and p_ref_id is not null then perform bk_admin_guard(uid, (select country_code from ad_slots where id = p_ref_id));
  else perform bk_admin_guard(uid, coalesce(v_cc,'SY')); end if;
  r := public.bk_engage(p_kind,p_ref_id,p_ref_text,p_title,p_client,p_phone,p_starts,p_ends,p_notes,uid);
  if p_kind not in ('ad','featured') and v_cc is not null then update public.engagements set country_code = v_cc where id = r.id returning * into r; end if;
  return row_to_json(r);
end $function$;

-- bk_admin_engage_end
CREATE OR REPLACE FUNCTION public.bk_admin_engage_end(p_token text, p_kind text, p_ref_id bigint, p_ref_text text DEFAULT NULL::text, p_status text DEFAULT 'ended'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['engage','featured','ads']::text[], 'bk_admin_engage_end', null, true, left(coalesce(p_ref_id::text,''),300), null);
  perform public.bk_engage_end(p_kind,p_ref_id,p_ref_text,p_status);
  return json_build_object('ok',true);
end $function$;

-- bk_admin_engagement_update
CREATE OR REPLACE FUNCTION public.bk_admin_engagement_update(p_token text, p_id bigint, p_client text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_ends timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['engage']::text[], 'bk_admin_engagement_update', (select coalesce(country_code,'SY') from engagements where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from engagements where id=p_id));
  update public.engagements set client_name=coalesce(p_client,client_name), phone=coalesce(p_phone,phone), notes=coalesce(p_notes,notes),
    ends_at=coalesce(p_ends,ends_at), status=coalesce(p_status,status),
    ended_at=case when p_status in ('ended','cancelled') then now() else ended_at end
   where id=p_id;
  return json_build_object('ok',true);
end $function$;

-- bk_admin_engagements
CREATE OR REPLACE FUNCTION public.bk_admin_engagements(p_token text, p_days integer DEFAULT NULL::integer, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; since timestamptz; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['engage','featured','ads']::text[], 'bk_admin_engagements', null, false, left(coalesce(p_days::text,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  since := case when p_days is null then null else now() - (p_days||' days')::interval end;
  return coalesce((select json_agg(row_to_json(x) order by x.created_at desc) from (
    select e.*,
      (e.status='active' and (e.starts_at is null or e.starts_at<=now()) and (e.ends_at is null or e.ends_at>=now())) as live,
      (e.status='active' and e.starts_at>now()) as scheduled,
      case e.kind
        when 'featured' then (select json_build_object('ref',l.ref,'listing_id',l.id,'user_id',l.user_id,'status',l.status,'is_featured',l.is_featured,'views',l.views,'saves',l.saves,'price',l.price_usd,
              'poster',trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),'phone',u.phone,'gov',g.name_ar,'area',ar.name_ar,'exists',true)
              from listings l left join users u on u.id=l.user_id left join governorates g on g.id=l.governorate_id left join areas ar on ar.id=l.area_id where l.id=e.ref_id)
        when 'ad' then (select json_build_object('label',a.label,'sponsor',a.sponsor_name,'enabled',a.enabled,'image',a.image_url,'link',a.link_url,'linked',a.linked_listing_id,'position',a.position,
              'listing_id',a.linked_listing_id,'ref',(select ref from listings where id=a.linked_listing_id),'user_id',(select user_id from listings where id=a.linked_listing_id),
              'views',(select count(*) from ad_events v where v.slot_id=a.id and v.kind='view' and v.created_at>=coalesce(e.starts_at,e.created_at) and v.created_at<=coalesce(e.ended_at,e.ends_at,now())),
              'clicks',(select count(*) from ad_events v where v.slot_id=a.id and v.kind='click' and v.created_at>=coalesce(e.starts_at,e.created_at) and v.created_at<=coalesce(e.ended_at,e.ends_at,now())),
              'exists',true) from ad_slots a where a.id=e.ref_id)
        else null end as obj
    from public.engagements e
    where (since is null or e.created_at>=since or e.status='active') and bk_scope_ok(coalesce(e.country_code,'SY'),sc,al)
  ) x), '[]'::json);
end $function$;

-- bk_admin_feature_listing
CREATE OR REPLACE FUNCTION public.bk_admin_feature_listing(p_token text, p_listing bigint, p_from timestamp with time zone, p_days integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; r public.engagements; v_ref text; v_client text; v_phone text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['featured']::text[], 'bk_admin_feature_listing', (select coalesce(country_code,'SY') from listings where id=p_listing), true, left(coalesce(p_listing::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing)); perform bk_admin_guard(uid, (select country_code from listings where id = p_listing));
  if p_days is null or p_days < 1 then raise exception 'invalid duration'; end if;
  update listings set featured_from = p_from, featured_until = p_from + (p_days || ' days')::interval, featured_source = 'admin' where id = p_listing;
  perform bk_recompute_featured(p_listing);
  select l.ref, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')), coalesce(l.contact_phone,u.phone) into v_ref, v_client, v_phone from listings l left join users u on u.id=l.user_id where l.id=p_listing;
  r := public.bk_engage('featured', p_listing, v_ref, v_ref, v_client, v_phone, p_from, p_from + (p_days||' days')::interval, null, uid);
  return json_build_object('ok', true, 'code', r.code);
end $function$;

-- bk_admin_geo_list
CREATE OR REPLACE FUNCTION public.bk_admin_geo_list(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid; al text[]; cc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_geo_list', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); al := bk_admin_allowed(uid);
  cc := nullif(upper(trim(coalesce(p_country,''))),''); if cc = 'ALL' then cc := null; end if;
  if cc is not null and al is not null and not (cc = any(al)) then cc := al[1]; end if;
  return json_build_object(
    'governorates', (select coalesce(json_agg(json_build_object('id',g.id,'name_ar',g.name_ar,'name_en',g.name_en,'slug',g.slug,'enabled',g.enabled,'sort_order',g.sort_order,'lat',g.lat,'lng',g.lng,'country_code',g.country_code,
        'listings',(select count(*) from listings l where l.governorate_id=g.id and l.status='live'), 'areas',(select count(*) from areas a where a.governorate_id=g.id)) order by g.sort_order, g.id), '[]'::json)
       from governorates g where (cc is null or g.country_code=cc) and (al is null or g.country_code = any(al))),
    'areas', (select coalesce(json_agg(json_build_object('id',a.id,'governorate_id',a.governorate_id,'name_ar',a.name_ar,'name_en',a.name_en,'slug',a.slug,'kind',a.kind,'enabled',a.enabled,'sort_order',a.sort_order,'lat',a.lat,'lng',a.lng,
        'listings',(select count(*) from listings l where l.area_id=a.id and l.status='live')) order by a.governorate_id, a.sort_order, a.id), '[]'::json)
       from areas a join governorates g on g.id=a.governorate_id where (cc is null or g.country_code=cc) and (al is null or g.country_code = any(al))));
end $function$;

-- bk_admin_get_settings
CREATE OR REPLACE FUNCTION public.bk_admin_get_settings(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_get_settings', null, false, null, null);
  return (select json_build_object('require_approval', require_approval, 'agency_auto_approve', agency_auto_approve) from site_settings where id = 1);
end $function$;

-- bk_admin_get_user
CREATE OR REPLACE FUNCTION public.bk_admin_get_user(p_token text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_view']::text[], 'bk_admin_get_user', (select coalesce(country,'SY') from users where id=p_user), false, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user));
  perform bk_admin_guard(uid, (select country from users where id = p_user));
  return (select json_build_object('id',u.id,'member_no',u.member_no,'name',u.name,'family_name',u.family_name,'phone',u.phone,'email',u.email,'city',u.city,'country',u.country,'bio',u.bio,'role',u.role) from users u where u.id = p_user);
end $function$;

-- bk_admin_gov_add
CREATE OR REPLACE FUNCTION public.bk_admin_gov_add(p_token text, p_row jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare uid uuid; r governorates; v_slug text; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_gov_add', nullif(upper(p_row->>'country_code'),''), true, left(coalesce(p_row::text,''),300), nullif(upper(p_row->>'country_code'),'')); perform bk_admin_guard(uid, p_row->>'country_code'); v_slug := lower(regexp_replace(regexp_replace(coalesce(nullif(trim(p_row->>'slug'),''), ar_slug(p_row->>'name_ar')), '[^a-z0-9-]+', '-', 'g'), '(^-+|-+$)', '', 'g')); if exists (select 1 from governorates where slug=v_slug) then raise exception 'slug_taken'; end if; insert into governorates (name_ar,name_en,slug,lat,lng,sort_order,enabled,country_code) values (trim(p_row->>'name_ar'), nullif(trim(coalesce(p_row->>'name_en','')),''), v_slug, nullif(p_row->>'lat','')::numeric, nullif(p_row->>'lng','')::numeric, coalesce((p_row->>'sort_order')::int,100), coalesce((p_row->>'enabled')::boolean,true), coalesce(nullif(p_row->>'country_code',''),'SY')) returning * into r; return row_to_json(r); end $function$;

-- bk_admin_gov_save
CREATE OR REPLACE FUNCTION public.bk_admin_gov_save(p_token text, p_row jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare uid uuid; r governorates; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_gov_save', (select country_code from governorates where id=nullif(p_row->>'id','')::bigint), true, left(coalesce(p_row::text,''),300), (select country_code from governorates where id=nullif(p_row->>'id','')::bigint)); perform bk_admin_guard(uid, (select country_code from governorates where id = (p_row->>'id')::int)); update governorates set name_ar = coalesce(nullif(trim(p_row->>'name_ar'),''), name_ar), name_en = coalesce(nullif(trim(p_row->>'name_en'),''), name_en), slug = coalesce(nullif(lower(trim(p_row->>'slug')),''), slug), enabled = coalesce((p_row->>'enabled')::boolean, enabled), sort_order = coalesce((p_row->>'sort_order')::int, sort_order), lat = coalesce(nullif(p_row->>'lat','')::numeric, lat), lng = coalesce(nullif(p_row->>'lng','')::numeric, lng) where id = (p_row->>'id')::int returning * into r; return row_to_json(r); end $function$;

-- bk_admin_house_accounts
CREATE OR REPLACE FUNCTION public.bk_admin_house_accounts(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['login_as']::text[], 'bk_admin_house_accounts', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country);
  return coalesce((select json_agg(row_to_json(x) order by x.created_at, x.id) from (
    select u.id, u.name, u.family_name, u.city, u.country, u.member_no, u.avatar_url, u.bio, u.hide_phone, u.blocked, u.created_at, u.last_seen_at,
           (select count(*) from listings l where l.user_id = u.id and l.status in ('live','pending') and (sc is null or coalesce(l.country_code,'SY') = sc)) as listings,
           (select count(*) from listings l where l.user_id = u.id and (sc is null or coalesce(l.country_code,'SY') = sc)) as listings_total,
           (select count(*) from reviews r where r.target_user = u.id) as reviews
      from users u where u.is_house and (sc is null or coalesce(u.country,'SY') = sc or exists (select 1 from listings l where l.user_id = u.id and coalesce(l.country_code,'SY') = sc)) order by u.created_at, u.id) x), '[]'::json);
end $function$;

-- bk_admin_intake
CREATE OR REPLACE FUNCTION public.bk_admin_intake(p_token text, p_country text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 200)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; cfg jsonb;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['intake']::text[], 'bk_admin_intake', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  cfg := bk_intake_cfg();
  return json_build_object(
    'cfg', cfg,
    'counts', (select json_build_object(
        'collecting', count(*) filter (where status in ('collecting','reading')),
        'ready', count(*) filter (where status in ('ready','needs_info')),
        'review', count(*) filter (where status = 'review'),
        'published', count(*) filter (where status = 'published'),
        'failed', count(*) filter (where status = 'failed'),
        'today', count(*) filter (where created_at > now() - interval '24 hours'),
        'cost_month', coalesce(sum(cost_usd) filter (where created_at > date_trunc('month', now())), 0)
          + (select coalesce(sum(cost_usd) filter (where created_at > date_trunc('month', now())), 0) from ai_search_log where bk_scope_ok(country_code, sc, al)),
        'cost_total', coalesce(sum(cost_usd), 0)
          + (select coalesce(sum(cost_usd), 0) from ai_search_log where bk_scope_ok(country_code, sc, al)),
        'search_today', (select count(*) from ai_search_log where bk_scope_ok(country_code, sc, al) and created_at > now() - interval '24 hours'),
        'search_total', (select count(*) from ai_search_log where bk_scope_ok(country_code, sc, al)))
      from intake_drafts where bk_scope_ok(country_code, sc, al)),
    'drafts', coalesce((select json_agg(row_to_json(x)) from (
        select d.id, d.source, d.chat_id, d.sender_name, d.agency_id, d.user_id, d.by_admin, d.country_code, d.status,
               d.raw_text, d.fields, d.missing, d.summary, d.photos, d.listing_id, d.error, d.model, d.tokens_in, d.tokens_out, d.cost_usd,
               d.reads, d.created_at, d.updated_at, d.last_message_at, d.processed_at, d.published_at,
               a.name as agency_name, a.intake_trusted, l.ref as listing_ref, l.status as listing_status,
               (select count(*) from intake_messages m where m.draft_id = d.id) as messages
          from intake_drafts d left join agencies a on a.id = d.agency_id left join listings l on l.id = d.listing_id
         where bk_scope_ok(d.country_code, sc, al) and (p_status is null or d.status = p_status)
         order by d.created_at desc limit greatest(1, least(coalesce(p_limit,200), 500))) x), '[]'::json),
    'agencies', coalesce((select json_agg(row_to_json(x)) from (
        select a.id, a.name, a.status, a.country_code, a.intake_enabled, a.intake_trusted, a.intake_phone, a.intake_telegram, a.intake_telegram_name, a.intake_code, a.intake_paired_at, a.whatsapp, a.phone, a.user_id
          from agencies a where a.status = 'approved' and bk_scope_ok(coalesce(a.country_code,'SY'), sc, al) order by a.name) x), '[]'::json),
    'members', coalesce((select json_agg(row_to_json(x)) from (
        select u.id, u.name, u.family_name, u.phone, u.member_no, u.account_type,
               (select a.id from agencies a where a.user_id = u.id and a.status = 'approved' order by a.id limit 1) as agency_id
          from users u where coalesce(u.blocked, false) = false order by u.name, u.family_name) x), '[]'::json),
    'log', coalesce((select json_agg(row_to_json(x)) from (
        select id, draft_id, chat_id, level, event, detail, created_at from intake_log order by created_at desc limit 80) x), '[]'::json));
end $function$;

-- bk_admin_intake_can
CREATE OR REPLACE FUNCTION public.bk_admin_intake_can(p_token text, p_draft bigint DEFAULT NULL::bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; cc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['intake']::text[], 'bk_admin_intake_can', (select coalesce(country_code,'SY') from intake_drafts where id=p_draft), false, left(coalesce(p_draft::text,''),300), (select coalesce(country_code,'SY') from intake_drafts where id=p_draft));
  al := bk_admin_allowed(uid);
  if p_draft is null then return al is null or cardinality(al) = 0; end if;
  select country_code into cc from intake_drafts where id = p_draft;
  if cc is null then return false; end if;
  return bk_admin_country_ok(uid, cc);
end $function$;

-- bk_admin_intake_delete
CREATE OR REPLACE FUNCTION public.bk_admin_intake_delete(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; d intake_drafts;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['intake']::text[], 'bk_admin_intake_delete', (select coalesce(country_code,'SY') from intake_drafts where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from intake_drafts where id=p_id));
  select * into d from intake_drafts where id = p_id;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if not bk_admin_country_ok(uid, d.country_code) then raise exception 'unauthorised'; end if;
  delete from intake_drafts where id = p_id;
  insert into intake_log (draft_id, chat_id, event, detail) values (p_id, d.chat_id, 'admin_delete', jsonb_build_object('by', uid, 'photos', d.photos));
  return json_build_object('ok', true, 'photos', d.photos);
end $function$;

-- bk_admin_intake_set
CREATE OR REPLACE FUNCTION public.bk_admin_intake_set(p_token text, p_id bigint, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; d intake_drafts; ag agencies; u users; st text; f jsonb; miss text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['intake']::text[], 'bk_admin_intake_set', (select coalesce(country_code,'SY') from intake_drafts where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from intake_drafts where id=p_id));
  select * into d from intake_drafts where id = p_id;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if not bk_admin_country_ok(uid, d.country_code) then raise exception 'unauthorised'; end if;
  if p_patch ? 'agency_id' then
    if p_patch->>'agency_id' is null or p_patch->>'agency_id' = '' then d.agency_id := null;
    else
      select * into ag from agencies where id = (p_patch->>'agency_id')::bigint;
      if ag.id is null then return json_build_object('error','noagency'); end if;
      if not bk_admin_country_ok(uid, ag.country_code) then raise exception 'unauthorised'; end if;
      d.agency_id := ag.id; d.user_id := ag.user_id; d.country_code := coalesce(ag.country_code, d.country_code);
    end if;
  end if;
  -- a plain member as the listing's owner: user_id set directly; agency_id becomes the member's own approved agency (or none)
  if p_patch ? 'user_id' then
    if p_patch->>'user_id' is null or p_patch->>'user_id' = '' then d.user_id := null; d.agency_id := null;
    else
      select * into u from users where id = (p_patch->>'user_id')::uuid;
      if u.id is null then return json_build_object('error','nouser'); end if;
      d.user_id := u.id;
      select a.id into d.agency_id from agencies a where a.user_id = u.id and a.status = 'approved' order by a.id limit 1;
    end if;
  end if;
  if p_patch ? 'fields' then
    d.fields := jsonb_strip_nulls(coalesce(d.fields,'{}'::jsonb) || (p_patch->'fields'));
    f := d.fields; miss := coalesce(d.missing, '{}');
    if coalesce(f->>'deal','') in ('sale','rent') then miss := array_remove(miss, 'deal'); end if;
    if coalesce(f->>'property_type','') <> '' then miss := array_remove(miss, 'property_type'); end if;
    if coalesce(f->>'governorate','') <> '' or coalesce(f->>'governorate_id','') <> '' then miss := array_remove(miss, 'governorate'); end if;
    if coalesce(f->>'area','') <> '' or coalesce(f->>'area_id','') <> '' then miss := array_remove(miss, 'area'); end if;
    if coalesce(f->>'price','') <> '' then miss := array_remove(miss, 'price'); end if;
    if coalesce(f->>'area_m2','') <> '' then miss := array_remove(miss, 'area_m2'); end if;
    if coalesce(f->>'tabu','') <> '' or coalesce(f->>'deal','') = 'rent' then miss := array_remove(miss, 'tabu'); end if;
    d.missing := miss;
  end if;
  if p_patch ? 'country_code' then
    if not bk_admin_country_ok(uid, upper(p_patch->>'country_code')) then raise exception 'unauthorised'; end if;
    d.country_code := upper(p_patch->>'country_code');
  end if;
  if p_patch ? 'photos' then d.photos := p_patch->'photos'; if jsonb_array_length(d.photos) > 0 then d.missing := array_remove(coalesce(d.missing,'{}'), 'photos'); end if; end if;
  st := p_patch->>'status';
  if st is not null then
    if st not in ('cancelled','ready','review','collecting') then return json_build_object('error','badstatus'); end if;
    if d.status = 'published' then return json_build_object('error','already'); end if;
    d.status := st;
  end if;
  update intake_drafts set agency_id = d.agency_id, user_id = d.user_id, fields = d.fields, missing = d.missing, country_code = d.country_code,
         photos = d.photos, status = d.status, updated_at = now(), error = case when p_patch ? 'agency_id' or p_patch ? 'user_id' or st is not null then null else error end
   where id = p_id returning * into d;
  insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'admin_edit', jsonb_build_object('keys', (select json_agg(k) from jsonb_object_keys(p_patch) k), 'by', uid));
  return ((row_to_json(d)::jsonb - 'error') || jsonb_build_object('err_text', d.error))::json;
end $function$;

-- bk_admin_list_admins
CREATE OR REPLACE FUNCTION public.bk_admin_list_admins(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_list_admins', null, false, null, null);
  if not bk_admin_is_super(uid) then raise exception 'super admin only'; end if;
  return coalesce((select json_agg(x) from (
    select id, member_no, phone, name, family_name, permissions, is_super_admin, created_at, admin_countries, last_seen_at,
           tg_chat_id is not null as tg_paired, tg_name, tg_paired_at, notify_tg, phone_verified,
           coalesce(cardinality(recovery_codes),0) as recovery_left, recovery_codes_at
      from users where role = 'admin' order by is_super_admin desc, created_at) x), '[]'::json);
end $function$;

-- bk_admin_list_ads
CREATE OR REPLACE FUNCTION public.bk_admin_list_ads(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['ads','homepage']::text[], 'bk_admin_list_ads', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x order by x.country_code, x.position) from (
    select id, position, image_url, link_url, label, enabled, media_type, linked_listing_id, image_urls, video_embed_url, sponsor_name, starts_at, expires_at, overlay_top, overlay_bottom, country_code
      from ad_slots where bk_scope_ok(country_code, sc, al)) x), '[]'::json);
end $function$;

-- bk_admin_list_featured
CREATE OR REPLACE FUNCTION public.bk_admin_list_featured(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['featured','social']::text[], 'bk_admin_list_featured', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  update listings set is_featured = (featured_from is not null and featured_until is not null and now() between featured_from and featured_until)
   where featured_until is not null and featured_until > now() - interval '1 day';
  return coalesce((select json_agg(x order by x.featured_from) from (
    select l.id, l.ref, l.status, l.price_usd, l.featured_from, l.featured_until, l.is_featured, l.country_code, l.featured_source,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name
      from listings l left join users u on u.id = l.user_id
     where l.featured_until is not null and l.featured_until > now() - interval '1 day' and bk_scope_ok(l.country_code,sc,al)) x), '[]'::json);
end $function$;

-- bk_admin_list_promos
CREATE OR REPLACE FUNCTION public.bk_admin_list_promos(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; v_cc text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['featured','social']::text[], 'bk_admin_list_promos', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  v_cc := coalesce(nullif(p_country,'ALL'), 'SY');
  update listings set is_featured = (featured_from is not null and featured_until is not null and now() between featured_from and featured_until)
   where featured_until is not null and featured_until > now() - interval '1 day'
     and is_featured is distinct from (featured_from is not null and featured_until is not null and now() between featured_from and featured_until);
  return json_build_object(
    'rows', coalesce((select json_agg(x order by x.sort_until desc nulls last, x.id desc) from (
      select l.id, l.ref, l.status, l.country_code, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name,
             l.featured_from as top_from, l.featured_until as top_until, l.featured_source as top_source,
             (l.featured_until is not null and l.featured_until > now() - interval '1 day') as has_top,
             l.is_featured as top_active,
             s.id as slot_id, s.enabled as home_enabled, s.starts_at as home_from, s.expires_at as home_until, s.sponsor_name, s.source as home_source,
             (s.id is not null and s.enabled and (s.starts_at is null or s.starts_at <= now()) and (s.expires_at is null or s.expires_at >= now())) as home_active,
             greatest(case when l.featured_until > now() - interval '1 day' then l.featured_until end, s.expires_at) as sort_until
        from listings l
        left join users u on u.id = l.user_id
        left join lateral (select * from ad_slots a where a.linked_listing_id = l.id and (a.expires_at is null or a.expires_at > now() - interval '1 day')
                             order by a.enabled desc, a.id desc limit 1) s on true
       where bk_scope_ok(l.country_code, sc, al)
         and ((l.featured_until is not null and l.featured_until > now() - interval '1 day') or s.id is not null)) x), '[]'::json),
    'squares', json_build_object('used', bk_ad_squares_used(v_cc, null), 'max', bk_ad_max_squares(),
        'custom', (select count(*) from ad_slots where linked_listing_id is null and enabled = true and country_code = v_cc and (expires_at is null or expires_at >= now()))));
end $function$;

-- bk_admin_listing
CREATE OR REPLACE FUNCTION public.bk_admin_listing(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; l record; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_view']::text[], 'bk_admin_listing', (select coalesce(country_code,'SY') from listings where id=p_id), false, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_id)); perform bk_admin_guard(uid, (select country_code from listings where id = p_id)); select ll.*, g.name_ar as gov, a.name_ar as area, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name, u.phone as poster_phone into l from listings ll join governorates g on g.id = ll.governorate_id left join areas a on a.id = ll.area_id left join users u on u.id = ll.user_id where ll.id = p_id; if l.id is null then return json_build_object('error','notfound'); end if; return to_json(l); end $function$;

-- bk_admin_listing_stats
CREATE OR REPLACE FUNCTION public.bk_admin_listing_stats(p_token text, p_days integer DEFAULT 30, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; t0 timestamptz; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['stats','listings_view']::text[], 'bk_admin_listing_stats', null, false, left(coalesce(p_days::text,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  t0 := now() - (greatest(1, least(coalesce(p_days,30), 3650)) || ' days')::interval;
  return coalesce((select json_agg(x) from (
    select l.id,
           (select count(*) from page_views v where v.listing_id=l.id and v.created_at >= t0) as views,
           (select count(*) from contact_events c where c.listing_id=l.id and c.created_at >= t0) as contacts,
           (select count(*) from saved_listings s where s.listing_id=l.id) as saves,
           l.views as views_total
      from listings l where bk_scope_ok(l.country_code,sc,al)) x), '[]'::json);
end $function$;

-- bk_admin_listings_map_status
CREATE OR REPLACE FUNCTION public.bk_admin_listings_map_status(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo','listings_view']::text[], 'bk_admin_listings_map_status', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select l.id, l.ref, l.property_type, l.price_usd, a.name_ar as area, g.name_ar as gov,
      case when l.lat is not null and l.lng is not null then 'user'
           when a.lat is not null and a.lng is not null then 'balkoun'
           else 'none' end as mstatus
    from listings l
    join areas a on a.id = l.area_id
    join governorates g on g.id = a.governorate_id
    where l.status='live' and bk_scope_ok(l.country_code, sc, al)
  ) x), '[]'::json);
end $function$;

-- bk_admin_login_as
CREATE OR REPLACE FUNCTION public.bk_admin_login_as(p_token text, p_user uuid, p_notify boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; u users; tok text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['login_as']::text[], 'bk_admin_login_as', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user));
  select * into u from users where id = p_user;
  if u.id is null then return json_build_object('error', 'nouser'); end if;
  if u.role = 'admin' then return json_build_object('error', 'isadmin'); end if;
  perform bk_admin_guard(uid, u.country);
  tok := bk_issue_member_token(u.id);
  if p_notify then
    insert into notifications (user_id, type, title, body, link) values (u.id, 'system', 'دخلت إدارة بلكون إلى حسابك', 'دخل فريق بلكون إلى حسابك بطلبك لنشر أو تعديل إعلاناتك. إن لم تطلب ذلك راسلنا.', '/mine');
  end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,'username',u.username,'city',u.city,'country',u.country,
    'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role,'preferred_currency',u.preferred_currency,'phone_verified',u.phone_verified,'member_no',u.member_no,
    'email',u.email,'email_verified',u.email_verified,'token',tok);
end $function$;

-- bk_admin_map_fallback_set
CREATE OR REPLACE FUNCTION public.bk_admin_map_fallback_set(p_token text, p_on boolean, p_country text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_c text := case when p_country is null or upper(p_country)='ALL' or p_country='' then 'SY' else upper(p_country) end;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_map_fallback_set', nullif(upper(p_country),''), true, left(coalesce(p_on::text,''),300), nullif(upper(p_country),'')); if uid is null then raise exception 'not admin'; end if;
  update site_content set extras = coalesce(extras,'{}'::jsonb) || jsonb_build_object('map_area_fallback_on', p_on) where country_code=v_c;
  return true;
end $function$;

-- bk_admin_mark_notifications_read
CREATE OR REPLACE FUNCTION public.bk_admin_mark_notifications_read(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_mark_notifications_read', null, false, null, null);
  update notifications set is_read = true where user_id = uid and not is_read;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_me
CREATE OR REPLACE FUNCTION public.bk_admin_me(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; u users; bot text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_me', null, false, null, null);
  select * into u from users where id = uid;
  if u.tg_pair_code is null then update users set tg_pair_code = 'ADM-' || upper(substr(encode(gen_random_bytes(6),'hex'),1,8)) where id = uid returning * into u; end if;
  select extras->>'intake_bot' into bot from site_content where id = 1;
  return json_build_object('id', u.id, 'member_no', u.member_no, 'name', u.name, 'family_name', u.family_name, 'phone', u.phone,
    'is_super_admin', u.is_super_admin, 'permissions', coalesce(to_jsonb(u.permissions),'[]'::jsonb), 'admin_countries', coalesce(to_jsonb(u.admin_countries),'[]'::jsonb),
    'tg_paired', u.tg_chat_id is not null, 'tg_name', u.tg_name, 'tg_paired_at', u.tg_paired_at, 'tg_code', u.tg_pair_code, 'bot', bot,
    'notify_tg', u.notify_tg, 'recovery_left', coalesce(cardinality(u.recovery_codes), 0), 'recovery_at', u.recovery_codes_at, 'last_seen_at', u.last_seen_at);
end $function$;

-- bk_admin_me_set
CREATE OR REPLACE FUNCTION public.bk_admin_me_set(p_token text, p_notify boolean DEFAULT NULL::boolean, p_new_code boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_me_set', null, false, left(coalesce(p_notify::text,''),300), null);
  update users set notify_tg = coalesce(p_notify, notify_tg),
                   tg_pair_code = case when p_new_code then 'ADM-' || upper(substr(encode(gen_random_bytes(6),'hex'),1,8)) else tg_pair_code end
   where id = uid;
  return bk_admin_me(p_token);
end $function$;

-- bk_admin_media_used
CREATE OR REPLACE FUNCTION public.bk_admin_media_used(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_media_used', null, false, null, null);
  return json_build_object(
    'ads', coalesce((select json_agg(distinct u) from (select image_url as u from ad_slots where image_url is not null union all select jsonb_array_elements_text(coalesce(image_urls,'[]'::jsonb)) from ad_slots) z where u is not null), '[]'::json),
    'banners', coalesce((select json_agg(distinct m[1]) from site_content s, regexp_matches(coalesce(s.banner_items,'') || ' ' || coalesce(s.banners_config,'') || ' ' || coalesce(s.banner_image_url,'') || ' ' || coalesce(s.banner_video_url,''), '(https?://[^"''\s\\]+)', 'g') m), '[]'::json),
    'background', coalesce((select json_agg(distinct u) from (select hero_bg_photo_url as u from site_content union all select hero_bg_video_url from site_content) z where u is not null and u <> ''), '[]'::json));
end $function$;

-- bk_admin_merge_gov
CREATE OR REPLACE FUNCTION public.bk_admin_merge_gov(p_token text, p_rural integer, p_city integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid; r governorates; c governorates; a record; dup_id int; n_areas int := 0; n_dup int := 0; n_list int := 0; n_ag int := 0; n_w int := 0; n_p int := 0; n_s int := 0; n_c int := 0;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['geo']::text[], 'bk_admin_merge_gov', (select country_code from governorates where id=p_rural), true, left(coalesce(p_rural::text,''),300), (select country_code from governorates where id=p_rural));
  select * into r from governorates where id = p_rural; select * into c from governorates where id = p_city;
  if r.id is null or c.id is null or r.country_code <> c.country_code or r.id = c.id then return json_build_object('error','badpair'); end if;
  perform bk_admin_guard(uid, c.country_code);
  if r.merged_into is not null then return json_build_object('error','already','into',r.merged_into); end if;
  for a in select * from areas where governorate_id = p_rural loop
    select id into dup_id from areas where governorate_id = p_city and bk_area_norm(name_ar) = bk_area_norm(a.name_ar) limit 1;
    if dup_id is not null then
      update listings set area_id = dup_id where area_id = a.id;
      update contacts set area_id = dup_id where area_id = a.id;
      update area_suggestions set area_id = dup_id where area_id = a.id;
      update areas set lat = coalesce(lat, a.lat), lng = coalesce(lng, a.lng) where id = dup_id;
      update areas set enabled = false, governorate_id = p_city, slug = slug || '-merged-' || a.id where id = a.id;
      n_dup := n_dup + 1;
    else
      update areas set governorate_id = p_city,
        kind = case when kind = 'city' then 'city'
                    when exists (select 1 from area_suggestions s where s.area_id = a.id and s.place in ('town','city')) then 'city'
                    when exists (select 1 from area_suggestions s where s.area_id = a.id and s.place in ('village','hamlet')) then 'village'
                    when kind = 'area' then 'village' else kind end
       where id = a.id;
      if exists (select 1 from areas x where x.governorate_id = p_city and x.slug = a.slug and x.id <> a.id) then update areas set slug = slug || '-' || a.id where id = a.id; end if;
      n_areas := n_areas + 1;
    end if;
  end loop;
  update listings set governorate_id = p_city where governorate_id = p_rural; get diagnostics n_list = row_count;
  update contacts set governorate_id = p_city where governorate_id = p_rural; get diagnostics n_c = row_count;
  update campaigns set governorate_id = p_city where governorate_id = p_rural;
  update wanted set gov_name = c.name_ar where gov_name = r.name_ar; get diagnostics n_w = row_count;
  update projects set gov_name = c.name_ar where gov_name = r.name_ar; get diagnostics n_p = row_count;
  update agencies set gov_names = (select array_agg(distinct x order by x) from unnest(array_replace(gov_names, r.name_ar, c.name_ar)) x) where r.name_ar = any(gov_names); get diagnostics n_ag = row_count;
  update area_suggestions set governorate_id = p_city where governorate_id = p_rural and status = 'pending'; get diagnostics n_s = row_count;
  update area_suggestions s set status = 'rejected', updated_at = now() where s.status = 'pending' and s.kind = 'new' and s.governorate_id = p_city
     and exists (select 1 from areas x where x.governorate_id = p_city and x.enabled and bk_area_norm(x.name_ar) = bk_area_norm(s.name_ar));
  update governorates set enabled = false, merged_into = p_city where id = p_rural;
  return json_build_object('ok', true, 'areas_moved', n_areas, 'areas_folded', n_dup, 'listings', n_list, 'agencies', n_ag, 'wanted', n_w, 'projects', n_p, 'contacts', n_c, 'suggestions', n_s);
end $function$;

-- bk_admin_message_contact
CREATE OR REPLACE FUNCTION public.bk_admin_message_contact(p_token text, p_contact_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid, p_channel text DEFAULT 'whatsapp'::text, p_text text DEFAULT ''::text, p_subject text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; c contacts; camp uuid; sid bigint; utg text;
begin
  begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns','users_edit']::text[], 'bk_admin_message_contact', coalesce((select coalesce(country_code,'SY') from contacts where id=p_contact_id),(select coalesce(country,'SY') from users where id=p_user_id)), true, left(coalesce(p_contact_id::text,''),300), coalesce((select coalesce(country_code,'SY') from contacts where id=p_contact_id),(select coalesce(country,'SY') from users where id=p_user_id))); exception when others then uid := null; end;
  if uid is null then return json_build_object('error','unauthorised'); end if;
  if p_channel not in ('whatsapp','telegram','email') then return json_build_object('error','badchannel'); end if;
  if length(trim(coalesce(p_text,''))) < 2 then return json_build_object('error','empty'); end if;
  select * into c from contacts where (p_contact_id is not null and id = p_contact_id) or (p_user_id is not null and user_id = p_user_id) order by created_at limit 1;
  if c.id is null then return json_build_object('error','nocontact'); end if;
  if p_channel = 'telegram' and c.tg_chat_id is null and c.user_id is not null then
    select tg_chat_id into utg from users where id = c.user_id;
    if utg is not null then update contacts set tg_chat_id = utg, updated_at = now() where id = c.id; c.tg_chat_id := utg; end if;
  end if;
  if p_channel = 'whatsapp' and coalesce(c.phone,'') = '' then return json_build_object('error','nophone'); end if;
  if p_channel = 'telegram' and c.tg_chat_id is null then return json_build_object('error','notg'); end if;
  if p_channel = 'email' and coalesce(c.email,'') = '' then return json_build_object('error','noemail'); end if;
  insert into campaigns (title, kind, channels, subject, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
    values ('direct: ' || coalesce(nullif(c.name,''), c.phone, c.email, ''), 'manual', array[p_channel], p_subject, trim(p_text), trim(p_text), c.country_code, false, 'sending', uid, now())
    returning id into camp;
  insert into campaign_sends (campaign_id, trigger_type, contact_id, channel, status) values (camp, 'manual', c.id, p_channel, 'queued') returning id into sid;
  return json_build_object('ok', true, 'send_id', sid, 'campaign_id', camp);
end $function$;

-- bk_admin_move_ad
CREATE OR REPLACE FUNCTION public.bk_admin_move_ad(p_token text, p_id bigint, p_dir text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_cc text; v_pos int; v_other_id bigint; v_other_pos int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['ads']::text[], 'bk_admin_move_ad', (select coalesce(country_code,'SY') from ad_slots where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from ad_slots where id=p_id));
  select position, country_code into v_pos, v_cc from ad_slots where id = p_id;
  if v_pos is null then raise exception 'not found'; end if;
  perform bk_admin_guard(uid, v_cc);
  if p_dir = 'up' then select id, position into v_other_id, v_other_pos from ad_slots where country_code = v_cc and position < v_pos order by position desc limit 1;
  else select id, position into v_other_id, v_other_pos from ad_slots where country_code = v_cc and position > v_pos order by position asc limit 1; end if;
  if v_other_id is null then return json_build_object('ok', true); end if;
  update ad_slots set position = v_other_pos where id = p_id;
  update ad_slots set position = v_pos where id = v_other_id;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_notifications
CREATE OR REPLACE FUNCTION public.bk_admin_notifications(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_notifications', null, false, null, null);
  return json_build_object(
    'items', coalesce((select json_agg(x) from (
        select id, type, title, body, link, is_read, created_at
          from notifications where user_id = uid
         order by created_at desc limit 50) x), '[]'::json),
    'unread', (select count(*) from notifications where user_id = uid and not is_read));
end $function$;

-- bk_admin_notify_test
CREATE OR REPLACE FUNCTION public.bk_admin_notify_test(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform bk_admin_uid(p_token); perform public.bk_admin_need(bk_admin_uid(p_token), ARRAY['settings']::text[], 'bk_admin_notify_test', null, true, null, null);
  insert into admin_notify_queue (event, title, body, link) values ('test', 'رسالة اختبار من لوحة بلكون ✅', 'إذا وصلتك هذه الرسالة فالتنبيهات تعمل.', 'https://balkoun.com/admin');
  return json_build_object('ok', true);
end $function$;

-- bk_admin_outreach_delete
CREATE OR REPLACE FUNCTION public.bk_admin_outreach_delete(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_outreach_delete', (select coalesce(country_code,'SY') from outreach where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from outreach where id=p_id));
  delete from outreach where id = p_id;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_outreach_list
CREATE OR REPLACE FUNCTION public.bk_admin_outreach_list(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_outreach_list', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by
      case x.stage when 'active' then 7 when 'first_listing' then 6 when 'account' then 5 when 'agreed' then 4 when 'replied' then 3 when 'messaged' then 2 when 'new' then 1 else 8 end,
      x.next_at nulls last, x.updated_at desc) from (
    select o.*,
           u.name as user_name, u.family_name as user_family, u.member_no,
           (select count(*) from listings l where l.user_id = o.user_id and l.status in ('live','pending')) as listings,
           -- a member whose phone matches, when the row is not linked yet (digits only, last 9 compared)
           (select m.id from users m where o.user_id is null and o.phone is not null
              and right(regexp_replace(m.phone,'\D','','g'), 9) = right(regexp_replace(o.phone,'\D','','g'), 9) limit 1) as match_user,
           (select trim(coalesce(m.name,'')||' '||coalesce(m.family_name,'')) from users m where o.user_id is null and o.phone is not null
              and right(regexp_replace(m.phone,'\D','','g'), 9) = right(regexp_replace(o.phone,'\D','','g'), 9) limit 1) as match_name
      from outreach o left join users u on u.id = o.user_id
     where bk_scope_ok(o.country_code, sc, al)) x), '[]'::json);
end $function$;

-- bk_admin_outreach_save
CREATE OR REPLACE FUNCTION public.bk_admin_outreach_save(p_token text, p_id bigint, p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; rid bigint; st text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_outreach_save', (case when p_id is null then nullif(upper(p_data->>'country_code'),'') else (select coalesce(country_code,'SY') from outreach where id=p_id) end), true, left(coalesce(p_id::text,''),300), (case when p_id is null then nullif(upper(p_data->>'country_code'),'') else (select coalesce(country_code,'SY') from outreach where id=p_id) end));
  st := coalesce(nullif(p_data->>'stage',''), 'new');
  if st not in ('new','messaged','replied','agreed','account','first_listing','active','declined') then st := 'new'; end if;
  if p_id is null then
    if coalesce(trim(p_data->>'name'),'') = '' then return json_build_object('error','name'); end if;
    insert into outreach (country_code, name, phone, city, area, source, stage, notes, last_contact_at, next_at, user_id, created_by)
    values (coalesce(nullif(upper(p_data->>'country_code'),''),'SY'), trim(p_data->>'name'), nullif(trim(p_data->>'phone'),''), nullif(trim(p_data->>'city'),''),
            nullif(trim(p_data->>'area'),''), nullif(trim(p_data->>'source'),''), st, nullif(p_data->>'notes',''),
            nullif(p_data->>'last_contact_at','')::timestamptz, nullif(p_data->>'next_at','')::timestamptz, nullif(p_data->>'user_id','')::uuid, uid)
    returning id into rid;
  else
    update outreach set
      name = coalesce(nullif(trim(p_data->>'name'),''), name),
      phone = case when p_data ? 'phone' then nullif(trim(p_data->>'phone'),'') else phone end,
      city = case when p_data ? 'city' then nullif(trim(p_data->>'city'),'') else city end,
      area = case when p_data ? 'area' then nullif(trim(p_data->>'area'),'') else area end,
      source = case when p_data ? 'source' then nullif(trim(p_data->>'source'),'') else source end,
      stage = case when p_data ? 'stage' then st else stage end,
      notes = case when p_data ? 'notes' then nullif(p_data->>'notes','') else notes end,
      last_contact_at = case when p_data ? 'last_contact_at' then nullif(p_data->>'last_contact_at','')::timestamptz else last_contact_at end,
      next_at = case when p_data ? 'next_at' then nullif(p_data->>'next_at','')::timestamptz else next_at end,
      user_id = case when p_data ? 'user_id' then nullif(p_data->>'user_id','')::uuid else user_id end,
      updated_at = now()
    where id = p_id returning id into rid;
  end if;
  return json_build_object('id', rid);
end $function$;

-- bk_admin_photo_add
CREATE OR REPLACE FUNCTION public.bk_admin_photo_add(p_token text, p_listing bigint, p_url text, p_thumb text, p_sort integer DEFAULT 0, p_kind text DEFAULT 'photo'::text, p_duration integer DEFAULT NULL::integer, p_size bigint DEFAULT NULL::bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_max int; v_on boolean;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_edit']::text[], 'bk_admin_photo_add', (select coalesce(country_code,'SY') from listings where id=p_listing), true, left(coalesce(p_listing::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing));
  perform bk_admin_guard_opt(uid, (select country_code from listings where id = p_listing));
  if not exists (select 1 from listings where id = p_listing) then return json_build_object('error','nolisting'); end if;
  if coalesce(p_kind,'photo') = 'video' then
    select coalesce((extras->>'video_enabled')::boolean, true), coalesce((extras->>'video_max')::int, 1) into v_on, v_max from site_content where id = 1;
    if (select count(*) from listing_photos where listing_id = p_listing and kind = 'video') >= coalesce(v_max,1) then return json_build_object('error','video_limit'); end if;
  end if;
  insert into listing_photos (listing_id, url, thumb_url, sort_order, kind, duration_s, size_bytes)
    values (p_listing, p_url, p_thumb, coalesce(p_sort, (select coalesce(max(sort_order),-1)+1 from listing_photos where listing_id = p_listing)), coalesce(p_kind,'photo'), p_duration, p_size);
  return json_build_object('ok', true);
end $function$;

-- bk_admin_photo_del
CREATE OR REPLACE FUNCTION public.bk_admin_photo_del(p_token text, p_photo bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_edit']::text[], 'bk_admin_photo_del', (select coalesce(country_code,'SY') from listings where id=(select listing_id from listing_photos where id=p_photo)), true, left(coalesce(p_photo::text,''),300), (select coalesce(country_code,'SY') from listings where id=(select listing_id from listing_photos where id=p_photo))); perform bk_admin_guard_opt(uid, (select l.country_code from listing_photos p join listings l on l.id = p.listing_id where p.id = p_photo)); delete from listing_photos where id = p_photo; return json_build_object('ok', true); end $function$;

-- bk_admin_photos
CREATE OR REPLACE FUNCTION public.bk_admin_photos(p_token text, p_country text DEFAULT NULL::text, p_limit integer DEFAULT 300)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_view']::text[], 'bk_admin_photos', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select p.id, p.listing_id, p.url, p.thumb_url, p.sort_order, p.created_at, p.kind, p.size_bytes, l.ref, l.status as listing_status, coalesce(l.country_code,'SY') as country_code
      from listing_photos p left join listings l on l.id = p.listing_id
     where (l.id is null and sc is null) or bk_scope_ok(coalesce(l.country_code,'SY'), sc, al)
     order by p.listing_id desc nulls last, p.sort_order asc
     limit greatest(1, least(coalesce(p_limit,300), 2000))) x), '[]'::json);
end $function$;

-- bk_admin_project_delete
CREATE OR REPLACE FUNCTION public.bk_admin_project_delete(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['projects']::text[], 'bk_admin_project_delete', (select coalesce(country_code,'SY') from projects where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from projects where id=p_id)); perform bk_admin_guard(uid, (select country_code from projects where id = p_id)); delete from projects where id=p_id; return json_build_object('ok',true); end $function$;

-- bk_admin_project_lead_set
CREATE OR REPLACE FUNCTION public.bk_admin_project_lead_set(p_token text, p_id bigint, p_handled boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['projects']::text[], 'bk_admin_project_lead_set', (select coalesce(pr.country_code,'SY') from project_leads pl join projects pr on pr.id=pl.project_id where pl.id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(pr.country_code,'SY') from project_leads pl join projects pr on pr.id=pl.project_id where pl.id=p_id)); perform bk_admin_guard(uid, (select p.country_code from project_leads l join projects p on p.id = l.project_id where l.id = p_id)); update project_leads set handled=p_handled where id=p_id; return json_build_object('ok',true); end $function$;

-- bk_admin_project_leads
CREATE OR REPLACE FUNCTION public.bk_admin_project_leads(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['projects']::text[], 'bk_admin_project_leads', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by x.created_at desc) from (
    select l.*, p.name as project_name, p.country_code from project_leads l join projects p on p.id=l.project_id
     where bk_scope_ok(coalesce(p.country_code,'SY'), sc, al) order by l.created_at desc limit 300) x), '[]'::json);
end $function$;

-- bk_admin_project_save
CREATE OR REPLACE FUNCTION public.bk_admin_project_save(p_token text, p_id bigint, p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; r projects; v_c text := nullif(p_data->>'country_code',''); begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['projects']::text[], 'bk_admin_project_save', (case when p_id is null then nullif(upper(p_data->>'country_code'),'') else (select coalesce(country_code,'SY') from projects where id=p_id) end), true, left(coalesce(p_id::text,''),300), (case when p_id is null then nullif(upper(p_data->>'country_code'),'') else (select coalesce(country_code,'SY') from projects where id=p_id) end)); perform bk_admin_guard(uid, case when p_id is null then coalesce(v_c,'SY') else (select country_code from projects where id = p_id) end); if p_id is null then insert into projects(name,developer_user_id,developer_name,gov_name,area_name,address,lat,lng,description,status,delivery,price_from,down_pct,months,handover_pct,photos,units,plans,featured,published,country_code) values (coalesce(p_data->>'name','مشروع'), nullif(p_data->>'developer_user_id','')::uuid, p_data->>'developer_name', p_data->>'gov_name', p_data->>'area_name', p_data->>'address', nullif(p_data->>'lat','')::numeric, nullif(p_data->>'lng','')::numeric, p_data->>'description', coalesce(p_data->>'status','soon'), p_data->>'delivery', nullif(p_data->>'price_from','')::int, nullif(p_data->>'down_pct','')::int, nullif(p_data->>'months','')::int, nullif(p_data->>'handover_pct','')::int, coalesce(p_data->'photos','[]'::jsonb), coalesce(p_data->'units','[]'::jsonb), coalesce(p_data->'plans','[]'::jsonb), coalesce((p_data->>'featured')::boolean,false), coalesce((p_data->>'published')::boolean,false), coalesce(v_c,'SY')) returning * into r; else update projects set name=coalesce(p_data->>'name',name), developer_user_id=nullif(p_data->>'developer_user_id','')::uuid, developer_name=p_data->>'developer_name', gov_name=p_data->>'gov_name', area_name=p_data->>'area_name', address=p_data->>'address', lat=nullif(p_data->>'lat','')::numeric, lng=nullif(p_data->>'lng','')::numeric, description=p_data->>'description', status=coalesce(p_data->>'status',status), delivery=p_data->>'delivery', price_from=nullif(p_data->>'price_from','')::int, down_pct=nullif(p_data->>'down_pct','')::int, months=nullif(p_data->>'months','')::int, handover_pct=nullif(p_data->>'handover_pct','')::int, photos=coalesce(p_data->'photos',photos), units=coalesce(p_data->'units',units), plans=coalesce(p_data->'plans',plans), featured=coalesce((p_data->>'featured')::boolean,featured), published=coalesce((p_data->>'published')::boolean,published), updated_at=now(), country_code=coalesce(v_c,country_code) where id=p_id returning * into r; end if; return row_to_json(r); end $function$;

-- bk_admin_projects
CREATE OR REPLACE FUNCTION public.bk_admin_projects(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['projects']::text[], 'bk_admin_projects', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(p) order by p.created_at desc) from (
    select pr.*, (select count(*) from project_leads l where l.project_id=pr.id) as leads, (select count(*) from project_leads l where l.project_id=pr.id and not l.handled) as new_leads
      from projects pr where bk_scope_ok(coalesce(pr.country_code,'SY'),sc,al)) p), '[]'::json);
end $function$;

-- bk_admin_promo_due
CREATE OR REPLACE FUNCTION public.bk_admin_promo_due(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['social','featured']::text[], 'bk_admin_promo_due', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); if uid is null then raise exception 'not admin'; end if; sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(json_build_object(
      'listing_id', l.id, 'ref', l.ref, 'property_type', l.property_type, 'area_m2', l.area_m2,
      'gov', g.name_ar, 'price_usd', l.price_usd, 'due_at', ps.due_at,
      'cover', (select coalesce(nullif(p.thumb_url,''), p.url) from listing_photos p
                 where p.listing_id=l.id and coalesce(p.kind,'photo')='photo' order by p.sort_order, p.id limit 1)
    ) order by ps.due_at)
    from promo_schedule ps join listings l on l.id=ps.listing_id join governorates g on g.id=l.governorate_id
    where ps.status='pending' and ps.due_at<=now() and l.status='live' and bk_scope_ok(l.country_code, sc, al) limit 50), '[]'::json);
end $function$;

-- bk_admin_promo_info
CREATE OR REPLACE FUNCTION public.bk_admin_promo_info(p_token text, p_listing bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; l listings; s ad_slots; u users; b json;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['featured','social']::text[], 'bk_admin_promo_info', (select coalesce(country_code,'SY') from listings where id=p_listing), false, left(coalesce(p_listing::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing));
  select * into l from listings where id = p_listing;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  perform bk_admin_guard(uid, l.country_code);
  perform bk_recompute_featured(l.id);
  select * into l from listings where id = p_listing;
  select * into s from ad_slots where linked_listing_id = l.id order by enabled desc, expires_at desc nulls first, id desc limit 1;
  select * into u from users where id = l.user_id;
  if u.id is not null then b := bk_reward_balance(u.id); end if;
  return json_build_object(
    'id', l.id, 'ref', l.ref, 'status', l.status, 'country_code', l.country_code, 'user_id', l.user_id,
    'poster_name', trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),
    'top', case when l.featured_until is null then null else json_build_object(
        'from', l.featured_from, 'until', l.featured_until, 'source', l.featured_source,
        'active', (l.featured_from <= now() and l.featured_until >= now()),
        'code', (select code from engagements where kind='featured' and ref_id=l.id and status='active' order by created_at desc limit 1)) end,
    'home', case when s.id is null then null else json_build_object(
        'slot_id', s.id, 'enabled', s.enabled, 'from', s.starts_at, 'until', s.expires_at, 'sponsor_name', s.sponsor_name, 'source', s.source,
        'active', (s.enabled and (s.starts_at is null or s.starts_at <= now()) and (s.expires_at is null or s.expires_at >= now())),
        'code', (select code from engagements where kind='ad' and ref_id=s.id and status='active' order by created_at desc limit 1)) end,
    'member', case when u.id is null then null else json_build_object(
        'credits', (b->>'credits')::int, 'hours', (b->>'hours')::int,
        'active_listing_id', b->'active_listing_id', 'active_until', b->'active_until') end,
    'squares', json_build_object('used', bk_ad_squares_used(l.country_code, null), 'max', bk_ad_max_squares()));
end $function$;

-- bk_admin_promo_mark_done
CREATE OR REPLACE FUNCTION public.bk_admin_promo_mark_done(p_token text, p_listing_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['social']::text[], 'bk_admin_promo_mark_done', (select coalesce(country_code,'SY') from listings where id=p_listing_id), true, left(coalesce(p_listing_id::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing_id)); if uid is null then raise exception 'not admin'; end if;
  update promo_schedule set status='done' where listing_id=p_listing_id and status='pending';
  return true;
end $function$;

-- bk_admin_promo_settings_get
CREATE OR REPLACE FUNCTION public.bk_admin_promo_settings_get(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_c text := coalesce(nullif(upper(p_country),''),'SY');
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['social']::text[], 'bk_admin_promo_settings_get', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); if uid is null then raise exception 'not admin'; end if;
  return coalesce((select extras->'promo' from site_content where country_code=v_c), '{}'::json);
end $function$;

-- bk_admin_promo_settings_set
CREATE OR REPLACE FUNCTION public.bk_admin_promo_settings_set(p_token text, p_settings jsonb, p_country text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_c text := coalesce(nullif(upper(p_country),''),'SY');
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['social']::text[], 'bk_admin_promo_settings_set', nullif(upper(p_country),''), true, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); if uid is null then raise exception 'not admin'; end if;
  update site_content set extras = coalesce(extras,'{}'::jsonb) || jsonb_build_object('promo', p_settings) where country_code=v_c;
  return true;
end $function$;

-- bk_admin_promote
CREATE OR REPLACE FUNCTION public.bk_admin_promote(p_token text, p_listing bigint, p_top boolean, p_home boolean, p_from timestamp with time zone, p_days integer, p_client text DEFAULT NULL::text, p_use_credit boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; l listings; u users; s ad_slots; b json; hrs int; sid bigint; v_from timestamptz; v_until timestamptz; r engagements; rr json;
        v_name text; v_client text; v_phone text; v_code_top text; v_code_home text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['featured']::text[], 'bk_admin_promote', (select coalesce(country_code,'SY') from listings where id=p_listing), true, left(coalesce(p_listing::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing));
  select * into l from listings where id = p_listing;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  perform bk_admin_guard(uid, l.country_code);
  if not coalesce(p_top,false) and not coalesce(p_home,false) and not coalesce(p_use_credit,false) then return json_build_object('error','nothing'); end if;
  if l.status <> 'live' then return json_build_object('error','notlive'); end if;
  select * into u from users where id = l.user_id;
  v_name := nullif(trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')), '');
  v_client := coalesce(nullif(trim(coalesce(p_client,'')),''), v_name);
  v_phone := coalesce(l.contact_phone, u.phone);
  v_from := coalesce(p_from, now());

  if coalesce(p_use_credit,false) then
    if u.id is null then return json_build_object('error','nouser'); end if;
    b := bk_reward_balance(u.id);
    if (b->>'credits')::int < 1 then return json_build_object('error','nocredit'); end if;
    if b->>'active_listing_id' is not null then return json_build_object('error','active', 'until', b->>'active_until'); end if;
    hrs := (b->>'hours')::int;
    sid := bk_reward_square(l.id, hrs);
    if sid is null then return json_build_object('error','max_squares'); end if;
    insert into reward_events (user_id, kind, listing_id, delta, note, created_by) values (u.id, 'used', l.id, -1, hrs || 'h home square · admin', uid);
  elsif coalesce(p_home,false) then
    if p_days is null or p_days < 1 then return json_build_object('error','baddays'); end if;
    v_until := v_from + make_interval(days => p_days);
    select * into s from ad_slots where linked_listing_id = l.id order by enabled desc, id desc limit 1;
    rr := bk_admin_save_ad(p_token, s.id, null, null, null, coalesce(s.label,''), true, 'image', l.id, coalesce(s.image_urls,'[]'::jsonb), null,
                           nullif(trim(coalesce(p_client,'')),''), v_from, v_until, s.overlay_top, s.overlay_bottom, l.country_code);
    v_code_home := rr->>'code';
    update ad_slots set source = 'admin' where id = (rr->>'id')::bigint;
  end if;

  if coalesce(p_top,false) then
    if p_days is null or p_days < 1 then return json_build_object('error','baddays'); end if;
    v_until := v_from + make_interval(days => p_days);
    update listings set featured_from = v_from, featured_until = v_until, featured_source = 'admin' where id = l.id;
    perform bk_recompute_featured(l.id);
    r := bk_engage('featured', l.id, l.ref, l.ref, v_client, v_phone, v_from, v_until, null, uid);
    v_code_top := r.code;
  end if;

  return (json_build_object('ok', true, 'code_top', v_code_top, 'code_home', v_code_home)::jsonb || bk_admin_promo_info(p_token, l.id)::jsonb)::json;
end $function$;

-- bk_admin_promote_end
CREATE OR REPLACE FUNCTION public.bk_admin_promote_end(p_token text, p_listing bigint, p_top boolean, p_home boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; l listings; s record;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['featured']::text[], 'bk_admin_promote_end', (select coalesce(country_code,'SY') from listings where id=p_listing), true, left(coalesce(p_listing::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing));
  select * into l from listings where id = p_listing;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  perform bk_admin_guard(uid, l.country_code);
  if coalesce(p_top,false) then
    update listings set featured_from = null, featured_until = null, is_featured = false where id = l.id;
    perform bk_engage_end('featured', l.id, null, 'cancelled');
  end if;
  if coalesce(p_home,false) then
    for s in select id from ad_slots where linked_listing_id = l.id loop
      perform bk_engage_end('ad', s.id, null, 'cancelled');
      delete from ad_slots where id = s.id;
    end loop;
  end if;
  return bk_admin_promo_info(p_token, l.id);
end $function$;

-- bk_admin_publish
CREATE OR REPLACE FUNCTION public.bk_admin_publish(p_token text, p_country text, p_patch jsonb, p_label text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; cc text := coalesce(p_country,'SY'); vid bigint; snap jsonb; begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['homepage','design','contact','ads']::text[], 'bk_admin_publish', nullif(upper(p_country),''), true, left(coalesce(p_label::text,''),300), nullif(upper(p_country),'')); perform bk_admin_guard(uid, cc);
  if not exists(select 1 from site_versions where country_code=cc) then
    select to_jsonb(s) into snap from site_content s where s.country_code=cc;
    if snap is not null then insert into site_versions(country_code,created_by,kind,label,snapshot) values (cc,uid,'original',null,snap); end if;
  end if;
  if p_patch is not null and p_patch <> '{}'::jsonb then perform bk_admin_set_content(p_token, p_patch, cc); end if;
  select to_jsonb(s) into snap from site_content s where s.country_code=cc;
  if snap is null then raise exception 'no settings row for country %', cc; end if;
  insert into site_versions(country_code,created_by,kind,label,snapshot) values (cc,uid,'publish',left(nullif(trim(p_label),''),160),snap) returning id into vid;
  delete from site_drafts where country_code=cc;
  delete from site_versions where country_code=cc and kind='publish' and id not in (select id from site_versions where country_code=cc and kind='publish' order by created_at desc, id desc limit 60);
  return json_build_object('ok',true,'version',vid);
end $function$;

-- bk_admin_recovery_new
CREATE OR REPLACE FUNCTION public.bk_admin_recovery_new(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; codes text[] := '{}'; hashes text[] := '{}'; c text; i int; alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; b bytea;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_recovery_new', null, true, null, null);
  for i in 1..8 loop
    b := gen_random_bytes(8); c := '';
    for j in 0..7 loop c := c || substr(alphabet, (get_byte(b, j) % 32) + 1, 1); if j = 3 then c := c || '-'; end if; end loop;
    codes := codes || c; hashes := hashes || encode(digest(c, 'sha256'), 'hex');
  end loop;
  update users set recovery_codes = hashes, recovery_codes_at = now() where id = uid;
  return json_build_object('codes', to_jsonb(codes));
end $function$;

-- bk_admin_remove_admin
CREATE OR REPLACE FUNCTION public.bk_admin_remove_admin(p_token text, p_admin uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_super boolean; v_target_super boolean;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_remove_admin', null, true, left(coalesce(p_admin::text,''),300), null);
  select is_super_admin into v_super from users where id = uid;
  if not coalesce(v_super,false) then raise exception 'super admin only'; end if;
  select is_super_admin into v_target_super from users where id = p_admin;
  if coalesce(v_target_super,false) then raise exception 'cannot remove a super admin'; end if;
  update users set role = 'owner', permissions = '{}' where id = p_admin;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_reply
CREATE OR REPLACE FUNCTION public.bk_admin_reply(p_token text, p_kind text, p_id bigint, p_reply text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; v_user uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['feedback','reports']::text[], 'bk_admin_reply', null, true, left(coalesce(p_id::text,''),300), null); perform bk_admin_guard_opt(uid, case when p_kind = 'feedback' then (select country_code from feedback where id = p_id) else (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id) end); if p_kind = 'feedback' then update feedback set admin_reply=p_reply, replied_at=now() where id=p_id returning user_id into v_user; insert into message_followups (kind, ref_id, sender, body) values ('feedback', p_id, 'admin', p_reply); if v_user is not null then insert into notifications (user_id, type, title, body, link) values (v_user, 'reply', 'reply_feedback', p_reply, '/#/msgs?feedback='||p_id); end if; elsif p_kind = 'report' then update listing_reports set admin_reply=p_reply, replied_at=now() where id=p_id returning user_id into v_user; insert into message_followups (kind, ref_id, sender, body) values ('report', p_id, 'admin', p_reply); if v_user is not null then insert into notifications (user_id, type, title, body, link) values (v_user, 'reply', 'reply_report', p_reply, '/#/msgs?report='||p_id); end if; end if; return json_build_object('ok', true); end $function$;

-- bk_admin_reset_ads
CREATE OR REPLACE FUNCTION public.bk_admin_reset_ads(p_token text, p_confirm text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; v_safety jsonb; v_count int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_reset_ads', null, true, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  if p_confirm is distinct from 'DELETE ALL AD SQUARES' then raise exception 'confirmation phrase did not match'; end if;
  if sc is null and al is not null then raise exception 'a country must be chosen'; end if;
  select count(*) into v_count from ad_slots where bk_scope_ok(coalesce(country_code,'SY'), sc, al);
  select jsonb_build_object('scope', coalesce(sc,'ALL'), 'ad_slots', coalesce(jsonb_agg(a), '[]'::jsonb)) into v_safety from ad_slots a where bk_scope_ok(coalesce(a.country_code,'SY'), sc, al);
  insert into backup_snapshots (created_by, reason, data) values (uid, 'auto-backup before bk_admin_reset_ads '||coalesce(sc,'ALL'), v_safety);
  delete from ad_slots where bk_scope_ok(coalesce(country_code,'SY'), sc, al);
  return json_build_object('ok', true, 'deleted', v_count, 'scope', coalesce(sc,'ALL'));
end $function$;

-- bk_admin_reset_listings
CREATE OR REPLACE FUNCTION public.bk_admin_reset_listings(p_token text, p_confirm text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; v_backup jsonb; v_count int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_reset_listings', null, true, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  if p_confirm is distinct from 'DELETE ALL LISTINGS' then raise exception 'confirmation phrase did not match'; end if;
  if sc is null and al is not null then raise exception 'a country must be chosen'; end if;
  create temp table _del_ids on commit drop as select id from listings where bk_scope_ok(coalesce(country_code,'SY'), sc, al);
  select count(*) into v_count from _del_ids;
  select jsonb_build_object('scope', coalesce(sc,'ALL'),
    'listings', (select coalesce(jsonb_agg(l), '[]'::jsonb) from listings l where l.id in (select id from _del_ids)),
    'listing_photos', (select coalesce(jsonb_agg(p), '[]'::jsonb) from listing_photos p where p.listing_id in (select id from _del_ids))) into v_backup;
  insert into backup_snapshots (created_by, reason, data) values (uid, 'auto-backup before bk_admin_reset_listings '||coalesce(sc,'ALL'), v_backup);
  delete from ad_slots where linked_listing_id in (select id from _del_ids);
  delete from listing_photos where listing_id in (select id from _del_ids);
  delete from listing_reports where listing_id in (select id from _del_ids);
  delete from saved_listings where listing_id in (select id from _del_ids);
  delete from contact_events where listing_id in (select id from _del_ids);
  delete from price_history where listing_id in (select id from _del_ids);
  delete from listings where id in (select id from _del_ids);
  return json_build_object('ok', true, 'deleted', v_count, 'scope', coalesce(sc,'ALL'));
end $function$;

-- bk_admin_reset_password
CREATE OR REPLACE FUNCTION public.bk_admin_reset_password(p_token text, p_user uuid, p_new_pass text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare v_admin uuid; begin v_admin := bk_admin_uid(p_token); perform public.bk_admin_need(v_admin, ARRAY['passwords']::text[], 'bk_admin_reset_password', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(v_admin, (select country from users where id = p_user)); if exists (select 1 from users where id = p_user and role = 'admin') and not bk_admin_is_super(v_admin) then raise exception 'super admin only'; end if; if length(p_new_pass) < 6 then raise exception 'password too short'; end if; update users set pass_hash = crypt(encode(digest('balkoun:'||p_new_pass,'sha256'),'hex'), gen_salt('bf')) where id = p_user; return json_build_object('ok', true); end $function$;

-- bk_admin_reset_users
CREATE OR REPLACE FUNCTION public.bk_admin_reset_users(p_token text, p_confirm text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; v_safety jsonb; v_count int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_reset_users', null, true, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  if p_confirm is distinct from 'DELETE ALL USERS' then raise exception 'confirmation phrase did not match'; end if;
  if sc is null and al is not null then raise exception 'a country must be chosen'; end if;
  select count(*) into v_count from users where role is distinct from 'admin' and bk_scope_ok(coalesce(country,'SY'), sc, al);
  select jsonb_build_object('scope', coalesce(sc,'ALL'), 'users', coalesce(jsonb_agg(u), '[]'::jsonb)) into v_safety from users u where role is distinct from 'admin' and bk_scope_ok(coalesce(u.country,'SY'), sc, al);
  insert into backup_snapshots (created_by, reason, data) values (uid, 'auto-backup before bk_admin_reset_users '||coalesce(sc,'ALL'), v_safety);
  delete from users where role is distinct from 'admin' and bk_scope_ok(coalesce(country,'SY'), sc, al);
  return json_build_object('ok', true, 'deleted', v_count, 'scope', coalesce(sc,'ALL'));
end $function$;

-- bk_admin_restore_backup
CREATE OR REPLACE FUNCTION public.bk_admin_restore_backup(p_token text, p_data jsonb, p_confirm text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_safety jsonb; v_listing_count int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_restore_backup', null, true, null, null);
  if p_confirm is distinct from 'RESTORE FROM BACKUP' then
    raise exception 'confirmation phrase did not match';
  end if;
  if p_data is null or not (p_data ? 'listings') then
    raise exception 'this does not look like a valid Balkoun backup file';
  end if;

  select jsonb_build_object(
    'listings', (select coalesce(jsonb_agg(l), '[]'::jsonb) from listings l),
    'listing_photos', (select coalesce(jsonb_agg(p), '[]'::jsonb) from listing_photos p),
    'ad_slots', (select coalesce(jsonb_agg(a), '[]'::jsonb) from ad_slots a)
  ) into v_safety;
  insert into backup_snapshots (created_by, reason, data)
    values (uid, 'auto-backup before bk_admin_restore_backup', v_safety);

  truncate table listing_photos, listing_reports, saved_listings, contact_events, price_history, listings, ad_slots;

  insert into listings select * from jsonb_populate_recordset(null::listings, p_data->'listings');
  if p_data ? 'listing_photos' then
    insert into listing_photos select * from jsonb_populate_recordset(null::listing_photos, p_data->'listing_photos');
  end if;
  if p_data ? 'ad_slots' then
    insert into ad_slots select * from jsonb_populate_recordset(null::ad_slots, p_data->'ad_slots');
  end if;
  if p_data ? 'site_content' and jsonb_array_length(p_data->'site_content') > 0 then
    update site_content sc set (
      hero_enabled, hero_ar, hero_en, hero_de, hero_sub_ar, hero_sub_en, hero_sub_de,
      stats_enabled, stats_areas_num, stats_listings_num, stats_use_real_count,
      stats1_ar, stats1_en, stats1_de, stats2_ar, stats2_en, stats2_de,
      fb_url, ig_url, yt_url, tiktok_url, wa_number, phone_number, email_address,
      ad_tag_enabled, ad_tag_size, ad_tag_ar, ad_tag_en, ad_tag_de,
      ad_square_size, ad_use_icons, ad_roominfo_size, ad_location_enabled, ad_location_size,
      ad_text_color, ad_shade_color, featured_badge_enabled, featured_badge_ar, featured_badge_en,
      featured_badge_de, featured_brightness, card_min_width, new_badge_hours, storage_limit_mb
    ) = (
      select r.hero_enabled, r.hero_ar, r.hero_en, r.hero_de, r.hero_sub_ar, r.hero_sub_en, r.hero_sub_de,
        r.stats_enabled, r.stats_areas_num, r.stats_listings_num, r.stats_use_real_count,
        r.stats1_ar, r.stats1_en, r.stats1_de, r.stats2_ar, r.stats2_en, r.stats2_de,
        r.fb_url, r.ig_url, r.yt_url, r.tiktok_url, r.wa_number, r.phone_number, r.email_address,
        r.ad_tag_enabled, r.ad_tag_size, r.ad_tag_ar, r.ad_tag_en, r.ad_tag_de,
        r.ad_square_size, r.ad_use_icons, r.ad_roominfo_size, r.ad_location_enabled, r.ad_location_size,
        r.ad_text_color, r.ad_shade_color, r.featured_badge_enabled, r.featured_badge_ar, r.featured_badge_en,
        r.featured_badge_de, r.featured_brightness, r.card_min_width, r.new_badge_hours, r.storage_limit_mb
      from jsonb_populate_record(null::site_content, p_data->'site_content'->0) r
    )
    where sc.id = 1;
  end if;

  perform setval(pg_get_serial_sequence('listings','id'), coalesce((select max(id) from listings),1));
  perform setval(pg_get_serial_sequence('listing_photos','id'), coalesce((select max(id) from listing_photos),1));
  perform setval(pg_get_serial_sequence('ad_slots','id'), coalesce((select max(id) from ad_slots),1));

  select count(*) into v_listing_count from listings;
  return json_build_object('ok', true, 'restored_listings', v_listing_count);
end $function$;

-- bk_admin_review_set
CREATE OR REPLACE FUNCTION public.bk_admin_review_set(p_token text, p_target uuid, p_stars integer, p_body text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare v_admin uuid; begin v_admin := bk_admin_uid(p_token); perform public.bk_admin_need(v_admin, ARRAY['reviews']::text[], 'bk_admin_review_set', (select coalesce(country,'SY') from users where id=p_target), true, left(coalesce(p_target::text,''),300), (select coalesce(country,'SY') from users where id=p_target)); perform bk_admin_guard(v_admin, (select country from users where id = p_target)); if p_stars < 1 or p_stars > 5 then raise exception 'bad rating'; end if; insert into reviews (target_user, author_user, stars, body) values (p_target, v_admin, p_stars, p_body) on conflict (target_user, author_user) do update set stars=excluded.stars, body=excluded.body, created_at=now(); return json_build_object('ok', true); end $function$;

-- bk_admin_reviews
CREATE OR REPLACE FUNCTION public.bk_admin_reviews(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['reviews']::text[], 'bk_admin_reviews', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select r.id, r.stars, r.body, r.created_at,
           trim(coalesce(au.name,'')||' '||coalesce(au.family_name,'')) as author_name, au.phone as author_phone,
           trim(coalesce(tu.name,'')||' '||coalesce(tu.family_name,'')) as target_name, tu.phone as target_phone,
           coalesce(tu.country,'SY') as country_code
      from reviews r join users au on au.id = r.author_user join users tu on tu.id = r.target_user
     where bk_scope_ok(coalesce(tu.country,'SY'), sc, al)
     order by r.created_at desc limit 300) x), '[]'::json);
end $function$;

-- bk_admin_reward_adjust
CREATE OR REPLACE FUNCTION public.bk_admin_reward_adjust(p_token text, p_user uuid, p_delta integer, p_note text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['rewards']::text[], 'bk_admin_reward_adjust', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user));
  if p_delta is null or p_delta = 0 or abs(p_delta) > 50 then return json_build_object('error', 'baddelta'); end if;
  insert into reward_events (user_id, kind, delta, note, created_by) values (p_user, case when p_delta > 0 then 'granted' else 'revoked' end, p_delta, nullif(trim(coalesce(p_note,'')), ''), uid);
  return bk_reward_balance(p_user);
end $function$;

-- bk_admin_rewards
CREATE OR REPLACE FUNCTION public.bk_admin_rewards(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; cfg jsonb := bk_reward_cfg();
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['rewards']::text[], 'bk_admin_rewards', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return json_build_object(
    'cfg', cfg,
    'balances', coalesce((select json_agg(x order by x.credits desc, x.points desc) from (
        select u.id as user_id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no, u.phone, u.country,
               (select name from agencies a where a.user_id = u.id and a.status = 'approved' limit 1) as agency,
               coalesce(sum(case e.kind when 'point' then 1 when 'point_revoked' then -1 else 0 end), 0)::int as points,
               coalesce(sum(case when e.kind in ('earned','welcome','used','granted','revoked') then e.delta else 0 end), 0)::int as credits,
               (select a.expires_at from ad_slots a join listings l on l.id = a.linked_listing_id where l.user_id = u.id and a.source = 'reward' and a.enabled and a.expires_at > now() order by a.expires_at desc limit 1) as active_until,
               bk_reward_window_end(cfg, u.id) as window_end
          from users u join reward_events e on e.user_id = u.id
         where bk_scope_ok(u.country, sc, al) group by u.id) x), '[]'::json),
    'events', coalesce((select json_agg(x) from (
        select e.id, e.kind, e.delta, e.note, e.created_at, e.listing_id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no
          from reward_events e join users u on u.id = e.user_id where bk_scope_ok(u.country, sc, al) order by e.created_at desc limit 60) x), '[]'::json));
end $function$;

-- bk_admin_save_ad
CREATE OR REPLACE FUNCTION public.bk_admin_save_ad(p_token text, p_id bigint, p_position integer, p_image_url text, p_link_url text, p_label text, p_enabled boolean, p_media_type text, p_linked_listing_id bigint, p_image_urls jsonb, p_video_embed_url text, p_sponsor_name text DEFAULT NULL::text, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_overlay_top text DEFAULT NULL::text, p_overlay_bottom text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_id bigint; v_pos int; v_code text; v_active public.engagements; v_title text; v_lref text; v_c text := coalesce(p_country,'SY'); v_was_on boolean := false;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['ads']::text[], 'bk_admin_save_ad', coalesce((select coalesce(country_code,'SY') from ad_slots where id=p_id),nullif(upper(p_country),'')), true, left(coalesce(p_id::text,''),300), coalesce((select coalesce(country_code,'SY') from ad_slots where id=p_id),nullif(upper(p_country),'')));
  if p_id is not null then select enabled, coalesce(p_country, country_code) into v_was_on, v_c from ad_slots where id = p_id; end if;
  -- the cap: a square that is new, or switched on just now, needs a free place (editing one already on never fails)
  if coalesce(p_enabled,true) and not coalesce(v_was_on,false)
     and bk_ad_squares_used(v_c, p_id) >= bk_ad_max_squares() then
    raise exception 'max_squares';
  end if;
  if p_id is null then
    select coalesce(max(position),0)+1 into v_pos from ad_slots where country_code=v_c;
    insert into ad_slots (position, image_url, link_url, label, enabled, media_type, linked_listing_id, image_urls, video_embed_url, sponsor_name, starts_at, expires_at, overlay_top, overlay_bottom, country_code)
      values (v_pos, p_image_url, p_link_url, p_label, coalesce(p_enabled,true), coalesce(p_media_type,'image'), p_linked_listing_id,
        coalesce(p_image_urls,'[]'::jsonb), p_video_embed_url, p_sponsor_name, p_starts_at, p_expires_at, p_overlay_top, p_overlay_bottom, v_c)
      returning id into v_id;
  else
    update ad_slots set image_url=p_image_url, link_url=p_link_url, label=p_label, enabled=coalesce(p_enabled,true), media_type=coalesce(p_media_type,'image'),
      linked_listing_id=p_linked_listing_id, image_urls=coalesce(p_image_urls,'[]'::jsonb), video_embed_url=p_video_embed_url, sponsor_name=p_sponsor_name,
      starts_at=p_starts_at, expires_at=p_expires_at, overlay_top=p_overlay_top, overlay_bottom=p_overlay_bottom, country_code=coalesce(p_country,country_code) where id=p_id;
    v_id := p_id;
  end if;
  select ref into v_lref from listings where id=p_linked_listing_id;
  v_title := coalesce(nullif(p_label,''), nullif(p_sponsor_name,''), v_lref, 'مربع #'||v_id);
  select * into v_active from public.engagements where kind='ad' and ref_id=v_id and status='active' order by created_at desc limit 1;
  if coalesce(p_enabled,true) then
    if v_active.id is null then
      v_active := public.bk_engage('ad', v_id, v_lref, v_title, p_sponsor_name, null, p_starts_at, p_expires_at, null, uid);
    else
      update public.engagements set title=v_title, client_name=coalesce(nullif(p_sponsor_name,''),client_name), starts_at=coalesce(p_starts_at,starts_at), ends_at=p_expires_at, ref_text=coalesce(v_lref,ref_text)
       where id=v_active.id;
    end if;
    v_code := v_active.code;
  else
    perform public.bk_engage_end('ad', v_id, null, 'ended');
  end if;
  update engagements set country_code=(select country_code from ad_slots where id=v_id) where kind='ad' and ref_id=v_id;
  return json_build_object('ok', true, 'id', v_id, 'code', v_code);
end $function$;

-- bk_admin_search
CREATE OR REPLACE FUNCTION public.bk_admin_search(p_token text, p_q text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; q text; qd text; num text; pat text; dpat text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_search', null, false, left(coalesce(p_q::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country);
  q := trim(coalesce(p_q, ''));
  if length(q) < 2 then return json_build_object('q', q); end if;
  qd := regexp_replace(q, '\D', '', 'g');                                      -- the digits (a phone, a number)
  num := substring(q from '(\d{3,9})\s*$');                                     -- a trailing number (SY10460, SYW1037, #742)
  pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  dpat := case when length(qd) >= 6 then '%' || right(qd, 9) || '%' else null end;   -- last 9 digits: local or international format
  return json_build_object('q', q,
    'listings', (select coalesce(json_agg(x), '[]'::json) from (
      select l.id, l.ref, l.status, l.deal, l.property_type, l.price_usd, a.name_ar as area, g.name_ar as gov,
             trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as owner, l.country_code
        from listings l left join areas a on a.id = l.area_id left join governorates g on g.id = l.governorate_id left join users u on u.id = l.user_id
       where bk_admin_country_ok(uid, coalesce(l.country_code,'SY')) and (sc is null or coalesce(l.country_code,'SY') = sc)
         and (upper(l.ref) = upper(regexp_replace(q, '\s|-', '', 'g')) or (num is not null and (l.ref like '%' || num or l.id::text = num))
              or (dpat is not null and regexp_replace(coalesce(l.contact_phone,''), '\D', '', 'g') like dpat)
              or l.description ilike pat or l.landmark ilike pat)
       order by (upper(l.ref) = upper(regexp_replace(q, '\s|-', '', 'g'))) desc, l.created_at desc limit 8) x),
    'users', (select coalesce(json_agg(x), '[]'::json) from (
      select u.id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no, u.phone, u.email, u.account_type,
             u.blocked,
             (select count(*) from listings l where l.user_id = u.id and l.status in ('live','pending')) as listings,
             (select count(*) from wanted w where w.user_id = u.id and w.status in ('open','pending')) as requests
        from users u
       where bk_admin_country_ok(uid, coalesce(u.country,'SY')) and (sc is null or coalesce(u.country,'SY') = sc)
         and ((trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,''))) ilike pat or u.member_no ilike pat or u.email ilike pat
              or (dpat is not null and regexp_replace(coalesce(u.phone,''), '\D', '', 'g') like dpat))
       order by u.created_at desc limit 8) x),
    'agencies', (select coalesce(json_agg(x), '[]'::json) from (
      select ag.id, ag.name, ag.status, ag.phone, ag.user_id
        from agencies ag
       where bk_admin_country_ok(uid, coalesce(ag.country_code,'SY')) and (sc is null or coalesce(ag.country_code,'SY') = sc)
         and (ag.name ilike pat or (dpat is not null and (regexp_replace(coalesce(ag.phone,''), '\D', '', 'g') like dpat or regexp_replace(coalesce(ag.whatsapp,''), '\D', '', 'g') like dpat)))
       order by ag.created_at desc limit 8) x),
    'requests', (select coalesce(json_agg(x), '[]'::json) from (
      select w.id, w.ref, w.status, w.deal, w.gov_name, coalesce(w.title,'') as title
        from wanted w
       where bk_admin_country_ok(uid, coalesce(w.country_code,'SY')) and (sc is null or coalesce(w.country_code,'SY') = sc)
         and (upper(coalesce(w.ref,'')) = upper(regexp_replace(q, '\s|-', '', 'g')) or (num is not null and (w.ref like '%' || num or w.id::text = num))
              or w.title ilike pat or w.description ilike pat)
       order by w.created_at desc limit 8) x),
    'drafts', (select coalesce(json_agg(x), '[]'::json) from (
      select d.id, d.status, d.source, d.sender_name, d.listing_id, left(coalesce(d.summary, d.raw_text, ''), 90) as text
        from intake_drafts d
       where bk_admin_country_ok(uid, coalesce(d.country_code,'SY')) and (sc is null or coalesce(d.country_code,'SY') = sc)
         and ((num is not null and d.id::text = num and q ~ '^\s*#') or (dpat is not null and regexp_replace(coalesce(d.chat_id,''), '\D', '', 'g') like dpat)
              or d.sender_name ilike pat)
       order by d.created_at desc limit 8) x));
end $function$;

-- bk_admin_send_notification
CREATE OR REPLACE FUNCTION public.bk_admin_send_notification(p_token text, p_user uuid, p_all boolean, p_title text, p_body text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; sc text; al text[]; v_count int; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['notify']::text[], 'bk_admin_send_notification', (case when p_user is not null then (select coalesce(country,'SY') from users where id=p_user) else nullif(upper(p_country),'') end), true, left(coalesce(p_user::text,''),300), (case when p_user is not null then (select coalesce(country,'SY') from users where id=p_user) else nullif(upper(p_country),'') end)); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid); if length(trim(coalesce(p_title,'')))<1 then raise exception 'title required'; end if; if coalesce(p_all,false) then insert into notifications (user_id, type, title, body) select id, 'admin_msg', p_title, p_body from users where role <> 'admin' and bk_scope_ok(country, sc, al); get diagnostics v_count = row_count; else perform bk_admin_guard(uid, (select country from users where id = p_user)); insert into notifications (user_id, type, title, body) values (p_user, 'admin_msg', p_title, p_body); v_count := 1; end if; return json_build_object('ok', true, 'sent', v_count, 'scope', coalesce(sc,'ALL')); end $function$;

-- bk_admin_set_account_type
CREATE OR REPLACE FUNCTION public.bk_admin_set_account_type(p_token text, p_user uuid, p_type text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_set_account_type', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user));
  if p_type not in ('member','broker','agency') then return json_build_object('error','badtype'); end if;
  update users set account_type = p_type where id = p_user and role <> 'admin';
  return json_build_object('ok', true);
end $function$;

-- bk_admin_set_agency_auto
CREATE OR REPLACE FUNCTION public.bk_admin_set_agency_auto(p_token text, p_on boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_set_agency_auto', null, true, left(coalesce(p_on::text,''),300), null);
  update site_settings set agency_auto_approve = p_on where id = 1;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_set_approval_mode
CREATE OR REPLACE FUNCTION public.bk_admin_set_approval_mode(p_token text, p_require boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['settings']::text[], 'bk_admin_set_approval_mode', null, true, left(coalesce(p_require::text,''),300), null);
  update site_settings set require_approval = p_require where id = 1;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_set_card_logo
CREATE OR REPLACE FUNCTION public.bk_admin_set_card_logo(p_token text, p_user uuid, p_on boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_set_card_logo', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user)); update users set card_logo = p_on where id = p_user and role <> 'admin'; return json_build_object('ok', true); end $function$;

-- bk_admin_set_content
CREATE OR REPLACE FUNCTION public.bk_admin_set_content(p_token text, p_patch jsonb, p_country text DEFAULT 'SY'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; n int; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['homepage','design','contact','settings','bot_cfg','types','ads','social','verify']::text[], 'bk_admin_set_content', nullif(upper(p_country),''), true, left(coalesce(p_patch::text,''),300), nullif(upper(p_country),'')); perform bk_admin_guard(uid, coalesce(p_country,'SY')); update site_content set hero_enabled = coalesce((p_patch->>'hero_enabled')::boolean, hero_enabled), hero_ar = coalesce(p_patch->>'hero_ar', hero_ar), hero_en = coalesce(p_patch->>'hero_en', hero_en), hero_de = coalesce(p_patch->>'hero_de', hero_de), hero_sub_ar = coalesce(p_patch->>'hero_sub_ar', hero_sub_ar), hero_sub_en = coalesce(p_patch->>'hero_sub_en', hero_sub_en), hero_sub_de = coalesce(p_patch->>'hero_sub_de', hero_sub_de), hero_bg_type = coalesce(p_patch->>'hero_bg_type', hero_bg_type), hero_bg_video_url = coalesce(p_patch->>'hero_bg_video_url', hero_bg_video_url), hero_bg_photo_url = coalesce(p_patch->>'hero_bg_photo_url', hero_bg_photo_url), hero_gap = coalesce((p_patch->>'hero_gap')::int, hero_gap), hero_bg_video_speed = coalesce((p_patch->>'hero_bg_video_speed')::int, hero_bg_video_speed), hero_title_size = coalesce(p_patch->>'hero_title_size', hero_title_size), hero_title_color = coalesce(p_patch->>'hero_title_color', hero_title_color), hero_sub_color = coalesce(p_patch->>'hero_sub_color', hero_sub_color), banner_enabled = coalesce((p_patch->>'banner_enabled')::boolean, banner_enabled), banner_media_type = coalesce(p_patch->>'banner_media_type', banner_media_type), banner_image_url = coalesce(p_patch->>'banner_image_url', banner_image_url), banner_video_url = coalesce(p_patch->>'banner_video_url', banner_video_url), banner_link_url = coalesce(p_patch->>'banner_link_url', banner_link_url), banner_items = coalesce(p_patch->>'banner_items', banner_items), banners_config = coalesce(p_patch->>'banners_config', banners_config), banner_rotation_seconds = coalesce((p_patch->>'banner_rotation_seconds')::int, banner_rotation_seconds), banner_transition = coalesce(p_patch->>'banner_transition', banner_transition), banner_size = coalesce(p_patch->>'banner_size', banner_size), banner_custom_w = coalesce((p_patch->>'banner_custom_w')::int, banner_custom_w), banner_custom_h = coalesce((p_patch->>'banner_custom_h')::int, banner_custom_h), banner_gap = coalesce((p_patch->>'banner_gap')::int, banner_gap), banner_text_enabled = coalesce((p_patch->>'banner_text_enabled')::boolean, banner_text_enabled), banner_text_size = coalesce((p_patch->>'banner_text_size')::int, banner_text_size), banner_text_color = coalesce(p_patch->>'banner_text_color', banner_text_color), banner_text_ar = coalesce(p_patch->>'banner_text_ar', banner_text_ar), banner_text_en = coalesce(p_patch->>'banner_text_en', banner_text_en), banner_text_de = coalesce(p_patch->>'banner_text_de', banner_text_de), stats_enabled = coalesce((p_patch->>'stats_enabled')::boolean, stats_enabled), stats_areas_num = coalesce(p_patch->>'stats_areas_num', stats_areas_num), stats_listings_num = coalesce(p_patch->>'stats_listings_num', stats_listings_num), stats_use_real_count = coalesce((p_patch->>'stats_use_real_count')::boolean, stats_use_real_count), stats1_ar = coalesce(p_patch->>'stats1_ar', stats1_ar), stats1_en = coalesce(p_patch->>'stats1_en', stats1_en), stats1_de = coalesce(p_patch->>'stats1_de', stats1_de), stats2_ar = coalesce(p_patch->>'stats2_ar', stats2_ar), stats2_en = coalesce(p_patch->>'stats2_en', stats2_en), stats2_de = coalesce(p_patch->>'stats2_de', stats2_de), fb_url = coalesce(p_patch->>'fb_url', fb_url), ig_url = coalesce(p_patch->>'ig_url', ig_url), yt_url = coalesce(p_patch->>'yt_url', yt_url), fb_name = coalesce(p_patch->>'fb_name', fb_name), ig_name = coalesce(p_patch->>'ig_name', ig_name), yt_name = coalesce(p_patch->>'yt_name', yt_name), tiktok_name = coalesce(p_patch->>'tiktok_name', tiktok_name), tiktok_url = coalesce(p_patch->>'tiktok_url', tiktok_url), wa_number = coalesce(p_patch->>'wa_number', wa_number), phone_number = coalesce(p_patch->>'phone_number', phone_number), email_address = coalesce(p_patch->>'email_address', email_address), ad_tag_enabled = coalesce((p_patch->>'ad_tag_enabled')::boolean, ad_tag_enabled), ad_tag_size = coalesce((p_patch->>'ad_tag_size')::int, ad_tag_size), ad_tag_ar = coalesce(p_patch->>'ad_tag_ar', ad_tag_ar), ad_tag_en = coalesce(p_patch->>'ad_tag_en', ad_tag_en), ad_tag_de = coalesce(p_patch->>'ad_tag_de', ad_tag_de), ad_square_size = coalesce((p_patch->>'ad_square_size')::int, ad_square_size), ad_carousel_seconds = coalesce((p_patch->>'ad_carousel_seconds')::numeric, ad_carousel_seconds), ad_carousel_direction = coalesce(p_patch->>'ad_carousel_direction', ad_carousel_direction), ad_carousel_gap = coalesce((p_patch->>'ad_carousel_gap')::int, ad_carousel_gap), ad_use_icons = coalesce((p_patch->>'ad_use_icons')::boolean, ad_use_icons), ad_roominfo_size = coalesce((p_patch->>'ad_roominfo_size')::int, ad_roominfo_size), ad_location_enabled = coalesce((p_patch->>'ad_location_enabled')::boolean, ad_location_enabled), ad_location_size = coalesce((p_patch->>'ad_location_size')::int, ad_location_size), ad_text_color = coalesce(p_patch->>'ad_text_color', ad_text_color), ad_shade_color = coalesce(p_patch->>'ad_shade_color', ad_shade_color), featured_badge_enabled = coalesce((p_patch->>'featured_badge_enabled')::boolean, featured_badge_enabled), featured_badge_ar = coalesce(p_patch->>'featured_badge_ar', featured_badge_ar), featured_badge_en = coalesce(p_patch->>'featured_badge_en', featured_badge_en), featured_badge_de = coalesce(p_patch->>'featured_badge_de', featured_badge_de), featured_brightness = coalesce((p_patch->>'featured_brightness')::int, featured_brightness), card_min_width = coalesce((p_patch->>'card_min_width')::int, card_min_width), card_min_width_mobile = coalesce((p_patch->>'card_min_width_mobile')::int, card_min_width_mobile), new_badge_hours = coalesce((p_patch->>'new_badge_hours')::int, new_badge_hours), storage_limit_mb = coalesce((p_patch->>'storage_limit_mb')::int, storage_limit_mb), syp_rate = coalesce((p_patch->>'syp_rate')::int, syp_rate), extras = jsonb_strip_nulls(coalesce(extras, '{}'::jsonb) || coalesce(p_patch->'extras', '{}'::jsonb)) where country_code = coalesce(p_country,'SY'); get diagnostics n = row_count; if n = 0 then raise exception 'no settings row for country %', p_country; end if; return json_build_object('ok', true); end $function$;

-- bk_admin_set_level
CREATE OR REPLACE FUNCTION public.bk_admin_set_level(p_token text, p_user uuid, p_level text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_set_level', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user)); update users set level = p_level where id = p_user and role <> 'admin'; return json_build_object('ok', true); end $function$;

-- bk_admin_set_permissions
CREATE OR REPLACE FUNCTION public.bk_admin_set_permissions(p_token text, p_admin uuid, p_permissions text[], p_countries text[] DEFAULT NULL::text[], p_notify boolean DEFAULT NULL::boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['__super__']::text[], 'bk_admin_set_permissions', null, true, left(coalesce(p_admin::text,''),300), null);
  if not bk_admin_is_super(uid) then raise exception 'super admin only'; end if;
  update users set permissions = coalesce(p_permissions, permissions),
                   admin_countries = case when p_countries is null then admin_countries when cardinality(p_countries)=0 then null else (select array_agg(upper(c)) from unnest(p_countries) c) end,
                   notify_tg = coalesce(p_notify, notify_tg)
   where id = p_admin and role = 'admin' and not is_super_admin;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_set_priority
CREATE OR REPLACE FUNCTION public.bk_admin_set_priority(p_token text, p_kind text, p_id bigint, p_priority text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['feedback','reports','tickets']::text[], 'bk_admin_set_priority', null, true, left(coalesce(p_id::text,''),300), null); perform bk_admin_guard_opt(uid, case when p_kind = 'feedback' then (select country_code from feedback where id = p_id) else (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id) end); if p_priority not in ('low','normal','high','urgent') then raise exception 'bad priority'; end if; if p_kind = 'feedback' then update feedback set priority = p_priority where id = p_id; elsif p_kind = 'report' then update listing_reports set priority = p_priority where id = p_id; end if; return json_build_object('ok', true); end $function$;

-- bk_admin_set_skip_review
CREATE OR REPLACE FUNCTION public.bk_admin_set_skip_review(p_token text, p_user uuid, p_skip boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_set_skip_review', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user)); perform bk_admin_guard(uid, (select country from users where id = p_user)); update users set skip_review = p_skip where id = p_user; return json_build_object('ok', true); end $function$;

-- bk_admin_set_solved
CREATE OR REPLACE FUNCTION public.bk_admin_set_solved(p_token text, p_kind text, p_id bigint, p_solved boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['feedback','reports']::text[], 'bk_admin_set_solved', null, true, left(coalesce(p_id::text,''),300), null); perform bk_admin_guard_opt(uid, case when p_kind = 'feedback' then (select country_code from feedback where id = p_id) else (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id) end); if p_kind = 'feedback' then update feedback set handled = p_solved where id = p_id; elsif p_kind = 'report' then update listing_reports set resolved = p_solved where id = p_id; end if; return json_build_object('ok', true); end $function$;

-- bk_admin_set_status
CREATE OR REPLACE FUNCTION public.bk_admin_set_status(p_token text, p_listing bigint, p_status text, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; v_owner uuid; v_lang text; v_ref text; v_title text; v_body text; v_reason text; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['listings_edit']::text[], 'bk_admin_set_status', (select coalesce(country_code,'SY') from listings where id=p_listing), true, left(coalesce(p_listing::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing)); perform bk_admin_guard(uid, (select country_code from listings where id = p_listing)); if p_status not in ('live','hidden','pending','rejected','sold','expired') then raise exception 'bad status'; end if; v_reason := nullif(left(trim(coalesce(p_reason,'')),500),''); update listings set status = p_status, published_at = case when p_status='live' then now() else published_at end, reject_reason = case when p_status='rejected' then v_reason when p_status='live' then null else reject_reason end, rejected_at = case when p_status='rejected' then now() else rejected_at end where id = p_listing returning user_id, ref into v_owner, v_ref; if v_owner is not null and p_status in ('live','rejected') then select coalesce(lang,'ar') into v_lang from users where id = v_owner; if p_status='live' then v_title := case v_lang when 'en' then 'Your listing is published' when 'de' then 'Ihre Anzeige ist online' when 'fr' then 'Votre annonce est en ligne' else 'تم نشر إعلانك' end; v_body := case v_lang when 'en' then 'Listing '||coalesce(v_ref,'')||' is now live on Balkoun.' when 'de' then 'Anzeige '||coalesce(v_ref,'')||' ist jetzt auf Balkoun online.' when 'fr' then 'L''annonce '||coalesce(v_ref,'')||' est maintenant en ligne sur Balkoun.' else 'الإعلان '||coalesce(v_ref,'')||' منشور الآن على بلكون.' end; else v_title := case v_lang when 'en' then 'Your listing was not approved' when 'de' then 'Ihre Anzeige wurde nicht freigegeben' when 'fr' then 'Votre annonce n''a pas été approuvée' else 'لم تتم الموافقة على إعلانك' end; v_body := case v_lang when 'en' then 'Listing '||coalesce(v_ref,'')||coalesce(': '||v_reason,'')||'. Edit it from “My listings” and publish again.' when 'de' then 'Anzeige '||coalesce(v_ref,'')||coalesce(': '||v_reason,'')||'. Bearbeiten Sie sie unter „Meine Anzeigen“ und veröffentlichen Sie erneut.' when 'fr' then 'Annonce '||coalesce(v_ref,'')||coalesce(' : '||v_reason,'')||'. Modifiez-la dans « Mes annonces » et republiez.' else 'الإعلان '||coalesce(v_ref,'')||coalesce(': '||v_reason,'')||'. عدّله من «إعلاناتي» وانشره مجدداً.' end; end if; insert into notifications (user_id, type, title, body, link) values (v_owner, 'system', v_title, v_body, '/mine'); end if; return json_build_object('ok', true); end $function$;

-- bk_admin_stats
CREATE OR REPLACE FUNCTION public.bk_admin_stats(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare v_admin uuid; sc text; al text[]; begin v_admin := bk_admin_uid(p_token); perform public.bk_admin_need(v_admin, null::text[], 'bk_admin_stats', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(v_admin, p_country); al := bk_admin_allowed(v_admin); return json_build_object( 'scope', sc, 'views_today', (select count(*) from page_views where bk_scope_ok(site_country,sc,al) and created_at > current_date), 'views_week', (select count(*) from page_views where bk_scope_ok(site_country,sc,al) and created_at > now() - interval '7 days'), 'views_total', (select count(*) from page_views where bk_scope_ok(site_country,sc,al)), 'visitors_week', (select count(distinct coalesce(user_id::text, path||date_trunc('day',created_at)::text)) from page_views where bk_scope_ok(site_country,sc,al) and created_at > now() - interval '7 days'), 'members_total', (select count(*) from users where role <> 'admin' and bk_scope_ok(country,sc,al)), 'members_week', (select count(*) from users where role <> 'admin' and created_at > now() - interval '7 days' and bk_scope_ok(country,sc,al)), 'online_now', (select count(*) from online_presence op join users ou on ou.id = op.user_id where op.last_seen > now() - interval '5 minutes' and bk_scope_ok(ou.country,sc,al)), 'online_list', coalesce((select json_agg(x) from ( select trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as name, u.id, p.last_seen from online_presence p join users u on u.id = p.user_id where p.last_seen > now() - interval '5 minutes' and bk_scope_ok(u.country,sc,al) order by p.last_seen desc limit 50) x), '[]'::json), 'by_country', coalesce((select json_object_agg(country, n) from ( select coalesce(country,'unknown') country, count(*) n from page_views where bk_scope_ok(site_country,sc,al) and created_at > now() - interval '30 days' group by 1 order by 2 desc limit 15) x), '{}'::json), 'by_site', coalesce((select json_object_agg(site_country, n) from ( select coalesce(site_country,'SY') site_country, count(*) n from page_views where bk_scope_ok(site_country,sc,al) and created_at > now() - interval '30 days' group by 1 order by 2 desc limit 30) x), '{}'::json), 'by_view', coalesce((select json_object_agg(view, n) from ( select coalesce(view,'home') view, count(*) n from page_views where bk_scope_ok(site_country,sc,al) and created_at > now() - interval '30 days' group by 1 order by 2 desc limit 15) y), '{}'::json)); end $function$;

-- bk_admin_storage_report
CREATE OR REPLACE FUNCTION public.bk_admin_storage_report(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['storage']::text[], 'bk_admin_storage_report', null, false, null, null);
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
    , owners as (
      select coalesce(a.country_code,'SY') as cc, row_to_json(a)::text as t from ad_slots a
      union all select coalesce(s.country_code,'SY'), row_to_json(s)::text from site_content s
      union all select coalesce(p.country_code,'SY'), row_to_json(p)::text from projects p
    ), kc as (
      select k.bytes, coalesce(
        case when k.kind = 'listings' then (select coalesce(l.country_code,'SY') from listings l where l.id::text = (case when k.f1 in ('photos','videos') and k.f2 = 'listings' then k.f3 else k.f1 end)) end,
        case when k.kind not in ('trash','orphans','stale_og','listings','avatars') then (select case when count(distinct o.cc) = 1 then min(o.cc) when count(distinct o.cc) > 1 then '_shared' end from owners o where position(k.name in o.t) > 0) end,
        '_shared') as cc
      from k
    )
    select json_build_object(
      'by_country', coalesce((select json_agg(x order by x.bytes desc) from (select cc, count(*) as files, sum(bytes) as bytes from kc group by cc) x), '[]'::json),
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

-- bk_admin_storage_usage
CREATE OR REPLACE FUNCTION public.bk_admin_storage_usage(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; v_bytes bigint; v_count int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_storage_usage', null, false, null, null);
  select coalesce(sum((metadata->>'size')::bigint), 0), count(*)
    into v_bytes, v_count
    from storage.objects where bucket_id = 'photos';
  return json_build_object('bytes', v_bytes, 'files', v_count);
end $function$;

-- bk_admin_switch_to_user
CREATE OR REPLACE FUNCTION public.bk_admin_switch_to_user(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; u users; tok text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_switch_to_user', null, false, null, null);
  select * into u from users where id = uid;
  if u.id is null then return json_build_object('error','nouser'); end if;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'token',tok);
end $function$;

-- bk_admin_tg_unpair
CREATE OR REPLACE FUNCTION public.bk_admin_tg_unpair(p_token text, p_admin uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; target uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_tg_unpair', null, true, left(coalesce(p_admin::text,''),300), null); target := coalesce(p_admin, uid);
  if target <> uid and not bk_admin_is_super(uid) then raise exception 'super admin only'; end if;
  update users set tg_chat_id = null, tg_name = null, tg_paired_at = null where id = target;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_ticket_add
CREATE OR REPLACE FUNCTION public.bk_admin_ticket_add(p_token text, p_title text, p_body text DEFAULT NULL::text, p_contact text DEFAULT NULL::text, p_priority text DEFAULT 'normal'::text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; t tickets; v_cc text; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['tickets']::text[], 'bk_admin_ticket_add', nullif(upper(p_country),''), true, left(coalesce(p_title::text,''),300), nullif(upper(p_country),'')); perform bk_admin_guard(uid, upper(coalesce(nullif(nullif(trim(p_country),''),'ALL'),'SY'))); if length(trim(coalesce(p_title,'')))<2 then raise exception 'title required'; end if; v_cc := upper(coalesce(nullif(nullif(trim(p_country),''),'ALL'),'SY')); insert into tickets (code, country_code, source_kind, title, body, contact, priority, created_by) values (bk_ticket_code(v_cc), v_cc, 'manual', left(trim(p_title),140), nullif(p_body,''), nullif(p_contact,''), case when p_priority in ('low','normal','high','urgent') then p_priority else 'normal' end, uid) returning * into t; return row_to_json(t); end $function$;

-- bk_admin_ticket_delete
CREATE OR REPLACE FUNCTION public.bk_admin_ticket_delete(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['tickets']::text[], 'bk_admin_ticket_delete', (select coalesce(country_code,'SY') from tickets where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from tickets where id=p_id)); perform bk_admin_guard(uid, (select country_code from tickets where id = p_id)); update feedback set ticket_id=null where ticket_id=p_id; update listing_reports set ticket_id=null where ticket_id=p_id; delete from tickets where id=p_id; return json_build_object('ok', true); end $function$;

-- bk_admin_ticket_from
CREATE OR REPLACE FUNCTION public.bk_admin_ticket_from(p_token text, p_kind text, p_id bigint, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; t tickets; f feedback; r listing_reports; v_ref text; v_title text; v_body text; v_contact text; v_link text; v_prio text; v_cc text; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['tickets','feedback','reports']::text[], 'bk_admin_ticket_from', nullif(upper(p_country),''), true, left(coalesce(p_id::text,''),300), nullif(upper(p_country),'')); perform bk_admin_guard_opt(uid, case when p_kind = 'feedback' then (select country_code from feedback where id = p_id) else (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id) end); if p_kind='feedback' then select * into f from feedback where id=p_id; if f.id is null then raise exception 'not found'; end if; if f.ticket_id is not null then select * into t from tickets where id=f.ticket_id; if t.id is not null then return row_to_json(t); end if; end if; v_title := coalesce(f.kind,'feedback')||' — '||coalesce(nullif(f.name,''), (select trim(coalesce(name,'')||' '||coalesce(family_name,'')) from users where id=f.user_id), 'guest'); v_body := f.body; v_contact := coalesce(nullif(f.contact,''), (select phone from users where id=f.user_id)); v_link := '/#/admin:feedback'; v_prio := coalesce(f.priority,'normal'); v_cc := coalesce((select country from users where id=f.user_id), nullif(p_country,'ALL'), 'SY'); insert into tickets (code, country_code, source_kind, source_id, title, body, contact, link, priority, created_by) values (bk_ticket_code(v_cc), upper(v_cc), 'feedback', f.id, left(v_title,140), v_body, v_contact, v_link, case when v_prio in ('low','normal','high','urgent') then v_prio else 'normal' end, uid) returning * into t; update feedback set ticket_id=t.id, handled=true where id=f.id; elsif p_kind='report' then select * into r from listing_reports where id=p_id; if r.id is null then raise exception 'not found'; end if; if r.ticket_id is not null then select * into t from tickets where id=r.ticket_id; if t.id is not null then return row_to_json(t); end if; end if; select ref, country_code into v_ref, v_cc from listings where id=r.listing_id; v_cc := coalesce(v_cc, nullif(p_country,'ALL'), 'SY'); v_title := coalesce(r.reason,'report')||coalesce(' — '||v_ref,''); v_body := r.note; v_contact := (select phone from users where id=r.user_id); v_link := case when r.listing_id is not null then '/#/listing/'||r.listing_id else '/#/admin:reports' end; v_prio := coalesce(r.priority,'normal'); insert into tickets (code, country_code, source_kind, source_id, title, body, contact, link, priority, created_by) values (bk_ticket_code(v_cc), upper(v_cc), 'report', r.id, left(v_title,140), v_body, v_contact, v_link, case when v_prio in ('low','normal','high','urgent') then v_prio else 'normal' end, uid) returning * into t; update listing_reports set ticket_id=t.id, resolved=true where id=r.id; else raise exception 'bad kind'; end if; return row_to_json(t); end $function$;

-- bk_admin_ticket_set
CREATE OR REPLACE FUNCTION public.bk_admin_ticket_set(p_token text, p_id bigint, p_status text DEFAULT NULL::text, p_priority text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_title text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; t tickets; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['tickets']::text[], 'bk_admin_ticket_set', (select coalesce(country_code,'SY') from tickets where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from tickets where id=p_id)); perform bk_admin_guard(uid, (select country_code from tickets where id = p_id)); update tickets set status = case when p_status in ('open','progress','done') then p_status else status end, priority = case when p_priority in ('low','normal','high','urgent') then p_priority else priority end, notes = case when p_notes is null then notes else nullif(p_notes,'') end, title = case when p_title is null or length(trim(p_title))<2 then title else left(trim(p_title),140) end, done_at = case when p_status='done' then coalesce(done_at, now()) when p_status in ('open','progress') then null else done_at end, updated_at = now() where id=p_id returning * into t; if t.id is null then raise exception 'not found'; end if; return row_to_json(t); end $function$;

-- bk_admin_tickets
CREATE OR REPLACE FUNCTION public.bk_admin_tickets(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['tickets']::text[], 'bk_admin_tickets', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by (x.status='done'), case x.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, x.created_at desc) from (
    select t.*, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as created_by_name from tickets t left join users u on u.id=t.created_by
     where bk_scope_ok(t.country_code, sc, al)) x), '[]'::json);
end $function$;

-- bk_admin_todo
CREATE OR REPLACE FUNCTION public.bk_admin_todo(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; sc text; al text[]; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_todo', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid); return json_build_object( 'pending_listings', (select count(*) from listings where status='pending' and bk_scope_ok(country_code,sc,al)), 'pending_agencies', (select count(*) from agencies where status='pending' and bk_scope_ok(country_code,sc,al)), 'pending_wanted', (select count(*) from wanted where status='pending' and bk_scope_ok(country_code,sc,al)), 'intake_review', (select count(*) from intake_drafts where status in ('review','failed') and bk_scope_ok(country_code,sc,al)), 'verify_pending', (select count(*) from verify_tickets where status='pending' and channel='whatsapp' and wa_sent_at is not null and expires_at > now() and bk_scope_ok(coalesce(country_code,'SY'),sc,al)), 'open_reports', (select count(*) from listing_reports r left join listings l on l.id=r.listing_id where not coalesce(r.resolved,false) and ((l.id is null and sc is null) or bk_scope_ok(l.country_code,sc,al))) + (select count(*) from reports where not coalesce(resolved,false)), 'open_feedback', (select count(*) from feedback where not coalesce(handled,false) and ((country_code is null and sc is null) or bk_scope_ok(country_code,sc,al))), 'unread_alerts', (select count(*) from notifications where user_id=uid and not is_read), 'latest', coalesce((select json_agg(x order by x.at desc) from ( (select 'listing' as kind, l.ref as label, l.created_at as at, l.id::text as ref, l.country_code as cc from listings l where l.status='pending' and bk_scope_ok(l.country_code,sc,al) order by l.created_at desc limit 5) union all (select 'agency', a.name, a.created_at, a.id::text, a.country_code from agencies a where a.status='pending' and bk_scope_ok(a.country_code,sc,al) order by a.created_at desc limit 5) union all (select 'wanted', coalesce(w.title, w.gov_name, ''), w.created_at, w.id::text, w.country_code from wanted w where w.status='pending' and bk_scope_ok(w.country_code,sc,al) order by w.created_at desc limit 5) union all (select 'intake', coalesce(d.sender_name, d.chat_id), d.created_at, d.id::text, d.country_code from intake_drafts d where d.status in ('review','failed') and bk_scope_ok(d.country_code,sc,al) order by d.created_at desc limit 5) union all (select 'verify', v.phone, v.wa_sent_at, v.id::text, v.country_code from verify_tickets v where v.status='pending' and v.channel='whatsapp' and v.wa_sent_at is not null and v.expires_at > now() and bk_scope_ok(coalesce(v.country_code,'SY'),sc,al) order by v.wa_sent_at desc limit 5) union all (select 'report', coalesce(r.reason,''), r.created_at, r.id::text, l.country_code from listing_reports r left join listings l on l.id=r.listing_id where not coalesce(r.resolved,false) and ((l.id is null and sc is null) or bk_scope_ok(l.country_code,sc,al)) order by r.created_at desc limit 5) union all (select 'feedback', coalesce(f.kind,'')||': '||left(coalesce(f.body,''),60), f.created_at, f.id::text, f.country_code from feedback f where not coalesce(f.handled,false) and ((f.country_code is null and sc is null) or bk_scope_ok(f.country_code,sc,al)) order by f.created_at desc limit 5) ) x), '[]'::json) ); end $function$;

-- bk_admin_unfeature_listing
CREATE OR REPLACE FUNCTION public.bk_admin_unfeature_listing(p_token text, p_listing bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['featured']::text[], 'bk_admin_unfeature_listing', (select coalesce(country_code,'SY') from listings where id=p_listing), true, left(coalesce(p_listing::text,''),300), (select coalesce(country_code,'SY') from listings where id=p_listing)); perform bk_admin_guard(uid, (select country_code from listings where id = p_listing)); update listings set featured_from = null, featured_until = null, is_featured = false where id = p_listing; perform public.bk_engage_end('featured', p_listing, null, 'cancelled'); return json_build_object('ok', true); end $function$;

-- bk_admin_user_activity
CREATE OR REPLACE FUNCTION public.bk_admin_user_activity(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['users_view','stats']::text[], 'bk_admin_user_activity', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select u.id, u.last_seen_at, u.phone_verified, u.lang, u.country, u.city,
           (select count(*) from listings l where l.user_id=u.id and l.status='live') as live_listings,
           (select max(l.created_at) from listings l where l.user_id=u.id) as last_listing_at,
           (select count(*) from saved_listings s where s.user_id=u.id) as saved,
           (select count(*) from contact_events c where c.user_id=u.id) as contacts_made,
           (select count(*) from page_views v where v.user_id=u.id and v.created_at > now()-interval '30 days') as views_30d
      from users u where u.role <> 'admin' and bk_scope_ok(coalesce(u.country,'SY'), sc, al)) x), '[]'::json);
end $function$;

-- bk_admin_verify_list
CREATE OR REPLACE FUNCTION public.bk_admin_verify_list(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['verify']::text[], 'bk_admin_verify_list', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  update verify_tickets set status = 'expired' where status = 'pending' and expires_at < now();
  return coalesce((select json_agg(json_build_object('id', t.id, 'phone', t.phone, 'code', t.code, 'purpose', t.purpose, 'created_at', t.created_at, 'wa_sent_at', t.wa_sent_at, 'country_code', t.country_code,
      'user_id', coalesce(t.user_id, u.id), 'name', trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,''))) order by t.wa_sent_at desc)
    from verify_tickets t left join users u on u.id = t.user_id or (t.user_id is null and u.phone = t.phone)
    where t.status = 'pending' and t.channel = 'whatsapp' and t.wa_sent_at is not null and bk_scope_ok(t.country_code, sc, al)), '[]'::json);
end $function$;

-- bk_admin_verify_set
CREATE OR REPLACE FUNCTION public.bk_admin_verify_set(p_token text, p_ticket uuid, p_ok boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; t verify_tickets;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['verify']::text[], 'bk_admin_verify_set', (select coalesce(country_code,'SY') from verify_tickets where id=p_ticket), true, left(coalesce(p_ticket::text,''),300), (select coalesce(country_code,'SY') from verify_tickets where id=p_ticket));
  select * into t from verify_tickets where id = p_ticket;
  if t.id is null then return json_build_object('error','notfound'); end if;
  if not bk_admin_country_ok(uid, coalesce(t.country_code, 'SY')) then raise exception 'unauthorised'; end if;
  if t.status <> 'pending' then return json_build_object('error','done'); end if;
  if p_ok then
    update verify_tickets set status = 'verified', verified_at = now(), verified_by = uid where id = t.id;
    if t.purpose = 'signup' and t.user_id is not null then
      update users set phone_verified = true where id = t.user_id;
      update verify_tickets set status = 'used', used_at = now() where id = t.id;
      insert into notifications (user_id, type, title, body, link, is_read) values (t.user_id, 'system', 'verified', null, '/#/post', false);
    end if;
  else
    update verify_tickets set status = 'rejected' where id = t.id;
  end if;
  return json_build_object('ok', true);
end $function$;

-- bk_admin_version_get
CREATE OR REPLACE FUNCTION public.bk_admin_version_get(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; r record; begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['homepage','design','contact','ads']::text[], 'bk_admin_version_get', (select coalesce(country_code,'SY') from site_versions where id=p_id), false, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from site_versions where id=p_id));
  select * into r from site_versions where id=p_id; if not found then raise exception 'not found'; end if;
  perform bk_admin_guard(uid, r.country_code);
  return json_build_object('id',r.id,'created_at',r.created_at,'kind',r.kind,'label',r.label,'snapshot',r.snapshot);
end $function$;

-- bk_admin_versions
CREATE OR REPLACE FUNCTION public.bk_admin_versions(p_token text, p_country text DEFAULT 'SY'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; cc text := coalesce(p_country,'SY'); begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['homepage','design','contact','ads']::text[], 'bk_admin_versions', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); perform bk_admin_guard(uid, cc);
  return coalesce((select json_agg(x order by x.created_at desc, x.id desc) from (
    select v.id, v.created_at, v.kind, v.label, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as who
      from site_versions v left join users u on u.id=v.created_by where v.country_code=cc order by v.created_at desc, v.id desc limit 61) x), '[]'::json);
end $function$;

-- bk_admin_visitors_now
CREATE OR REPLACE FUNCTION public.bk_admin_visitors_now(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; t5 timestamptz := now() - interval '5 minutes'; t30 timestamptz := now() - interval '30 minutes';
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_visitors_now', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return json_build_object(
    'total',    (select count(*) from visitor_presence v where v.last_seen > t5 and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'members',  (select count(*) from visitor_presence v where v.last_seen > t5 and v.user_id is not null and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'guests',   (select count(*) from visitor_presence v where v.last_seen > t5 and v.user_id is null and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'mobile',   (select count(*) from visitor_presence v where v.last_seen > t5 and v.device = 'mobile' and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'desktop',  (select count(*) from visitor_presence v where v.last_seen > t5 and coalesce(v.device,'') <> 'mobile' and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'last_30m', (select count(*) from visitor_presence v where v.last_seen > t30 and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al)),
    'pages',    coalesce((select json_agg(x) from (select v.view, count(*) n from visitor_presence v where v.last_seen > t5 and v.view is not null and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al) group by v.view order by n desc limit 6) x), '[]'::json),
    'countries',coalesce((select json_agg(x) from (select coalesce(v.country,'?') country, count(*) n from visitor_presence v where v.last_seen > t5 and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al) group by 1 order by n desc limit 6) x), '[]'::json),
    'members_list', coalesce((select json_agg(x) from (
        select u.id, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as name, v.view, v.device, v.last_seen
          from visitor_presence v join users u on u.id = v.user_id
         where v.last_seen > t5 and bk_scope_ok(coalesce(v.site_country,'SY'),sc,al) order by v.last_seen desc limit 20) x), '[]'::json),
    'at', now());
end $function$;

-- bk_admin_wanted
CREATE OR REPLACE FUNCTION public.bk_admin_wanted(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['wanted']::text[], 'bk_admin_wanted', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg((bk_wanted_row(w)::jsonb || jsonb_build_object('user_phone', u.phone, 'expired', w.expires_at < now(), 'country_code', w.country_code))::json order by (w.status='pending') desc, w.created_at desc)
                     from wanted w join users u on u.id=w.user_id where bk_scope_ok(coalesce(w.country_code,'SY'),sc,al)), '[]'::json);
end $function$;

-- bk_admin_wanted_delete
CREATE OR REPLACE FUNCTION public.bk_admin_wanted_delete(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['wanted']::text[], 'bk_admin_wanted_delete', (select coalesce(country_code,'SY') from wanted where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from wanted where id=p_id)); perform bk_admin_guard(uid, (select country_code from wanted where id = p_id)); delete from wanted where id=p_id; return json_build_object('ok', true); end $function$;

-- bk_admin_wanted_edit
CREATE OR REPLACE FUNCTION public.bk_admin_wanted_edit(p_token text, p_id bigint, p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; w wanted; v_types text[]; v_deal text; v_gov text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['wanted']::text[], 'bk_admin_wanted_edit', (select coalesce(country_code,'SY') from wanted where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from wanted where id=p_id));
  select * into w from wanted where id = p_id;
  if w.id is null then raise exception 'not found'; end if;
  perform bk_admin_guard(uid, w.country_code);
  v_deal := p_data->>'deal';
  if v_deal not in ('sale','rent') then raise exception 'deal required'; end if;
  v_gov := nullif(trim(coalesce(p_data->>'gov_name','')),'');
  if v_gov is null then raise exception 'gov required'; end if;
  v_types := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_data->'property_types','[]'::jsonb)) x), '{}');
  update wanted set
    deal = v_deal, property_types = v_types, property_type = v_types[1], gov_name = v_gov,
    area_names = coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_data->'area_names','[]'::jsonb)) x), '{}'),
    budget_min = nullif(p_data->>'budget_min','')::numeric, budget_max = nullif(p_data->>'budget_max','')::numeric,
    currency = coalesce(nullif(p_data->>'currency',''), currency, 'USD'),
    rooms_min = nullif(p_data->>'rooms_min','')::int, area_min = nullif(nullif(p_data->>'area_min','')::numeric, 0),
    tabu = case when v_deal = 'rent' then null else nullif(p_data->>'tabu','') end,
    title = nullif(trim(coalesce(p_data->>'title','')),''), description = nullif(trim(coalesce(p_data->>'description','')),''),
    updated_at = now()
  where id = p_id returning * into w;
  return bk_wanted_row(w);
end $function$;

-- bk_admin_wanted_send
CREATE OR REPLACE FUNCTION public.bk_admin_wanted_send(p_token text, p_id bigint, p_who text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; w wanted; ids bigint[]; n int; lines text := ''; wtitle text; m record; o record; sent int := 0;
        reach_seeker boolean; reach_owners int; owners int;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['wanted']::text[], 'bk_admin_wanted_send', (select coalesce(country_code,'SY') from wanted where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from wanted where id=p_id));
  select * into w from wanted where id = p_id;
  if w.id is null then raise exception 'not found'; end if;
  perform bk_admin_guard(uid, w.country_code);
  if w.status <> 'open' then raise exception 'not open'; end if;
  if p_who not in ('seeker','owners','preview') then raise exception 'bad target'; end if;

  select coalesce(array_agg(l.id order by l.created_at desc), '{}') into ids
    from listings l where l.status = 'live' and l.deal = w.deal and bk_wanted_fits(w, l);
  n := coalesce(array_length(ids, 1), 0);
  select count(distinct l.user_id) into owners from listings l where l.id = any(ids);
  select count(distinct l.user_id) into reach_owners from listings l join contacts c on c.user_id = l.user_id
   where l.id = any(ids) and (c.tg_chat_id is not null or coalesce(c.phone,'') <> '');
  reach_seeker := exists (select 1 from contacts c where c.user_id = w.user_id and (c.tg_chat_id is not null or coalesce(c.phone,'') <> ''));
  if p_who = 'preview' or n = 0 then
    return json_build_object('matches', n, 'owners', owners, 'owners_reachable', reach_owners, 'seeker_reachable', reach_seeker, 'sent', 0);
  end if;

  insert into wanted_matches (wanted_id, listing_id) select w.id, x from unnest(ids) x on conflict do nothing;
  wtitle := coalesce(w.title, 'مطلوب '||case w.deal when 'rent' then 'للإيجار' else 'للشراء' end||' في '||coalesce(w.gov_name,''));

  if p_who = 'seeker' then
    for m in select l.id, l.ref from listings l where l.id = any(ids) order by l.created_at desc limit 15 loop
      lines := lines || E'\n' || '• ' || coalesce(m.ref,'') || ' https://balkoun.com/listing/' || m.id;
    end loop;
    insert into notifications (user_id, type, title, body, link)
      values (w.user_id, 'wanted_listing', n||' إعلان يطابق طلبك', coalesce(w.ref,'')||' · '||wtitle, '/wanted/'||w.id);
    perform bk_wanted_msg(w.user_id, 'direct: wanted match (seeker) w'||w.id||'/admin',
      '🏠 '||n||' إعلان يطابق طلبك'||coalesce(' '||w.ref,'')||' («'||wtitle||'»):'||lines||
        (case when n > 15 then E'\n\n'||'وكل الإعلانات المطابقة هنا: https://balkoun.com/wanted/'||w.id else '' end),
      '🏠 '||n||' listings match your request'||coalesce(' '||w.ref,'')||':'||lines||
        (case when n > 15 then E'\n\n'||'All of them: https://balkoun.com/wanted/'||w.id else '' end),
      coalesce(w.country_code,'SY'), null);
    sent := case when reach_seeker then 1 else 0 end;
  else
    for o in select l.user_id, string_agg(coalesce(l.ref,'#'||l.id), '، ' order by l.id) refs, count(*) c, min(l.id) first_id, max(l.country_code) cc
               from listings l where l.id = any(ids) group by l.user_id loop
      insert into notifications (user_id, type, title, body, link)
        values (o.user_id, 'wanted_match', 'طلب يطابق '||(case when o.c > 1 then 'إعلاناتك' else 'إعلانك' end), wtitle||coalesce(' · '||w.ref,''), '/wanted/'||w.id);
      perform bk_wanted_msg(o.user_id, 'direct: wanted match (owner) w'||w.id||'/admin',
        '📋 يوجد طلب شراء/إيجار يطابق '||(case when o.c > 1 then 'إعلاناتك ' else 'إعلانك ' end)||o.refs||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'شاهد الطلب وتواصل مع صاحبه: https://balkoun.com/wanted/'||w.id,
        '📋 A buy/rent request matches your listing(s) '||o.refs||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'See it and contact the requester: https://balkoun.com/wanted/'||w.id,
        coalesce(o.cc,'SY'), o.first_id);
    end loop;
    sent := reach_owners;
  end if;
  return json_build_object('matches', n, 'owners', owners, 'owners_reachable', reach_owners, 'seeker_reachable', reach_seeker, 'sent', sent);
end $function$;

-- bk_admin_wanted_set
CREATE OR REPLACE FUNCTION public.bk_admin_wanted_set(p_token text, p_id bigint, p_status text DEFAULT NULL::text, p_featured boolean DEFAULT NULL::boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; w wanted; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['wanted']::text[], 'bk_admin_wanted_set', (select coalesce(country_code,'SY') from wanted where id=p_id), true, left(coalesce(p_id::text,''),300), (select coalesce(country_code,'SY') from wanted where id=p_id)); perform bk_admin_guard(uid, (select country_code from wanted where id = p_id)); update wanted set status=coalesce(p_status,status), featured=coalesce(p_featured,featured), expires_at = case when p_status='open' and expires_at < now() then now() + interval '60 days' else expires_at end, updated_at=now() where id=p_id returning * into w; if p_status='open' then perform bk_wanted_notify(p_id); end if; return json_build_object('ok', true); end $function$;


-- bk_admin_data and bk_admin_search return several lists at once: each list needs its own permission
alter function public.bk_admin_data(text,text) rename to bk_admin_data_core;
revoke all on function public.bk_admin_data_core(text,text) from public, anon, authenticated;
create or replace function public.bk_admin_data(p_token text, p_country text default null::text)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; r jsonb; su boolean; pm text[];
begin
  uid := bk_admin_uid(p_token); r := public.bk_admin_data_core(p_token, p_country)::jsonb;
  select coalesce(is_super_admin,false), coalesce(permissions,'{}'::text[]) into su, pm from users where id = uid;
  if not su then
    if not pm && array['listings_view','listings_edit','listings_delete'] then r := r || '{"listings":[]}'::jsonb; end if;
    if not pm && array['users_view','users_edit','users_delete'] then r := r || '{"users":[]}'::jsonb; end if;
    if not pm && array['reports'] then r := r || '{"reports":[]}'::jsonb; end if;
    if not pm && array['feedback'] then r := r || '{"feedback":[]}'::jsonb; end if;
  end if;
  return r::json;
end $fn$;
grant execute on function public.bk_admin_data(text,text) to anon, authenticated;
alter function public.bk_admin_search(text,text,text) rename to bk_admin_search_core;
revoke all on function public.bk_admin_search_core(text,text,text) from public, anon, authenticated;
create or replace function public.bk_admin_search(p_token text, p_q text, p_country text default null::text)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; r jsonb; su boolean; pm text[];
begin
  uid := bk_admin_uid(p_token); r := public.bk_admin_search_core(p_token, p_q, p_country)::jsonb;
  select coalesce(is_super_admin,false), coalesce(permissions,'{}'::text[]) into su, pm from users where id = uid;
  if not su then
    if not pm && array['listings_view','listings_edit','listings_delete'] then r := r || '{"listings":[]}'::jsonb; end if;
    if not pm && array['users_view','users_edit','users_delete'] then r := r || '{"users":[]}'::jsonb; end if;
    if not pm && array['agencies'] then r := r || '{"agencies":[]}'::jsonb; end if;
    if not pm && array['wanted'] then r := r || '{"requests":[]}'::jsonb; end if;
    if not pm && array['intake'] then r := r || '{"drafts":[]}'::jsonb; end if;
  end if;
  return r::json;
end $fn$;
revoke all on function public.bk_admin_search(text,text,text) from public;
grant execute on function public.bk_admin_search(text,text,text) to anon, authenticated;

commit;
