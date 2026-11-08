-- 2026-11-07 panel search (owner: "make it more flexible … find listings and users in general")
-- Before: the whole typed phrase had to appear as-is in one field («شقة المزة» found nothing; «سامر حداد» only in that order).
-- Now: every word is looked for anywhere in the row (title text, area, governorate, owner, contact, member no…), in any order,
-- with the site's Arabic normalisation (أ/إ/آ, ة/ه, ى/ي, no tashkeel; «ال/و/ب/ل» prefixes dropped by bk_kw_hit).
-- Arabic digits count as digits. The exact ref / number / phone matches stay and still sort first.
CREATE OR REPLACE FUNCTION public.bk_admin_search_core(p_token text, p_q text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; q text; qd text; num text; pat text; dpat text; w text[]; qref text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, null::text[], 'bk_admin_search', null, false, left(coalesce(p_q::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country);
  q := trim(translate(coalesce(p_q, ''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789'));
  if length(q) < 2 then return json_build_object('q', q); end if;
  qd := regexp_replace(q, '\D', '', 'g');                                      -- the digits (a phone, a number)
  num := substring(q from '(\d{3,9})\s*$');                                     -- a trailing number (SY10460, SYW1037, #742)
  pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  dpat := case when length(qd) >= 6 then '%' || right(qd, 9) || '%' else null end;   -- last 9 digits: local or international format
  qref := upper(regexp_replace(q, '\s|-', '', 'g'));
  w := bk_kw_words(q); if cardinality(w) = 0 then w := null; end if;            -- the words, each may sit anywhere in the row
  return json_build_object('q', q,
    'listings', (select coalesce(json_agg(x), '[]'::json) from (
      select l.id, l.ref, l.status, l.deal, l.property_type, l.price_usd, a.name_ar as area, g.name_ar as gov,
             trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as owner, l.country_code
        from listings l left join areas a on a.id = l.area_id left join governorates g on g.id = l.governorate_id left join users u on u.id = l.user_id
       where bk_admin_country_ok(uid, coalesce(l.country_code,'SY')) and (sc is null or coalesce(l.country_code,'SY') = sc)
         and (upper(l.ref) = qref or (num is not null and (l.ref like '%' || num or l.id::text = num))
              or (dpat is not null and regexp_replace(coalesce(l.contact_phone,''), '\D', '', 'g') like dpat)
              or l.description ilike pat or l.landmark ilike pat
              or (w is not null and bk_kw_hit(bk_kw_norm(concat_ws(' ', l.ref, a.name_ar, a.name_en, g.name_ar, g.name_en, l.landmark, l.contact_name,
                                                        u.name, u.family_name, u.member_no, l.property_type, l.deal, l.description,
                                                        case l.deal when 'rent' then 'ايجار اجار للايجار' else 'بيع للبيع' end,
                                                        case l.property_type when 'apartment' then 'شقة' when 'shop' then 'محل' when 'plot' then 'ارض' when 'house' then 'بيت منزل'
                                                          when 'farm' then 'مزرعة' when 'arab' then 'بيت عربي' when 'villa' then 'فيلا' when 'office' then 'مكتب'
                                                          when 'agri' then 'ارض زراعية' when 'building' then 'بناء كامل' when 'showroom' then 'صالة عرض' when 'restaurant' then 'مطعم'
                                                          when 'warehouse' then 'مستودع' when 'resid' then 'ارض سكنية' when 'comm' then 'ارض تجارية' when 'duplex' then 'دوبلكس'
                                                          when 'factory' then 'معمل' when 'tourist' then 'ارض سياحية' when 'mahdar' then 'محضر' when 'hotel' then 'فندق'
                                                          when 'chalet' then 'شاليه' when 'studio' then 'ستوديو' when 'basement' then 'قبو' when 'terrace' then 'سطح'
                                                          when 'floor' then 'طابق' when 'fullfloor' then 'طابق كامل' else '' end)), w)))
       order by (upper(l.ref) = qref) desc, (l.status = 'live') desc, l.created_at desc limit 10) x),
    'users', (select coalesce(json_agg(x), '[]'::json) from (
      select u.id, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) as name, u.member_no, u.phone, u.email, u.account_type,
             u.blocked,
             (select count(*) from listings l where l.user_id = u.id and l.status in ('live','pending')) as listings,
             (select count(*) from wanted w2 where w2.user_id = u.id and w2.status in ('open','pending')) as requests
        from users u
       where bk_admin_country_ok(uid, coalesce(u.country,'SY')) and (sc is null or coalesce(u.country,'SY') = sc)
         and ((trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,''))) ilike pat or u.member_no ilike pat or u.email ilike pat
              or (dpat is not null and regexp_replace(coalesce(u.phone,''), '\D', '', 'g') like dpat)
              or (w is not null and bk_kw_hit(bk_kw_norm(concat_ws(' ', u.name, u.family_name, u.member_no, u.email,
                                                        (select string_agg(ag.name, ' ') from agencies ag where ag.user_id = u.id))), w)))
       order by u.created_at desc limit 10) x),
    'agencies', (select coalesce(json_agg(x), '[]'::json) from (
      select ag.id, ag.name, ag.status, ag.phone, ag.user_id
        from agencies ag
       where bk_admin_country_ok(uid, coalesce(ag.country_code,'SY')) and (sc is null or coalesce(ag.country_code,'SY') = sc)
         and (ag.name ilike pat or (dpat is not null and (regexp_replace(coalesce(ag.phone,''), '\D', '', 'g') like dpat or regexp_replace(coalesce(ag.whatsapp,''), '\D', '', 'g') like dpat))
              or (w is not null and bk_kw_hit(bk_kw_norm(ag.name), w)))
       order by ag.created_at desc limit 8) x),
    'requests', (select coalesce(json_agg(x), '[]'::json) from (
      select wq.id, wq.ref, wq.status, wq.deal, wq.gov_name, coalesce(wq.title,'') as title
        from wanted wq
       where bk_admin_country_ok(uid, coalesce(wq.country_code,'SY')) and (sc is null or coalesce(wq.country_code,'SY') = sc)
         and (upper(coalesce(wq.ref,'')) = qref or (num is not null and (wq.ref like '%' || num or wq.id::text = num))
              or wq.title ilike pat or wq.description ilike pat
              or (w is not null and bk_kw_hit(bk_kw_norm(concat_ws(' ', wq.ref, wq.title, wq.gov_name, wq.description)), w)))
       order by wq.created_at desc limit 8) x),
    'drafts', (select coalesce(json_agg(x), '[]'::json) from (
      select d.id, d.status, d.source, d.sender_name, d.listing_id, left(coalesce(d.summary, d.raw_text, ''), 90) as text
        from intake_drafts d
       where bk_admin_country_ok(uid, coalesce(d.country_code,'SY')) and (sc is null or coalesce(d.country_code,'SY') = sc)
         and ((num is not null and d.id::text = num and q ~ '^\s*#') or (dpat is not null and regexp_replace(coalesce(d.chat_id,''), '\D', '', 'g') like dpat)
              or d.sender_name ilike pat
              or (w is not null and bk_kw_hit(bk_kw_norm(concat_ws(' ', d.sender_name, d.fields->>'title')), w)))
       order by d.created_at desc limit 8) x));
end $function$;
