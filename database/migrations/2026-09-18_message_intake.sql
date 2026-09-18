-- 2026-09-18 — message intake: listings sent by WhatsApp / Telegram / pasted text are read by Claude
-- (inside the Edge Function bk-intake) and published under an approved agency's account.
-- Applied with the Supabase MCP apply_migration as "message_intake". This file is the copy of record.
--
-- Tables    intake_drafts (one per listing being collected), intake_messages (every incoming message, idempotent
--           by source + external id), intake_log (events for the panel).
-- Agencies  intake_enabled (may post by message), intake_trusted (published live, no review), intake_phone
--           (WhatsApp sender override), intake_telegram (+ name, paired via /start <code>), intake_code (pairing).
-- Settings  site_content id=1 extras.intake_* (see bk_intake_cfg for the defaults) — edited from the panel.
-- Service functions bk_intake_* are callable by the service role only (the Edge Function); admin/member
-- functions check the session token as everywhere else.

alter table public.agencies
  add column if not exists intake_enabled boolean not null default false,
  add column if not exists intake_trusted boolean not null default false,
  add column if not exists intake_phone text,
  add column if not exists intake_telegram bigint,
  add column if not exists intake_telegram_name text,
  add column if not exists intake_code text,
  add column if not exists intake_paired_at timestamptz;
create unique index if not exists agencies_intake_telegram_uq on public.agencies(intake_telegram) where intake_telegram is not null;
create unique index if not exists agencies_intake_code_uq on public.agencies(intake_code) where intake_code is not null;

create table if not exists public.intake_drafts (
  id bigserial primary key,
  source text not null check (source in ('telegram','whatsapp','web')),
  chat_id text not null,
  sender_name text,
  agency_id bigint references public.agencies(id) on delete set null,
  user_id uuid references public.users(id) on delete set null,
  by_admin boolean not null default false,
  country_code text not null default 'SY',
  status text not null default 'collecting'
    check (status in ('collecting','reading','ready','needs_info','review','published','cancelled','failed')),
  raw_text text not null default '',
  fields jsonb not null default '{}'::jsonb,
  missing text[] not null default '{}',
  summary text,
  photos jsonb not null default '[]'::jsonb,
  listing_id bigint references public.listings(id) on delete set null,
  error text,
  model text,
  tokens_in integer not null default 0,
  tokens_out integer not null default 0,
  cost_usd numeric(10,5) not null default 0,
  reads integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  claimed_at timestamptz,
  processed_at timestamptz,
  published_at timestamptz
);
create index if not exists intake_drafts_status_idx on public.intake_drafts (status, last_message_at);
create index if not exists intake_drafts_chat_idx on public.intake_drafts (source, chat_id, created_at desc);
create index if not exists intake_drafts_created_idx on public.intake_drafts (created_at desc);

create table if not exists public.intake_messages (
  id bigserial primary key,
  draft_id bigint references public.intake_drafts(id) on delete cascade,
  source text not null,
  external_id text not null,
  chat_id text not null,
  kind text not null default 'text',
  text text,
  media jsonb,
  payload jsonb,
  received_at timestamptz not null default now(),
  unique (source, external_id)
);
create index if not exists intake_messages_draft_idx on public.intake_messages (draft_id, received_at);

create table if not exists public.intake_log (
  id bigserial primary key,
  draft_id bigint,
  chat_id text,
  level text not null default 'info',
  event text not null,
  detail jsonb,
  created_at timestamptz not null default now()
);
create index if not exists intake_log_created_idx on public.intake_log (created_at desc);
create index if not exists intake_log_chat_idx on public.intake_log (chat_id, event, created_at desc);

alter table public.intake_drafts enable row level security;
alter table public.intake_messages enable row level security;
alter table public.intake_log enable row level security;
revoke all on public.intake_drafts, public.intake_messages, public.intake_log from anon, authenticated;
revoke all on sequence public.intake_drafts_id_seq, public.intake_messages_id_seq, public.intake_log_id_seq from anon, authenticated;

-- ───────────────────────────── settings ─────────────────────────────
create or replace function public.bk_intake_cfg()
returns jsonb language sql stable security definer set search_path to 'public','extensions' as $$
  select jsonb_build_object(
    'intake_enabled', true, 'intake_wait_s', 90, 'intake_model', 'claude-haiku-4-5-20251001',
    'intake_max_photos', 12, 'intake_reply_lang', 'ar', 'intake_daily_limit', 30,
    'intake_price_in', 1, 'intake_price_out', 5, 'intake_admin_chats', '{}'::jsonb,
    'intake_admin_code', null, 'intake_bot', null, 'intake_wa_display', null, 'intake_telegram_on', true, 'intake_whatsapp_on', true)
  || coalesce((select (select jsonb_object_agg(key, value) from jsonb_each(coalesce(extras,'{}'::jsonb)) where key like 'intake\_%') from site_content where id = 1), '{}'::jsonb);
$$;

-- digits only; "00963…" and "+963…" become "963…"; a bare local "09xx…" keeps its digits (matched loosely below)
create or replace function public.bk_intake_norm_phone(p text)
returns text language sql immutable as $$
  select nullif(regexp_replace(regexp_replace(coalesce(p,''), '\D', '', 'g'), '^00', ''), '');
$$;
-- tolerant casts for what the model hands back ("3", " 3 ", "3 غرف" → 3; "yes"/"نعم" → true)
create or replace function public.bk_intake_int(t text)
returns integer language sql immutable as $$
  select case when regexp_replace(coalesce(t,''), '[^0-9-]', '', 'g') ~ '^-?\d{1,9}$' then regexp_replace(t, '[^0-9-]', '', 'g')::int end;
$$;
create or replace function public.bk_intake_num(t text)
returns numeric language sql immutable as $$
  select case when trim(coalesce(t,'')) ~ '^-?\d{1,12}(\.\d{1,8})?$' then trim(t)::numeric end;
