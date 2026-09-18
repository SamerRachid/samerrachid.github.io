-- 2026-09-18 — message intake, second pass after the code review. Applied as "message_intake_fixes2".
--  • one chat at a time: advisory lock in bk_intake_message (albums / WhatsApp batches no longer open several drafts)
--  • Arabic-Indic digits ١ ٢ count as the 1 / 2 commands; a captioned photo is stored first, the command runs after
--  • «جديد» closes any open draft; commands on a ready draft keep it alive 3 days; old drafts expire
--  • save_read only writes a draft that is still "reading" (a cancel during the read wins)
--  • publish: the 'already' guard looks at listing_id, local phone numbers get the country code, no silent 0 h power
--  • country-restricted admins may only touch drafts/agencies of their countries (bk_admin_country_ok / bk_admin_intake_can)
--  • WhatsApp sender matching by suffix only for locally-typed numbers of the same country
--  • pairing: admin code with or without the ADM- prefix, failed attempts logged and throttled
--  • unknown senders: message body trimmed, nothing kept beyond 200 characters
--  • bk_intake_next_due for the in-worker timer loop

create or replace function public.bk_admin_country_ok(p_uid uuid, p_cc text)
returns boolean language sql stable security definer set search_path to 'public','extensions' as $$
  select al is null or cardinality(al) = 0 or coalesce(upper(p_cc),'SY') = any(al) from (select bk_admin_allowed(p_uid) al) x;
$$;
-- the Edge Function asks with the admin's session token: may this admin act on this draft (or on global settings when p_draft is null)?
-- volatile (not stable): bk_admin_uid deletes expired sessions, which a read-only PostgREST transaction refuses
create or replace function public.bk_admin_intake_can(p_token text, p_draft bigint default null)
returns boolean language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; cc text; al text[];
begin
  uid := bk_admin_uid(p_token);
  al := bk_admin_allowed(uid);
  if p_draft is null then return al is null or cardinality(al) = 0; end if;
  select country_code into cc from intake_drafts where id = p_draft;
  if cc is null then return false; end if;
  return bk_admin_country_ok(uid, cc);
end $$;

create or replace function public.bk_intake_next_due()
returns integer language sql stable security definer set search_path to 'public','extensions' as $$
  select ceil(extract(epoch from min(last_message_at) + make_interval(secs => coalesce(bk_intake_int(bk_intake_cfg()->>'intake_wait_s'), 90)) - now()))::int
    from intake_drafts where status = 'collecting' and (raw_text <> '' or jsonb_array_length(photos) > 0);
$$;
revoke execute on function public.bk_intake_next_due() from public, anon, authenticated;
revoke execute on function public.bk_admin_country_ok(uuid, text) from public, anon, authenticated;

create or replace function public.bk_intake_sender(p_source text, p_chat_id text)
returns json language plpgsql stable security definer set search_path to 'public','extensions' as $$
declare cfg jsonb; a agencies; u users; is_admin boolean := false; digits text; wa text;
begin
  cfg := bk_intake_cfg();
  if p_source = 'telegram' then
    if p_chat_id ~ '^-?\d+$' then select * into a from agencies where intake_telegram = p_chat_id::bigint; end if;
    is_admin := coalesce(cfg->'intake_admin_chats'->'telegram', '[]'::jsonb) ? p_chat_id;
  elsif p_source = 'whatsapp' then
    digits := bk_intake_norm_phone(p_chat_id);
    if digits is not null then
      -- exact match on any stored number; a suffix match only when the stored number was typed locally (leading 0 / short)
      -- and the sender's prefix is that agency's country code
      select ag.* into a from agencies ag
        left join users us on us.id = ag.user_id
        left join countries co on co.code = coalesce(ag.country_code,'SY')
       where ag.status = 'approved' and (
             bk_intake_norm_phone(ag.intake_phone) = digits
          or bk_intake_norm_phone(ag.whatsapp) = digits or bk_intake_norm_phone(ag.phone) = digits
          or bk_intake_norm_phone(us.phone) = digits
          or (length(digits) >= 9 and digits like (regexp_replace(coalesce(co.phone_code,''), '\D', '', 'g') || '%')
              and ((coalesce(ag.whatsapp,'') ~ '^\s*0' or length(bk_intake_norm_phone(ag.whatsapp)) <= 10) and right(bk_intake_norm_phone(ag.whatsapp), 9) = right(digits, 9)
                or (coalesce(ag.phone,'') ~ '^\s*0' or length(bk_intake_norm_phone(ag.phone)) <= 10) and right(bk_intake_norm_phone(ag.phone), 9) = right(digits, 9))))
       order by (bk_intake_norm_phone(ag.intake_phone) = digits) desc nulls last, ag.id limit 1;
      select bk_intake_norm_phone(wa_number) into wa from site_content where id = 1;
      is_admin := (wa is not null and wa = digits)
               or coalesce(cfg->'intake_admin_chats'->'whatsapp', '[]'::jsonb) ? digits
               or exists (select 1 from users where role = 'admin' and bk_intake_norm_phone(phone) = digits);
    end if;
  elsif p_source = 'web' then
    select * into u from users where id::text = p_chat_id;
    if u.id is not null then select * into a from agencies where user_id = u.id; is_admin := u.role = 'admin'; end if;
  end if;
  if a.id is not null then select * into u from users where id = a.user_id; end if;
  return json_build_object(
    'agency_id', a.id, 'agency_name', a.name, 'agency_status', a.status,
    'user_id', coalesce(a.user_id, u.id), 'user_name', trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),
    'enabled', coalesce(a.status = 'approved' and a.intake_enabled, false) or is_admin,
    'trusted', coalesce(a.intake_trusted, false), 'is_admin', is_admin, 'blocked', coalesce(u.blocked, false),
    'country_code', coalesce(a.country_code, 'SY'), 'lang', coalesce(u.lang, 'ar'));
