-- the admin panel shows one country at a time (owner, 2026-10-17: «I asked to be completely separated»): the search box,
-- house accounts and «listings due for promotion» follow the panel's country (p_country; «ALL» = every allowed country)
begin;
drop function if exists public.bk_admin_search(text,text);
drop function if exists public.bk_admin_house_accounts(text);
drop function if exists public.bk_admin_promo_due(text);
CREATE OR REPLACE FUNCTION public.bk_admin_search(p_token text, p_q text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; q text; qd text; num text; pat text; dpat text;
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country);
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
end $function$
;
CREATE OR REPLACE FUNCTION public.bk_admin_house_accounts(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text;
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country);
  return coalesce((select json_agg(row_to_json(x) order by x.created_at, x.id) from (
    select u.id, u.name, u.family_name, u.city, u.country, u.member_no, u.avatar_url, u.bio, u.hide_phone, u.blocked, u.created_at, u.last_seen_at,
           (select count(*) from listings l where l.user_id = u.id and l.status in ('live','pending') and (sc is null or coalesce(l.country_code,'SY') = sc)) as listings,
           (select count(*) from listings l where l.user_id = u.id and (sc is null or coalesce(l.country_code,'SY') = sc)) as listings_total,
           (select count(*) from reviews r where r.target_user = u.id) as reviews
      from users u where u.is_house and (sc is null or coalesce(u.country,'SY') = sc or exists (select 1 from listings l where l.user_id = u.id and coalesce(l.country_code,'SY') = sc)) order by u.created_at, u.id) x), '[]'::json);
end $function$
;
CREATE OR REPLACE FUNCTION public.bk_admin_promo_due(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); if uid is null then raise exception 'not admin'; end if; sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(json_build_object(
      'listing_id', l.id, 'ref', l.ref, 'property_type', l.property_type, 'area_m2', l.area_m2,
      'gov', g.name_ar, 'price_usd', l.price_usd, 'due_at', ps.due_at,
      'cover', (select coalesce(nullif(p.thumb_url,''), p.url) from listing_photos p
                 where p.listing_id=l.id and coalesce(p.kind,'photo')='photo' order by p.sort_order, p.id limit 1)
    ) order by ps.due_at)
    from promo_schedule ps join listings l on l.id=ps.listing_id join governorates g on g.id=l.governorate_id
    where ps.status='pending' and ps.due_at<=now() and l.status='live' and bk_scope_ok(l.country_code, sc, al) limit 50), '[]'::json);
end $function$
;
grant execute on function public.bk_admin_search(text,text,text), public.bk_admin_house_accounts(text,text), public.bk_admin_promo_due(text,text) to anon, authenticated;
revoke execute on function public.bk_admin_search(text,text,text) from public;
commit;
