-- 2026-10-13 — retire the "send this code to Balkoun's WhatsApp" verification flow (owner's decision after the
-- audit). Verification is now only by a code the server delivers (WhatsApp/email → bk_verify_check), by Telegram
-- contact-share, or by the admin's manual approval. Consequences:
--   • no verification function returns the claim `code` to the browser any more (nothing needs it);
--   • bk_verify_start / bk_admin_verify_start always report whatsapp=false, so the option never renders;
--   • bk_verify_sent (the claim flow's "I sent it" step) answers 'off';
--   • bk_register only accepts a VERIFIED ticket — the "account created through WhatsApp, waiting for the
--     owner's confirmation" path is gone with the flow; the legacy 7-argument overload is dropped (the app
--     calls the 8-argument one with p_type);
--   • the panel switch verify_whatsapp_on is removed from the UI and forced to false in site_content.

begin;

create or replace function public.bk_verify_start(p_phone text, p_purpose text, p_country text default null, p_email text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare c jsonb; u users; sec text; code text; v_otp text; t verify_tickets; hrs int; wa_code boolean; email_on boolean; is_sy boolean; cand_email text; tg_on boolean;
begin
  if p_purpose not in ('signup','reset') then raise exception 'badpurpose'; end if;
  if p_phone !~ '^\+[0-9]{8,15}$' then return json_build_object('error','badphone'); end if;
  c := bk_verify_cfg(coalesce(p_country,'SY'));
  is_sy := p_phone like '+963%';
  wa_code := (c->>'verify_wa_code_on') <> 'false' and
             ((c->>'verify_waha_ready') = 'true' or (not is_sy and (c->>'verify_wa_ready') = 'true'));
  email_on := (c->>'verify_email_on') <> 'false' and (c->>'verify_email_ready') = 'true';
  tg_on := (c->>'verify_telegram_on') <> 'false' and nullif(c->>'intake_bot','') is not null;
  if not tg_on and not wa_code and not email_on then return json_build_object('error','off'); end if;
  select * into u from users where phone = p_phone;
  if p_purpose = 'signup' and u.id is not null and u.phone_verified is distinct from false then return json_build_object('error','exists'); end if;
  if p_purpose = 'reset' then
    if u.id is null then return json_build_object('error','nouser'); end if;
    if u.blocked then return json_build_object('error','blocked'); end if;
  end if;
  if (select count(*) from verify_tickets where phone = p_phone and created_at > now() - interval '1 hour') >= 6
     or (select count(*) from verify_tickets where created_at > now() - interval '1 minute') >= 60 then
    return json_build_object('error','throttled');
  end if;
  if p_purpose = 'signup' and p_email is not null then
    cand_email := lower(trim(p_email));
    if cand_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then cand_email := null;
    elsif exists (select 1 from users where lower(email) = cand_email) then cand_email := null;
    end if;
  end if;
  update verify_tickets set status = 'expired' where phone = p_phone and purpose = p_purpose and status = 'pending';
  hrs := greatest(1, least(168, coalesce(nullif(c->>'verify_ticket_hours','')::int, 48)));
  sec := encode(gen_random_bytes(24), 'hex');
  code := lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0');
  v_otp := lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0');
  insert into verify_tickets (secret_hash, phone, purpose, code, otp, country_code, expires_at, user_id, email)
    values (encode(digest(sec, 'sha256'), 'hex'), p_phone, p_purpose, code, v_otp, upper(nullif(p_country,'')), now() + make_interval(hours => hrs),
            case when p_purpose = 'signup' then u.id end,
            case when p_purpose = 'signup' then cand_email end)
    returning * into t;
  return json_build_object('ticket', t.id, 'secret', sec, 'phone', t.phone, 'purpose', t.purpose, 'expires_at', t.expires_at,
    'telegram', tg_on,
    'whatsapp', false,
    'wa_code', wa_code,
    'email', case when p_purpose = 'signup' then email_on and cand_email is not null else email_on and u.email is not null and u.email_verified end,
    'bot', c->>'intake_bot', 'existing', u.id is not null);
end $$;

create or replace function public.bk_admin_verify_start(p_phone text) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare u users; sec text; code text; v_otp text; t verify_tickets; c jsonb;
begin
  if p_phone !~ '^\+[0-9]{8,15}$' then return json_build_object('error','badphone'); end if;
  if not bk_login_guard(p_phone) then return json_build_object('error','locked'); end if;
  select * into u from users where phone = p_phone and role = 'admin';
  if u.id is null then perform bk_login_fail(p_phone); return json_build_object('error','notadmin'); end if;
  if (select count(*) from verify_tickets where phone = p_phone and purpose = 'admin_reset' and created_at > now() - interval '1 hour') >= 5 then return json_build_object('error','throttled'); end if;
  c := bk_verify_cfg();
  update verify_tickets set status = 'expired' where phone = p_phone and purpose = 'admin_reset' and status = 'pending';
  sec := encode(gen_random_bytes(24), 'hex');
  code := lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0');
  v_otp := lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0');
  insert into verify_tickets (secret_hash, phone, purpose, code, otp, country_code, expires_at, user_id)
    values (encode(digest(sec, 'sha256'), 'hex'), p_phone, 'admin_reset', code, v_otp, coalesce(u.admin_countries[1], 'SY'), now() + interval '2 hours', u.id)
    returning * into t;
  return json_build_object('ticket', t.id, 'secret', sec, 'expires_at', t.expires_at,
    'telegram', nullif(c->>'intake_bot','') is not null, 'whatsapp', false, 'bot', c->>'intake_bot');
end $$;

create or replace function public.bk_verify_status(p_ticket uuid, p_secret text) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare t verify_tickets;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.status = 'pending' and t.expires_at < now() then update verify_tickets set status = 'expired' where id = t.id; t.status := 'expired'; end if;
  return json_build_object('status', t.status, 'channel', t.channel, 'purpose', t.purpose, 'phone', t.phone, 'expires_at', t.expires_at, 'user_id', t.user_id,
    'verified', t.status in ('verified','used'));
end $$;

create or replace function public.bk_verify_sent(p_ticket uuid, p_secret text) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
begin
  perform bk_verify_ticket(p_ticket, p_secret);
  return json_build_object('error','off');   -- the claim flow is retired
end $$;

drop function if exists public.bk_register(uuid, text, text, text, text, text, text);
create or replace function public.bk_register(p_ticket uuid, p_secret text, p_name text, p_family text, p_hash text, p_currency text default 'USD', p_lang text default null, p_type text default 'member') returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare t verify_tickets; u users; v_currency text; tok text; v_lang text; v_email text; v_type text;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.purpose <> 'signup' then raise exception 'badticket'; end if;
  if t.status <> 'verified' then return json_build_object('error','notverified'); end if;
  if exists (select 1 from users where phone = t.phone) then return json_build_object('error','exists'); end if;
  if length(coalesce(p_hash,'')) < 32 then raise exception 'bad hash'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'name required'; end if;
  v_currency := case when upper(coalesce(p_currency,'')) ~ '^[A-Z]{3}$' then upper(p_currency) else 'USD' end;
  v_lang := case when p_lang in ('ar','en','de','fr') then p_lang else null end;
  v_type := case when p_type in ('member','broker','agency') then p_type else 'member' end;
  v_email := case when t.channel = 'email' and t.email is not null and not exists (select 1 from users where lower(email) = t.email) then t.email end;
  insert into users (phone, name, family_name, pass_hash, phone_verified, preferred_currency, lang, country, email, email_verified, account_type)
    values (t.phone, left(trim(p_name),60), left(trim(coalesce(p_family,'')),60), crypt(p_hash, gen_salt('bf')), true, v_currency, v_lang, t.country_code, v_email, v_email is not null, v_type)
    returning * into u;
  update verify_tickets set user_id = u.id, status = 'used', used_at = now() where id = t.id;
  if t.channel = 'telegram' and t.tg_chat_id is not null then
    update users set tg_chat_id = t.tg_chat_id, tg_name = left(t.tg_name, 80), tg_paired_at = now() where id = u.id;
    update contacts set tg_chat_id = t.tg_chat_id, tg_consent = 'subscribed', updated_at = now() where user_id = u.id;
  end if;
  insert into notifications (user_id, type, title, body, link, is_read) values (u.id, 'system', 'welcome', null, '/#/post', false);
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'city',u.city,'country',u.country,'preferred_currency',u.preferred_currency,'role',u.role,'phone_verified',u.phone_verified,'member_no',u.member_no,
    'email',u.email,'email_verified',u.email_verified,'account_type',u.account_type,'token',tok);
end $$;

update site_content set extras = coalesce(extras,'{}'::jsonb) || '{"verify_whatsapp_on":"false"}'::jsonb where true;

commit;

select count(*) as rows_off from site_content where extras->>'verify_whatsapp_on' = 'false';