end $$;

create or replace function public.bk_intake_pair(p_source text, p_chat_id text, p_code text, p_name text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare cfg jsonb; a agencies; code text; chats jsonb; arr jsonb; key text; fails int; admcode text;
begin
  code := upper(trim(coalesce(p_code,'')));
  if code = '' then return json_build_object('error','nocode'); end if;
  select count(*) into fails from intake_log where chat_id = p_chat_id and event = 'pair_failed' and created_at > now() - interval '1 hour';
  if fails >= 5 then return json_build_object('error','throttled'); end if;
  cfg := bk_intake_cfg();
  admcode := upper(coalesce(cfg->>'intake_admin_code',''));
  if admcode <> '' and (admcode = code or admcode = 'ADM-' || code or 'ADM-' || admcode = code) then
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
  if a.id is null then
    insert into intake_log (chat_id, level, event, detail) values (p_chat_id, 'warn', 'pair_failed', jsonb_build_object('source', p_source, 'name', p_name));
    return json_build_object('error','badcode');
  end if;
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

create or replace function public.bk_intake_message(
  p_source text, p_external_id text, p_chat_id text, p_kind text, p_text text,
  p_media jsonb default null, p_payload jsonb default null, p_sender_name text default null, p_country text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare cfg jsonb; s json; d intake_drafts; cmd text; cmd_after text; tx text; cmdtx text; ins int; is_new boolean := false; cc text;
        n_today int; replied boolean; was text; kind text;
begin
  -- one chat at a time: two photos of one album arrive in parallel and must land in one draft
  perform pg_advisory_xact_lock(hashtext(p_source || ':' || p_chat_id));
  cfg := bk_intake_cfg();
  kind := coalesce(p_kind,'text');
  insert into intake_messages (source, external_id, chat_id, kind, text, media, payload)
    values (p_source, p_external_id, p_chat_id, kind, p_text, p_media, p_payload)
    on conflict (source, external_id) do nothing;
  get diagnostics ins = row_count;
  if ins = 0 then return json_build_object('duplicate', true); end if;

  s := bk_intake_sender(p_source, p_chat_id);
  if not coalesce((s->>'enabled')::boolean, false) or coalesce((s->>'blocked')::boolean, false) then
    update intake_messages set text = left(text, 200), media = null, payload = null where source = p_source and external_id = p_external_id;   -- strangers: keep almost nothing
    replied := exists (select 1 from intake_log where chat_id = p_chat_id and event = 'unknown_reply' and created_at > now() - interval '24 hours');
    insert into intake_log (chat_id, event, detail) values (p_chat_id, 'unknown_sender', jsonb_build_object('source', p_source, 'name', left(coalesce(p_sender_name,''),80), 'kind', kind));
    return json_build_object('reason', case when coalesce((s->>'blocked')::boolean,false) then 'blocked' else 'unknown' end, 'replied_recently', replied, 'sender', s);
  end if;

  tx := trim(coalesce(p_text, ''));
  cmdtx := translate(tx, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
  cmd := case
    when cmdtx ~* '^(1|نعم|انشر|نشر|publish|ok|اوك|أوك|✅)[.!]?$' then 'confirm'
    when cmdtx ~* '^(2|إلغاء|الغاء|الغي|ألغي|cancel|x|❌)[.!]?$' then 'cancel'
    when cmdtx ~* '^(تم|تمام|انتهيت|خلص|خلاص|done|end|finish)[.!]?$' then 'done'
    when cmdtx ~* '^(جديد|إعلان جديد|اعلان جديد|new|/new)$' then 'new'
    when cmdtx ~* '^(مساعدة|help|/help|\?)$' then 'help'
    else null end;
  -- a photo whose caption is a command: the photo is content, the command runs after it is stored
  if cmd is not null and kind <> 'text' then cmd_after := cmd; cmd := null; end if;

  -- the open draft of this chat: collecting for 12 hours, waiting for the sender's answer for 3 days
  select * into d from intake_drafts
   where source = p_source and chat_id = p_chat_id
     and ((status in ('collecting','reading') and last_message_at > now() - interval '12 hours')
       or (status in ('ready','needs_info') and updated_at > now() - interval '3 days'))
   order by created_at desc limit 1;
  was := d.status;

  if cmd = 'help' then return json_build_object('command','help','draft_id',d.id,'status',d.status,'sender',s); end if;
  if cmd = 'confirm' then
    if d.id is not null then update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id; end if;
    if d.id is not null and d.status = 'ready' then
      update intake_drafts set updated_at = now() where id = d.id;
      return json_build_object('command','confirm','draft_id',d.id,'status',d.status,'sender',s);
    end if;
    return json_build_object('command','confirm','draft_id',null,'status',d.status,'open_id',d.id,'sender',s);
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
    if d.id is not null then
      update intake_drafts set status = 'cancelled', updated_at = now() where id = d.id;
      insert into intake_log (draft_id, chat_id, event) values (d.id, p_chat_id, 'new_by_sender');
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
    if n_today >= coalesce(bk_intake_int(cfg->>'intake_daily_limit'), 30) then
      insert into intake_log (chat_id, event, detail) values (p_chat_id, 'daily_limit', jsonb_build_object('n', n_today));
      return json_build_object('reason','limit','sender',s);
    end if;
    insert into intake_drafts (source, chat_id, sender_name, agency_id, user_id, by_admin, country_code, raw_text, status, fields)
      values (p_source, p_chat_id, p_sender_name, (s->>'agency_id')::bigint, (s->>'user_id')::uuid,
              coalesce((s->>'is_admin')::boolean,false) and s->>'agency_id' is null, cc, tx, 'collecting',
              case when kind = 'location' and p_media ? 'lat' then jsonb_build_object('lat', p_media->'lat', 'lng', p_media->'lng') else '{}'::jsonb end)
      returning * into d;
    is_new := true;
    insert into intake_log (draft_id, chat_id, event, detail) values (d.id, p_chat_id, 'draft_open', jsonb_build_object('source', p_source, 'agency_id', s->>'agency_id', 'admin', s->>'is_admin'));
  else
    update intake_drafts set
      raw_text = case when tx <> '' then rtrim(raw_text) || case when raw_text = '' then '' else E'\n' end || tx else raw_text end,
      fields = case when kind = 'location' and p_media ? 'lat' then fields || jsonb_build_object('lat', p_media->'lat', 'lng', p_media->'lng') else fields end,
      status = case when status in ('ready','needs_info') then 'collecting' else status end,
      last_message_at = now(), updated_at = now()
     where id = d.id returning * into d;
  end if;
  update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
  return json_build_object('draft_id', d.id, 'status', d.status, 'was_status', was, 'is_new', is_new, 'sender', s, 'country_code', d.country_code,
    'photo_count', jsonb_array_length(d.photos), 'has_text', d.raw_text <> '', 'command_after', cmd_after);
end $$;

create or replace function public.bk_intake_add_photo(p_draft bigint, p_photo jsonb)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare n int; mx int;
begin
  mx := coalesce(bk_intake_int(bk_intake_cfg()->>'intake_max_photos'), 12);
  select jsonb_array_length(photos) into n from intake_drafts where id = p_draft for update;
  if n is null then return json_build_object('error','nodraft'); end if;
  if n >= mx then return json_build_object('ok', false, 'reason', 'max', 'n', n, 'max', mx); end if;
  update intake_drafts set photos = photos || jsonb_build_array(p_photo), last_message_at = now(), updated_at = now() where id = p_draft;
  return json_build_object('ok', true, 'n', n + 1, 'max', mx);
end $$;

create or replace function public.bk_intake_due(p_wait_s integer default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare w int; out json;
begin
  w := coalesce(p_wait_s, bk_intake_int(bk_intake_cfg()->>'intake_wait_s'), 90);
  update intake_drafts set status = 'collecting', updated_at = now() where status = 'reading' and claimed_at < now() - interval '10 minutes';   -- a crashed read goes back to the queue
  with old as (update intake_drafts set status = 'cancelled', updated_at = now(), error = coalesce(error,'') || ' expired'
     where (status = 'collecting' and last_message_at < now() - interval '2 days') or (status in ('ready','needs_info') and updated_at < now() - interval '3 days') returning id, chat_id)
  insert into intake_log (draft_id, chat_id, event) select id, chat_id, 'expired' from old;
  with u as (
    update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
     where id in (select id from intake_drafts
                   where status = 'collecting' and last_message_at < now() - make_interval(secs => w)
                     and (raw_text <> '' or jsonb_array_length(photos) > 0) and reads < 6
                   order by last_message_at limit 5 for update skip locked)
     returning *)
  select coalesce(json_agg(row_to_json(u)), '[]'::json) into out from u;
  update intake_drafts set status = 'review', error = 'too many reads', updated_at = now() where status = 'collecting' and reads >= 6 and last_message_at < now() - make_interval(secs => w);
  return out;
end $$;

create or replace function public.bk_intake_claim(p_draft bigint)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare d intake_drafts;
begin
  update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
   where id = p_draft and status in ('collecting','ready','needs_info','failed','review') and reads < 8 returning * into d;
  if d.id is null then return null; end if;
  return row_to_json(d);
end $$;

create or replace function public.bk_intake_save_read(
  p_draft bigint, p_fields jsonb, p_missing text[], p_summary text, p_status text,
  p_model text default null, p_in integer default 0, p_out integer default 0, p_cost numeric default 0, p_error text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare d intake_drafts; st text; keep jsonb;
begin
  select * into d from intake_drafts where id = p_draft for update;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if d.status <> 'reading' then
    -- cancelled by the sender or changed by the admin while Claude was reading: their state wins, only the cost is booked
    update intake_drafts set tokens_in = tokens_in + coalesce(p_in,0), tokens_out = tokens_out + coalesce(p_out,0), cost_usd = cost_usd + coalesce(p_cost,0), updated_at = now() where id = p_draft;
    insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'read_skipped', jsonb_build_object('status', d.status, 'in', p_in, 'out', p_out, 'cost', p_cost));
    return json_build_object('skipped', true, 'id', d.id, 'status', d.status);
  end if;
  st := coalesce(p_status, 'ready');
  if p_error is null and d.claimed_at is not null and d.last_message_at > d.claimed_at then st := 'collecting'; end if;   -- more content arrived while reading
  if st not in ('ready','needs_info','review','failed','collecting') then st := 'review'; end if;
  keep := jsonb_strip_nulls(jsonb_build_object('lat', d.fields->'lat', 'lng', d.fields->'lng'));   -- a shared pin survives the read
  update intake_drafts set
    fields = keep || coalesce(p_fields, fields), missing = coalesce(p_missing, '{}'), summary = coalesce(p_summary, summary),
    status = st, error = p_error, model = coalesce(p_model, model),
    tokens_in = tokens_in + coalesce(p_in,0), tokens_out = tokens_out + coalesce(p_out,0), cost_usd = cost_usd + coalesce(p_cost,0),
    processed_at = now(), updated_at = now()
   where id = p_draft returning * into d;
  insert into intake_log (draft_id, chat_id, level, event, detail) values (d.id, d.chat_id, case when p_error is null then 'info' else 'warn' end, 'read',
    jsonb_build_object('status', st, 'missing', p_missing, 'model', p_model, 'in', p_in, 'out', p_out, 'cost', p_cost, 'error', p_error));
  return row_to_json(d);
end $$;

create or replace function public.bk_intake_publish(p_draft bigint, p_force_status text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare d intake_drafts; f jsonb; a agencies; u users; tax json; l listings; gid int; aid int; cc text;
        ptype text; sec text; deal text; price numeric; ptxt text; cur text; rate numeric; usd int; m2 int; descr text;
        cond text; tabu text; st text; ph jsonb; i int; phone text; pc text; amen text[]; gname text; aname text;
        rent boolean; deed_ok boolean; ph_int int;
begin
  select * into d from intake_drafts where id = p_draft for update;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if d.listing_id is not null then return json_build_object('error','already','listing_id',d.listing_id,'status',d.status); end if;
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

  -- money: "85,000", "85.000" (thousands), "85000.50" all read; anything else → noprice instead of an exception
  ptxt := regexp_replace(coalesce(f->>'price',''), '[^0-9.,]', '', 'g');
  if ptxt ~ '^\d{1,3}(\.\d{3})+$' then ptxt := replace(ptxt, '.', ''); end if;
  ptxt := replace(ptxt, ',', '');
  price := bk_intake_num(ptxt);
  if price is null or price <= 0 then return json_build_object('error','noprice'); end if;
  cur := upper(coalesce(nullif(f->>'currency',''), 'USD'));
  if cur = 'USD' then usd := round(price);
  else
    tax := bk_intake_taxonomy(cc);
    rate := bk_intake_num(tax->'country'->'rates'->>cur);
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
  -- the contact number: from the text, else the agency's, else the account's; local "09…" numbers get the country code
  select regexp_replace(coalesce(phone_code,''), '\D', '', 'g') into pc from countries where code = cc;
  phone := coalesce(nullif(bk_intake_norm_phone(f->>'contact_phone'),''), bk_intake_norm_phone(a.whatsapp), bk_intake_norm_phone(a.phone), bk_intake_norm_phone(u.phone));
  if phone is null then return json_build_object('error','nophone'); end if;
  if phone ~ '^0' or length(phone) <= 10 then
    phone := regexp_replace(phone, '^0+', '');
    if coalesce(pc,'') <> '' and phone !~ ('^' || pc) then phone := pc || phone; end if;
  end if;
  phone := '+' || phone;
  amen := case when jsonb_typeof(f->'amenities') = 'array' then (select array_agg(x) from jsonb_array_elements_text(f->'amenities') x) else '{}'::text[] end;
  ph_int := bk_intake_int(f->>'power_hours');

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
      case when ph_int is null then null else least(24, greatest(0, ph_int)) end, bk_intake_int(f->>'generator_amps'), left(nullif(f->>'heating',''), 60),
      bk_intake_bool(f->>'furnished', false),
      case when rent then bk_intake_int(f->>'lease_months') end, case when rent then bk_intake_int(f->>'advance_months') end,
      case when rent then bk_intake_int(f->>'deposit_usd') end, bk_intake_bool(f->>'bills_included', false), coalesce(amen, '{}'),
      descr, phone, coalesce(a.name, nullif(trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),'')),
      bk_intake_bool(f->>'accepts_whatsapp', true), false,
      case when lower(f->>'direction') in ('n','s','e','w','ne','nw','se','sw') then lower(f->>'direction') end,
      case when rent then (case when lower(f->>'rental_period') in ('daily','weekly','monthly','yearly') then lower(f->>'rental_period') else 'yearly' end) end,
      case when st = 'live' then now() end, cc)
  returning * into l;

  ph := coalesce(d.photos, '[]'::jsonb); i := 0;
  for i in 0 .. jsonb_array_length(ph) - 1 loop
    insert into listing_photos (listing_id, url, thumb_url, sort_order, kind, size_bytes)
      values (l.id, ph->i->>'url', ph->i->>'thumb_url', i, 'photo', bk_intake_int(ph->i->>'bytes'));
  end loop;
  update intake_drafts set status = 'published', listing_id = l.id, published_at = now(), updated_at = now(), error = null where id = d.id;
  insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'published', jsonb_build_object('listing_id', l.id, 'ref', l.ref, 'status', l.status, 'photos', jsonb_array_length(ph)));
  return json_build_object('ok', true, 'listing_id', l.id, 'ref', l.ref, 'status', l.status, 'user_id', l.user_id, 'country_code', l.country_code, 'photos', jsonb_array_length(ph));
end $$;

-- admin write paths: only inside the admin's countries
create or replace function public.bk_admin_intake_set(p_token text, p_id bigint, p_patch jsonb)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; d intake_drafts; ag agencies; st text;
begin
  uid := bk_admin_uid(p_token);
  select * into d from intake_drafts where id = p_id;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if not bk_admin_country_ok(uid, d.country_code) then raise exception 'unauthorised'; end if;
  if p_patch ? 'agency_id' then
    if p_patch->>'agency_id' is null or p_patch->>'agency_id' = '' then d.agency_id := null;
    else
      select * into ag from agencies where id = (p_patch->>'agency_id')::bigint;
      if ag.id is null then return json_build_object('error','noagency'); end if;
      if not bk_admin_country_ok(uid, ag.country_code) then raise exception 'unauthorised'; end if;
      d.agency_id := ag.id; d.user_id := ag.user_id; d.country_code := coalesce(ag.country_code, d.country_code);
    end if;
  end if;
  if p_patch ? 'fields' then d.fields := coalesce(d.fields,'{}'::jsonb) || (p_patch->'fields'); end if;
  if p_patch ? 'country_code' then
    if not bk_admin_country_ok(uid, upper(p_patch->>'country_code')) then raise exception 'unauthorised'; end if;
    d.country_code := upper(p_patch->>'country_code');
  end if;
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
  select * into d from intake_drafts where id = p_id;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if not bk_admin_country_ok(uid, d.country_code) then raise exception 'unauthorised'; end if;
  delete from intake_drafts where id = p_id;
  insert into intake_log (draft_id, chat_id, event, detail) values (p_id, d.chat_id, 'admin_delete', jsonb_build_object('by', uid, 'photos', d.photos));
  return json_build_object('ok', true, 'photos', d.photos);
end $$;

create or replace function public.bk_admin_agency_set(p_token text, p_id bigint, p_status text default null, p_verified boolean default null,
  p_intake boolean default null, p_trusted boolean default null, p_intake_phone text default null, p_unpair boolean default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; a agencies;
begin
  uid := bk_admin_uid(p_token);
  select * into a from agencies where id = p_id;
  if a.id is null then return json_build_object('error','noagency'); end if;
  if not bk_admin_country_ok(uid, a.country_code) then raise exception 'unauthorised'; end if;
  update agencies set status = coalesce(p_status, status), verified = coalesce(p_verified, verified),
         intake_enabled = coalesce(p_intake, intake_enabled), intake_trusted = coalesce(p_trusted, intake_trusted),
         intake_phone = case when p_intake_phone is null then intake_phone when trim(p_intake_phone) = '' then null else bk_intake_norm_phone(p_intake_phone) end,
         intake_telegram = case when coalesce(p_unpair,false) then null else intake_telegram end,
         intake_telegram_name = case when coalesce(p_unpair,false) then null else intake_telegram_name end,
         updated_at = now()
   where id = p_id returning * into a;
  if p_status = 'approved' then update users set card_logo = true where id = a.user_id; end if;
  if coalesce(p_intake,false) and a.intake_code is null then
    update agencies set intake_code = upper(substr(encode(gen_random_bytes(6),'hex'),1,8)) where id = a.id returning * into a;
  end if;
  return json_build_object('ok', true, 'intake_enabled', a.intake_enabled, 'intake_trusted', a.intake_trusted, 'intake_code', a.intake_code);
end $$;

-- the log block of the panel page follows the admin's countries too (rows without a draft: unrestricted admins only)
create or replace function public.bk_admin_intake(p_token text, p_country text default null, p_status text default null, p_limit integer default 200)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; sc text; al text[]; cfg jsonb; unrestricted boolean;
begin
  uid := bk_admin_uid(p_token);
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  unrestricted := al is null or cardinality(al) = 0;
  cfg := bk_intake_cfg();
  return json_build_object(
    'cfg', case when unrestricted then cfg else cfg - 'intake_admin_code' - 'intake_admin_chats' end,
    'unrestricted', unrestricted,
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
        select g.id, g.draft_id, g.chat_id, g.level, g.event, g.detail, g.created_at from intake_log g left join intake_drafts d on d.id = g.draft_id
         where (d.id is not null and bk_scope_ok(d.country_code, sc, al)) or (d.id is null and unrestricted)
         order by g.created_at desc limit 80) x), '[]'::json));
end $$;
