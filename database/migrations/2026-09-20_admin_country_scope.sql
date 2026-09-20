-- Balkoun · 2026-09-20 · admin panel country scope (applied as migrations "admin_country_scope" + "admin_country_scope_guards")
-- Why: the switch card was dead outside the Countries page; users/feedback/tickets/ads/verify queue/counts ignored the country;
-- restricted admins could act on any country's rows by id; stale replies could overwrite the new country's data.

-- Balkoun · 2026-09-20 · admin panel country scope (applied as migration "admin_country_scope")
-- 1. bk_scope_ok treats a NULL country as 'SY' everywhere (callers coalesced inconsistently; NULL rows vanished from every scope).
create or replace function public.bk_scope_ok(p_cc text, p_scope text, p_allowed text[]) returns boolean
language sql immutable set search_path = public, extensions as $$
  select (p_scope is null or coalesce(p_cc,'SY') = p_scope) and (p_allowed is null or coalesce(p_cc,'SY') = any(p_allowed))
$$;
-- a restricted admin may only touch rows of their countries
create or replace function public.bk_admin_guard(p_uid uuid, p_cc text) returns void
language plpgsql stable security definer set search_path = public, extensions as $$
begin if not bk_admin_country_ok(p_uid, coalesce(p_cc,'SY')) then raise exception 'forbidden: other country'; end if; end $$;

-- 2. members carry their site country (new sign-ups already do, from the verification ticket); older rows: from the phone prefix
update public.users set country = bk_member_country(country, phone) where country is null;
alter table public.feedback add column if not exists country_code text;

-- 3. bk_feedback records the site country the visitor was on
drop function if exists public.bk_feedback(text, text, text, text, uuid, text);
create or replace function public.bk_feedback(p_kind text, p_name text, p_contact text, p_body text, p_user uuid, p_token text default null, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare v_id bigint;
begin
  perform bk_require_member(p_token, p_user);
  insert into feedback (kind, name, contact, body, user_id, country_code) values (p_kind, p_name, p_contact, p_body, p_user, (select code from countries where code = upper(nullif(trim(p_country),'')) limit 1)) returning id into v_id;
  insert into notifications (user_id, type, title, body, link) select id, 'admin_alert', 'new_feedback', p_body, '/#/admin:feedback' from users where role = 'admin';
  return json_build_object('ok', true);
end $$;

-- 4. text patches on the big read functions: every user / feedback / review count and list follows the scope
do $$
declare r record; src text; new text; fixes text[]; f text; parts text[]; n int;
begin
  for r in select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('bk_admin_data','bk_admin_stats','bk_admin_analytics','bk_admin_todo') loop
    src := regexp_replace(pg_get_functiondef(r.oid), E'[\n\r\t ]+', ' ', 'g'); new := src;
    if r.proname = 'bk_admin_data' then
      fixes := array[
        $x$'users', (select count(*) from users where role <> 'admin'),$x$ || '||' || $x$'users', (select count(*) from users where role <> 'admin' and bk_scope_ok(country,sc,al)),$x$,
        $x$'reviews', (select count(*) from reviews),$x$ || '||' || $x$'reviews', (select count(*) from reviews rv join users tu on tu.id = rv.target_user where bk_scope_ok(tu.country,sc,al)),$x$,
        $x$'openFeedback', (select count(*) from feedback where not handled),$x$ || '||' || $x$'openFeedback', (select count(*) from feedback where not handled and (country_code is null or bk_scope_ok(country_code,sc,al))),$x$,
        $x$from users u where u.role <> 'admin' order by u.created_at desc limit 500$x$ || '||' || $x$from users u where u.role <> 'admin' and bk_scope_ok(u.country,sc,al) order by u.created_at desc limit 500$x$,
        $x$as thread from feedback f left join users fu on fu.id = f.user_id order by f.created_at desc limit 500$x$ || '||' || $x$as thread, f.country_code from feedback f left join users fu on fu.id = f.user_id where f.country_code is null or bk_scope_ok(f.country_code,sc,al) order by f.created_at desc limit 500$x$
      ];
    elsif r.proname = 'bk_admin_stats' then
      fixes := array[
        $x$'members_total', (select count(*) from users where role <> 'admin'),$x$ || '||' || $x$'members_total', (select count(*) from users where role <> 'admin' and bk_scope_ok(country,sc,al)),$x$,
        $x$'members_week', (select count(*) from users where created_at > now() - interval '7 days'),$x$ || '||' || $x$'members_week', (select count(*) from users where role <> 'admin' and created_at > now() - interval '7 days' and bk_scope_ok(country,sc,al)),$x$,
        $x$'online_now', (select count(*) from online_presence where last_seen > now() - interval '5 minutes'),$x$ || '||' || $x$'online_now', (select count(*) from online_presence op join users ou on ou.id = op.user_id where op.last_seen > now() - interval '5 minutes' and bk_scope_ok(ou.country,sc,al)),$x$,
        $x$where p.last_seen > now() - interval '5 minutes' order by p.last_seen desc limit 50$x$ || '||' || $x$where p.last_seen > now() - interval '5 minutes' and bk_scope_ok(u.country,sc,al) order by p.last_seen desc limit 50$x$
      ];
    elsif r.proname = 'bk_admin_analytics' then
      fixes := array[
        $x$from users where role<>'admin'$x$ || '||' || $x$from users where role<>'admin' and bk_scope_ok(country,sc,al)$x$,
        $x$from users u where u.role<>'admin'$x$ || '||' || $x$from users u where u.role<>'admin' and bk_scope_ok(u.country,sc,al)$x$,
        $x$from users where blocked)$x$ || '||' || $x$from users where blocked and bk_scope_ok(country,sc,al))$x$,
        $x$'online_now', (select count(*) from online_presence where last_seen > now() - interval '5 minutes')$x$ || '||' || $x$'online_now', (select count(*) from online_presence op join users ou on ou.id = op.user_id where op.last_seen > now() - interval '5 minutes' and bk_scope_ok(ou.country,sc,al))$x$,
        $x$from feedback where not handled)$x$ || '||' || $x$from feedback where not handled and (country_code is null or bk_scope_ok(country_code,sc,al)))$x$
      ];
    else
      fixes := array[
        $x$'open_feedback', (select count(*) from feedback where not coalesce(handled,false)),$x$ || '||' || $x$'open_feedback', (select count(*) from feedback where not coalesce(handled,false) and (country_code is null or bk_scope_ok(country_code,sc,al))),$x$,
        $x$from feedback f where not coalesce(f.handled,false) order by$x$ || '||' || $x$from feedback f where not coalesce(f.handled,false) and (f.country_code is null or bk_scope_ok(f.country_code,sc,al)) order by$x$,
        $x$f.id::text, null from feedback f$x$ || '||' || $x$f.id::text, f.country_code from feedback f$x$
      ];
    end if;
    foreach f in array fixes loop
      parts := string_to_array(f, '||');
      n := (length(new) - length(replace(new, parts[1], ''))) / length(parts[1]);
      if n = 0 then raise exception '% : anchor not found: %', r.proname, left(parts[1], 80); end if;
      new := replace(new, parts[1], parts[2]);
    end loop;
    execute new;
  end loop;
