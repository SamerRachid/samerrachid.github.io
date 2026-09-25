-- Balkoun · 2026-09-25 · Contacts notebook + marketing/notification campaigns (WhatsApp, Telegram, Email).
-- Plan file: C:\Users\Farm\.claude\plans\parallel-painting-plum.md
--
-- Three new tables, all RLS-enabled with zero policies (default deny), matching the existing
-- admin_notify_queue/verify_tickets pattern — every access goes through a SECURITY DEFINER RPC below.
--
--   contacts        — the notebook. One row per contact, auto-synced from `users` (source='member')
--                      or added/imported by the admin (source='manual'|'import'). Geography reuses the
--                      real governorates/areas tables, not free text, so "notify this city" is an exact
--                      join. Per-channel consent (pending|subscribed|unsubscribed) — nothing sends to a
--                      contact who isn't explicitly subscribed on that channel.
--   campaigns       — a composed message, manual or the automatic 'auto_new_listing' kind.
--   campaign_sends  — the queue AND the audit log, one row per contact × channel actually attempted,
--                      mirroring admin_notify_queue's role for this feature.
--
-- KNOWN ACCEPTED RISK (do not silently increase Syria WhatsApp marketing volume without re-reading this):
-- Syria's WhatsApp OTP and Syria's WhatsApp marketing both send through the SAME shared WAHA-linked
-- number (a personal-style WhatsApp session, not Meta's official API). The user was told a WhatsApp ban
-- on that number would break OTP delivery for all of Syria too, and explicitly chose "allow it, no
-- special limit" anyway. This migration does not add any Syria-specific cap — that was a deliberate,
-- informed choice, not an oversight.

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  phone text,
  email text,
  name text,
  country_code text not null references public.countries(code),
  governorate_id integer references public.governorates(id),
  area_id integer references public.areas(id),
  city_text text,
  source text not null default 'manual' check (source in ('member','manual','import')),
  tags text[] not null default '{}',
  wa_consent text not null default 'pending' check (wa_consent in ('pending','subscribed','unsubscribed')),
  tg_consent text not null default 'pending' check (tg_consent in ('pending','subscribed','unsubscribed')),
  email_consent text not null default 'pending' check (email_consent in ('pending','subscribed','unsubscribed')),
  tg_chat_id text,
  unsub_token text not null unique default encode(gen_random_bytes(16), 'hex'),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contacts_has_contact_info check (phone is not null or email is not null)
);
create unique index contacts_user_uq on public.contacts(user_id) where user_id is not null;
create index contacts_country_idx on public.contacts(country_code);
create index contacts_gov_idx on public.contacts(governorate_id);
create index contacts_area_idx on public.contacts(area_id);
create index contacts_tags_idx on public.contacts using gin(tags);
alter table public.contacts enable row level security;

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kind text not null default 'manual' check (kind in ('manual','auto_new_listing')),
  channels text[] not null default '{}',
  subject text,
  body_ar text,
  body_en text,
  country_code text references public.countries(code),
  governorate_id integer references public.governorates(id),
  area_id integer references public.areas(id),
  tag_filter text[] not null default '{}',
  consent_required boolean not null default true,
  status text not null default 'draft' check (status in ('draft','scheduled','sending','sent','failed')),
  scheduled_at timestamptz,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  sent_count integer not null default 0,
  failed_count integer not null default 0
);
create index campaigns_country_idx on public.campaigns(country_code);
alter table public.campaigns enable row level security;

