-- 2026-10-13 — security audit fixes (server side). Three findings closed here:
--
-- (1) Phone verification was bypassable: bk_verify_start / bk_admin_verify_start / bk_verify_status handed the
--     6-digit code to the browser (needed for the "send this code to Balkoun's WhatsApp" claim flow, where the bot
--     checks the SENDER's number), but bk_verify_check compared the typed code against that same value — so for the
--     channels where the server delivers the code (WhatsApp code, email) anyone could "verify" any phone number,
--     and with purpose=reset take over any member's account (or the admin's) knowing only the phone number.
--     Fix: a second, server-only column `otp`. The claim `code` stays public (it proves nothing by itself); `otp`
--     is what gets delivered and what bk_verify_check compares, and it is never returned to anon.
--     bk_verify_send_claim (the only reader of otp, called by the edge function with the service key) loses its
--     public grant. Telegram: the "code" mode sent the code to whoever opened the link (no phone proof) — gone;
--     every purpose now uses the contact-share mode (bk_verify_tg_contact checks the shared number).
-- (2) Internal helpers were executable with the public key: bk_user_purge (delete any member + listings by uuid),
--     bk_reward_square (free homepage square for any listing), bk_wanted_ping (send WhatsApp/Telegram pings),
--     bk_campaign_audience, admin scope helpers, reward helpers. Revoked; their callers are SECURITY DEFINER.
-- (3) Unused public INSERT policies (listings as any user_id, feedback, reports, contact events, page views): the
--     app writes all of these through RPCs; the policies only served spam and HTML injection into the admin panel.

begin;

-- ───────────── (1) OTP split ─────────────
alter table public.verify_tickets add column if not exists otp text;

