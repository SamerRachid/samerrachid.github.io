-- Balkoun · 2026-09-28 · message-to-listing bot: fewer mistakes for senders.
--  * "guided": the bot's short how-to goes out once per chat (intake_log event guide_sent); returned so the function knows
--  * a plain "لا"/"no" cancels only while a summary is on the table (ready / needs_info); otherwise it is ordinary text.
--    Hard words (إلغاء, cancel, 2, لا تنشر…) always cancel.
--  * "رجّع" / undo: brings back a listing cancelled by the sender within 10 minutes, or one that expired within 24 hours.
--    If the sender had already started a new draft after that, the two are merged and read again.
--  * a draft waiting for the sender's answer expires after 24 hours (was 3 days): the next message starts a new listing
--    and the bot says so (expired_prev), instead of silently gluing it onto last week's property.
--  * photos arriving within 5 minutes after a publish are added to that published listing (attach), not a new draft.

create or replace function public.bk_intake_listing_add_photo(p_listing bigint, p_photo jsonb) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare n int; mx int;
begin
  mx := coalesce(bk_intake_int(bk_intake_cfg()->>'intake_max_photos'), 12);
  select count(*) into n from listing_photos where listing_id = p_listing and kind = 'photo';
  if not exists (select 1 from listings where id = p_listing) then return json_build_object('error','nolisting'); end if;
  if n >= mx then return json_build_object('ok', false, 'reason', 'max', 'n', n, 'max', mx); end if;
  insert into listing_photos (listing_id, url, thumb_url, sort_order, kind, size_bytes)
    values (p_listing, p_photo->>'url', p_photo->>'thumb_url', n, 'photo', bk_intake_int(p_photo->>'bytes'));
  return json_build_object('ok', true, 'n', n + 1, 'max', mx);
end $function$;
grant execute on function public.bk_intake_listing_add_photo(bigint, jsonb) to anon, authenticated, service_role;

create or replace function public.bk_intake_message(p_source text, p_external_id text, p_chat_id text, p_kind text, p_text text, p_media jsonb default null, p_payload jsonb default null, p_sender_name text default null, p_country text default null) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare cfg jsonb; s json; d intake_drafts; prev intake_drafts; cur intake_drafts; cmd text; cmd_after text; tx text; cmdtx text; ins int; is_new boolean := false; cc text;
        n_today int; replied boolean; was text; kind text; soft_no boolean := false; guided boolean; expired jsonb; new_status text; merged boolean := false;