create table public.campaign_sends (
  id bigint generated always as identity primary key,
  campaign_id uuid references public.campaigns(id) on delete cascade,
  trigger_type text not null default 'manual' check (trigger_type in ('manual','auto_new_listing')),
  listing_id bigint references public.listings(id) on delete set null,
  contact_id uuid not null references public.contacts(id) on delete cascade,
  channel text not null check (channel in ('telegram','whatsapp','email')),
  status text not null default 'queued' check (status in ('queued','sent','failed','skipped_no_consent','skipped_no_contact_info')),
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index campaign_sends_queued_idx on public.campaign_sends(created_at) where status = 'queued';
create index campaign_sends_campaign_idx on public.campaign_sends(campaign_id);
alter table public.campaign_sends enable row level security;

-- ── auto-sync: every insert/update of a user's contact-relevant fields keeps one mirrored
-- source='member' contacts row — including admin/staff accounts, deliberately: an admin needs their own
-- contacts row for the campaign composer's "send test to me" button to have somewhere to attach to, and
-- an unsolicited-consent staff row is harmless since consent always starts 'pending' regardless of who
-- the row belongs to (registering an account is not, by itself, consent to be messaged). Members only
-- have free-text `city` (no governorate_id/area_id), so a synced contact starts country-wide-targeted;
-- the admin can narrow any contact to a real governorate/area from the notebook's edit drawer.
create or replace function public.bk_trg_sync_member_contact()
returns trigger language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  insert into contacts (user_id, phone, email, name, country_code, city_text, source)
    values (new.id, new.phone, new.email, trim(coalesce(new.name,'') || ' ' || coalesce(new.family_name,'')),
            coalesce((select code from countries where code = upper(new.country)), 'SY'), new.city, 'member')
  on conflict (user_id) where user_id is not null do update set
    phone = excluded.phone, email = excluded.email, name = excluded.name,
    country_code = excluded.country_code, city_text = excluded.city_text, updated_at = now();
  return new;
exception when others then return new;   -- a contact-sync hiccup must never break a signup/profile save
end $function$;
create trigger trg_sync_member_contact after insert or update of phone, email, country, city, name on public.users
  for each row execute function public.bk_trg_sync_member_contact();

-- one-time backfill: the trigger above only fires on future inserts/updates, so every user who already
-- existed before this migration needs their first contacts row seeded now. Left-joined against countries
-- (falling back to 'SY') rather than trusting users.country directly — contacts.country_code has a real
-- FK, and one stray/legacy value in a users row must not abort the whole backfill.
insert into contacts (user_id, phone, email, name, country_code, city_text, source)
  select u.id, u.phone, u.email, trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')),
         coalesce(co.code, 'SY'), u.city, 'member'
    from users u left join countries co on co.code = upper(u.country)
  on conflict (user_id) where user_id is not null do nothing;

-- ── automatic "new listing" notification: fires exactly like the existing trg_listing_live_wanted
-- (status transitions to 'live'), gated per-country by site_content.extras.auto_notify_new_listing_on
-- (off by default until the admin turns it on). Matching is "does this contact's own targeting
-- granularity cover this specific listing" — an area-level contact only hears about that exact area, a
-- governorate-level contact hears about anything in that governorate, a country-level contact hears
-- about anything in the country. One row per channel the contact is actually subscribed on, skipped
-- outright (not queued) when the contact has no usable address for that channel.
create or replace function public.bk_trg_contacts_new_listing()
returns trigger language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare c jsonb;
begin
  if new.status = 'live' and (tg_op = 'INSERT' or old.status is distinct from 'live') then
    select extras into c from site_content where country_code = new.country_code;
    if c is null or (c->>'auto_notify_new_listing_on') is distinct from 'true' then return new; end if;
    insert into campaign_sends (trigger_type, listing_id, contact_id, channel)
    select 'auto_new_listing', new.id, m.id, m.channel from (
      select ct.id, ch.channel from contacts ct
        cross join unnest(array['telegram','whatsapp','email']) as ch(channel)
      where ct.country_code = new.country_code
        and (
          ct.area_id = new.area_id
          or (ct.area_id is null and ct.governorate_id = new.governorate_id)
          or (ct.area_id is null and ct.governorate_id is null)
        )
        and (
          (ch.channel = 'telegram' and ct.tg_consent = 'subscribed' and ct.tg_chat_id is not null)
          or (ch.channel = 'whatsapp' and ct.wa_consent = 'subscribed' and ct.phone is not null)
          or (ch.channel = 'email' and ct.email_consent = 'subscribed' and ct.email is not null)
        )
    ) m
    limit 5000;   -- a hard safety cap per listing; if a country ever legitimately exceeds this, it needs the digest follow-up, not a silent unbounded insert
  end if;
  return new;
exception when others then return new;   -- a notify hiccup must never block publishing a listing
end $function$;
create trigger trg_contacts_notify_new_listing after insert or update of status on public.listings
  for each row execute function public.bk_trg_contacts_new_listing();

-- ── admin RPCs (country-scoped exactly like bk_admin_list_ads: bk_admin_scope + bk_scope_ok for reads,
-- bk_admin_guard for writes) ──

create or replace function public.bk_admin_contacts(p_token text, p_country text default null, p_q text default null, p_consent text default null, p_source text default null, p_tag text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by x.created_at desc) from (
    select c.* from contacts c
     where bk_scope_ok(c.country_code, sc, al)
       and (p_q is null or c.phone ilike '%'||p_q||'%' or c.email ilike '%'||p_q||'%' or c.name ilike '%'||p_q||'%')
       and (p_consent is null or c.wa_consent = p_consent or c.tg_consent = p_consent or c.email_consent = p_consent)
       and (p_source is null or c.source = p_source)
       and (p_tag is null or p_tag = any(c.tags))
     limit 2000) x), '[]'::json);
