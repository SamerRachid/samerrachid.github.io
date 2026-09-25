-- Balkoun · 2026-09-24 · Telegram verification becomes a typed code (signup/reset), matching WhatsApp/Email.
--
-- The admin panel's own password-recovery flow (purpose='admin_reset') keeps the original "share my contact"
-- button unchanged — it has no OTP-entry UI and never will (bk_verify_tg_contact, untouched, still serves it
-- exclusively). Only signup/reset switch to: open Telegram → bot sends the ticket's own 6-digit code as a
-- plain message → typed into the same OTP boxes wa_code/email already use → bk_verify_check (widened below).
--
-- No separate "send-claim" step exists for Telegram the way wa_code/email have one (the send is triggered by
-- Telegram's own server hitting the bot webhook when the user taps the deep link, not by a site-initiated
-- call) — so the rate limit lives directly in bk_verify_tg_open, capped generously (10) since re-tapping the
-- link is a bounded, free-to-send action, unlike WhatsApp/email sends which cost money or hit provider limits.

create or replace function public.bk_verify_tg_open(p_ticket uuid, p_chat_id text, p_name text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare t verify_tickets; c jsonb;
begin
  select * into t from verify_tickets where id = p_ticket;
  if t.id is null or t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','notfound'); end if;
  c := bk_verify_cfg(coalesce(t.country_code,'SY'));
  if (c->>'verify_telegram_on') = 'false' then return json_build_object('error','off'); end if;
  if t.purpose = 'admin_reset' then
    update verify_tickets set tg_chat_id = p_chat_id, tg_name = left(p_name, 80), channel = 'telegram' where id = t.id;
    return json_build_object('ok', true, 'mode', 'contact', 'purpose', t.purpose, 'tail', right(t.phone, 4));
  end if;
  if t.sends >= 10 then return json_build_object('error', 'limit'); end if;
  update verify_tickets set tg_chat_id = p_chat_id, tg_name = left(p_name, 80), channel = 'telegram', sends = sends + 1, last_sent_at = now() where id = t.id;
  return json_build_object('ok', true, 'mode', 'code', 'code', t.code, 'purpose', t.purpose, 'tail', right(t.phone, 4));
end $function$;

-- allow-list widened to add 'telegram' alongside the existing 'wa_code'/'email' — bk_verify_tg_contact
-- (the admin_reset contact-share path) is untouched and doesn't call bk_verify_check at all.
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
  if t.purpose = 'signup' and t.user_id is not null then update users set phone_verified = true where id = t.user_id; end if;
  return json_build_object('ok', true, 'purpose', t.purpose);
end $$;
