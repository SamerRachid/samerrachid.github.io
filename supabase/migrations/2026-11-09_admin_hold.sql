-- Admin takeover of a WhatsApp chat (owner, 2026-11-09).
-- The owner types «admin on» in a chat from Balkoun's own WhatsApp (phone or WhatsApp Desktop): the bot stops answering
-- that number and only collects what the person sends (text, photos, videos, location) into one draft with status
-- 'held'. Nothing is published by itself: «admin post» publishes it live, or the owner publishes it from the panel.
-- «admin off» (or the hours in extras.intake_admin_hold_hours, default 24) hands the chat back to the bot; a held draft
-- that was not published waits for the owner as 'review'.

create table if not exists intake_hold (
  chat_id  text primary key,                 -- '+<digits>', as the bot stores WhatsApp chats
  source   text not null default 'whatsapp',
  draft_id bigint references intake_drafts(id) on delete set null,
  by       text not null default 'command',   -- command | panel
  since    timestamptz not null default now(),
  until    timestamptz not null
);
alter table intake_hold enable row level security;
revoke all on intake_hold from anon, authenticated;

alter table intake_drafts drop constraint intake_drafts_status_check;
alter table intake_drafts add constraint intake_drafts_status_check
  check (status = any (array['collecting','reading','ready','needs_info','review','published','cancelled','failed','held']));