end $function$;

create or replace function public.bk_admin_contact_save(p_token text, p_id uuid, p_patch jsonb)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; row_cc text; new_cc text; c contacts;
begin
  uid := bk_admin_uid(p_token);
  new_cc := coalesce(upper(p_patch->>'country_code'), 'SY');
  if p_id is not null then
    select country_code into row_cc from contacts where id = p_id;
    if row_cc is null then return json_build_object('error', 'notfound'); end if;
    perform bk_admin_guard(uid, row_cc); perform bk_admin_guard(uid, new_cc);
    update contacts set
      phone = nullif(trim(coalesce(p_patch->>'phone', phone)), ''),
      email = nullif(lower(trim(coalesce(p_patch->>'email', email))), ''),
      name = coalesce(p_patch->>'name', name),
      country_code = new_cc,
      governorate_id = case when p_patch ? 'governorate_id' then (p_patch->>'governorate_id')::int else governorate_id end,
      area_id = case when p_patch ? 'area_id' then (p_patch->>'area_id')::int else area_id end,
      city_text = coalesce(p_patch->>'city_text', city_text),
      tags = case when p_patch ? 'tags' then (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(p_patch->'tags')) else tags end,
      wa_consent = coalesce(p_patch->>'wa_consent', wa_consent),
      tg_consent = coalesce(p_patch->>'tg_consent', tg_consent),
      email_consent = coalesce(p_patch->>'email_consent', email_consent),
      notes = coalesce(p_patch->>'notes', notes),
      updated_at = now()
    where id = p_id returning * into c;
  else
    perform bk_admin_guard(uid, new_cc);
    insert into contacts (phone, email, name, country_code, governorate_id, area_id, city_text, tags, source,
        wa_consent, tg_consent, email_consent, notes)
      values (nullif(trim(p_patch->>'phone'), ''), nullif(lower(trim(p_patch->>'email')), ''), p_patch->>'name', new_cc,
        (p_patch->>'governorate_id')::int, (p_patch->>'area_id')::int, p_patch->>'city_text',
        (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(coalesce(p_patch->'tags', '[]'::jsonb))),
        'manual', coalesce(p_patch->>'wa_consent', 'pending'), coalesce(p_patch->>'tg_consent', 'pending'),
        coalesce(p_patch->>'email_consent', 'pending'), p_patch->>'notes')
      returning * into c;
  end if;
  return row_to_json(c);
exception when check_violation then return json_build_object('error', 'need_phone_or_email');
end $function$;

create or replace function public.bk_admin_contact_delete(p_token text, p_id uuid)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; row_cc text;
begin
  uid := bk_admin_uid(p_token);
  select country_code into row_cc from contacts where id = p_id;
  if row_cc is null then return json_build_object('ok', true); end if;
  perform bk_admin_guard(uid, row_cc);
  delete from contacts where id = p_id;
  return json_build_object('ok', true);
end $function$;