create or replace function public.bk_verify_start(p_phone text, p_purpose text, p_country text default null, p_email text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare c jsonb; u users; sec text; code text; v_otp text; t verify_tickets; hrs int; wa_code boolean; email_on boolean; is_sy boolean; cand_email text;
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
  v_otp := lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0');
  insert into verify_tickets (secret_hash, phone, purpose, code, otp, country_code, expires_at, user_id, email)
    values (encode(digest(sec, 'sha256'), 'hex'), p_phone, p_purpose, code, v_otp, upper(nullif(p_country,'')), now() + make_interval(hours => hrs),
            case when p_purpose = 'signup' then u.id end,
            case when p_purpose = 'signup' then cand_email end)
    returning * into t;
  -- `code` is the claim code the member sends to Balkoun's WhatsApp from their own phone; the delivered otp is never returned
  return json_build_object('ticket', t.id, 'secret', sec, 'code', t.code, 'phone', t.phone, 'purpose', t.purpose, 'expires_at', t.expires_at,
    'telegram', (c->>'verify_telegram_on') <> 'false' and nullif(c->>'intake_bot','') is not null,
    'whatsapp', (c->>'verify_whatsapp_on') <> 'false',
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
  return json_build_object('ticket', t.id, 'secret', sec, 'code', t.code, 'expires_at', t.expires_at,
    'telegram', nullif(c->>'intake_bot','') is not null, 'whatsapp', not u.is_super_admin, 'bot', c->>'intake_bot');
end $$;

create or replace function public.bk_verify_check(p_ticket uuid, p_secret text, p_code text) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare t verify_tickets;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.status in ('verified','used') then return json_build_object('ok', true, 'purpose', t.purpose); end if;
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  if t.channel not in ('wa_code','email','telegram') or t.sends = 0 then return json_build_object('error','notsent'); end if;
  if t.attempts >= 5 then update verify_tickets set status = 'rejected' where id = t.id; return json_build_object('error','rejected'); end if;
  -- only the server-delivered otp counts; a ticket without one (made before this fix) can never pass
  if t.otp is null or regexp_replace(coalesce(p_code,''), '\D', '', 'g') <> t.otp then
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

-- the delivering function: service key only (the edge function), returns the otp under the key it already sends
drop function if exists public.bk_verify_send_claim(uuid, text);
create or replace function public.bk_verify_send_claim(p_ticket uuid, p_secret text, p_channel text default 'wa_code', p_email text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare t verify_tickets; c jsonb; is_sy boolean; ready boolean; via text; v_email text; v_ok boolean; regen boolean;
begin
  begin t := bk_verify_ticket(p_ticket, p_secret); exception when others then return json_build_object('error','badticket'); end;
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  if t.sends >= 3 then return json_build_object('error','limit'); end if;
  if t.last_sent_at is not null and t.last_sent_at > now() - interval '45 seconds' then return json_build_object('error','wait'); end if;
  if t.otp is null then
    update verify_tickets set otp = lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0') where id = t.id returning * into t;
  end if;
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
        otp = lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0'), attempts = 0
        where id = t.id returning * into t;
    else
      update verify_tickets set sends = sends + 1, last_sent_at = now(), channel = 'email', email = v_email where id = t.id returning * into t;
    end if;
    return json_build_object('ok', true, 'to', v_email, 'code', t.otp, 'via', 'email');
  end if;

  is_sy := t.phone like '+963%';
  via := case when not is_sy and (c->>'verify_wa_ready') = 'true' then 'meta' else 'waha' end;
  ready := case when via = 'waha' then (c->>'verify_waha_ready') = 'true' else true end;
  if not ready then return json_build_object('error','country'); end if;
  update verify_tickets set sends = sends + 1, last_sent_at = now(), channel = 'wa_code' where id = t.id;
  return json_build_object('ok', true, 'phone', t.phone, 'code', t.otp, 'via', via,
    'template', c->>'verify_wa_template', 'lang', c->>'verify_wa_lang');
end $$;
revoke execute on function public.bk_verify_send_claim(uuid, text, text, text) from public, anon, authenticated;

-- Telegram: contact-share for every purpose (the bot already asks for the contact when mode <> 'code')
create or replace function public.bk_verify_tg_open(p_ticket uuid, p_chat_id text, p_name text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare t verify_tickets; c jsonb;
begin
  select * into t from verify_tickets where id = p_ticket;
  if t.id is null or t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','notfound'); end if;
  c := bk_verify_cfg(coalesce(t.country_code,'SY'));
  if (c->>'verify_telegram_on') = 'false' then return json_build_object('error','off'); end if;
  update verify_tickets set tg_chat_id = p_chat_id, tg_name = left(p_name, 80), channel = 'telegram' where id = t.id;
  return json_build_object('ok', true, 'mode', 'contact', 'purpose', t.purpose, 'tail', right(t.phone, 4));
end $$;

-- ───────────── (2) internal helpers: not callable with the public key ─────────────
revoke execute on function public.bk_user_purge(uuid, text, uuid) from public, anon, authenticated;
revoke execute on function public.bk_reward_square(bigint, integer) from public, anon, authenticated;
revoke execute on function public.bk_recompute_featured(bigint) from public, anon, authenticated;
revoke execute on function public.bk_wanted_ping(bigint, bigint) from public, anon, authenticated;
revoke execute on function public.bk_campaign_audience(uuid) from public, anon, authenticated;
revoke execute on function public.bk_admin_scope(uuid, text) from public, anon, authenticated;
revoke execute on function public.bk_admin_allowed(uuid) from public, anon, authenticated;
revoke execute on function public.bk_admin_guard(uuid, text) from public, anon, authenticated;
revoke execute on function public.bk_admin_guard_opt(uuid, text) from public, anon, authenticated;
revoke execute on function public.bk_admin_is_super(uuid) from public, anon, authenticated;
revoke execute on function public.bk_reward_balance(uuid) from public, anon, authenticated;
revoke execute on function public.bk_reward_earning(jsonb, uuid) from public, anon, authenticated;
revoke execute on function public.bk_reward_window_end(jsonb, uuid) from public, anon, authenticated;
revoke execute on function public.bk_require_verified(uuid) from public, anon, authenticated;
revoke execute on function public.bk_verify_tg_open(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.bk_verify_tg_contact(text, text, text) from public, anon, authenticated;

-- ───────────── (3) public INSERT policies the app never used ─────────────
drop policy if exists p_listing_insert on public.listings;
drop policy if exists p_feedback_write on public.feedback;
drop policy if exists p_report_write on public.listing_reports;
drop policy if exists p_contact_write on public.contact_events;
drop policy if exists p_pv_insert on public.page_views;

commit;

select proname, has_function_privilege('anon', oid, 'EXECUTE') as anon_exec
  from pg_proc where pronamespace = 'public'::regnamespace and proname in ('bk_user_purge','bk_verify_send_claim','bk_verify_start','bk_verify_check')
 order by 1;
