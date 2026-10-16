-- One search for the whole panel (owner, 2026-10-16): the header box finds listings, members, offices, requests and
-- bot drafts by number, name, phone or text. READ ONLY: it selects and returns, it never writes anything. Every row is
-- filtered by the countries the signed-in admin may see (bk_admin_country_ok), up to 8 per kind.
create or replace function public.bk_admin_search(p_token text, p_q text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare uid uuid; q text; qd text; num text; pat text; dpat text;
begin
  uid := bk_admin_uid(p_token);
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
       where bk_admin_country_ok(uid, coalesce(l.country_code,'SY'))
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
       where bk_admin_country_ok(uid, coalesce(u.country,'SY'))
         and ((trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,''))) ilike pat or u.member_no ilike pat or u.email ilike pat
              or (dpat is not null and regexp_replace(coalesce(u.phone,''), '\D', '', 'g') like dpat))
       order by u.created_at desc limit 8) x),
    'agencies', (select coalesce(json_agg(x), '[]'::json) from (
      select ag.id, ag.name, ag.status, ag.phone, ag.user_id
        from agencies ag
       where bk_admin_country_ok(uid, coalesce(ag.country_code,'SY'))
         and (ag.name ilike pat or (dpat is not null and (regexp_replace(coalesce(ag.phone,''), '\D', '', 'g') like dpat or regexp_replace(coalesce(ag.whatsapp,''), '\D', '', 'g') like dpat)))
       order by ag.created_at desc limit 8) x),
    'requests', (select coalesce(json_agg(x), '[]'::json) from (
      select w.id, w.ref, w.status, w.deal, w.gov_name, coalesce(w.title,'') as title
        from wanted w
       where bk_admin_country_ok(uid, coalesce(w.country_code,'SY'))
         and (upper(coalesce(w.ref,'')) = upper(regexp_replace(q, '\s|-', '', 'g')) or (num is not null and (w.ref like '%' || num or w.id::text = num))
              or w.title ilike pat or w.description ilike pat)
       order by w.created_at desc limit 8) x),
    'drafts', (select coalesce(json_agg(x), '[]'::json) from (
      select d.id, d.status, d.source, d.sender_name, d.listing_id, left(coalesce(d.summary, d.raw_text, ''), 90) as text
        from intake_drafts d
       where bk_admin_country_ok(uid, coalesce(d.country_code,'SY'))
         and ((num is not null and d.id::text = num and q ~ '^\s*#') or (dpat is not null and regexp_replace(coalesce(d.chat_id,''), '\D', '', 'g') like dpat)
              or d.sender_name ilike pat)
       order by d.created_at desc limit 8) x));
end $f$;
revoke all on function public.bk_admin_search(text, text) from public;
grant execute on function public.bk_admin_search(text, text) to anon, authenticated;