-- bulk import: each row {phone,email,name,city_text,tags[]}; consent is set to 'subscribed' on every
-- channel the row has an address for ONLY when p_assume_consent is true — an explicit admin assertion at
-- import time ("I already have consent for this list"), never a silent default.
create or replace function public.bk_admin_contacts_import(p_token text, p_country text, p_rows jsonb, p_assume_consent boolean default false)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; cc text; r jsonb; n_ins int := 0; n_skip int := 0;
begin
  uid := bk_admin_uid(p_token); cc := coalesce(upper(p_country), 'SY'); perform bk_admin_guard(uid, cc);
  if jsonb_array_length(p_rows) > 5000 then raise exception 'too many rows (max 5000 per import)'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(trim(r->>'phone'), '') = '' and coalesce(trim(r->>'email'), '') = '' then
      n_skip := n_skip + 1; continue;
    end if;
    insert into contacts (phone, email, name, country_code, city_text, tags, source, wa_consent, tg_consent, email_consent)
      values (nullif(trim(r->>'phone'), ''), nullif(lower(trim(r->>'email')), ''), r->>'name', cc, r->>'city_text',
        (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(coalesce(r->'tags', '[]'::jsonb))),
        'import',
        case when p_assume_consent and coalesce(trim(r->>'phone'),'')<>'' then 'subscribed' else 'pending' end,
        'pending',
        case when p_assume_consent and coalesce(trim(r->>'email'),'')<>'' then 'subscribed' else 'pending' end);
    n_ins := n_ins + 1;
  end loop;
  return json_build_object('ok', true, 'inserted', n_ins, 'skipped', n_skip);
end $function$;

create or replace function public.bk_admin_campaigns(p_token text, p_country text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by x.created_at desc) from (
    select * from campaigns c where bk_scope_ok(c.country_code, sc, al) limit 500) x), '[]'::json);
end $function$;

create or replace function public.bk_admin_campaign_save(p_token text, p_id uuid, p_patch jsonb)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; row_cc text; row_status text; new_cc text; c campaigns;
begin
  uid := bk_admin_uid(p_token);
  new_cc := nullif(upper(p_patch->>'country_code'), '');
  perform bk_admin_guard(uid, coalesce(new_cc, 'SY'));
  if p_id is not null then
    select country_code, status into row_cc, row_status from campaigns where id = p_id;
    if row_cc is null then return json_build_object('error', 'notfound'); end if;
    if row_status not in ('draft', 'scheduled') then
      return json_build_object('error', 'not_editable');
    end if;
    perform bk_admin_guard(uid, row_cc);
    update campaigns set
      title = coalesce(p_patch->>'title', title),
      channels = case when p_patch ? 'channels' then (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(p_patch->'channels')) else channels end,
      subject = coalesce(p_patch->>'subject', subject),
      body_ar = coalesce(p_patch->>'body_ar', body_ar),
      body_en = coalesce(p_patch->>'body_en', body_en),
      country_code = coalesce(new_cc, country_code),
      governorate_id = case when p_patch ? 'governorate_id' then (p_patch->>'governorate_id')::int else governorate_id end,
      area_id = case when p_patch ? 'area_id' then (p_patch->>'area_id')::int else area_id end,
      tag_filter = case when p_patch ? 'tag_filter' then (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(p_patch->'tag_filter')) else tag_filter end,
      consent_required = coalesce((p_patch->>'consent_required')::boolean, consent_required),
      scheduled_at = case when p_patch ? 'scheduled_at' then (p_patch->>'scheduled_at')::timestamptz else scheduled_at end,
      status = case when p_patch ? 'scheduled_at' and (p_patch->>'scheduled_at') is not null then 'scheduled' else status end
    where id = p_id returning * into c;
  else
    insert into campaigns (title, kind, channels, subject, body_ar, body_en, country_code, governorate_id, area_id, tag_filter, consent_required, created_by)
      values (coalesce(p_patch->>'title', 'بدون عنوان'), 'manual',
        (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(coalesce(p_patch->'channels', '[]'::jsonb))),
        p_patch->>'subject', p_patch->>'body_ar', p_patch->>'body_en', coalesce(new_cc, 'SY'),
        (p_patch->>'governorate_id')::int, (p_patch->>'area_id')::int,
        (select coalesce(array_agg(value::text), '{}') from jsonb_array_elements_text(coalesce(p_patch->'tag_filter', '[]'::jsonb))),
        coalesce((p_patch->>'consent_required')::boolean, true), uid)
      returning * into c;
  end if;
  return row_to_json(c);
end $function$;

create or replace function public.bk_admin_campaign_delete(p_token text, p_id uuid)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; row_cc text; row_status text;
begin
  uid := bk_admin_uid(p_token);
  select country_code, status into row_cc, row_status from campaigns where id = p_id;
  if row_cc is null then return json_build_object('ok', true); end if;
  if row_status not in ('draft', 'scheduled') then return json_build_object('error', 'not_deletable'); end if;
  perform bk_admin_guard(uid, row_cc);
  delete from campaigns where id = p_id;
  return json_build_object('ok', true);