begin
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
    update intake_messages set text = left(text, 200), media = null, payload = null where source = p_source and external_id = p_external_id;
    replied := exists (select 1 from intake_log where chat_id = p_chat_id and event = 'unknown_reply' and created_at > now() - interval '24 hours');
    insert into intake_log (chat_id, event, detail) values (p_chat_id, 'unknown_sender', jsonb_build_object('source', p_source, 'name', left(coalesce(p_sender_name,''),80), 'kind', kind));
    return json_build_object('reason', case when coalesce((s->>'blocked')::boolean,false) then 'blocked' else 'unknown' end, 'replied_recently', replied, 'sender', s);
  end if;
  guided := exists (select 1 from intake_log where chat_id = p_chat_id and event = 'guide_sent');

  tx := trim(coalesce(p_text, ''));
  cmdtx := translate(tx, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
  cmd := case
    when cmdtx ~* '^(1|نعم|انشر|نشر|publish|ok|اوك|أوك|✅)[.!]?$' then 'confirm'
    when cmdtx ~* '^(2|إلغاء|الغاء|الغي|ألغي|الغيه|ألغيه|الغه|لا تنشر|cancel|x|❌)[.!]?$' then 'cancel'
    when cmdtx ~* '^(تم|تمام|انتهيت|خلص|خلاص|done|end|finish)[.!]?$' then 'done'
    when cmdtx ~* '^(جديد|إعلان جديد|اعلان جديد|new|/new)$' then 'new'
    when cmdtx ~* '^(مساعدة|help|/help|\?|؟)$' then 'help'
    when cmdtx ~* '^(رجع|رجّع|رجعه|رجّعه|تراجع|رجوع|undo|back)[.!]?$' then 'undo'
    else null end;
  soft_no := cmd is null and kind = 'text' and cmdtx ~* '^(لا|لأ|كلا|no|nope)[.!]?$';
  if cmd is not null and kind <> 'text' then cmd_after := cmd; cmd := null; end if;

  select * into d from intake_drafts
   where source = p_source and chat_id = p_chat_id
     and ((status in ('collecting','reading') and last_message_at > now() - interval '12 hours')
       or (status in ('ready','needs_info') and updated_at > now() - interval '24 hours'))
   order by created_at desc limit 1;
  was := d.status;
  -- "لا" alone: an answer to "shall I publish?" only while a summary is on the table
  if soft_no then
    if d.id is not null and d.status in ('ready','needs_info') then cmd := 'cancel';
    elsif d.id is null then return json_build_object('command','nothing','sender',s,'guided',guided);
    end if;
  end if;

  if cmd = 'help' then return json_build_object('command','help','draft_id',d.id,'status',d.status,'sender',s,'guided',guided); end if;
  if cmd = 'confirm' then
    if d.id is not null then update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id; end if;
    if d.id is not null and d.status = 'ready' then
      update intake_drafts set updated_at = now() where id = d.id;
      return json_build_object('command','confirm','draft_id',d.id,'status',d.status,'sender',s,'guided',guided);
    end if;
    return json_build_object('command','confirm','draft_id',null,'status',d.status,'open_id',d.id,'sender',s,'guided',guided);
  end if;
  if cmd = 'cancel' then
    if d.id is not null then
      update intake_drafts set status = 'cancelled', error = null, updated_at = now() where id = d.id;
      update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
      insert into intake_log (draft_id, chat_id, event) values (d.id, p_chat_id, 'cancelled_by_sender');
    end if;
    return json_build_object('command','cancel','draft_id',d.id,'sender',s,'guided',guided);
  end if;
  if cmd = 'new' then
    if d.id is not null then
      update intake_drafts set status = 'cancelled', error = null, updated_at = now() where id = d.id;
      insert into intake_log (draft_id, chat_id, event) values (d.id, p_chat_id, 'new_by_sender');
    end if;
    return json_build_object('command','new','draft_id',null,'sender',s,'guided',guided);
  end if;
  if cmd = 'undo' then
    select * into prev from intake_drafts
     where source = p_source and chat_id = p_chat_id and status = 'cancelled' and listing_id is null
       and ((coalesce(error,'') = '' and updated_at > now() - interval '10 minutes')
         or (error = 'expired' and updated_at > now() - interval '24 hours'))
     order by updated_at desc limit 1;
    if prev.id is null then return json_build_object('command','undo','restored',false,'draft_id',d.id,'status',d.status,'sender',s,'guided',guided); end if;
    if d.id is not null and d.id <> prev.id and d.created_at >= prev.updated_at then
      -- the sender went on with a new draft meanwhile: fold it into the restored one and read again
      update intake_drafts set
        raw_text = rtrim(raw_text) || case when raw_text = '' or coalesce(d.raw_text,'') = '' then '' else E'\n' end || coalesce(d.raw_text,''),
        photos = coalesce(photos,'[]'::jsonb) || coalesce(d.photos,'[]'::jsonb)
       where id = prev.id;
      update intake_drafts set status = 'cancelled', error = 'merged', updated_at = now() where id = d.id;
      update intake_messages set draft_id = prev.id where draft_id = d.id;
      merged := true;
    end if;
    new_status := case when merged then 'collecting'
                       when prev.summary is not null and coalesce(array_length(prev.missing,1),0) = 0 then 'ready'
                       when prev.summary is not null then 'needs_info'
                       else 'collecting' end;
    update intake_drafts set status = new_status, error = null, updated_at = now(), last_message_at = now(), claimed_at = null where id = prev.id;
    update intake_messages set draft_id = prev.id where source = p_source and external_id = p_external_id;
    insert into intake_log (draft_id, chat_id, event, detail) values (prev.id, p_chat_id, 'restored_by_sender', jsonb_build_object('merged', merged, 'status', new_status));
    return json_build_object('command','undo','restored',true,'merged',merged,'draft_id',prev.id,'status',new_status,'sender',s,'guided',guided);
  end if;
  if cmd = 'done' then
    if d.id is not null then update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id; end if;
    return json_build_object('command','done','draft_id',d.id,'status',d.status,'sender',s,'guided',guided,
      'empty', d.id is null or (coalesce(d.raw_text,'') = '' and jsonb_array_length(d.photos) = 0));
  end if;

  cc := coalesce(nullif(upper(p_country),''), s->>'country_code', 'SY');
  if d.id is null then
    -- a photo right after the chat's LATEST draft was published belongs to that listing; a photo right after the latest
    -- draft went to the panel for review joins that draft (the sender is still sending photos of the same property)
    -- (a photo carrying a caption is a NEW listing: the rules below only take bare photos)
    if kind = 'photo' and tx = '' then
      select * into prev from intake_drafts where source = p_source and chat_id = p_chat_id order by created_at desc limit 1;
      if prev.id is not null and prev.status = 'published' and prev.listing_id is not null and prev.published_at > now() - interval '5 minutes' then
        update intake_messages set draft_id = prev.id where source = p_source and external_id = p_external_id;
        replied := exists (select 1 from intake_log where draft_id = prev.id and event = 'photo_attached' and created_at > now() - interval '90 seconds');
        insert into intake_log (draft_id, chat_id, event, detail) values (prev.id, p_chat_id, 'photo_attached', jsonb_build_object('listing_id', prev.listing_id));
        return json_build_object('attach_listing', prev.listing_id, 'draft_id', prev.id, 'replied_recently', replied, 'sender', s, 'guided', guided,
          'ref', (select ref from listings where id = prev.listing_id));
      elsif prev.id is not null and prev.status = 'review' and prev.updated_at > now() - interval '10 minutes' then
        update intake_messages set draft_id = prev.id where source = p_source and external_id = p_external_id;
        replied := exists (select 1 from intake_log where draft_id = prev.id and event = 'photo_to_review' and created_at > now() - interval '90 seconds');
        insert into intake_log (draft_id, chat_id, event) values (prev.id, p_chat_id, 'photo_to_review');
        return json_build_object('draft_id', prev.id, 'status', prev.status, 'attach_review', true, 'replied_recently', replied, 'is_new', false, 'sender', s,
          'country_code', prev.country_code, 'photo_count', jsonb_array_length(prev.photos), 'has_text', prev.raw_text <> '', 'guided', guided);
      end if;
    end if;
    select count(*) into n_today from intake_drafts where source = p_source and chat_id = p_chat_id and created_at > now() - interval '24 hours';
    if n_today >= coalesce(bk_intake_int(cfg->>'intake_daily_limit'), 30) then
      insert into intake_log (chat_id, event, detail) values (p_chat_id, 'daily_limit', jsonb_build_object('n', n_today));
      return json_build_object('reason','limit','sender',s,'guided',guided);
    end if;
    -- a listing still waiting for the sender's answer from more than a day ago is closed, and the sender is told
    select * into prev from intake_drafts
     where source = p_source and chat_id = p_chat_id and status in ('ready','needs_info')
       and updated_at <= now() - interval '24 hours' and updated_at > now() - interval '4 days'
     order by updated_at desc limit 1;
    if prev.id is not null then
      update intake_drafts set status = 'cancelled', error = 'expired', updated_at = now() where id = prev.id;
      insert into intake_log (draft_id, chat_id, event) values (prev.id, p_chat_id, 'expired');
      expired := jsonb_build_object('id', prev.id, 'title', coalesce(prev.fields->>'title', ''));
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
    'photo_count', jsonb_array_length(d.photos), 'has_text', d.raw_text <> '', 'command_after', cmd_after, 'guided', guided, 'expired_prev', expired);
end $function$;