end $$;

-- 5. functions that ignored the scope or the admin's allowed countries
create or replace function public.bk_admin_tickets(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by (x.status='done'), case x.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end, x.created_at desc) from (
    select t.*, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as created_by_name from tickets t left join users u on u.id=t.created_by
     where bk_scope_ok(t.country_code, sc, al)) x), '[]'::json);
end $$;

create or replace function public.bk_admin_list_ads(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x order by x.country_code, x.position) from (
    select id, position, image_url, link_url, label, enabled, media_type, linked_listing_id, image_urls, video_embed_url, sponsor_name, starts_at, expires_at, overlay_top, overlay_bottom, country_code
      from ad_slots where bk_scope_ok(country_code, sc, al)) x), '[]'::json);
end $$;

drop function if exists public.bk_admin_verify_list(text);
create or replace function public.bk_admin_verify_list(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  update verify_tickets set status = 'expired' where status = 'pending' and expires_at < now();
  return coalesce((select json_agg(json_build_object('id', t.id, 'phone', t.phone, 'code', t.code, 'purpose', t.purpose, 'created_at', t.created_at, 'wa_sent_at', t.wa_sent_at, 'country_code', t.country_code,
      'user_id', coalesce(t.user_id, u.id), 'name', trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,''))) order by t.wa_sent_at desc)
    from verify_tickets t left join users u on u.id = t.user_id or (t.user_id is null and u.phone = t.phone)
    where t.status = 'pending' and t.channel = 'whatsapp' and t.wa_sent_at is not null and bk_scope_ok(t.country_code, sc, al)), '[]'::json);
end $$;