$$;
create or replace function public.bk_intake_bool(t text, d boolean)
returns boolean language sql immutable as $$
  select case when lower(trim(coalesce(t,''))) in ('true','1','yes','y','نعم','t') then true
              when lower(trim(coalesce(t,''))) in ('false','0','no','n','لا','f') then false else d end;
$$;

-- who is talking: an approved agency that may post by message, the site owner (admin chat), or unknown
create or replace function public.bk_intake_sender(p_source text, p_chat_id text)
returns json language plpgsql stable security definer set search_path to 'public','extensions' as $$
declare cfg jsonb; a agencies; u users; is_admin boolean := false; digits text; wa text;
begin
  cfg := bk_intake_cfg();
  if p_source = 'telegram' then
    if p_chat_id ~ '^-?\d+$' then
      select * into a from agencies where intake_telegram = p_chat_id::bigint;
    end if;
    is_admin := coalesce(cfg->'intake_admin_chats'->'telegram', '[]'::jsonb) ? p_chat_id;
  elsif p_source = 'whatsapp' then
    digits := bk_intake_norm_phone(p_chat_id);
    if digits is not null then
      select ag.* into a from agencies ag
        left join users us on us.id = ag.user_id
       where ag.status = 'approved' and (
             bk_intake_norm_phone(ag.intake_phone) = digits
          or bk_intake_norm_phone(ag.whatsapp) = digits or bk_intake_norm_phone(ag.phone) = digits
          or bk_intake_norm_phone(us.phone) = digits
          or (length(digits) >= 9 and (right(bk_intake_norm_phone(ag.intake_phone), 9) = right(digits, 9)
                                     or right(bk_intake_norm_phone(ag.whatsapp), 9) = right(digits, 9))))
       order by (bk_intake_norm_phone(ag.intake_phone) = digits) desc nulls last, ag.id limit 1;
      select bk_intake_norm_phone(wa_number) into wa from site_content where id = 1;
      is_admin := (wa is not null and wa = digits)
               or coalesce(cfg->'intake_admin_chats'->'whatsapp', '[]'::jsonb) ? digits
               or exists (select 1 from users where role = 'admin' and bk_intake_norm_phone(phone) = digits);
    end if;
  elsif p_source = 'web' then
    select * into u from users where id::text = p_chat_id;
    if u.id is not null then
      select * into a from agencies where user_id = u.id;
      is_admin := u.role = 'admin';
    end if;
  end if;
  if a.id is not null then select * into u from users where id = a.user_id; end if;
  return json_build_object(
    'agency_id', a.id, 'agency_name', a.name, 'agency_status', a.status,
    'user_id', coalesce(a.user_id, u.id), 'user_name', trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),
    'enabled', coalesce(a.status = 'approved' and a.intake_enabled, false) or is_admin,
    'trusted', coalesce(a.intake_trusted, false),
    'is_admin', is_admin,
    'blocked', coalesce(u.blocked, false),
    'country_code', coalesce(a.country_code, 'SY'),
    'lang', coalesce(u.lang, 'ar'));
end $$;

