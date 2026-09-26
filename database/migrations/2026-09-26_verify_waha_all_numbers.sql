-- Balkoun · 2026-09-26 · the WhatsApp verification code goes through WAHA for EVERY number while Meta's Cloud API
-- is not ready (verify_wa_ready = false). Before, wa_code was offered to non-Syrian numbers only when Meta was
-- ready, so a Canadian sign-up saw email/Telegram only. Once Meta is ready, non-Syrian numbers switch to it.

create or replace function public.bk_verify_start(p_phone text, p_purpose text, p_country text default null::text, p_email text default null::text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare c jsonb; u users; sec text; code text; t verify_tickets; hrs int; wa_code boolean; email_on boolean; is_sy boolean; cand_email text;
begin
  if p_purpose not in ('signup','reset') then raise exception 'badpurpose'; end if;
  if p_phone !~ '^\+[0-9]{8,15}$' then return json_build_object('error','badphone'); end if;
  c := bk_verify_cfg(coalesce(p_country,'SY'));
  is_sy := p_phone like '+963%';
  wa_code := (c->>'verify_wa_code_on') <> 'false' and
             ((c->>'verify_waha_ready') = 'true' or (not is_sy and (c->>'verify_wa_ready') = 'true'));
  email_on := (c->>'verify_email_on') <> 'false' and (c->>'verify_email_ready') = 'true';
  if (c->>'verify_telegram_on') = 'false' and (c->>'verify_whatsapp_on') = 'false' and not wa_code and not email_on then return json_build_object('error','off'); end if;
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
  insert into verify_tickets (secret_hash, phone, purpose, code, country_code, expires_at, user_id, email)
    values (encode(digest(sec, 'sha256'), 'hex'), p_phone, p_purpose, code, upper(nullif(p_country,'')), now() + make_interval(hours => hrs),
            case when p_purpose = 'signup' then u.id end,
            case when p_purpose = 'signup' then cand_email end)
    returning * into t;
  return json_build_object('ticket', t.id, 'secret', sec, 'code', t.code, 'phone', t.phone, 'purpose', t.purpose, 'expires_at', t.expires_at,
    'telegram', (c->>'verify_telegram_on') <> 'false' and nullif(c->>'intake_bot','') is not null,
    'whatsapp', (c->>'verify_whatsapp_on') <> 'false',
    'wa_code', wa_code,
    'email', case when p_purpose = 'signup' then email_on and cand_email is not null else email_on and u.email is not null and u.email_verified end,
    'bot', c->>'intake_bot', 'existing', u.id is not null);
end $function$;

create or replace function public.bk_verify_send_claim(p_ticket uuid, p_secret text, p_channel text default 'wa_code'::text, p_email text default null::text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare t verify_tickets; c jsonb; is_sy boolean; ready boolean; via text; v_email text; v_ok boolean; regen boolean;
begin
  begin t := bk_verify_ticket(p_ticket, p_secret); exception when others then return json_build_object('error','badticket'); end;
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  if t.sends >= 3 then return json_build_object('error','limit'); end if;
  if t.last_sent_at is not null and t.last_sent_at > now() - interval '45 seconds' then return json_build_object('error','wait'); end if;
  c := bk_verify_cfg(coalesce(t.country_code,'SY'));

  if p_channel = 'email' then
    if (c->>'verify_email_on') = 'false' or (c->>'verify_email_ready') <> 'true' then return json_build_object('error','off'); end if;
    if t.purpose = 'signup' then
      v_email := lower(trim(coalesce(p_email,'')));
      if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then return json_build_object('error','bademail'); end if;
      if exists (select 1 from users where lower(email) = v_email) then return json_build_object('error','exists'); end if;
      if (select count(*) from verify_tickets where lower(email) = v_email and last_sent_at > now() - interval '1 hour') >= 6
        then return json_build_object('error','throttled'); end if;
      regen := t.email is not null and t.email <> v_email;
    elsif t.purpose = 'reset' then
      select lower(u.email), u.email_verified into v_email, v_ok from users u where u.phone = t.phone;
      if not coalesce(v_ok,false) or v_email is null then return json_build_object('error','off'); end if;
    else
      return json_build_object('error','badticket');
    end if;
    if regen then
      update verify_tickets set sends = sends + 1, last_sent_at = now(), channel = 'email', email = v_email,
        code = lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0'), attempts = 0
        where id = t.id returning * into t;
    else
      update verify_tickets set sends = sends + 1, last_sent_at = now(), channel = 'email', email = v_email where id = t.id returning * into t;
    end if;
    return json_build_object('ok', true, 'to', v_email, 'code', t.code, 'via', 'email');
  end if;

  is_sy := t.phone like '+963%';
  -- Meta (official) for non-Syrian numbers once it is ready; WAHA for Syria always, and for everyone until then
  via := case when not is_sy and (c->>'verify_wa_ready') = 'true' then 'meta' else 'waha' end;
  ready := case when via = 'waha' then (c->>'verify_waha_ready') = 'true' else true end;
  if not ready then return json_build_object('error','country'); end if;
  update verify_tickets set sends = sends + 1, last_sent_at = now(), channel = 'wa_code' where id = t.id;
  return json_build_object('ok', true, 'phone', t.phone, 'code', t.code, 'via', via,
    'template', c->>'verify_wa_template', 'lang', c->>'verify_wa_lang');
end $function$;
