-- bk_intake_sender: a member's listings go to a switched-on country (the +966 sender, draft 833, 2026-10-24)
CREATE OR REPLACE FUNCTION public.bk_intake_sender(p_source text, p_chat_id text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cfg jsonb; a agencies; u users; is_admin boolean := false; digits text; wa text; cc text; member_ok boolean := false; member_on boolean;
begin
  cfg := bk_intake_cfg();
  member_on := coalesce(cfg->>'intake_member_listing_on','false') = 'true';
  if p_source = 'telegram' then
    if p_chat_id ~ '^-?\d+$' then select * into a from agencies where intake_telegram = p_chat_id::bigint; end if;
    is_admin := coalesce(cfg->'intake_admin_chats'->'telegram', '[]'::jsonb) ? p_chat_id or exists (select 1 from users where role = 'admin' and tg_chat_id = p_chat_id);
    if a.id is null and not is_admin and member_on then
      select * into u from users
       where tg_chat_id = p_chat_id and role <> 'admin' and coalesce(blocked,false) = false
       order by tg_paired_at desc nulls last limit 1;
      member_ok := u.id is not null;
      if member_ok then select code into cc from countries where enabled and code = upper(u.country); end if;
    end if;
  elsif p_source = 'whatsapp' then
    digits := bk_intake_norm_phone(p_chat_id);
    if digits is not null then
      select ag.* into a from agencies ag
        left join users us on us.id = ag.user_id
        left join countries co on co.code = coalesce(ag.country_code,'SY')
       where ag.status = 'approved' and (
             bk_intake_norm_phone(ag.intake_phone) = digits
          or bk_intake_norm_phone(ag.whatsapp) = digits or bk_intake_norm_phone(ag.phone) = digits
          or bk_intake_norm_phone(us.phone) = digits
          or (length(digits) >= 9 and digits like (regexp_replace(coalesce(co.phone_code,''), '\D', '', 'g') || '%')
              and ((coalesce(ag.whatsapp,'') ~ '^\s*0' or length(bk_intake_norm_phone(ag.whatsapp)) <= 10) and right(bk_intake_norm_phone(ag.whatsapp), 9) = right(digits, 9)
                or (coalesce(ag.phone,'') ~ '^\s*0' or length(bk_intake_norm_phone(ag.phone)) <= 10) and right(bk_intake_norm_phone(ag.phone), 9) = right(digits, 9))))
       order by (bk_intake_norm_phone(ag.intake_phone) = digits) desc nulls last, ag.id limit 1;
      select bk_intake_norm_phone(wa_number) into wa from site_content where id = 1;
      is_admin := (wa is not null and wa = digits)
               or coalesce(cfg->'intake_admin_chats'->'whatsapp', '[]'::jsonb) ? digits
               or exists (select 1 from users where role = 'admin' and bk_intake_norm_phone(phone) = digits);
      if a.id is null and not is_admin and member_on then
        select * into u from users
         where bk_intake_norm_phone(phone) = digits and coalesce(blocked,false) = false
         order by created_at desc nulls last limit 1;
        member_ok := u.id is not null;
        -- the listing country: the member's own country, then the phone's, but only a country the site has switched on
        -- (owner, 2026-10-24: a Syrian in Saudi Arabia, +966, had his Damascus flat read against Saudi places)
        if member_ok then
          select co.code into cc from countries co where co.enabled and co.code = upper(u.country);
          if cc is null then
            select co.code into cc from countries co
             where co.enabled and co.phone_code is not null and digits like (regexp_replace(co.phone_code, '\D', '', 'g') || '%')
             order by length(regexp_replace(co.phone_code, '\D', '', 'g')) desc limit 1;
          end if;
        end if;
      end if;
    end if;
  elsif p_source = 'web' then
    select * into u from users where id::text = p_chat_id;
    if u.id is not null then select * into a from agencies where user_id = u.id; is_admin := u.role = 'admin'; end if;
  end if;
  if a.id is not null then select * into u from users where id = a.user_id; end if;
  return json_build_object(
    'agency_id', a.id, 'agency_name', a.name, 'agency_status', a.status,
    'user_id', coalesce(a.user_id, u.id), 'user_name', trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),
    'enabled', coalesce(a.status = 'approved' and a.intake_enabled, false) or is_admin or member_ok,
    'trusted', coalesce(a.intake_trusted, false), 'is_admin', is_admin, 'blocked', coalesce(u.blocked, false),
    'country_code', coalesce(a.country_code, cc, 'SY'), 'lang', coalesce(u.lang, 'ar'), 'member_listing', member_on, 'account_type', u.account_type,
    'hide_phone', coalesce(u.hide_phone, false));
end $function$;