-- on: start (or extend) the hold; the chat's open drafts become 'held' so the bot's timer never answers them
-- off: end it; held drafts that were not published wait for the owner as 'review'
create or replace function bk_intake_hold_set(p_chat_id text, p_on boolean, p_by text default 'command', p_hours int default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare digits text; chat text; hrs int; did bigint; n int := 0;
begin
  digits := bk_intake_norm_phone(p_chat_id);
  if digits is null then return json_build_object('error', 'chat'); end if;
  chat := '+' || digits;
  if coalesce(p_on, false) then
    hrs := greatest(1, least(coalesce(p_hours, bk_intake_int(bk_intake_cfg()->>'intake_admin_hold_hours'), 24), 168));
    update intake_drafts set status = 'held', fields = coalesce(fields, '{}'::jsonb) || '{"held_by_admin": true}'::jsonb, updated_at = now()
     where source = 'whatsapp' and bk_intake_norm_phone(chat_id) = digits and status in ('collecting','reading','ready','needs_info');
    get diagnostics n = row_count;
    select id into did from intake_drafts
     where source = 'whatsapp' and bk_intake_norm_phone(chat_id) = digits and status = 'held'
     order by last_message_at desc limit 1;
    delete from intake_hold where bk_intake_norm_phone(chat_id) = digits and chat_id <> chat;
    insert into intake_hold (chat_id, source, draft_id, by, since, until)
    values (chat, 'whatsapp', did, coalesce(p_by, 'command'), now(), now() + make_interval(hours => hrs))
    on conflict (chat_id) do update set until = excluded.until, by = excluded.by,
      draft_id = coalesce(intake_hold.draft_id, excluded.draft_id),
      since = case when intake_hold.until > now() then intake_hold.since else now() end;
    insert into intake_log (chat_id, event, detail) values (chat, 'admin_on', jsonb_build_object('by', p_by, 'hours', hrs, 'draft', did, 'moved', n));
    return json_build_object('ok', true, 'on', true, 'chat', chat, 'hours', hrs, 'draft_id', did);
  end if;
  delete from intake_hold where bk_intake_norm_phone(chat_id) = digits;
  update intake_drafts set status = 'review', error = 'جُمع أثناء تولّي المشرف للمحادثة', updated_at = now()
   where source = 'whatsapp' and bk_intake_norm_phone(chat_id) = digits and status = 'held';
  get diagnostics n = row_count;
  insert into intake_log (chat_id, event, detail) values (chat, 'admin_off', jsonb_build_object('by', p_by, 'to_review', n));
  return json_build_object('ok', true, 'on', false, 'chat', chat, 'to_review', n);
end $$;

-- one message while the chat is held: into the hold's draft (made on the first message), never answered
create or replace function bk_intake_hold_collect(p_chat_id text, p_external_id text, p_kind text, p_text text, p_media jsonb, p_payload jsonb, p_sender_name text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare h intake_hold; d intake_drafts; s json; mid bigint;
begin
  select * into h from intake_hold where bk_intake_norm_phone(chat_id) = bk_intake_norm_phone(p_chat_id) and until > now() for update;
  if h.chat_id is null then return json_build_object('error', 'nohold'); end if;
  if exists (select 1 from intake_messages where source = 'whatsapp' and external_id = p_external_id) then
    return json_build_object('duplicate', true);
  end if;
  -- the hold's draft, also after a panel read made it ready / needs_info (it goes back to 'held' below)
  if h.draft_id is not null then
    select * into d from intake_drafts where id = h.draft_id and status in ('held','ready','needs_info','review','failed') for update;
  end if;
  if d.id is null then
    s := bk_intake_sender('whatsapp', h.chat_id);
    insert into intake_drafts (source, chat_id, sender_name, agency_id, user_id, country_code, status, fields)
    values ('whatsapp', h.chat_id, nullif(p_sender_name, ''), nullif(s->>'agency_id', '')::bigint, nullif(s->>'user_id', '')::uuid,
            coalesce(nullif(s->>'country_code', ''), 'SY'), 'held', '{"held_by_admin": true}'::jsonb)
    returning * into d;
    update intake_hold set draft_id = d.id where chat_id = h.chat_id;
  end if;
  insert into intake_messages (draft_id, source, external_id, chat_id, kind, text, media, payload)
  values (d.id, 'whatsapp', p_external_id, h.chat_id, coalesce(p_kind, 'text'), p_text, p_media, p_payload)
  on conflict (source, external_id) do nothing returning id into mid;
  if mid is null then return json_build_object('duplicate', true); end if;
  update intake_drafts set
    raw_text = case when coalesce(btrim(p_text), '') = '' then raw_text
                    when raw_text = '' then btrim(p_text) else raw_text || E'\n\n' || btrim(p_text) end,
    fields = case when p_kind = 'location' and p_media ? 'lat' and p_media ? 'lng'
                  then fields || jsonb_build_object('lat', p_media->'lat', 'lng', p_media->'lng') else fields end,
    sender_name = coalesce(sender_name, nullif(p_sender_name, '')), status = 'held',
    last_message_at = now(), updated_at = now()
   where id = d.id returning * into d;
  return json_build_object('ok', true, 'draft_id', d.id, 'photo_count', jsonb_array_length(coalesce(d.photos, '[]'::jsonb)));
end $$;

-- «admin post»: the held draft is claimed for one quiet read; after the publish the hold starts a fresh draft
create or replace function bk_intake_hold_take(p_chat_id text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare h intake_hold; d intake_drafts;
begin
  select * into h from intake_hold where bk_intake_norm_phone(chat_id) = bk_intake_norm_phone(p_chat_id) and until > now() for update;
  if h.chat_id is null then return json_build_object('error', 'nohold'); end if;
  if h.draft_id is null then return json_build_object('error', 'empty'); end if;
  update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
   where id = h.draft_id and status = 'held' and (raw_text <> '' or jsonb_array_length(photos) > 0) returning * into d;
  if d.id is null then return json_build_object('error', 'empty'); end if;
  update intake_hold set draft_id = null where chat_id = h.chat_id;
  return json_build_object('ok', true, 'draft_id', d.id);
end $$;

-- is the chat held right now? (the bot's reply() asks before every WhatsApp message)
create or replace function bk_intake_held(p_chat_id text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from intake_hold where bk_intake_norm_phone(chat_id) = bk_intake_norm_phone(p_chat_id) and until > now())
$$;

-- called from the bot's tick: holds past their hours end by themselves, and any draft of a held chat that slipped
-- past the hold (a message that was already on its way at «admin on», a split part) is pulled back into 'held'
create or replace function bk_intake_hold_expire()
returns json language plpgsql security definer set search_path = public, extensions as $$
declare r record; n int := 0; m int := 0;
begin
  for r in select chat_id from intake_hold where until <= now() loop
    perform bk_intake_hold_set(r.chat_id, false, 'expired', null); n := n + 1;
  end loop;
  update intake_drafts d set status = 'held', fields = coalesce(d.fields, '{}'::jsonb) || '{"held_by_admin": true}'::jsonb, updated_at = now()
    from intake_hold h
   where h.until > now() and d.source = 'whatsapp' and bk_intake_norm_phone(d.chat_id) = bk_intake_norm_phone(h.chat_id)
     and d.status in ('collecting','ready','needs_info') and d.listing_id is null;
  get diagnostics m = row_count;
  return json_build_object('ended', n, 'pulled', m);
end $$;

revoke all on function bk_intake_held(text), bk_intake_hold_set(text, boolean, text, int),
  bk_intake_hold_collect(text, text, text, text, jsonb, jsonb, text), bk_intake_hold_take(text), bk_intake_hold_expire()
  from public, anon, authenticated;

-- the panel: the chats the owner holds now, and the switch per chat
create or replace function bk_admin_intake_holds(p_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['intake']::text[], 'bk_admin_intake_holds', null, false, '', null);
  return coalesce((select json_agg(row_to_json(x) order by x.since desc) from (
    select h.chat_id, h.by, h.since, h.until, h.draft_id,
           coalesce(d.sender_name, (select trim(coalesce(u.name,'') || ' ' || coalesce(u.family_name,'')) from users u
             where bk_intake_norm_phone(u.phone) = bk_intake_norm_phone(h.chat_id) order by u.created_at desc limit 1)) as name,
           (select count(*) from intake_messages m where m.draft_id = h.draft_id) as messages
      from intake_hold h left join intake_drafts d on d.id = h.draft_id
     where h.until > now()) x), '[]'::json);
end $$;

create or replace function bk_admin_intake_hold(p_token text, p_chat_id text, p_on boolean)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['intake']::text[], 'bk_admin_intake_hold', null, true, left(coalesce(p_chat_id,''), 40), null);
  return bk_intake_hold_set(p_chat_id, p_on, 'panel', null);
end $$;
grant execute on function bk_admin_intake_holds(text), bk_admin_intake_hold(text, text, boolean) to anon, authenticated;

-- the quiet check: a running hold comes first and tells the bot to collect
create or replace function public.bk_intake_quiet(p_chat_id text)
 returns json language plpgsql stable security definer set search_path to 'public', 'extensions'
as $function$
declare digits text; hrs int; u users; h intake_hold;
begin
  digits := bk_intake_norm_phone(p_chat_id);
  if digits is null then return json_build_object('quiet', false); end if;
  select * into h from intake_hold where bk_intake_norm_phone(chat_id) = digits and until > now() limit 1;
  if h.chat_id is not null then return json_build_object('quiet', true, 'reason', 'admin', 'collect', true, 'draft_id', h.draft_id); end if;
  select * into u from users where bk_intake_norm_phone(phone) = digits and coalesce(bot_off,false) order by created_at desc limit 1;
  if u.id is not null then return json_build_object('quiet', true, 'reason', 'member', 'user_id', u.id); end if;
  select coalesce(nullif(extras->>'intake_quiet_after_dm_hours','')::int, 48) into hrs from site_content where id = 1;
  if coalesce(hrs, 48) > 0 and exists (
       select 1 from campaign_sends s join campaigns cp on cp.id = s.campaign_id join contacts c on c.id = s.contact_id
        where s.trigger_type = 'manual' and cp.kind = 'manual' and s.channel = 'whatsapp' and s.status = 'sent'
          and s.sent_at > now() - make_interval(hours => coalesce(hrs, 48))
          and bk_intake_norm_phone(c.phone) = digits) then
    return json_build_object('quiet', true, 'reason', 'direct_message');
  end if;
  return json_build_object('quiet', false);
end $function$;

-- the panel's «اقرأ من جديد» works on a held draft too
create or replace function public.bk_intake_claim(p_draft bigint)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare d intake_drafts;
begin
  update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
   where id = p_draft and status in ('collecting','ready','needs_info','failed','review','held') and reads < 15 returning * into d;
  if d.id is null then return null; end if;
  return row_to_json(d);
end $function$;

-- a draft collected while the owner held the chat never gets the bot's 20-hour reminder
create or replace function public.bk_intake_remind_due()
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare out json;
begin
  with c as (
    select d.id from intake_drafts d
     where d.status = 'ready' and d.source in ('whatsapp','telegram') and not coalesce(d.by_admin, false)
       and coalesce(d.fields->>'held_by_admin', '') <> 'true'
       and d.updated_at < now() - interval '20 hours' and d.updated_at > now() - interval '3 days'
       and coalesce(d.fields->>'reminded_at', '') = ''
       and not exists (select 1 from users u where u.id = d.user_id and coalesce(u.is_house, false))
     order by d.updated_at limit 10 for update skip locked),
  u as (
    update intake_drafts d set fields = coalesce(d.fields, '{}'::jsonb) || jsonb_build_object('reminded_at', now())
      from c where d.id = c.id
    returning d.id, d.source, d.chat_id, d.fields->>'title' as title),
  l as (insert into intake_log (draft_id, chat_id, event) select id, chat_id, 'reminded' from u)
  select coalesce(json_agg(row_to_json(u)), '[]'::json) into out from u;
  return out;
end $function$;

-- the panel's counts: held drafts on their own
do $do$
declare def text;
begin
  def := pg_get_functiondef('bk_admin_intake'::regproc);
  if position($q$'held'$q$ in def) = 0 then
    def := replace(def, $r$'review', count(*) filter (where status = 'review'),$r$,
                        $r$'held', count(*) filter (where status = 'held'),
        'review', count(*) filter (where status = 'review'),$r$);
    if position($q$'held'$q$ in def) = 0 then raise exception 'bk_admin_intake: counts line not found'; end if;
    execute def;
  end if;
end $do$;

-- a read keeps the «collected while held» mark (like lat/lng), so the reminder above still skips the draft
do $do$
declare def text;
begin
  def := pg_get_functiondef('bk_intake_save_read'::regproc);
  if position('held_by_admin' in def) = 0 then
    def := replace(def, $r$'auto_confirm', d.fields->'auto_confirm'))$r$, $r$'auto_confirm', d.fields->'auto_confirm', 'held_by_admin', d.fields->'held_by_admin'))$r$);
    if position('held_by_admin' in def) = 0 then raise exception 'bk_intake_save_read: keep line not found'; end if;
    execute def;
  end if;
end $do$;
