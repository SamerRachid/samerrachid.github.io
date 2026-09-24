-- Balkoun · 2026-09-24 · WhatsApp verification codes for Syrian numbers via a self-hosted WAHA gateway
-- (applied as migration "waha_verify")
-- Meta's official WhatsApp Cloud API refuses Syrian (+963) numbers entirely, so bk_verify_send_claim
-- used to hard-refuse them. Now Syrian numbers route through a self-hosted WAHA server instead (a real
-- WhatsApp account linked via QR code, running in Docker on a small VPS), while every other country
-- keeps using the existing Meta Cloud API path unchanged. The client's "code by WhatsApp" UI does not
-- change at all — same tickets, same channel value, same OTP boxes; only the Edge Function's send step
-- picks a different transport based on the phone's country. Readiness flag extras.verify_waha_ready is
-- written by the Edge Function's admin "status" action, mirroring verify_wa_ready for the Meta path.

create or replace function public.bk_verify_start(p_phone text, p_purpose text, p_country text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare c jsonb; u users; sec text; code text; t verify_tickets; hrs int; wa_code boolean; is_sy boolean;
begin
  if p_purpose not in ('signup','reset') then raise exception 'badpurpose'; end if;
  if p_phone !~ '^\+[0-9]{8,15}$' then return json_build_object('error','badphone'); end if;
  c := bk_verify_cfg();
  is_sy := p_phone like '+963%';
  wa_code := (c->>'verify_wa_code_on') <> 'false' and
             (case when is_sy then (c->>'verify_waha_ready') = 'true' else (c->>'verify_wa_ready') = 'true' end);
  if (c->>'verify_telegram_on') = 'false' and (c->>'verify_whatsapp_on') = 'false' and not wa_code then return json_build_object('error','off'); end if;
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
  update verify_tickets set status = 'expired' where phone = p_phone and purpose = p_purpose and status = 'pending';
  hrs := greatest(1, least(168, coalesce(nullif(c->>'verify_ticket_hours','')::int, 48)));
  sec := encode(gen_random_bytes(24), 'hex');
  code := lpad(((('x' || encode(gen_random_bytes(3), 'hex'))::bit(24)::int) % 1000000)::text, 6, '0');
  insert into verify_tickets (secret_hash, phone, purpose, code, country_code, expires_at, user_id)
    values (encode(digest(sec, 'sha256'), 'hex'), p_phone, p_purpose, code, upper(nullif(p_country,'')), now() + make_interval(hours => hrs),
            case when p_purpose = 'signup' then u.id end)
    returning * into t;
  return json_build_object('ticket', t.id, 'secret', sec, 'code', t.code, 'phone', t.phone, 'purpose', t.purpose, 'expires_at', t.expires_at,
    'telegram', (c->>'verify_telegram_on') <> 'false' and nullif(c->>'intake_bot','') is not null,
    'whatsapp', (c->>'verify_whatsapp_on') <> 'false',
    'wa_code', wa_code,
    'bot', c->>'intake_bot', 'existing', u.id is not null);
end $$;

create or replace function public.bk_verify_send_claim(p_ticket uuid, p_secret text)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare t verify_tickets; c jsonb; is_sy boolean; ready boolean;
begin
  begin t := bk_verify_ticket(p_ticket, p_secret); exception when others then return json_build_object('error','badticket'); end;
  c := bk_verify_cfg();
  if (c->>'verify_wa_code_on') = 'false' then return json_build_object('error','off'); end if;
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  is_sy := t.phone like '+963%';
  ready := case when is_sy then (c->>'verify_waha_ready') = 'true' else true end;
  if not ready then return json_build_object('error','country'); end if;
  if t.sends >= 3 then return json_build_object('error','limit'); end if;
  if t.last_sent_at is not null and t.last_sent_at > now() - interval '45 seconds' then return json_build_object('error','wait'); end if;
  update verify_tickets set sends = sends + 1, last_sent_at = now(), channel = 'wa_code' where id = t.id;
  return json_build_object('ok', true, 'phone', t.phone, 'code', t.code, 'via', case when is_sy then 'waha' else 'meta' end,
    'template', c->>'verify_wa_template', 'lang', c->>'verify_wa_lang');
end $$;
