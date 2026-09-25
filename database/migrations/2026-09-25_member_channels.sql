-- Balkoun · 2026-09-25 · Members get their channels wired at signup: consent for WhatsApp/email, Telegram
-- linked with one tap, and listing-by-message recognised on Telegram too (WhatsApp already matches by phone).
--
-- Telegram can never message someone who hasn't opened a chat with the bot, so "automatic" here means:
--   1. verified via Telegram at signup → the ticket already knows the chat → users.tg_chat_id + the contacts row
--      are linked inside bk_register (and in bk_verify_check for an account that verifies later);
--   2. otherwise the account page / welcome screen offers the existing "/start n<contact>" deep link, and
--      bk_contact_tg_open now links the user as well as the contact;
--   3. an unlinked member who just messages the bot gets a "share my number" button; Telegram vouches for the
--      number, bk_member_tg_link matches it to the account (and counts as phone verification, same trust as the
--      admin_reset share-contact road).
-- Consent is the member's own (bk_member_consent / bk_member_channels, token-guarded), never assumed.

-- 1. bk_register: live body + the Telegram link when the ticket was verified through the bot
create or replace function public.bk_register(p_ticket uuid, p_secret text, p_name text, p_family text, p_hash text, p_currency text default 'USD'::text, p_lang text default null::text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare t verify_tickets; u users; v_currency text; tok text; v_lang text; v_ok boolean; v_email text;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.purpose <> 'signup' then raise exception 'badticket'; end if;
  if t.status = 'verified' then v_ok := true;
  elsif t.status = 'pending' and t.channel = 'whatsapp' and t.wa_sent_at is not null and t.expires_at > now() then v_ok := false;
  else return json_build_object('error','notverified'); end if;
  if exists (select 1 from users where phone = t.phone) then return json_build_object('error','exists'); end if;
  if length(coalesce(p_hash,'')) < 32 then raise exception 'bad hash'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'name required'; end if;
  v_currency := case when upper(coalesce(p_currency,'')) ~ '^[A-Z]{3}$' then upper(p_currency) else 'USD' end;
  v_lang := case when p_lang in ('ar','en','de','fr') then p_lang else null end;
  v_email := case when v_ok and t.channel = 'email' and t.email is not null and not exists (select 1 from users where lower(email) = t.email)
             then t.email end;
  insert into users (phone, name, family_name, pass_hash, phone_verified, preferred_currency, lang, country, email, email_verified)
    values (t.phone, left(trim(p_name),60), left(trim(coalesce(p_family,'')),60), crypt(p_hash, gen_salt('bf')), v_ok, v_currency, v_lang, t.country_code, v_email, v_email is not null)
    returning * into u;
  update verify_tickets set user_id = u.id, status = case when v_ok then 'used' else 'pending' end, used_at = case when v_ok then now() end where id = t.id;
  if v_ok and t.channel = 'telegram' and t.tg_chat_id is not null then
    update users set tg_chat_id = t.tg_chat_id, tg_name = left(t.tg_name, 80), tg_paired_at = now() where id = u.id;
    update contacts set tg_chat_id = t.tg_chat_id, tg_consent = 'subscribed', updated_at = now() where user_id = u.id;
  end if;
  insert into notifications (user_id, type, title, body, link, is_read) values (u.id, 'system', 'welcome', null, '/#/post', false);
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'city',u.city,'country',u.country,'preferred_currency',u.preferred_currency,'role',u.role,'phone_verified',u.phone_verified,'member_no',u.member_no,
    'email',u.email,'email_verified',u.email_verified,'token',tok);
end $function$;

-- 2. bk_verify_check: an existing account that verifies through Telegram later (the "unverified" page) links too
create or replace function public.bk_verify_check(p_ticket uuid, p_secret text, p_code text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.status in ('verified','used') then return json_build_object('ok', true, 'purpose', t.purpose); end if;
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  if t.channel not in ('wa_code','email','telegram') or t.sends = 0 then return json_build_object('error','notsent'); end if;
  if t.attempts >= 5 then update verify_tickets set status = 'rejected' where id = t.id; return json_build_object('error','rejected'); end if;
  if regexp_replace(coalesce(p_code,''), '\D', '', 'g') <> t.code then
    update verify_tickets set attempts = attempts + 1 where id = t.id;
    return json_build_object('error','wrong', 'left', 5 - t.attempts - 1);
  end if;
  update verify_tickets set status = 'verified', verified_at = now() where id = t.id;
  if t.purpose = 'signup' and t.user_id is not null then
    update users set phone_verified = true where id = t.user_id;
    if t.channel = 'telegram' and t.tg_chat_id is not null then
      update users set tg_chat_id = t.tg_chat_id, tg_name = left(t.tg_name, 80), tg_paired_at = now() where id = t.user_id and role <> 'admin';
      update contacts set tg_chat_id = t.tg_chat_id, tg_consent = case when tg_consent = 'unsubscribed' then tg_consent else 'subscribed' end, updated_at = now() where user_id = t.user_id;
    end if;
  end if;
  return json_build_object('ok', true, 'purpose', t.purpose);
end $$;

-- 3. bk_intake_sender: a linked, phone-verified member is a known Telegram sender too (same flag as WhatsApp);
--    the JSON now also says whether that member road is open so the bot knows to offer the share-number button
create or replace function public.bk_intake_sender(p_source text, p_chat_id text)
returns json language plpgsql stable security definer set search_path to 'public', 'extensions' as $function$
declare cfg jsonb; a agencies; u users; is_admin boolean := false; digits text; wa text; cc text; member_ok boolean := false; member_on boolean;
begin
  cfg := bk_intake_cfg();
  member_on := coalesce(cfg->>'intake_member_listing_on','false') = 'true';
  if p_source = 'telegram' then
    if p_chat_id ~ '^-?\d+$' then select * into a from agencies where intake_telegram = p_chat_id::bigint; end if;
    is_admin := coalesce(cfg->'intake_admin_chats'->'telegram', '[]'::jsonb) ? p_chat_id or exists (select 1 from users where role = 'admin' and tg_chat_id = p_chat_id);
    if a.id is null and not is_admin and member_on then
      select * into u from users
       where tg_chat_id = p_chat_id and role <> 'admin' and coalesce(blocked,false) = false and coalesce(phone_verified,false) = true
       order by tg_paired_at desc nulls last limit 1;
      member_ok := u.id is not null;
      if member_ok then select code into cc from countries where code = upper(u.country); end if;
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
         where bk_intake_norm_phone(phone) = digits and coalesce(blocked,false) = false and coalesce(phone_verified,false) = true
         order by created_at desc nulls last limit 1;
        member_ok := u.id is not null;
        if member_ok then
          select co.code into cc from countries co
           where co.phone_code is not null and digits like (regexp_replace(co.phone_code, '\D', '', 'g') || '%')
           order by length(regexp_replace(co.phone_code, '\D', '', 'g')) desc limit 1;
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
    'country_code', coalesce(a.country_code, cc, 'SY'), 'lang', coalesce(u.lang, 'ar'), 'member_listing', member_on);