-- pairing: /start <code> from Telegram (or "ربط <code>" from WhatsApp) links the chat to an agency, or to the owner
create or replace function public.bk_intake_pair(p_source text, p_chat_id text, p_code text, p_name text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare cfg jsonb; a agencies; code text; chats jsonb; arr jsonb; key text;
begin
  code := upper(trim(coalesce(p_code,'')));
  if code = '' then return json_build_object('error','nocode'); end if;
  cfg := bk_intake_cfg();
  if cfg->>'intake_admin_code' is not null and upper(cfg->>'intake_admin_code') = code then
    key := case when p_source = 'whatsapp' then 'whatsapp' else 'telegram' end;
    chats := coalesce(cfg->'intake_admin_chats', '{}'::jsonb);
    arr := coalesce(chats->key, '[]'::jsonb);
    if not arr ? p_chat_id then arr := arr || to_jsonb(p_chat_id); end if;
    chats := chats || jsonb_build_object(key, arr);
    update site_content set extras = coalesce(extras,'{}'::jsonb) || jsonb_build_object('intake_admin_chats', chats) where id = 1;
    insert into intake_log (chat_id, event, detail) values (p_chat_id, 'paired_admin', jsonb_build_object('source', p_source, 'name', p_name));
    return json_build_object('ok', true, 'kind', 'admin');
  end if;
  select * into a from agencies where upper(intake_code) = code;
  if a.id is null then return json_build_object('error','badcode'); end if;
  if a.status <> 'approved' then return json_build_object('error','notapproved','name',a.name); end if;
  if p_source = 'telegram' then
    if not (p_chat_id ~ '^-?\d+$') then return json_build_object('error','badchat'); end if;
    update agencies set intake_telegram = null where intake_telegram = p_chat_id::bigint and id <> a.id;
    update agencies set intake_telegram = p_chat_id::bigint, intake_telegram_name = p_name, intake_paired_at = now(), updated_at = now() where id = a.id;
  else
    update agencies set intake_phone = bk_intake_norm_phone(p_chat_id), intake_paired_at = now(), updated_at = now() where id = a.id;
  end if;
  insert into intake_log (chat_id, event, detail) values (p_chat_id, 'paired', jsonb_build_object('source', p_source, 'agency_id', a.id, 'name', p_name));
  return json_build_object('ok', true, 'kind', 'agency', 'agency_id', a.id, 'name', a.name, 'enabled', a.intake_enabled);
end $$;

-- every incoming message lands here (idempotent). Returns what the Edge Function should do next.
create or replace function public.bk_intake_message(
  p_source text, p_external_id text, p_chat_id text, p_kind text, p_text text,
  p_media jsonb default null, p_payload jsonb default null, p_sender_name text default null, p_country text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare cfg jsonb; s json; d intake_drafts; cmd text; tx text; ins int; is_new boolean := false; cc text;
        n_today int; replied boolean;
begin
  cfg := bk_intake_cfg();
  insert into intake_messages (source, external_id, chat_id, kind, text, media, payload)
    values (p_source, p_external_id, p_chat_id, coalesce(p_kind,'text'), p_text, p_media, p_payload)
    on conflict (source, external_id) do nothing;
  get diagnostics ins = row_count;
  if ins = 0 then return json_build_object('duplicate', true); end if;

  s := bk_intake_sender(p_source, p_chat_id);
  if not coalesce((s->>'enabled')::boolean, false) or coalesce((s->>'blocked')::boolean, false) then
    replied := exists (select 1 from intake_log where chat_id = p_chat_id and event = 'unknown_reply' and created_at > now() - interval '24 hours');
    insert into intake_log (chat_id, event, detail) values (p_chat_id, 'unknown_sender', jsonb_build_object('source', p_source, 'name', p_sender_name, 'kind', p_kind));
    return json_build_object('reason', case when coalesce((s->>'blocked')::boolean,false) then 'blocked' else 'unknown' end, 'replied_recently', replied, 'sender', s);
  end if;

  tx := trim(coalesce(p_text, ''));
  cmd := case
    when tx ~* '^(1|نعم|انشر|نشر|publish|ok|اوك|أوك|✅)[.!]?$' then 'confirm'
    when tx ~* '^(2|إلغاء|الغاء|الغي|ألغي|cancel|x|❌)[.!]?$' then 'cancel'
    when tx ~* '^(تم|تمام|انتهيت|خلص|خلاص|done|end|finish)[.!]?$' then 'done'
    when tx ~* '^(جديد|إعلان جديد|اعلان جديد|new|/new)$' then 'new'
    when tx ~* '^(مساعدة|help|/help|\?)$' then 'help'
    else null end;

  -- the open draft of this chat (one listing at a time per chat)
  select * into d from intake_drafts
   where source = p_source and chat_id = p_chat_id and status in ('collecting','reading','ready','needs_info')
     and last_message_at > now() - interval '12 hours'
   order by created_at desc limit 1;

  if cmd = 'help' then return json_build_object('command','help','draft_id',d.id,'status',d.status,'sender',s); end if;
  if cmd = 'confirm' then
    if d.id is not null and d.status = 'ready' then
      update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
      return json_build_object('command','confirm','draft_id',d.id,'status',d.status,'sender',s);
    end if;
    return json_build_object('command','confirm','draft_id',null,'status',d.status,'sender',s);
  end if;
  if cmd = 'cancel' then
    if d.id is not null then
      update intake_drafts set status = 'cancelled', updated_at = now() where id = d.id;
      update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
      insert into intake_log (draft_id, chat_id, event) values (d.id, p_chat_id, 'cancelled_by_sender');
    end if;
    return json_build_object('command','cancel','draft_id',d.id,'sender',s);
  end if;
  if cmd = 'new' then
    if d.id is not null and d.status in ('ready','needs_info') then
      update intake_drafts set status = 'cancelled', updated_at = now() where id = d.id;
    end if;
    return json_build_object('command','new','draft_id',null,'sender',s);
  end if;
  if cmd = 'done' then
    if d.id is not null then update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id; end if;
    return json_build_object('command','done','draft_id',d.id,'status',d.status,'sender',s,
      'empty', d.id is null or (coalesce(d.raw_text,'') = '' and jsonb_array_length(d.photos) = 0));
  end if;

  -- content: attach to the open draft, or open a new one
  cc := coalesce(nullif(upper(p_country),''), s->>'country_code', 'SY');
  if d.id is null then
    select count(*) into n_today from intake_drafts where source = p_source and chat_id = p_chat_id and created_at > now() - interval '24 hours';
    if n_today >= coalesce((cfg->>'intake_daily_limit')::int, 30) then
      insert into intake_log (chat_id, event, detail) values (p_chat_id, 'daily_limit', jsonb_build_object('n', n_today));
      return json_build_object('reason','limit','sender',s);
    end if;
    insert into intake_drafts (source, chat_id, sender_name, agency_id, user_id, by_admin, country_code, raw_text, status)
      values (p_source, p_chat_id, p_sender_name, (s->>'agency_id')::bigint, (s->>'user_id')::uuid,
              coalesce((s->>'is_admin')::boolean,false) and s->>'agency_id' is null, cc, tx, 'collecting')
      returning * into d;
    is_new := true;
    insert into intake_log (draft_id, chat_id, event, detail) values (d.id, p_chat_id, 'draft_open', jsonb_build_object('source', p_source, 'agency_id', s->>'agency_id', 'admin', s->>'is_admin'));
  else
    update intake_drafts set
      raw_text = case when tx <> '' then rtrim(raw_text) || case when raw_text = '' then '' else E'\n' end || tx else raw_text end,
      status = case when status in ('ready','needs_info') then 'collecting' else status end,
      last_message_at = now(), updated_at = now()
     where id = d.id returning * into d;
  end if;
  update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
  return json_build_object('draft_id', d.id, 'status', d.status, 'is_new', is_new, 'sender', s, 'country_code', d.country_code,
    'photo_count', jsonb_array_length(d.photos), 'has_text', d.raw_text <> '');
end $$;

create or replace function public.bk_intake_add_photo(p_draft bigint, p_photo jsonb)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare n int; mx int;
begin
  mx := coalesce((bk_intake_cfg()->>'intake_max_photos')::int, 12);
  select jsonb_array_length(photos) into n from intake_drafts where id = p_draft;
  if n is null then return json_build_object('error','nodraft'); end if;
  if n >= mx then return json_build_object('ok', false, 'reason', 'max', 'n', n); end if;
  update intake_drafts set photos = photos || jsonb_build_array(p_photo), last_message_at = now(), updated_at = now() where id = p_draft;
  return json_build_object('ok', true, 'n', n + 1);
end $$;

-- drafts whose sender went quiet: claim them for reading (skip-locked so two ticks never read the same draft)
create or replace function public.bk_intake_due(p_wait_s integer default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare w int; out json;
begin
  w := coalesce(p_wait_s, (bk_intake_cfg()->>'intake_wait_s')::int, 90);
  update intake_drafts set status = 'collecting', updated_at = now() where status = 'reading' and claimed_at < now() - interval '10 minutes';   -- a crashed read goes back to the queue
  with u as (
    update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
     where id in (select id from intake_drafts
                   where status = 'collecting' and last_message_at < now() - make_interval(secs => w)
                     and (raw_text <> '' or jsonb_array_length(photos) > 0)
                   order by last_message_at limit 5 for update skip locked)
     returning *)
  select coalesce(json_agg(row_to_json(u)), '[]'::json) into out from u;
  return out;
end $$;

-- immediate reading ("تم", admin "read again"): claim one draft
create or replace function public.bk_intake_claim(p_draft bigint)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare d intake_drafts;
begin
  update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
   where id = p_draft and status in ('collecting','ready','needs_info','failed','review') returning * into d;
  if d.id is null then return null; end if;
  return row_to_json(d);
end $$;

-- everything Claude needs to know about one country's vocabulary
create or replace function public.bk_intake_taxonomy(p_country text default 'SY')
returns json language plpgsql stable security definer set search_path to 'public','extensions' as $$
declare cc text; c countries; types jsonb; rates jsonb; syp int;
begin
  cc := coalesce(nullif(upper(p_country),''), 'SY');
  select * into c from countries where code = cc;
  if c.code is null then select * into c from countries where code = 'SY'; cc := 'SY'; end if;
  types := coalesce(c.types, '[]'::jsonb);
  if jsonb_array_length(types) = 0 then
    types := '[{"code":"apartment","ar":"شقة","en":"Apartment"},{"code":"arab","ar":"بيت عربي","en":"Arab courtyard house"},{"code":"villa","ar":"فيلا","en":"Villa"},{"code":"floor","ar":"طابق كامل","en":"Whole floor"},{"code":"building","ar":"بناء كامل","en":"Whole building"},{"code":"chalet","ar":"شاليه","en":"Chalet"},{"code":"restaurant","ar":"مطعم","en":"Restaurant"},{"code":"farm","ar":"مزرعة","en":"Farm"},{"code":"resid","ar":"أرض سكنية","en":"Residential land"},{"code":"agri","ar":"أرض زراعية","en":"Agricultural land"},{"code":"comm","ar":"أرض تجارية","en":"Commercial land"},{"code":"shop","ar":"محل تجاري","en":"Shop"},{"code":"office","ar":"مكتب","en":"Office"},{"code":"factory","ar":"مصنع","en":"Factory"},{"code":"warehouse","ar":"مستودع","en":"Warehouse"}]'::jsonb;
  end if;
  rates := coalesce(c.rates, '{}'::jsonb);
  if cc = 'SY' then select syp_rate into syp from site_content where id = 1; if syp > 0 then rates := rates || jsonb_build_object('SYP', syp); end if; end if;
  return json_build_object(
    'country', json_build_object('code', cc, 'name_ar', c.name_ar, 'name_en', c.name_en, 'currencies', c.currencies, 'rates', rates, 'phone_code', c.phone_code),
    'governorates', coalesce((select json_agg(json_build_object('id', g.id, 'ar', g.name_ar, 'en', g.name_en,
        'areas', coalesce((select json_agg(json_build_array(a.id, a.name_ar, a.name_en) order by a.sort_order, a.id) from areas a where a.governorate_id = g.id and coalesce(a.enabled,true)), '[]'::json)) order by g.sort_order, g.id)
        from governorates g where g.country_code = cc and coalesce(g.enabled,true)), '[]'::json),
    'types', types,
    'deeds', coalesce((select json_agg(json_build_object('code', d.code, 'ar', d.name_ar, 'en', d.name_en, 'strong', d.is_strong) order by d.sort_order) from deed_types d where d.country_code = cc and coalesce(d.enabled,true)), '[]'::json),
    'conditions', case when cc = 'SY'
        then '[{"code":"intact","ar":"سليم"},{"code":"repair","ar":"يحتاج ترميم"},{"code":"shell","ar":"على العظم"},{"code":"stripped","ar":"معفش"},{"code":"damaged","ar":"متضرر"}]'::json
        else '[{"code":"intact","ar":"سليم"},{"code":"repair","ar":"يحتاج ترميم"},{"code":"shell","ar":"على العظم"},{"code":"damaged","ar":"متضرر"}]'::json end,
    'land_conditions', '[{"code":"empty","ar":"أرض فارغة"},{"code":"built","ar":"عليها بناء"},{"code":"fenced","ar":"مسوّرة"},{"code":"planted","ar":"مزروعة"}]'::json,
    'amenities', '["مصعد","موقف سيارات","تدفئة مركزية","خزّان مياه","اشتراك مولّدة","حارس","إنترنت","باب أمان","شرفة","تكييف","طاقة بديلة"]'::json,
    'land_amenities', '["سور","بئر ماء","كهرباء واصلة","ماء واصل","طريق معبّد","أرض مستوية","داخل التنظيم","مفرزة","إطلالة","قريبة من الطريق العام"]'::json,
    'directions', '[{"code":"s","ar":"قبلي (جنوبي)"},{"code":"n","ar":"شمالي"},{"code":"e","ar":"شرقي"},{"code":"w","ar":"غربي"},{"code":"se","ar":"قبلي شرقي"},{"code":"sw","ar":"قبلي غربي"},{"code":"ne","ar":"شمالي شرقي"},{"code":"nw","ar":"شمالي غربي"}]'::json,
    'rental_periods', '["yearly","monthly","weekly","daily"]'::json,
    'land_types', '["resid","agri","comm"]'::json,
    'commercial_types', '["shop","office","factory","warehouse"]'::json);
end $$;

-- what Claude read; the draft becomes ready (or needs_info / review) unless new messages arrived meanwhile
create or replace function public.bk_intake_save_read(
  p_draft bigint, p_fields jsonb, p_missing text[], p_summary text, p_status text,
  p_model text default null, p_in integer default 0, p_out integer default 0, p_cost numeric default 0, p_error text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare d intake_drafts; st text;
begin
  select * into d from intake_drafts where id = p_draft;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  st := coalesce(p_status, 'ready');
  if p_error is null and d.claimed_at is not null and (d.last_message_at > d.claimed_at
     or exists (select 1 from intake_messages m where m.draft_id = d.id and m.received_at > d.claimed_at)) then
    st := 'collecting';   -- more arrived while reading: read again after the wait
  end if;
  if st not in ('ready','needs_info','review','failed','collecting') then st := 'review'; end if;
  update intake_drafts set
    fields = coalesce(p_fields, fields), missing = coalesce(p_missing, '{}'), summary = coalesce(p_summary, summary),
    status = st, error = p_error, model = coalesce(p_model, model),
    tokens_in = tokens_in + coalesce(p_in,0), tokens_out = tokens_out + coalesce(p_out,0), cost_usd = cost_usd + coalesce(p_cost,0),
    processed_at = now(), updated_at = now()
   where id = p_draft returning * into d;
  insert into intake_log (draft_id, chat_id, level, event, detail) values (d.id, d.chat_id, case when p_error is null then 'info' else 'warn' end, 'read',
    jsonb_build_object('status', st, 'missing', p_missing, 'model', p_model, 'in', p_in, 'out', p_out, 'cost', p_cost, 'error', p_error));
  return row_to_json(d);
end $$;

create or replace function public.bk_intake_set(p_draft bigint, p_patch jsonb)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare d intake_drafts;
begin
  update intake_drafts set
    status = coalesce(p_patch->>'status', status),
    error = case when p_patch ? 'error' then p_patch->>'error' else error end,
    summary = coalesce(p_patch->>'summary', summary),
    fields = case when p_patch ? 'fields' then p_patch->'fields' else fields end,
    photos = case when p_patch ? 'photos' then p_patch->'photos' else photos end,
    agency_id = case when p_patch ? 'agency_id' then (p_patch->>'agency_id')::bigint else agency_id end,
    user_id = case when p_patch ? 'user_id' then (p_patch->>'user_id')::uuid else user_id end,
    listing_id = case when p_patch ? 'listing_id' then (p_patch->>'listing_id')::bigint else listing_id end,
    updated_at = now()
   where id = p_draft returning * into d;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  return row_to_json(d);
end $$;

create or replace function public.bk_intake_log(p_draft bigint, p_chat text, p_level text, p_event text, p_detail jsonb default null)
returns void language sql security definer set search_path to 'public','extensions' as $$
  insert into intake_log (draft_id, chat_id, level, event, detail) values (p_draft, p_chat, coalesce(p_level,'info'), p_event, p_detail);
$$;

create or replace function public.bk_intake_get(p_draft bigint)
returns json language plpgsql stable security definer set search_path to 'public','extensions' as $$
declare d intake_drafts;
begin
  select * into d from intake_drafts where id = p_draft;
  if d.id is null then return null; end if;
  return (select row_to_json(x) from (
    select dd.*, a.name as agency_name, a.phone as agency_phone, a.whatsapp as agency_whatsapp, a.intake_trusted as agency_trusted,
           u.phone as user_phone, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as user_name, u.skip_review, u.lang as user_lang
      from intake_drafts dd left join agencies a on a.id = dd.agency_id left join users u on u.id = dd.user_id where dd.id = p_draft) x);
end $$;

-- the listing itself. Photos keep their intake URLs here; the Edge Function moves the files and calls
-- bk_intake_photos_moved afterwards.
create or replace function public.bk_intake_publish(p_draft bigint, p_force_status text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare d intake_drafts; f jsonb; a agencies; u users; tax json; l listings; gid int; aid int; cc text;
        ptype text; sec text; deal text; price numeric; cur text; rate numeric; usd int; m2 int; descr text;
        cond text; tabu text; st text; ph jsonb; i int; phone text; amen text[]; gname text; aname text;
        rent boolean; deed_ok boolean;
begin
  select * into d from intake_drafts where id = p_draft for update;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if d.status = 'published' and d.listing_id is not null then return json_build_object('error','already','listing_id',d.listing_id); end if;
  if d.user_id is null then return json_build_object('error','noagency'); end if;
  select * into u from users where id = d.user_id;
  if u.id is null or u.blocked then return json_build_object('error','nouser'); end if;
  if d.agency_id is not null then select * into a from agencies where id = d.agency_id; end if;
  f := coalesce(d.fields, '{}'::jsonb);
  cc := coalesce(nullif(upper(f->>'country_code'),''), d.country_code, 'SY');

  deal := lower(coalesce(f->>'deal','sale')); if deal not in ('sale','rent') then deal := 'sale'; end if;
  rent := deal = 'rent';
  ptype := lower(coalesce(f->>'property_type','apartment'));
  if ptype not in ('apartment','arab','villa','floor','building','chalet','restaurant','farm','resid','agri','comm','shop','office','factory','warehouse') then
    return json_build_object('error','badtype','value',ptype); end if;
  sec := case when ptype in ('resid','agri','comm') then 'land' when ptype in ('shop','office','factory','warehouse') then 'commercial' else 'homes' end;

  -- place: id first, then Arabic/English names inside the country
  gid := bk_intake_int(f->>'governorate_id');
  if gid is not null and not exists (select 1 from governorates where id = gid and country_code = cc) then gid := null; end if;
  gname := coalesce(f->>'governorate', f->>'gov');
  if gid is null and gname is not null then
    select id into gid from governorates where country_code = cc and (name_ar = gname or lower(name_en) = lower(gname)) limit 1;
    if gid is null then select id into gid from governorates where country_code = cc and (name_ar like '%'||gname||'%' or gname like '%'||name_ar||'%') order by length(name_ar) limit 1; end if;
  end if;
  if gid is null then return json_build_object('error','nogov'); end if;
  aid := bk_intake_int(f->>'area_id');
  if aid is not null and not exists (select 1 from areas where id = aid and governorate_id = gid) then aid := null; end if;
  aname := f->>'area';
  if aid is null and aname is not null then
    select id into aid from areas where governorate_id = gid and (name_ar = aname or lower(coalesce(name_en,'')) = lower(aname)) limit 1;
    if aid is null then select id into aid from areas where governorate_id = gid and (name_ar like '%'||aname||'%' or aname like '%'||name_ar||'%') order by length(name_ar) limit 1; end if;
  end if;

  -- money
  price := nullif(regexp_replace(coalesce(f->>'price',''), '[^0-9.]', '', 'g'), '')::numeric;
  if price is null or price <= 0 then return json_build_object('error','noprice'); end if;
  cur := upper(coalesce(nullif(f->>'currency',''), 'USD'));
  if cur = 'USD' then usd := round(price);
  else
    tax := bk_intake_taxonomy(cc);
    rate := nullif(tax->'country'->'rates'->>cur, '')::numeric;
    if rate is null or rate <= 0 then return json_build_object('error','norate','currency',cur); end if;
    usd := greatest(1, round(price / rate));
  end if;
  m2 := bk_intake_int(f->>'area_m2');
  if m2 is null or m2 <= 0 then return json_build_object('error','noarea'); end if;

  descr := trim(coalesce(f->>'description',''));
  if length(descr) < 30 then descr := trim(descr || E'\n' || coalesce(d.raw_text,'')); end if;
  if length(descr) < 30 then descr := rpad(descr || ' ' || coalesce(f->>'title',''), 30, '.'); end if;
  descr := left(descr, 1200);

  cond := lower(coalesce(f->>'condition',''));
  if sec = 'land' then if cond not in ('empty','built','fenced','planted') then cond := 'empty'; end if;
  else if cond not in ('intact','repair','shell','stripped','damaged') or (cond = 'stripped' and cc <> 'SY') then cond := 'intact'; end if; end if;
  tabu := lower(coalesce(f->>'tabu',''));
  if rent then tabu := 'none';
  else
    deed_ok := tabu <> '' and exists (select 1 from deed_types dt where dt.country_code = cc and dt.code = tabu);
    if not deed_ok then tabu := 'none'; end if;
  end if;
  phone := coalesce(nullif(bk_intake_norm_phone(f->>'contact_phone'),''), bk_intake_norm_phone(a.whatsapp), bk_intake_norm_phone(a.phone), bk_intake_norm_phone(u.phone));
  if phone is null then return json_build_object('error','nophone'); end if;
  phone := '+' || phone;
  amen := case when jsonb_typeof(f->'amenities') = 'array' then (select array_agg(x) from jsonb_array_elements_text(f->'amenities') x) else '{}'::text[] end;

  st := coalesce(p_force_status, case when coalesce(a.intake_trusted,false) or coalesce(u.skip_review,false) then 'live' else 'pending' end);
  if st not in ('pending','live') then st := 'pending'; end if;

  insert into listings (user_id, status, section, deal, property_type, governorate_id, area_id, landmark, lat, lng,
      price_usd, price_negotiable, area_m2, rooms, baths, living_rooms, floor, floors_total, year_built, tabu, condition,
      power_hours, generator_amps, heating, furnished, lease_months, advance_months, deposit_usd, bills_included, amenities,
      description, contact_phone, contact_name, accepts_whatsapp, by_owner, direction, rental_period, published_at, country_code)
  values (u.id, st, sec, deal, ptype, gid, aid, left(nullif(f->>'landmark',''), 120), bk_intake_num(f->>'lat'), bk_intake_num(f->>'lng'),
      usd, bk_intake_bool(f->>'negotiable', true), m2,
      case when sec = 'land' then null else bk_intake_int(f->>'rooms') end,
      case when sec = 'land' then null else bk_intake_int(f->>'baths') end,
      case when ptype in ('apartment','arab','villa') then bk_intake_int(f->>'living_rooms') else null end,
      bk_intake_int(f->>'floor'), bk_intake_int(f->>'floors_total'), bk_intake_int(f->>'year_built'), tabu, cond,
      least(24, greatest(0, bk_intake_int(f->>'power_hours'))), bk_intake_int(f->>'generator_amps'), left(nullif(f->>'heating',''), 60),
      bk_intake_bool(f->>'furnished', false),
      case when rent then bk_intake_int(f->>'lease_months') end, case when rent then bk_intake_int(f->>'advance_months') end,
      case when rent then bk_intake_int(f->>'deposit_usd') end, bk_intake_bool(f->>'bills_included', false), coalesce(amen, '{}'),
      descr, phone, coalesce(a.name, nullif(trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),'')),
      bk_intake_bool(f->>'accepts_whatsapp', true), false,
      case when lower(f->>'direction') in ('n','s','e','w','ne','nw','se','sw') then lower(f->>'direction') end,
      case when rent then (case when lower(f->>'rental_period') in ('daily','weekly','monthly','yearly') then lower(f->>'rental_period') else 'monthly' end) end,
      case when st = 'live' then now() end, cc)
  returning * into l;

  ph := coalesce(d.photos, '[]'::jsonb); i := 0;
  for i in 0 .. jsonb_array_length(ph) - 1 loop
    insert into listing_photos (listing_id, url, thumb_url, sort_order, kind, size_bytes)
      values (l.id, ph->i->>'url', ph->i->>'thumb_url', i, 'photo', nullif(ph->i->>'bytes','')::bigint);
  end loop;
  update intake_drafts set status = 'published', listing_id = l.id, published_at = now(), updated_at = now(), error = null where id = d.id;
  insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'published', jsonb_build_object('listing_id', l.id, 'ref', l.ref, 'status', l.status, 'photos', jsonb_array_length(ph)));
  return json_build_object('ok', true, 'listing_id', l.id, 'ref', l.ref, 'status', l.status, 'user_id', l.user_id, 'country_code', l.country_code, 'photos', jsonb_array_length(ph));
end $$;

-- after the files moved from intake/<draft>/ to photos/listings/<id>/ : {old_url: new_url}
create or replace function public.bk_intake_photos_moved(p_listing bigint, p_map jsonb)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare k text; n int := 0; r int;
begin
  for k in select jsonb_object_keys(coalesce(p_map,'{}'::jsonb)) loop
    update listing_photos set url = p_map->>k where listing_id = p_listing and url = k; get diagnostics r = row_count; n := n + r;
    update listing_photos set thumb_url = p_map->>k where listing_id = p_listing and thumb_url = k;
  end loop;
  return json_build_object('ok', true, 'updated', n);
end $$;

-- service-only: nobody but the Edge Function (service role) may call the bk_intake_* functions
revoke execute on function public.bk_intake_cfg() from public, anon, authenticated;
revoke execute on function public.bk_intake_sender(text, text) from public, anon, authenticated;
revoke execute on function public.bk_intake_pair(text, text, text, text) from public, anon, authenticated;
revoke execute on function public.bk_intake_message(text, text, text, text, text, jsonb, jsonb, text, text) from public, anon, authenticated;
revoke execute on function public.bk_intake_add_photo(bigint, jsonb) from public, anon, authenticated;
revoke execute on function public.bk_intake_due(integer) from public, anon, authenticated;
revoke execute on function public.bk_intake_claim(bigint) from public, anon, authenticated;
revoke execute on function public.bk_intake_taxonomy(text) from public, anon, authenticated;
revoke execute on function public.bk_intake_save_read(bigint, jsonb, text[], text, text, text, integer, integer, numeric, text) from public, anon, authenticated;
revoke execute on function public.bk_intake_set(bigint, jsonb) from public, anon, authenticated;
revoke execute on function public.bk_intake_log(bigint, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.bk_intake_get(bigint) from public, anon, authenticated;
revoke execute on function public.bk_intake_publish(bigint, text) from public, anon, authenticated;
revoke execute on function public.bk_intake_photos_moved(bigint, jsonb) from public, anon, authenticated;
revoke execute on function public.bk_intake_norm_phone(text) from public, anon, authenticated;
revoke execute on function public.bk_intake_int(text) from public, anon, authenticated;
revoke execute on function public.bk_intake_num(text) from public, anon, authenticated;
revoke execute on function public.bk_intake_bool(text, boolean) from public, anon, authenticated;

-- ───────────────────────────── admin ─────────────────────────────
create or replace function public.bk_admin_intake(p_token text, p_country text default null, p_status text default null, p_limit integer default 200)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; sc text; al text[]; cfg jsonb;
begin
  uid := bk_admin_uid(p_token);
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  cfg := bk_intake_cfg();
  return json_build_object(
    'cfg', cfg,
    'counts', (select json_build_object(
        'collecting', count(*) filter (where status in ('collecting','reading')),
        'ready', count(*) filter (where status in ('ready','needs_info')),
        'review', count(*) filter (where status = 'review'),
        'published', count(*) filter (where status = 'published'),
        'failed', count(*) filter (where status = 'failed'),
        'today', count(*) filter (where created_at > now() - interval '24 hours'),
        'cost_month', coalesce(sum(cost_usd) filter (where created_at > date_trunc('month', now())), 0),
        'cost_total', coalesce(sum(cost_usd), 0))
      from intake_drafts where bk_scope_ok(country_code, sc, al)),
    'drafts', coalesce((select json_agg(row_to_json(x)) from (
        select d.id, d.source, d.chat_id, d.sender_name, d.agency_id, d.user_id, d.by_admin, d.country_code, d.status,
               d.raw_text, d.fields, d.missing, d.summary, d.photos, d.listing_id, d.error, d.model, d.tokens_in, d.tokens_out, d.cost_usd,
               d.reads, d.created_at, d.updated_at, d.last_message_at, d.processed_at, d.published_at,
               a.name as agency_name, a.intake_trusted, l.ref as listing_ref, l.status as listing_status,
               (select count(*) from intake_messages m where m.draft_id = d.id) as messages
          from intake_drafts d left join agencies a on a.id = d.agency_id left join listings l on l.id = d.listing_id
         where bk_scope_ok(d.country_code, sc, al) and (p_status is null or d.status = p_status)
         order by d.created_at desc limit greatest(1, least(coalesce(p_limit,200), 500))) x), '[]'::json),
    'agencies', coalesce((select json_agg(row_to_json(x)) from (
        select a.id, a.name, a.status, a.country_code, a.intake_enabled, a.intake_trusted, a.intake_phone, a.intake_telegram, a.intake_telegram_name, a.intake_code, a.intake_paired_at, a.whatsapp, a.phone, a.user_id
          from agencies a where a.status = 'approved' and bk_scope_ok(coalesce(a.country_code,'SY'), sc, al) order by a.name) x), '[]'::json),
    'log', coalesce((select json_agg(row_to_json(x)) from (
        select id, draft_id, chat_id, level, event, detail, created_at from intake_log order by created_at desc limit 80) x), '[]'::json));
end $$;

create or replace function public.bk_admin_intake_set(p_token text, p_id bigint, p_patch jsonb)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; d intake_drafts; ag agencies; st text;
begin
  uid := bk_admin_uid(p_token);
  select * into d from intake_drafts where id = p_id;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if p_patch ? 'agency_id' then
    if p_patch->>'agency_id' is null or p_patch->>'agency_id' = '' then
      d.agency_id := null;
    else
      select * into ag from agencies where id = (p_patch->>'agency_id')::bigint;
      if ag.id is null then return json_build_object('error','noagency'); end if;
      d.agency_id := ag.id; d.user_id := ag.user_id; d.country_code := coalesce(ag.country_code, d.country_code);
    end if;
  end if;
  if p_patch ? 'user_id' and p_patch->>'user_id' <> '' then d.user_id := (p_patch->>'user_id')::uuid; end if;
  if p_patch ? 'fields' then d.fields := coalesce(d.fields,'{}'::jsonb) || (p_patch->'fields'); end if;
  if p_patch ? 'country_code' then d.country_code := upper(p_patch->>'country_code'); end if;
  if p_patch ? 'photos' then d.photos := p_patch->'photos'; end if;
  st := p_patch->>'status';
  if st is not null then
    if st not in ('cancelled','ready','review','collecting') then return json_build_object('error','badstatus'); end if;
    if d.status = 'published' then return json_build_object('error','already'); end if;
    d.status := st;
  end if;
  update intake_drafts set agency_id = d.agency_id, user_id = d.user_id, fields = d.fields, country_code = d.country_code,
         photos = d.photos, status = d.status, updated_at = now() where id = p_id returning * into d;
  insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'admin_edit', jsonb_build_object('keys', (select json_agg(k) from jsonb_object_keys(p_patch) k), 'by', uid));
  return row_to_json(d);
end $$;

create or replace function public.bk_admin_intake_delete(p_token text, p_id bigint)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; d intake_drafts;
begin
  uid := bk_admin_uid(p_token);
  delete from intake_drafts where id = p_id returning * into d;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  insert into intake_log (draft_id, chat_id, event, detail) values (p_id, d.chat_id, 'admin_delete', jsonb_build_object('by', uid, 'photos', d.photos));
  return json_build_object('ok', true, 'photos', d.photos);
end $$;

-- the agency switches (drop the old signature first: PostgREST cannot pick between overloads)
drop function if exists public.bk_admin_agency_set(text, bigint, text, boolean);
create or replace function public.bk_admin_agency_set(p_token text, p_id bigint, p_status text default null, p_verified boolean default null,
  p_intake boolean default null, p_trusted boolean default null, p_intake_phone text default null, p_unpair boolean default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; a agencies;
begin
  uid := bk_admin_uid(p_token);
  update agencies set status = coalesce(p_status, status), verified = coalesce(p_verified, verified),
         intake_enabled = coalesce(p_intake, intake_enabled), intake_trusted = coalesce(p_trusted, intake_trusted),
         intake_phone = case when p_intake_phone is null then intake_phone when trim(p_intake_phone) = '' then null else bk_intake_norm_phone(p_intake_phone) end,
         intake_telegram = case when coalesce(p_unpair,false) then null else intake_telegram end,
         intake_telegram_name = case when coalesce(p_unpair,false) then null else intake_telegram_name end,
         updated_at = now()
   where id = p_id returning * into a;
  if a.id is null then return json_build_object('error','noagency'); end if;
  if p_status = 'approved' then update users set card_logo = true where id = a.user_id; end if;
  if coalesce(p_intake,false) and a.intake_code is null then
    update agencies set intake_code = upper(substr(encode(gen_random_bytes(6),'hex'),1,8)) where id = a.id returning * into a;
  end if;
  return json_build_object('ok', true, 'intake_enabled', a.intake_enabled, 'intake_trusted', a.intake_trusted, 'intake_code', a.intake_code);
end $$;

-- the panel bell: drafts waiting for the owner
create or replace function public.bk_admin_todo(p_token text, p_country text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token);
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return json_build_object(
    'pending_listings', (select count(*) from listings where status='pending' and bk_scope_ok(country_code,sc,al)),
    'pending_agencies', (select count(*) from agencies where status='pending' and bk_scope_ok(country_code,sc,al)),
    'pending_wanted', (select count(*) from wanted where status='pending' and bk_scope_ok(country_code,sc,al)),
    'intake_review', (select count(*) from intake_drafts where status in ('review','failed') and bk_scope_ok(country_code,sc,al)),
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
        (select 'report', coalesce(r.reason,''), r.created_at, r.id::text, l.country_code from listing_reports r left join listings l on l.id=r.listing_id where not coalesce(r.resolved,false) and (l.id is null or bk_scope_ok(l.country_code,sc,al)) order by r.created_at desc limit 5)
        union all
        (select 'feedback', coalesce(f.kind,'')||': '||left(coalesce(f.body,''),60), f.created_at, f.id::text, null from feedback f where not coalesce(f.handled,false) order by f.created_at desc limit 5)
      ) x), '[]'::json)
  );
end $$;

-- ───────────────────────────── member (the agency's own account page) ─────────────────────────────
create or replace function public.bk_agency_intake(p_token text)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; a agencies; cfg jsonb;
begin
  uid := bk_member_uid(p_token);
  if uid is null then raise exception 'unauthorised'; end if;
  select * into a from agencies where user_id = uid;
  if a.id is null then return json_build_object('agency', null); end if;
  cfg := bk_intake_cfg();
  if a.status = 'approved' and a.intake_enabled and a.intake_code is null then
    update agencies set intake_code = upper(substr(encode(gen_random_bytes(6),'hex'),1,8)) where id = a.id returning * into a;
  end if;
  return json_build_object(
    'agency', json_build_object('id', a.id, 'name', a.name, 'status', a.status, 'intake_enabled', a.intake_enabled, 'intake_trusted', a.intake_trusted,
      'paired', a.intake_telegram is not null, 'telegram_name', a.intake_telegram_name, 'whatsapp', coalesce(a.intake_phone, bk_intake_norm_phone(a.whatsapp)), 'code', case when a.status = 'approved' and a.intake_enabled then a.intake_code end),
    'bot', cfg->>'intake_bot', 'wa_display', cfg->>'intake_wa_display',
    'telegram_on', coalesce((cfg->>'intake_telegram_on')::boolean, true), 'whatsapp_on', coalesce((cfg->>'intake_whatsapp_on')::boolean, true),
    'enabled', coalesce((cfg->>'intake_enabled')::boolean, true));
end $$;