create or replace function public.bk_admin_geo_list(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid; al text[]; cc text;
begin
  uid := bk_admin_uid(p_token); al := bk_admin_allowed(uid);
  cc := nullif(upper(trim(coalesce(p_country,''))),''); if cc = 'ALL' then cc := null; end if;
  if cc is not null and al is not null and not (cc = any(al)) then cc := al[1]; end if;
  return json_build_object(
    'governorates', (select coalesce(json_agg(json_build_object('id',g.id,'name_ar',g.name_ar,'name_en',g.name_en,'slug',g.slug,'enabled',g.enabled,'sort_order',g.sort_order,'lat',g.lat,'lng',g.lng,'country_code',g.country_code,
        'listings',(select count(*) from listings l where l.governorate_id=g.id and l.status='live'), 'areas',(select count(*) from areas a where a.governorate_id=g.id)) order by g.sort_order, g.id), '[]'::json)
       from governorates g where (cc is null or g.country_code=cc) and (al is null or g.country_code = any(al))),
    'areas', (select coalesce(json_agg(json_build_object('id',a.id,'governorate_id',a.governorate_id,'name_ar',a.name_ar,'name_en',a.name_en,'slug',a.slug,'kind',a.kind,'enabled',a.enabled,'sort_order',a.sort_order,'lat',a.lat,'lng',a.lng,
        'listings',(select count(*) from listings l where l.area_id=a.id and l.status='live')) order by a.governorate_id, a.sort_order, a.id), '[]'::json)
       from areas a join governorates g on g.id=a.governorate_id where (cc is null or g.country_code=cc) and (al is null or g.country_code = any(al))));
end $$;

-- restricted admins only see their own countries in the country list (header select, switch card, countries page)
do $$ declare src text; new text;
begin
  select regexp_replace(pg_get_functiondef(p.oid), E'[\n\r\t ]+', ' ', 'g') into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='bk_admin_countries';
  new := replace(src, 'declare uid uuid; begin uid := bk_admin_uid(p_token); return', 'declare uid uuid; al text[]; begin uid := bk_admin_uid(p_token); al := bk_admin_allowed(uid); return');
  new := replace(new, 'order by c.sort_order) from countries c), ''[]''::json); end', 'order by c.sort_order) from countries c where al is null or c.code = any(al)), ''[]''::json); end');
  if new = src then raise exception 'bk_admin_countries anchors'; end if;
  execute new;
end $$;

-- 6. every write function refuses rows outside the admin's countries (super admins and unrestricted admins pass everywhere)
create or replace function public.bk_admin_guard_opt(p_uid uuid, p_cc text) returns void
language plpgsql stable security definer set search_path = public, extensions as $$
begin if p_cc is not null and not bk_admin_country_ok(p_uid, p_cc) then raise exception 'forbidden: other country'; end if; end $$;
do $$
declare r record; src text; new text; anchor text; n int;
  G constant text[][] := array[
    ['bk_admin_set_status',        'perform bk_admin_guard(uid, (select country_code from listings where id = p_listing));'],
    ['bk_admin_delete_listing',    'perform bk_admin_guard(uid, (select country_code from listings where id = p_listing));'],
    ['bk_admin_edit_listing',      'perform bk_admin_guard(uid, (select country_code from listings where id = p_id));'],
    ['bk_admin_listing',           'perform bk_admin_guard(uid, (select country_code from listings where id = p_id));'],
    ['bk_admin_feature_listing',   'perform bk_admin_guard(uid, (select country_code from listings where id = p_listing));'],
    ['bk_admin_unfeature_listing', 'perform bk_admin_guard(uid, (select country_code from listings where id = p_listing));'],
    ['bk_admin_wanted_set',        'perform bk_admin_guard(uid, (select country_code from wanted where id = p_id));'],
    ['bk_admin_wanted_delete',     'perform bk_admin_guard(uid, (select country_code from wanted where id = p_id));'],
    ['bk_admin_photo_del',         'perform bk_admin_guard_opt(uid, (select l.country_code from listing_photos p join listings l on l.id = p.listing_id where p.id = p_photo));'],
    ['bk_admin_delete_ad',         'perform bk_admin_guard(uid, (select country_code from ad_slots where id = p_id));'],
    ['bk_admin_ad_country',        'perform bk_admin_guard(uid, (select country_code from ad_slots where id = p_id)); perform bk_admin_guard(uid, p_country);'],
    ['bk_admin_project_delete',    'perform bk_admin_guard(uid, (select country_code from projects where id = p_id));'],
    ['bk_admin_project_lead_set',  'perform bk_admin_guard(uid, (select p.country_code from project_leads l join projects p on p.id = l.project_id where l.id = p_id));'],
    ['bk_admin_project_save',      'perform bk_admin_guard(uid, case when p_id is null then coalesce(v_c,''SY'') else (select country_code from projects where id = p_id) end);'],
    ['bk_admin_ticket_set',        'perform bk_admin_guard(uid, (select country_code from tickets where id = p_id));'],
    ['bk_admin_ticket_delete',     'perform bk_admin_guard(uid, (select country_code from tickets where id = p_id));'],
    ['bk_admin_ticket_add',        'perform bk_admin_guard(uid, upper(coalesce(nullif(nullif(trim(p_country),''''),''ALL''),''SY'')));'],
    ['bk_admin_ticket_from',       'perform bk_admin_guard_opt(uid, case when p_kind = ''feedback'' then (select country_code from feedback where id = p_id) else (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id) end);'],
    ['bk_admin_delete_report',     'perform bk_admin_guard_opt(uid, (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id));'],
    ['bk_admin_delete_feedback',   'perform bk_admin_guard_opt(uid, (select country_code from feedback where id = p_id));'],
    ['bk_admin_delete_review',     'perform bk_admin_guard(uid, (select u.country from reviews rv join users u on u.id = rv.target_user where rv.id = p_id));'],
    ['bk_admin_reply',             'perform bk_admin_guard_opt(uid, case when p_kind = ''feedback'' then (select country_code from feedback where id = p_id) else (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id) end);'],
    ['bk_admin_set_solved',        'perform bk_admin_guard_opt(uid, case when p_kind = ''feedback'' then (select country_code from feedback where id = p_id) else (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id) end);'],
    ['bk_admin_set_priority',      'perform bk_admin_guard_opt(uid, case when p_kind = ''feedback'' then (select country_code from feedback where id = p_id) else (select l.country_code from listing_reports rr left join listings l on l.id = rr.listing_id where rr.id = p_id) end);'],
    ['bk_admin_block_user',        'perform bk_admin_guard(uid, (select country from users where id = p_user));'],
    ['bk_admin_set_level',         'perform bk_admin_guard(uid, (select country from users where id = p_user));'],
    ['bk_admin_set_card_logo',     'perform bk_admin_guard(uid, (select country from users where id = p_user));'],
    ['bk_admin_set_skip_review',   'perform bk_admin_guard(uid, (select country from users where id = p_user));'],
    ['bk_admin_clear_avatar',      'perform bk_admin_guard(uid, (select country from users where id = p_user));'],
    ['bk_admin_clear_bio',         'perform bk_admin_guard(uid, (select country from users where id = p_user));'],
    ['bk_admin_set_content',       'perform bk_admin_guard(uid, coalesce(p_country,''SY''));'],
    ['bk_admin_deed_save',         'perform bk_admin_guard(uid, p_country);'],
    ['bk_admin_gov_save',          'perform bk_admin_guard(uid, (select country_code from governorates where id = (p_row->>''id'')::int));'],
    ['bk_admin_gov_add',           'perform bk_admin_guard(uid, p_row->>''country_code'');'],
    ['bk_admin_area_save',         'perform bk_admin_guard(uid, (select country_code from governorates where id = (p_row->>''governorate_id'')::int));'],
    ['bk_admin_area_delete',       'perform bk_admin_guard(uid, (select g.country_code from areas a join governorates g on g.id = a.governorate_id where a.id = p_id));'],
    ['bk_admin_reset_password',    'perform bk_admin_guard(v_admin, (select country from users where id = p_user)); if exists (select 1 from users where id = p_user and role = ''admin'') and not bk_admin_is_super(v_admin) then raise exception ''super admin only''; end if;'],
    ['bk_admin_review_set',        'perform bk_admin_guard(v_admin, (select country from users where id = p_target));']
  ];
begin
  for n in 1..array_length(G, 1) loop
    select p.oid into r from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = G[n][1];
    if r.oid is null then raise exception 'missing %', G[n][1]; end if;
    src := regexp_replace(pg_get_functiondef(r.oid), E'[\n\r\t ]+', ' ', 'g');
    anchor := case when G[n][2] like 'perform bk_admin_guard(v_admin%' then 'v_admin := bk_admin_uid(p_token);' else 'uid := bk_admin_uid(p_token);' end;
    if position(anchor in src) = 0 then raise exception '% : no anchor', G[n][1]; end if;
    if position('bk_admin_guard' in src) > 0 then continue; end if;
    new := replace(src, anchor, anchor || ' ' || G[n][2]);
    execute new;
  end loop;
end $$;

-- ad reorder stays inside one country
create or replace function public.bk_admin_move_ad(p_token text, p_id bigint, p_dir text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; v_cc text; v_pos int; v_other_id bigint; v_other_pos int;
begin
  uid := bk_admin_uid(p_token);
  select position, country_code into v_pos, v_cc from ad_slots where id = p_id;
  if v_pos is null then raise exception 'not found'; end if;
  perform bk_admin_guard(uid, v_cc);
  if p_dir = 'up' then select id, position into v_other_id, v_other_pos from ad_slots where country_code = v_cc and position < v_pos order by position desc limit 1;
  else select id, position into v_other_id, v_other_pos from ad_slots where country_code = v_cc and position > v_pos order by position asc limit 1; end if;
  if v_other_id is null then return json_build_object('ok', true); end if;
  update ad_slots set position = v_other_pos where id = p_id;
  update ad_slots set position = v_pos where id = v_other_id;
  return json_build_object('ok', true);
end $$;

-- the single-recipient notification checks the member's country
do $$ declare src text; new text;
begin
  select regexp_replace(pg_get_functiondef(p.oid), E'[\n\r\t ]+', ' ', 'g') into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='bk_admin_send_notification';
  new := replace(src, 'else insert into notifications (user_id, type, title, body) values (p_user,', 'else perform bk_admin_guard(uid, (select country from users where id = p_user)); insert into notifications (user_id, type, title, body) values (p_user,');
  new := replace(new, 'bk_scope_ok(coalesce(country,''SY''), sc, al)', 'bk_scope_ok(country, sc, al)');
  if new = src then raise exception 'send_notification anchor'; end if;
  execute new;
end $$;

-- manual / banner engagements carry the country they were recorded for
drop function if exists public.bk_admin_engage(text, text, bigint, text, text, text, text, timestamptz, timestamptz, text);
create or replace function public.bk_admin_engage(p_token text, p_kind text, p_ref_id bigint, p_ref_text text, p_title text, p_client text default null, p_phone text default null, p_starts timestamptz default null, p_ends timestamptz default null, p_notes text default null, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; r public.engagements; v_cc text;
begin
  uid := bk_admin_uid(p_token);
  v_cc := upper(nullif(nullif(trim(coalesce(p_country,'')),''),'ALL'));
  if p_kind = 'featured' and p_ref_id is not null then perform bk_admin_guard(uid, (select country_code from listings where id = p_ref_id));
  elsif p_kind = 'ad' and p_ref_id is not null then perform bk_admin_guard(uid, (select country_code from ad_slots where id = p_ref_id));
  else perform bk_admin_guard(uid, coalesce(v_cc,'SY')); end if;
  r := public.bk_engage(p_kind,p_ref_id,p_ref_text,p_title,p_client,p_phone,p_starts,p_ends,p_notes,uid);
  if p_kind not in ('ad','featured') and v_cc is not null then update public.engagements set country_code = v_cc where id = r.id returning * into r; end if;
  return row_to_json(r);
end $$;

-- global (site-wide) extras for the panel: alert + verification settings live on the SY row only
do $$ declare src text; new text;
begin
  select regexp_replace(pg_get_functiondef(p.oid), E'[\n\r\t ]+', ' ', 'g') into src from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='bk_admin_data';
  new := replace(src, $x$'scope', sc, 'stats', (select json_build_object($x$, $x$'scope', sc, 'gx', (select coalesce((select jsonb_object_agg(key, value) from jsonb_each(coalesce(extras,'{}'::jsonb)) where key like 'notify\_%' or key like 'verify\_%' or key = 'intake_bot'), '{}'::jsonb) from site_content where id = 1), 'stats', (select json_build_object($x$);
  if new = src then raise exception 'bk_admin_data gx anchor'; end if;
  execute new;
end $$;

-- media in use across every country (the storage folders are shared): the media library must never call another country's live file "unused"
create or replace function public.bk_admin_media_used(p_token text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return json_build_object(
    'ads', coalesce((select json_agg(distinct u) from (select image_url as u from ad_slots where image_url is not null union all select jsonb_array_elements_text(coalesce(image_urls,'[]'::jsonb)) from ad_slots) z where u is not null), '[]'::json),
    'banners', coalesce((select json_agg(distinct m[1]) from site_content s, regexp_matches(coalesce(s.banner_items,'') || ' ' || coalesce(s.banners_config,'') || ' ' || coalesce(s.banner_image_url,'') || ' ' || coalesce(s.banner_video_url,''), '(https?://[^"''\s\\]+)', 'g') m), '[]'::json),
    'background', coalesce((select json_agg(distinct u) from (select hero_bg_photo_url as u from site_content union all select hero_bg_video_url from site_content) z where u is not null and u <> ''), '[]'::json));
end $$;