end $function$;

-- shared audience match for a MANUAL campaign: a straightforward drill-down filter (country required;
-- governorate/area equality when the campaign set one; tag overlap when set) — simpler and more
-- predictable for an admin picking a target than the "compatible broadness" rule the automatic
-- new-listing trigger uses, which instead asks whether a fixed listing falls inside each contact's own
-- stated coverage. The two are different questions and deliberately use different logic.
create or replace function public.bk_campaign_audience(p_campaign_id uuid)
returns table(contact_id uuid, channel text) language sql stable security definer set search_path to 'public', 'extensions' as $function$
  select c.id, ch.channel
  from campaigns camp
  cross join unnest(camp.channels) as ch(channel)
  join contacts c on c.country_code = camp.country_code
    and (camp.governorate_id is null or c.governorate_id = camp.governorate_id)
    and (camp.area_id is null or c.area_id = camp.area_id)
    and (cardinality(camp.tag_filter) = 0 or c.tags && camp.tag_filter)
  where camp.id = p_campaign_id
    and (
      not camp.consent_required
      or (ch.channel = 'telegram' and c.tg_consent = 'subscribed')
      or (ch.channel = 'whatsapp' and c.wa_consent = 'subscribed')
      or (ch.channel = 'email' and c.email_consent = 'subscribed')
    )
    and (
      (ch.channel = 'telegram' and c.tg_chat_id is not null)
      or (ch.channel = 'whatsapp' and c.phone is not null)
      or (ch.channel = 'email' and c.email is not null)
    )
$function$;

create or replace function public.bk_admin_campaign_audience_count(p_token text, p_id uuid)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; row_cc text;
begin
  uid := bk_admin_uid(p_token);
  select country_code into row_cc from campaigns where id = p_id;
  if row_cc is null then return json_build_object('error', 'notfound'); end if;
  perform bk_admin_guard(uid, row_cc);
  return coalesce((select json_object_agg(channel, n) from (
    select channel, count(*) as n from bk_campaign_audience(p_id) group by channel) x), '{}'::json);
end $function$;

create or replace function public.bk_admin_campaign_send(p_token text, p_id uuid, p_test boolean default false)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; row_cc text; row_status text; n int;
begin
  uid := bk_admin_uid(p_token);
  select country_code, status into row_cc, row_status from campaigns where id = p_id;
  if row_cc is null then return json_build_object('error', 'notfound'); end if;
  if row_status not in ('draft', 'scheduled') then return json_build_object('error', 'already_sent'); end if;
  perform bk_admin_guard(uid, row_cc);
  if p_test then
    insert into campaign_sends (campaign_id, contact_id, channel)
    select p_id, c.id, ch.channel from contacts c
      cross join unnest((select channels from campaigns where id = p_id)) as ch(channel)
     where c.user_id = uid
       and ((ch.channel = 'telegram' and c.tg_chat_id is not null)
         or (ch.channel = 'whatsapp' and c.phone is not null)
         or (ch.channel = 'email' and c.email is not null));
    get diagnostics n = row_count;
    if n = 0 then return json_build_object('error', 'no_test_contact'); end if;
    return json_build_object('ok', true, 'queued', n, 'test', true);
  end if;
  insert into campaign_sends (campaign_id, contact_id, channel)
    select p_id, contact_id, channel from bk_campaign_audience(p_id);
  get diagnostics n = row_count;
  update campaigns set status = 'sending', sent_at = now() where id = p_id;
  return json_build_object('ok', true, 'queued', n);
end $function$;

create or replace function public.bk_admin_campaign_stats(p_token text, p_id uuid)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; row_cc text;
begin
  uid := bk_admin_uid(p_token);
  select country_code into row_cc from campaigns where id = p_id;
  if row_cc is null then return json_build_object('error', 'notfound'); end if;
  perform bk_admin_guard(uid, row_cc);
  return coalesce((select json_object_agg(status, n) from (
    select status, count(*) as n from campaign_sends where campaign_id = p_id group by status) x), '{}'::json);
end $function$;

