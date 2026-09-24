-- Balkoun · 2026-09-24 · Email as a third verification channel (alongside Telegram and WhatsApp's wa_code),
-- plus per-country control over which channels a sign-up/reset picker shows.
--
-- Identity model: phone stays the ONLY login identifier. Email is an additional, optional, *verified*
-- delivery channel — never an alternate account identity. No email login, no email-only accounts.
--
-- SECURITY INVARIANT (the whole reason this needs care): for password RESET, the code is only ever sent
-- to the address already on file and verified for that account (users.email where email_verified=true).
-- The client can NEVER supply/type a destination during reset — bk_verify_send_claim's email branch below
-- re-resolves users.email/email_verified by t.phone itself and ignores p_email entirely whenever
-- t.purpose <> 'signup'. Allowing a client-typed reset destination would let anyone who knows a victim's
-- PHONE NUMBER pick "reset by email", type their own address, and take over the account. For SIGNUP there
-- is no account yet, so typing a fresh address and confirming it via the code *is* how it becomes verified
-- — same trust model phone numbers already use with WhatsApp/Telegram.
--
-- Per-country scope: only the on/off *offer* toggles (verify_telegram_on, verify_wa_code_on, new
-- verify_email_on) become per-country in this migration (bk_verify_cfg now takes p_country and merges that
-- country's own site_content row on top of the SY-row defaults). Provider *readiness* flags
-- (verify_wa_ready, verify_waha_ready, new verify_email_ready) stay global/SY-row — they reflect whether
-- the underlying provider is configured at all, not a per-country business choice.
--
-- NOT included in this migration (deliberately — see project notes):
--   - bk_register / bk_set_password / bk_login / bk_me: need `email`/`email_verified` added to their
--     returned json, and bk_register needs to copy email/email_verified onto the new user row. Their
--     true CURRENT bodies are not fully captured in any on-disk migration file (a later, comment-only
--     migration says bk_register/bk_login/bk_me also gained a member_no field, with no SQL on disk) — so
--     rewriting them here from a possibly-stale copy risks silently reverting that live-only logic. These
--     four need their live definitions pulled first (pg_get_functiondef), then a precise, reviewed patch.
--   - bk_admin_countries: needs to also return each country's own verify-toggle subset from extras, so the
--     new admin "الدول" checkboxes can render per-country state. Its true current body isn't in any
--     on-disk file either (only ever patched live via introspect-and-replace) — same caution applies.
--   - Removing the legacy manual "send a code to Balkoun's WhatsApp, admin confirms" reset fallback. That's
--     a separable deletion (a whole admin review-queue feature) — a follow-up once email is live and stable.
--   - Any way for an *existing* user (or one who signed up via Telegram/WhatsApp) to add/verify an email
--     afterward — so reset-by-email will be unreachable for most of the current user base until a future
--     "add/verify email from account settings" flow ships. Not building that now; the purpose check
--     constraint below is left easy to widen later (e.g. a future 'link_email' purpose) for exactly that.

alter table public.users
  add column if not exists email text,
  add column if not exists email_verified boolean not null default false;

create unique index if not exists users_email_uq on public.users (lower(email)) where email is not null;

alter table public.verify_tickets add column if not exists email text;
alter table public.verify_tickets drop constraint if exists verify_tickets_channel_check;
alter table public.verify_tickets add constraint verify_tickets_channel_check check (channel in ('telegram','whatsapp','wa_code','email'));

-- bk_verify_cfg gains p_country: the hardcoded-SY tier (defaults/readiness/templates) is unchanged; when
-- p_country <> 'SY', the country's OWN site_content row's offer-toggle keys are merged on top. Every
-- country already has its own site_content row (multi-country work), so no new table is needed.
create or replace function public.bk_verify_cfg(p_country text default 'SY') returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select (
    jsonb_build_object('verify_telegram_on', true, 'verify_whatsapp_on', true, 'verify_wa_code_on', true, 'verify_email_on', true,
                        'verify_email_ready', false, 'verify_required_post', true, 'verify_ticket_hours', 48,
                        'intake_bot', null, 'intake_wa_display', null)
    || coalesce((select (select jsonb_object_agg(key, value) from jsonb_each(coalesce(extras,'{}'::jsonb))
                         where key like 'verify\_%' or key in ('intake_bot','intake_wa_display')) from site_content where id = 1), '{}'::jsonb)
  ) || case when coalesce(p_country,'SY') = 'SY' then '{}'::jsonb else
    coalesce((select (select jsonb_object_agg(key, value) from jsonb_each(coalesce(extras,'{}'::jsonb))
                       where key in ('verify_telegram_on','verify_wa_code_on','verify_email_on'))
              from site_content where country_code = p_country), '{}'::jsonb)
  end;
$$;

-- bk_verify_start: adds p_email (signup only — stored as a candidate on the ticket, unverified until the
-- code confirms it; reset ignores it and looks up the account's own on-file email instead), and reports an
-- `email` offer flag alongside the existing telegram/whatsapp/wa_code ones.
create or replace function public.bk_verify_start(p_phone text, p_purpose text, p_country text default null, p_email text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare c jsonb; u users; sec text; code text; t verify_tickets; hrs int; wa_code boolean; email_on boolean; is_sy boolean; cand_email text;
begin
  if p_purpose not in ('signup','reset') then raise exception 'badpurpose'; end if;
  if p_phone !~ '^\+[0-9]{8,15}$' then return json_build_object('error','badphone'); end if;
  c := bk_verify_cfg(coalesce(p_country,'SY'));
  is_sy := p_phone like '+963%';
  wa_code := (c->>'verify_wa_code_on') <> 'false' and
             (case when is_sy then (c->>'verify_waha_ready') = 'true' else (c->>'verify_wa_ready') = 'true' end);
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
  -- signup candidate email: format-checked and collision-checked here too (not just at send time) so the
  -- picker never advertises `email` as usable when it's already a dead end
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
end $$;

-- bk_verify_send_claim: p_channel picks the transport ('wa_code', unchanged default, or new 'email').
-- p_email is consulted ONLY under purpose='signup' — the reset branch re-resolves users.email/email_verified
-- by t.phone unconditionally and never reads p_email at all, which is what makes the security invariant hold
-- regardless of what a caller sends. A per-normalized-email send cap is added alongside the existing
-- per-phone cap, because email is the first channel where the rate-limited key (phone) and the actual
-- destination differ — the phone-keyed throttle alone doesn't bound one inbox being hit from many phones.
create or replace function public.bk_verify_send_claim(p_ticket uuid, p_secret text, p_channel text default 'wa_code', p_email text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare t verify_tickets; c jsonb; is_sy boolean; ready boolean; v_email text; v_ok boolean; regen boolean;
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
      regen := t.email is not null and t.email <> v_email;   -- typo correction on a still-pending ticket: don't leave the old address's code valid
    elsif t.purpose = 'reset' then
      select lower(u.email), u.email_verified into v_email, v_ok from users u where u.phone = t.phone;   -- p_email is READ, NEVER USED for reset
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

  -- default / unchanged path: WhatsApp's wa_code (WAHA for Syria, Meta's Cloud API elsewhere)
  is_sy := t.phone like '+963%';
  ready := case when is_sy then (c->>'verify_waha_ready') = 'true' else true end;
  if not ready then return json_build_object('error','country'); end if;
  update verify_tickets set sends = sends + 1, last_sent_at = now(), channel = 'wa_code' where id = t.id;
  return json_build_object('ok', true, 'phone', t.phone, 'code', t.code, 'via', case when is_sy then 'waha' else 'meta' end,
    'template', c->>'verify_wa_template', 'lang', c->>'verify_wa_lang');
end $$;

-- bk_verify_check: widened to an allow-list (not a `<>` negation) specifically because the separate,
-- in-flight Telegram-typed-code task will need to add 'telegram' here too.
create or replace function public.bk_verify_check(p_ticket uuid, p_secret text, p_code text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.status in ('verified','used') then return json_build_object('ok', true, 'purpose', t.purpose); end if;
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  if t.channel not in ('wa_code','email') or t.sends = 0 then return json_build_object('error','notsent'); end if;
  if t.attempts >= 5 then update verify_tickets set status = 'rejected' where id = t.id; return json_build_object('error','rejected'); end if;
  if regexp_replace(coalesce(p_code,''), '\D', '', 'g') <> t.code then
    update verify_tickets set attempts = attempts + 1 where id = t.id;
    return json_build_object('error','wrong', 'left', 5 - t.attempts - 1);
  end if;
  update verify_tickets set status = 'verified', verified_at = now() where id = t.id;
  if t.purpose = 'signup' and t.user_id is not null then update users set phone_verified = true where id = t.user_id; end if;
  return json_build_object('ok', true, 'purpose', t.purpose);
end $$;