end $function$;

-- 4. the bot's "share my number" answer from a member with no open verification ticket (service-only).
--    Telegram only lets a user share their own contact card, and the Edge Function already refuses a card
--    whose user_id is not the sender's — so the number is proven, and this also verifies an unverified account.
create or replace function public.bk_member_tg_link(p_chat_id text, p_phone text, p_name text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare digits text; u users;
begin
  digits := bk_intake_norm_phone(p_phone);
  if digits is null or digits = '' then return json_build_object('error','notfound'); end if;
  select * into u from users
   where bk_intake_norm_phone(phone) = digits and role <> 'admin' and coalesce(blocked,false) = false
   order by (coalesce(phone_verified,false)) desc, created_at desc limit 1;
  if u.id is null then return json_build_object('error','notfound'); end if;
  update users set tg_chat_id = p_chat_id, tg_name = left(p_name, 80), tg_paired_at = now(), phone_verified = true where id = u.id;
  update contacts set tg_chat_id = p_chat_id, tg_consent = case when tg_consent = 'unsubscribed' then tg_consent else 'subscribed' end, updated_at = now() where user_id = u.id;
  insert into intake_log (chat_id, event, detail) values (p_chat_id, 'member_tg_linked', jsonb_build_object('user_id', u.id));
  return json_build_object('ok', true, 'name', trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')));
end $function$;
revoke execute on function public.bk_member_tg_link(text, text, text) from public, anon, authenticated;

-- 5. the "/start n<contact>" deep link links the account behind the contact as well (admins keep their own pairing)
create or replace function public.bk_contact_tg_open(p_contact_id uuid, p_chat_id text, p_name text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  update contacts set tg_chat_id = p_chat_id, tg_consent = case when tg_consent = 'unsubscribed' then tg_consent else 'subscribed' end, updated_at = now()
   where id = p_contact_id;
  if not found then return json_build_object('error', 'notfound'); end if;
  update users set tg_chat_id = p_chat_id, tg_name = left(p_name, 80), tg_paired_at = now()
   where id = (select user_id from contacts where id = p_contact_id) and role <> 'admin';
  return json_build_object('ok', true);
end $function$;
revoke execute on function public.bk_contact_tg_open(uuid, text, text) from public, anon, authenticated;

-- 6. member-facing: the account page's channels card (creates the contacts row if the sync trigger never ran)
create or replace function public.bk_member_channels(p_token text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; c contacts; u users; bot text;
begin
  uid := bk_member_uid(p_token); if uid is null then return json_build_object('error', 'unauthorised'); end if;
  select * into u from users where id = uid;
  if u.id is null then return json_build_object('error', 'unauthorised'); end if;
  select * into c from contacts where user_id = uid;
  if c.id is null then
    insert into contacts (user_id, phone, email, name, country_code, city_text, source)
      values (uid, u.phone, u.email, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),
              coalesce((select code from countries where code = upper(u.country)), 'SY'), u.city, 'member')
      returning * into c;
  end if;
  select coalesce(extras->>'intake_bot','') into bot from site_content where id = 1;
  return json_build_object('contact_id', c.id, 'wa_consent', c.wa_consent, 'tg_consent', c.tg_consent, 'email_consent', c.email_consent,
    'tg_linked', (u.tg_chat_id is not null or c.tg_chat_id is not null), 'has_email', u.email is not null, 'bot', bot);
end $function$;

-- 7. member-facing: the member sets their own consent per channel (null = leave as is)
create or replace function public.bk_member_consent(p_token text, p_wa text default null, p_email text default null, p_tg text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; ok text[] := array['subscribed','unsubscribed'];
begin
  uid := bk_member_uid(p_token); if uid is null then return json_build_object('error', 'unauthorised'); end if;
  perform bk_member_channels(p_token);
  update contacts set
    wa_consent = case when p_wa = any(ok) then p_wa else wa_consent end,
    email_consent = case when p_email = any(ok) then p_email else email_consent end,
    tg_consent = case when p_tg = any(ok) then p_tg else tg_consent end,
    updated_at = now()
   where user_id = uid;
  return json_build_object('ok', true);
end $function$;