-- ── service-only (Edge Function, service-role key; execute revoked from anon/authenticated below,
-- matching bk_notify_pending/bk_notify_mark/bk_verify_tg_open) ──

create or replace function public.bk_campaign_sends_pending(p_limit int default 200)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  return coalesce((select json_agg(row_to_json(x)) from (
    select s.id, s.channel, c.phone, c.email, c.tg_chat_id,
           coalesce(camp.body_ar, l.description, '') as body_ar, coalesce(camp.body_en, '') as body_en,
           camp.subject
      from campaign_sends s
      join contacts c on c.id = s.contact_id
      left join campaigns camp on camp.id = s.campaign_id
      left join listings l on l.id = s.listing_id
     where s.status = 'queued'
     order by s.created_at limit p_limit) x), '[]'::json);
end $function$;
revoke execute on function public.bk_campaign_sends_pending(int) from public, anon, authenticated;

create or replace function public.bk_campaign_sends_mark(p_ok_ids bigint[], p_failed jsonb default '[]'::jsonb)
returns void language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare f jsonb; camp uuid;
begin
  update campaign_sends set status = 'sent', sent_at = now() where id = any(p_ok_ids);
  for f in select * from jsonb_array_elements(p_failed) loop
    update campaign_sends set status = 'failed', error = left(f->>'error', 300) where id = (f->>'id')::bigint;
  end loop;
  for camp in select distinct campaign_id from campaign_sends where campaign_id is not null and (id = any(p_ok_ids) or exists (select 1 from jsonb_array_elements(p_failed) e where (e->>'id')::bigint = campaign_sends.id)) loop
    update campaigns set
      sent_count = (select count(*) from campaign_sends where campaign_id = camp and status = 'sent'),
      failed_count = (select count(*) from campaign_sends where campaign_id = camp and status = 'failed'),
      status = case when not exists (select 1 from campaign_sends where campaign_id = camp and status = 'queued')
                    then (case when exists (select 1 from campaign_sends where campaign_id = camp and status = 'failed') then 'failed' else 'sent' end)
                    else status end
      where id = camp;
  end loop;
end $function$;
revoke execute on function public.bk_campaign_sends_mark(bigint[], jsonb) from public, anon, authenticated;

