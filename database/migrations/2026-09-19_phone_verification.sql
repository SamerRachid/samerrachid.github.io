-- Balkoun · 2026-09-19 · real phone verification for sign-up and password reset (applied as migration "phone_verification")
--
-- Before: the browser invented a 4-digit code, nothing checked it; bk_register / bk_set_password were callable
-- by anyone with just a phone number (anyone could reset anyone's password).
-- After: the server issues a ticket (id + secret + 6-digit code). The person proves the number either
--   • on Telegram: opens @<bot>?start=v<ticket>, taps "share my number"; Telegram hands us the number bound to
--     that account → ticket verified at once (bk_verify_tg_open / bk_verify_tg_contact, service-only), or
--   • on WhatsApp: sends the code to the owner's WhatsApp; the owner confirms in the panel (bk_admin_verify_set).
--     A sign-up through this road creates the account immediately with phone_verified = false; posting waits
--     until the owner confirms (bk_require_verified inside bk_post_listing / bk_agency_save / bk_wanted_save).
-- Settings (site_content.extras): verify_telegram_on, verify_whatsapp_on (default true), verify_required_post
--   (default true), verify_ticket_hours (default 48).

create table if not exists public.verify_tickets (
  id uuid primary key default gen_random_uuid(),
  secret_hash text not null,
  phone text not null,
  purpose text not null check (purpose in ('signup','reset')),
  channel text check (channel in ('telegram','whatsapp')),
  code text not null,
  status text not null default 'pending' check (status in ('pending','verified','used','expired','rejected')),
  country_code text,
  user_id uuid,
  tg_chat_id text,
  tg_name text,
  wa_sent_at timestamptz,
  verified_at timestamptz,
  verified_by uuid,
  used_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '48 hours'
);
create index if not exists verify_tickets_phone_idx on public.verify_tickets (phone, created_at desc);
create index if not exists verify_tickets_chat_idx on public.verify_tickets (tg_chat_id) where status = 'pending';
alter table public.verify_tickets enable row level security;
revoke all on public.verify_tickets from public, anon, authenticated;

create or replace function public.bk_verify_cfg() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('verify_telegram_on', true, 'verify_whatsapp_on', true, 'verify_required_post', true, 'verify_ticket_hours', 48,
                            'intake_bot', null, 'intake_wa_display', null)
      || coalesce((select (select jsonb_object_agg(key, value) from jsonb_each(coalesce(extras,'{}'::jsonb))
                           where key like 'verify\_%' or key in ('intake_bot','intake_wa_display')) from site_content where id = 1), '{}'::jsonb);
$$;

-- the ticket a browser holds (id + secret) → row, or an exception
create or replace function public.bk_verify_ticket(p_ticket uuid, p_secret text) returns public.verify_tickets
language plpgsql stable security definer set search_path = public, extensions as $$
declare t verify_tickets;
begin
  if p_ticket is null or length(coalesce(p_secret,'')) < 20 then raise exception 'badticket'; end if;
  select * into t from verify_tickets where id = p_ticket;
  if t.id is null or t.secret_hash <> encode(digest(p_secret, 'sha256'), 'hex') then raise exception 'badticket'; end if;
  return t;
end $$;

create or replace function public.bk_verify_start(p_phone text, p_purpose text, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare c jsonb; u users; sec text; code text; t verify_tickets; hrs int;
begin
  if p_purpose not in ('signup','reset') then raise exception 'badpurpose'; end if;
  if p_phone !~ '^\+[0-9]{8,15}$' then return json_build_object('error','badphone'); end if;
  c := bk_verify_cfg();
  if (c->>'verify_telegram_on') = 'false' and (c->>'verify_whatsapp_on') = 'false' then return json_build_object('error','off'); end if;
  select * into u from users where phone = p_phone;
  if p_purpose = 'signup' and u.id is not null then return json_build_object('error','exists'); end if;
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
  insert into verify_tickets (secret_hash, phone, purpose, code, country_code, expires_at)
    values (encode(digest(sec, 'sha256'), 'hex'), p_phone, p_purpose, code, upper(nullif(p_country,'')), now() + make_interval(hours => hrs))
    returning * into t;
  return json_build_object('ticket', t.id, 'secret', sec, 'code', t.code, 'phone', t.phone, 'purpose', t.purpose, 'expires_at', t.expires_at,
    'telegram', (c->>'verify_telegram_on') <> 'false' and nullif(c->>'intake_bot','') is not null,
    'whatsapp', (c->>'verify_whatsapp_on') <> 'false',
    'bot', c->>'intake_bot');
end $$;

create or replace function public.bk_verify_status(p_ticket uuid, p_secret text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.status = 'pending' and t.expires_at < now() then update verify_tickets set status = 'expired' where id = t.id; t.status := 'expired'; end if;
  return json_build_object('status', t.status, 'channel', t.channel, 'purpose', t.purpose, 'phone', t.phone, 'code', t.code, 'expires_at', t.expires_at, 'user_id', t.user_id);
end $$;

-- the person says they sent the code on WhatsApp → the ticket goes to the owner's confirmation list
create or replace function public.bk_verify_sent(p_ticket uuid, p_secret text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  if (bk_verify_cfg()->>'verify_whatsapp_on') = 'false' then return json_build_object('error','off'); end if;
  update verify_tickets set channel = 'whatsapp', wa_sent_at = coalesce(wa_sent_at, now()) where id = t.id;
  return json_build_object('ok', true);
end $$;

-- ── sign-up needs a ticket now (old 9-argument signature dropped) ──
drop function if exists public.bk_register(text, text, text, text, text, text, text, text, text);
create or replace function public.bk_register(p_ticket uuid, p_secret text, p_name text, p_family text, p_hash text,
                                              p_currency text default 'USD', p_lang text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets; u users; v_currency text; tok text; v_lang text; v_ok boolean;
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
  insert into users (phone, name, family_name, pass_hash, phone_verified, preferred_currency, lang, country)
    values (t.phone, left(trim(p_name),60), left(trim(coalesce(p_family,'')),60), crypt(p_hash, gen_salt('bf')), v_ok, v_currency, v_lang, t.country_code)
    returning * into u;
  update verify_tickets set user_id = u.id, status = case when v_ok then 'used' else 'pending' end, used_at = case when v_ok then now() end where id = t.id;
  insert into notifications (user_id, type, title, body, link, is_read) values (u.id, 'system', 'welcome', null, '/#/post', false);
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'city',u.city,'country',u.country,'preferred_currency',u.preferred_currency,'role',u.role,'phone_verified',u.phone_verified,'token',tok);
end $$;

-- ── password reset needs a VERIFIED ticket (old phone-only signature dropped) ──
drop function if exists public.bk_set_password(text, text);
create or replace function public.bk_set_password(p_ticket uuid, p_secret text, p_hash text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets; u users; tok text;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.purpose <> 'reset' or t.status <> 'verified' then return json_build_object('error','notverified'); end if;
  if t.verified_at < now() - interval '2 hours' then update verify_tickets set status = 'expired' where id = t.id; return json_build_object('error','expired'); end if;
  select * into u from users where phone = t.phone;
  if u.id is null then return json_build_object('error','nouser'); end if;
  if u.blocked then return json_build_object('error','blocked'); end if;
  if length(coalesce(p_hash,'')) < 32 then raise exception 'bad hash'; end if;
  update users set pass_hash = crypt(p_hash, gen_salt('bf')), phone_verified = true where id = u.id;
  update verify_tickets set status = 'used', used_at = now(), user_id = u.id where id = t.id;
  delete from member_sessions where user_id = u.id;
  delete from login_attempts where phone = u.phone;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'phone_verified',true,'token',tok);
end $$;

-- ── Telegram road (service role only; called by the bk-intake Edge Function) ──
create or replace function public.bk_verify_tg_open(p_ticket uuid, p_chat_id text, p_name text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets;
begin
  select * into t from verify_tickets where id = p_ticket;
  if t.id is null or t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','notfound'); end if;
  if (bk_verify_cfg()->>'verify_telegram_on') = 'false' then return json_build_object('error','off'); end if;
  update verify_tickets set tg_chat_id = p_chat_id, tg_name = left(p_name, 80), channel = 'telegram' where id = t.id;
  return json_build_object('ok', true, 'purpose', t.purpose, 'tail', right(t.phone, 4));
end $$;

create or replace function public.bk_verify_tg_contact(p_chat_id text, p_phone text, p_tg_user_id text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets; want text; got text;
begin
  select * into t from verify_tickets where tg_chat_id = p_chat_id and status = 'pending' order by created_at desc limit 1;
  if t.id is null then return json_build_object('error','none'); end if;
  if t.expires_at < now() then update verify_tickets set status = 'expired' where id = t.id; return json_build_object('error','expired'); end if;
  want := bk_intake_norm_phone(t.phone); got := bk_intake_norm_phone(p_phone);
  if want is null or got is null or want <> got then
    insert into intake_log (chat_id, event, detail) values (p_chat_id, 'verify_mismatch', jsonb_build_object('ticket', t.id, 'tail', right(t.phone, 4)));
    return json_build_object('error','mismatch', 'tail', right(t.phone, 4));
  end if;
  update verify_tickets set status = 'verified', verified_at = now(), channel = 'telegram',
         tg_name = coalesce(tg_name, '') || case when p_tg_user_id is null then '' else ' #' || p_tg_user_id end where id = t.id;
  if t.purpose = 'signup' and t.user_id is not null then update users set phone_verified = true where id = t.user_id; end if;
  insert into intake_log (chat_id, event, detail) values (p_chat_id, 'verify_ok', jsonb_build_object('ticket', t.id, 'purpose', t.purpose));
  return json_build_object('ok', true, 'purpose', t.purpose);
end $$;
revoke execute on function public.bk_verify_tg_open(uuid, text, text) from public, anon, authenticated;
revoke execute on function public.bk_verify_tg_contact(text, text, text) from public, anon, authenticated;
revoke execute on function public.bk_verify_ticket(uuid, text) from public, anon, authenticated;

-- ── owner side: WhatsApp confirmations ──
create or replace function public.bk_admin_verify_list(p_token text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update verify_tickets set status = 'expired' where status = 'pending' and expires_at < now();
  return coalesce((select json_agg(json_build_object('id', t.id, 'phone', t.phone, 'code', t.code, 'purpose', t.purpose, 'created_at', t.created_at,
                     'wa_sent_at', t.wa_sent_at, 'country_code', t.country_code, 'user_id', coalesce(t.user_id, u.id),
                     'name', trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,''))) order by t.wa_sent_at desc)
     from verify_tickets t left join users u on u.id = t.user_id or (t.user_id is null and u.phone = t.phone)
     where t.status = 'pending' and t.channel = 'whatsapp' and t.wa_sent_at is not null
       and bk_admin_country_ok(uid, coalesce(t.country_code, 'SY'))), '[]'::json);
end $$;

create or replace function public.bk_admin_verify_set(p_token text, p_ticket uuid, p_ok boolean) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; t verify_tickets;
begin
  uid := bk_admin_uid(p_token);
  select * into t from verify_tickets where id = p_ticket;
  if t.id is null then return json_build_object('error','notfound'); end if;
  if not bk_admin_country_ok(uid, coalesce(t.country_code, 'SY')) then raise exception 'unauthorised'; end if;
  if t.status <> 'pending' then return json_build_object('error','done'); end if;
  if p_ok then
    update verify_tickets set status = 'verified', verified_at = now(), verified_by = uid where id = t.id;
    if t.purpose = 'signup' and t.user_id is not null then
      update users set phone_verified = true where id = t.user_id;
      update verify_tickets set status = 'used', used_at = now() where id = t.id;
      insert into notifications (user_id, type, title, body, link, is_read) values (t.user_id, 'system', 'verified', null, '/#/post', false);
    end if;
  else
    update verify_tickets set status = 'rejected' where id = t.id;
  end if;
  return json_build_object('ok', true);
end $$;

-- posting needs a confirmed number (only an explicit false blocks; old accounts have null/true)
create or replace function public.bk_require_verified(p_uid uuid) returns void
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if coalesce((select extras->>'verify_required_post' from site_content where id = 1), 'true') <> 'false'
     and exists (select 1 from users where id = p_uid and phone_verified = false) then
    raise exception 'unverified';
  end if;
end $$;

do $$
declare r record; src text; new text;
begin
  for r in select p.oid, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('bk_post_listing','bk_agency_save','bk_wanted_save') loop
    src := pg_get_functiondef(r.oid);
    if src like '%bk_require_verified%' then continue; end if;
    new := replace(src, 'if uid is null then raise exception ''unauthorised''; end if;', 'if uid is null then raise exception ''unauthorised''; end if; perform bk_require_verified(uid);');
    new := replace(new, 'if uid is null then raise exception ''not signed in''; end if;', 'if uid is null then raise exception ''not signed in''; end if; perform bk_require_verified(uid);');
    if new = src then raise exception 'anchor not found in %', r.proname; end if;
    execute new;
  end loop;
end $$;

-- sessions carry phone_verified so the site can show the "awaiting confirmation" notice
create or replace function public.bk_login(p_phone text, p_hash text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare u users; tok text;
begin
  if not bk_login_guard(p_phone) then return json_build_object('error','locked'); end if;
  select * into u from users where phone = p_phone;
  if u.id is null then perform bk_login_fail(p_phone); return json_build_object('error','nouser'); end if;
  if u.pass_hash is null or u.pass_hash <> crypt(p_hash, u.pass_hash) then perform bk_login_fail(p_phone); return json_build_object('error','badpass'); end if;
  if u.blocked then return json_build_object('error','blocked'); end if;
  delete from login_attempts where phone = p_phone;
  update users set last_seen_at = now() where id = u.id;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'phone_verified',u.phone_verified,'token',tok);
end $$;

create or replace function public.bk_me(p_id uuid, p_token text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare u users; uid uuid;
begin
  uid := bk_member_uid(p_token);
  if uid is null or uid <> p_id then return json_build_object('error','nouser'); end if;
  select * into u from users where id = uid and not blocked;
  if u.id is null then return json_build_object('error','nouser'); end if;
  update member_sessions set expires_at = now() + interval '30 days' where token = p_token;
  update users set last_seen_at = now() where id = u.id;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'phone_verified',u.phone_verified,'token',p_token);
end $$;

-- bell: confirmations waiting for the owner
create or replace function public.bk_admin_todo(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token);
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return json_build_object(
    'pending_listings', (select count(*) from listings where status='pending' and bk_scope_ok(country_code,sc,al)),
    'pending_agencies', (select count(*) from agencies where status='pending' and bk_scope_ok(country_code,sc,al)),
    'pending_wanted', (select count(*) from wanted where status='pending' and bk_scope_ok(country_code,sc,al)),
    'intake_review', (select count(*) from intake_drafts where status in ('review','failed') and bk_scope_ok(country_code,sc,al)),
    'verify_pending', (select count(*) from verify_tickets where status='pending' and channel='whatsapp' and wa_sent_at is not null and expires_at > now() and bk_scope_ok(coalesce(country_code,'SY'),sc,al)),
    'open_reports', (select count(*) from listing_reports r left join listings l on l.id=r.listing_id where not coalesce(r.resolved,false) and (l.id is null or bk_scope_ok(l.country_code,sc,al))) + (select count(*) from reports where not coalesce(resolved,false)),
    'open_feedback', (select count(*) from feedback where not coalesce(handled,false)),
    'unread_alerts', (select count(*) from notifications where user_id=uid and not is_read),
    'latest', coalesce((select json_agg(x order by x.at desc) from (
        (select 'listing' as kind, l.ref as label, l.created_at as at, l.id::text as ref, l.country_code as cc from listings l where l.status='pending' and bk_scope_ok(l.country_code,sc,al) order by l.created_at desc limit 5)
        union all
        (select 'agency', a.name, a.created_at, a.id::text, a.country_code from agencies a where a.status='pending' and bk_scope_ok(a.country_code,sc,al) order by a.created_at desc limit 5)
        union all
        (select 'wanted', coalesce(w.title, w.gov_name, ''), w.created_at, w.id::text, w.country_code from wanted w where w.status='pending' and bk_scope_ok(w.country_code,sc,al) order by w.created_at desc limit 5)
        union all
        (select 'intake', coalesce(d.sender_name, d.chat_id), d.created_at, d.id::text, d.country_code from intake_drafts d where d.status in ('review','failed') and bk_scope_ok(d.country_code,sc,al) order by d.created_at desc limit 5)
        union all
        (select 'verify', v.phone, v.wa_sent_at, v.id::text, v.country_code from verify_tickets v where v.status='pending' and v.channel='whatsapp' and v.wa_sent_at is not null and v.expires_at > now() and bk_scope_ok(coalesce(v.country_code,'SY'),sc,al) order by v.wa_sent_at desc limit 5)
        union all
        (select 'report', coalesce(r.reason,''), r.created_at, r.id::text, l.country_code from listing_reports r left join listings l on l.id=r.listing_id where not coalesce(r.resolved,false) and (l.id is null or bk_scope_ok(l.country_code,sc,al)) order by r.created_at desc limit 5)
        union all
        (select 'feedback', coalesce(f.kind,'')||': '||left(coalesce(f.body,''),60), f.created_at, f.id::text, null from feedback f where not coalesce(f.handled,false) order by f.created_at desc limit 5)
      ) x), '[]'::json)
  );
end $$;

-- ── fix1 (applied as migration "phone_verification_fix1") ──
-- an existing but unconfirmed account (WhatsApp sign-up) may verify itself on Telegram later: same 'signup' ticket, bound to the user;
-- bk_verify_status also returns 'verified' = status in (verified, used).
create or replace function public.bk_verify_start(p_phone text, p_purpose text, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare c jsonb; u users; sec text; code text; t verify_tickets; hrs int;
begin
  if p_purpose not in ('signup','reset') then raise exception 'badpurpose'; end if;
  if p_phone !~ '^\+[0-9]{8,15}$' then return json_build_object('error','badphone'); end if;
  c := bk_verify_cfg();
  if (c->>'verify_telegram_on') = 'false' and (c->>'verify_whatsapp_on') = 'false' then return json_build_object('error','off'); end if;
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
    'bot', c->>'intake_bot', 'existing', u.id is not null);
end $$;

create or replace function public.bk_verify_status(p_ticket uuid, p_secret text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.status = 'pending' and t.expires_at < now() then update verify_tickets set status = 'expired' where id = t.id; t.status := 'expired'; end if;
  return json_build_object('status', t.status, 'channel', t.channel, 'purpose', t.purpose, 'phone', t.phone, 'code', t.code, 'expires_at', t.expires_at, 'user_id', t.user_id,
    'verified', t.status in ('verified','used'));
end $$;

-- ── wa_code (applied as migration "phone_verification_wa_code") ──
-- Third road: the Edge Function (/bk-intake/verify) sends the ticket's code as a WhatsApp authentication template (Cloud API),
-- the person types it on the site. Non-Syrian numbers only (Meta blocks +963). Shown only while extras.verify_wa_ready = true,
-- which the panel's status check writes when the Cloud API answers. Settings: verify_wa_code_on, verify_wa_template, verify_wa_lang.
alter table public.verify_tickets drop constraint if exists verify_tickets_channel_check;
alter table public.verify_tickets add constraint verify_tickets_channel_check check (channel in ('telegram','whatsapp','wa_code'));
alter table public.verify_tickets add column if not exists sends int not null default 0, add column if not exists attempts int not null default 0, add column if not exists last_sent_at timestamptz;
-- bk_verify_cfg: + verify_wa_code_on (true), verify_wa_ready (false), verify_wa_template ('balkoun_code'), verify_wa_lang ('ar')
-- bk_verify_start: + 'wa_code' = verify_wa_code_on and verify_wa_ready and phone not like '+963%'
create or replace function public.bk_verify_send_claim(p_ticket uuid, p_secret text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets; c jsonb;
begin
  begin t := bk_verify_ticket(p_ticket, p_secret); exception when others then return json_build_object('error','badticket'); end;
  c := bk_verify_cfg();
  if (c->>'verify_wa_code_on') = 'false' then return json_build_object('error','off'); end if;
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  if t.phone like '+963%' then return json_build_object('error','country'); end if;
  if t.sends >= 3 then return json_build_object('error','limit'); end if;
  if t.last_sent_at is not null and t.last_sent_at > now() - interval '45 seconds' then return json_build_object('error','wait'); end if;
  update verify_tickets set sends = sends + 1, last_sent_at = now(), channel = 'wa_code' where id = t.id;
  return json_build_object('ok', true, 'phone', t.phone, 'code', t.code, 'template', c->>'verify_wa_template', 'lang', c->>'verify_wa_lang');
end $$;
revoke execute on function public.bk_verify_send_claim(uuid, text) from public, anon, authenticated;

create or replace function public.bk_verify_check(p_ticket uuid, p_secret text, p_code text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare t verify_tickets;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.status in ('verified','used') then return json_build_object('ok', true, 'purpose', t.purpose); end if;
  if t.status <> 'pending' or t.expires_at < now() then return json_build_object('error','expired'); end if;
  if t.channel <> 'wa_code' or t.sends = 0 then return json_build_object('error','notsent'); end if;
  if t.attempts >= 5 then update verify_tickets set status = 'rejected' where id = t.id; return json_build_object('error','rejected'); end if;
  if regexp_replace(coalesce(p_code,''), '\D', '', 'g') <> t.code then
    update verify_tickets set attempts = attempts + 1 where id = t.id;
    return json_build_object('error','wrong', 'left', 5 - t.attempts - 1);
  end if;
  update verify_tickets set status = 'verified', verified_at = now() where id = t.id;
  if t.purpose = 'signup' and t.user_id is not null then update users set phone_verified = true where id = t.user_id; end if;
  return json_build_object('ok', true, 'purpose', t.purpose);
end $$;
