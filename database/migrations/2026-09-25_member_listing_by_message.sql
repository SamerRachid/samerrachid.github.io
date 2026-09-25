-- Balkoun · 2026-09-25 · Listing-by-message opened to any phone-verified member, not just approved agencies.
--
-- Until now bk_intake_sender() only recognised two kinds of WhatsApp/Telegram senders: an approved,
-- intake_enabled agency (matched by its own phone/whatsapp field) and the site's fixed admin numbers.
-- A plain registered member had no way in — their phone matched nothing, bk_intake_message returned
-- reason:'unknown', and they got the "register your agency" reply. bk_intake_publish already fully
-- supports this case (it only requires d.user_id, not an agency; with no agency and no skip_review it
-- inserts the listing as 'pending', i.e. exactly "read it and ask me to accept to be listed") — the only
-- missing piece was sender recognition.
--
-- Gated behind intake_member_listing_on (absent/false by default, read through the existing generic
-- 'intake_%' extras merge in bk_intake_cfg — no schema change needed there) because turning this on lets
-- any phone-verified member trigger a paid Claude read over WhatsApp, so it stays off until explicitly
-- switched on by the admin. Only phone_verified, non-blocked members match, by exact digit equality (no
-- last-9-digits fuzzy fallback — that fallback exists only for agencies' inconsistently formatted legacy
-- phone data). Telegram is intentionally left alone: unlike WhatsApp there is no phone number on the
-- incoming update to match against, and members never get users.tg_chat_id populated today (only admins do).

create or replace function public.bk_intake_sender(p_source text, p_chat_id text)
returns json language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare cfg jsonb; a agencies; u users; is_admin boolean := false; digits text; wa text; cc text; member_ok boolean := false;
begin
  cfg := bk_intake_cfg();
  if p_source = 'telegram' then
    if p_chat_id ~ '^-?\d+$' then select * into a from agencies where intake_telegram = p_chat_id::bigint; end if;
    is_admin := coalesce(cfg->'intake_admin_chats'->'telegram', '[]'::jsonb) ? p_chat_id or exists (select 1 from users where role = 'admin' and tg_chat_id = p_chat_id);
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
      if a.id is null and not is_admin and coalesce(cfg->>'intake_member_listing_on','false') = 'true' then
        select * into u from users
         where bk_intake_norm_phone(phone) = digits and coalesce(blocked,false) = false and coalesce(phone_verified,false) = true
         order by created_at desc nulls last limit 1;
        member_ok := u.id is not null;
      end if;
    end if;
  elsif p_source = 'web' then
    select * into u from users where id::text = p_chat_id;
    if u.id is not null then select * into a from agencies where user_id = u.id; is_admin := u.role = 'admin'; end if;
  end if;
  if a.id is not null then select * into u from users where id = a.user_id; end if;
  if member_ok then
    select co.code into cc from countries co
     where co.phone_code is not null and digits like (regexp_replace(co.phone_code, '\D', '', 'g') || '%')
     order by length(regexp_replace(co.phone_code, '\D', '', 'g')) desc limit 1;
  end if;
  return json_build_object(
    'agency_id', a.id, 'agency_name', a.name, 'agency_status', a.status,
    'user_id', coalesce(a.user_id, u.id), 'user_name', trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),
    'enabled', coalesce(a.status = 'approved' and a.intake_enabled, false) or is_admin or member_ok,
    'trusted', coalesce(a.intake_trusted, false), 'is_admin', is_admin, 'blocked', coalesce(u.blocked, false),
    'country_code', coalesce(a.country_code, cc, 'SY'), 'lang', coalesce(u.lang, 'ar'));
end $function$;