-- Telegram opt-in: "/start n<hex>" in the Edge Function calls this with the tapped contact's id (encoded
-- in the deep link the admin/account-page shares) and the chat id that tapped it — distinct namespace
-- from the verification flow's "/start v<ticket>", and from a different table entirely (contacts, not
-- verify_tickets), so the two can never collide.
create or replace function public.bk_contact_tg_open(p_contact_id uuid, p_chat_id text, p_name text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  update contacts set tg_chat_id = p_chat_id, tg_consent = case when tg_consent = 'unsubscribed' then tg_consent else 'subscribed' end
   where id = p_contact_id;
  if not found then return json_build_object('error', 'notfound'); end if;
  return json_build_object('ok', true);
end $function$;
revoke execute on function public.bk_contact_tg_open(uuid, text, text) from public, anon, authenticated;

-- public, anon-callable (like bk_verify_check) — one-click email unsubscribe, no login
create or replace function public.bk_contact_unsub(p_token text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  update contacts set email_consent = 'unsubscribed' where unsub_token = p_token;
  if not found then return json_build_object('error', 'notfound'); end if;
  return json_build_object('ok', true);
end $function$;

-- member-facing: a logged-in member's own Telegram opt-in link for the account page (creates their
-- contacts row on first use if the sync trigger hasn't run yet for some reason)
create or replace function public.bk_member_contact_tg_link(p_token text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; cid uuid;
begin
  uid := bk_member_uid(p_token); if uid is null then return json_build_object('error', 'unauthorised'); end if;
  select id into cid from contacts where user_id = uid;
  if cid is null then
    insert into contacts (user_id, phone, email, country_code, source)
      select id, phone, email, coalesce(upper(country), 'SY'), 'member' from users where id = uid
      returning id into cid;
  end if;
  return json_build_object('ok', true, 'contact_id', cid);
end $function$;

-- bk_admin_countries reproduced byte-for-byte from its live body (pulled just now via
-- pg_get_functiondef) plus one more coalesce key, 'campaign_cfg', so the campaigns tab's per-country
-- automation card can render real current state — same jsonb_object_agg-over-extras-keys shape already
-- used for 'verify' two lines above it. Nothing else in this function changed.
create or replace function public.bk_admin_countries(p_token text)
returns json language plpgsql security definer set search_path to 'public' as $function$
declare uid uuid; al text[];
begin
  uid := bk_admin_uid(p_token); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(json_build_object(
    'code',c.code,'name_ar',c.name_ar,'name_en',c.name_en,'name_de',c.name_de,'name_fr',c.name_fr,'name_tr',c.name_tr,
    'enabled',c.enabled,'is_default',c.is_default,'currencies',c.currencies,'rates',c.rates,'phone_code',c.phone_code,
    'tz',c.tz,'lat',c.lat,'lng',c.lng,'zoom',c.zoom,'sort_order',c.sort_order,'languages',c.languages,'notes',c.notes,'types',c.types,
    'govs',(select count(*) from governorates g where g.country_code=c.code),
    'areas',(select count(*) from areas a join governorates g on g.id=a.governorate_id where g.country_code=c.code),
    'listings',(select count(*) from listings l where l.country_code=c.code and l.status='live'),
    'wanted',(select count(*) from wanted w where w.country_code=c.code and w.status='open'),
    'agencies',(select count(*) from agencies a where a.country_code=c.code),
    'ads',(select count(*) from ad_slots a where a.country_code=c.code and a.enabled),
    'featured',(select count(*) from listings l where l.country_code=c.code and l.status='live' and l.is_featured),
    'bg',(select s.hero_bg_type from site_content s where s.country_code=c.code limit 1),
    'bg_photo',(select s.hero_bg_photo_url from site_content s where s.country_code=c.code limit 1),
    'banners',(select case when s.banner_items is null or s.banner_items='' then 0 else coalesce(jsonb_array_length(s.banner_items::jsonb),0) end from site_content s where s.country_code=c.code limit 1),
    'banner_on',(select s.banner_enabled from site_content s where s.country_code=c.code limit 1),
    'deeds',(select coalesce(json_agg(json_build_object('code',d.code,'ar',d.name_ar,'en',d.name_en,'de',d.name_de,'fr',d.name_fr,'strong',d.is_strong,'enabled',d.enabled) order by d.sort_order),'[]'::json) from deed_types d where d.country_code=c.code),
    'verify',coalesce((select (select jsonb_object_agg(key,value) from jsonb_each(coalesce(extras,'{}'::jsonb)) where key in ('verify_telegram_on','verify_wa_code_on','verify_email_on')) from site_content s where s.country_code=c.code), '{}'::jsonb),
    'campaign_cfg',coalesce((select (select jsonb_object_agg(key,value) from jsonb_each(coalesce(extras,'{}'::jsonb)) where key in ('auto_notify_new_listing_on','auto_notify_ch_telegram','auto_notify_ch_whatsapp','auto_notify_ch_email')) from site_content s where s.country_code=c.code), '{}'::jsonb),
    'contacts',(select count(*) from contacts ct where ct.country_code=c.code)
  ) order by c.sort_order) from countries c where al is null or c.code = any(al)), '[]'::json);
end $function$;

-- follow-up (applied as contacts_campaigns_pending_followup): bk_campaign_sends_pending needed the
-- contact's unsub_token (email unsubscribe link) and listing detail so the Edge Function can build a real
-- message for an automatic 'auto_new_listing' send, which has no campaigns row to read a body from.
create or replace function public.bk_campaign_sends_pending(p_limit int default 200)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  return coalesce((select json_agg(row_to_json(x)) from (
    select s.id, s.channel, s.trigger_type, c.phone, c.email, c.tg_chat_id, c.unsub_token,
           coalesce(camp.body_ar, '') as body_ar, coalesce(camp.body_en, '') as body_en, camp.subject,
           l.id as listing_id, l.ref as listing_ref, l.price_usd as listing_price, l.description as listing_description
      from campaign_sends s
      join contacts c on c.id = s.contact_id
      left join campaigns camp on camp.id = s.campaign_id
      left join listings l on l.id = s.listing_id
     where s.status = 'queued'
     order by s.created_at limit p_limit) x), '[]'::json);
end $function$;
revoke execute on function public.bk_campaign_sends_pending(int) from public, anon, authenticated;
