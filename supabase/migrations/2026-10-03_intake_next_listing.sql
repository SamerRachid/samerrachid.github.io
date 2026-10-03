-- 2026-10-03 · bot: a text that opens with للبيع/للإيجار/مطلوب while the previous draft was already read (review / ready /
-- needs_info) opens its OWN draft instead of being appended to the previous one. The previous draft keeps waiting where it
-- was (panel review, or the sender's confirmation). Bare photos that follow join the newest draft, so "text → photos →
-- next text → its photos" lands each photo on its own listing.
-- Same day, second change: «جديد» no longer cancels a draft that already waits in the panel (review) — the admin had typed
-- «جديد» between forwards and lost four listings. The chat just lets go of it (fields.chat_closed = 1).
CREATE OR REPLACE FUNCTION public.bk_intake_message(p_source text, p_external_id text, p_chat_id text, p_kind text, p_text text, p_media jsonb DEFAULT NULL::jsonb, p_payload jsonb DEFAULT NULL::jsonb, p_sender_name text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cfg jsonb; s json; d intake_drafts; prev intake_drafts; cmd text; cmd_after text; tx text; cmdtx text; ins int; is_new boolean := false; cc text;
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
    when cmdtx ~* '^(تخطي|تخطى|تجاوز|skip|/skip)[.!]?$' then 'skip'
    else null end;
  soft_no := cmd is null and kind = 'text' and cmdtx ~* '^(لا|لأ|كلا|no|nope)[.!]?$';
  if cmd is not null and kind <> 'text' then cmd_after := cmd; cmd := null; end if;

  select * into d from intake_drafts
   where source = p_source and chat_id = p_chat_id
     and ((status in ('collecting','reading') and last_message_at > now() - interval '12 hours')
       or (status in ('ready','needs_info') and updated_at > now() - interval '24 hours')
       or (status = 'review' and updated_at > now() - interval '10 minutes' and coalesce(fields->>'chat_closed','') <> '1'))
   order by created_at desc limit 1;
  was := d.status;
  -- a bare photo/video while the listing sits in the panel for review (10-minute window): joins it, short acknowledgement
  if d.id is not null and d.status = 'review' and kind in ('photo','video') and tx = '' then
    update intake_drafts set last_message_at = now(), updated_at = now() where id = d.id;
    update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
    replied := exists (select 1 from intake_log where draft_id = d.id and event = 'photo_to_review' and created_at > now() - interval '90 seconds');
    insert into intake_log (draft_id, chat_id, event) values (d.id, p_chat_id, 'photo_to_review');
    return json_build_object('draft_id', d.id, 'status', d.status, 'attach_review', true, 'replied_recently', replied, 'is_new', false, 'sender', s,
      'country_code', d.country_code, 'photo_count', jsonb_array_length(d.photos), 'has_text', d.raw_text <> '', 'guided', guided);
  end if;
  -- the neighbourhood question: the draft waits for the sender to confirm the unknown name or write the right one
  if d.id is not null and kind = 'text' and d.fields->>'area_wait' = '1' and cmd is null and not soft_no then
    update intake_drafts set fields = fields - 'area_wait', updated_at = now() where id = d.id;
    update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
    return json_build_object('command','area_set','draft_id',d.id,'text',tx,'sender',s,'guided',guided);
  end if;
  if d.id is not null and kind = 'text' and d.status = 'ready' and d.fields->>'area_pending' = '1' and cmdtx ~* '^(لا|لأ|كلا|no|nope)([.!،,:\s]|$)' then
    update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
    if cmdtx ~* '^(لا|لأ|كلا|no|nope)[.!،,:\s]+\S' then
      return json_build_object('command','area_set','draft_id',d.id,'text',regexp_replace(tx, '^(لا|لأ|كلا|no|nope)[.!،,:\s]+', ''),'sender',s,'guided',guided);
    end if;
    update intake_drafts set fields = fields || '{"area_wait":"1"}'::jsonb, updated_at = now() where id = d.id;
    return json_build_object('command','area_ask','draft_id',d.id,'sender',s,'guided',guided);
  end if;
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
    if d.id is not null and d.status in ('reading','collecting') then
      update intake_drafts set fields = fields || '{"auto_confirm":"1"}'::jsonb, updated_at = now() where id = d.id;
      return json_build_object('command','confirm_wait','draft_id',d.id,'status',d.status,'sender',s,'guided',guided);
    end if;
    return json_build_object('command','confirm','draft_id',null,'status',d.status,'open_id',d.id,'sender',s,'guided',guided);
  end if;
  if cmd = 'cancel' then
    if d.id is null then
      select * into prev from intake_drafts where source = p_source and chat_id = p_chat_id order by created_at desc limit 1;
      if prev.id is not null and prev.status = 'published' and prev.listing_id is not null and prev.published_at > now() - interval '60 minutes'
         and not exists (select 1 from intake_log l where l.chat_id = p_chat_id and l.event = 'new_by_sender' and l.created_at > prev.published_at)
         and exists (select 1 from listings where id = prev.listing_id and status in ('live','pending')) then
        update listings set status = 'hidden', updated_at = now() where id = prev.listing_id;
        update intake_messages set draft_id = prev.id where source = p_source and external_id = p_external_id;
        insert into intake_log (draft_id, chat_id, event, detail) values (prev.id, p_chat_id, 'listing_removed_by_sender', jsonb_build_object('listing_id', prev.listing_id));
        return json_build_object('command','cancel_published','draft_id',prev.id,'listing_id',prev.listing_id,'ref',(select ref from listings where id = prev.listing_id),'sender',s,'guided',guided);
      end if;
    end if;
    if d.id is not null then
      update intake_drafts set status = 'cancelled', error = null, updated_at = now() where id = d.id;
      update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id;
      insert into intake_log (draft_id, chat_id, event) values (d.id, p_chat_id, 'cancelled_by_sender');
    end if;
    return json_build_object('command','cancel','draft_id',d.id,'sender',s,'guided',guided);
  end if;
  if cmd = 'new' then
    -- a listing already waiting in the panel (review) is NOT cancelled by «جديد»: the chat merely lets go of it
    -- (no more photos / corrections join it); the admin decides in the panel. Anything else open is cancelled.
    if d.id is not null and d.status = 'review' then
      update intake_drafts set fields = coalesce(fields,'{}'::jsonb) || '{"chat_closed":"1"}'::jsonb where id = d.id;
      insert into intake_log (draft_id, chat_id, event, detail) values (d.id, p_chat_id, 'new_by_sender', '{"kept_review":true}'::jsonb);
    elsif d.id is not null then
      update intake_drafts set status = 'cancelled', error = null, updated_at = now() where id = d.id;
      insert into intake_log (draft_id, chat_id, event) values (d.id, p_chat_id, 'new_by_sender');
    end if;
    if d.id is null then insert into intake_log (chat_id, event) values (p_chat_id, 'new_by_sender'); end if;
    return json_build_object('command','new','draft_id',null,'sender',s,'guided',guided);
  end if;
  if cmd = 'undo' then
    -- a listing the sender removed with «إلغاء» a moment ago comes back
    select dd.* into prev from intake_log l join intake_drafts dd on dd.id = l.draft_id
     where l.chat_id = p_chat_id and l.event = 'listing_removed_by_sender' and l.created_at > now() - interval '10 minutes'
     order by l.created_at desc limit 1;
    if prev.listing_id is not null and exists (select 1 from listings where id = prev.listing_id and status = 'hidden') then
      update listings set status = 'live', updated_at = now() where id = prev.listing_id;
      update intake_messages set draft_id = prev.id where source = p_source and external_id = p_external_id;
      insert into intake_log (draft_id, chat_id, event, detail) values (prev.id, p_chat_id, 'listing_restored_by_sender', jsonb_build_object('listing_id', prev.listing_id));
      return json_build_object('command','undo','restored',true,'listing_restored',true,'draft_id',prev.id,'listing_id',prev.listing_id,'ref',(select ref from listings where id = prev.listing_id),'status','published','sender',s,'guided',guided);
    end if;
    prev := null;
    select * into prev from intake_drafts
     where source = p_source and chat_id = p_chat_id and status = 'cancelled' and listing_id is null
       and ((coalesce(error,'') = '' and updated_at > now() - interval '10 minutes')
         or (error = 'expired' and updated_at > now() - interval '24 hours'))
     order by updated_at desc limit 1;
    if prev.id is null then return json_build_object('command','undo','restored',false,'draft_id',d.id,'status',d.status,'sender',s,'guided',guided); end if;
    if d.id is not null and d.id <> prev.id and d.created_at >= prev.updated_at then
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
  if cmd = 'skip' then
    if d.id is not null then update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id; end if;
    return json_build_object('command','skip','draft_id',d.id,'status',d.status,'missing',to_jsonb(d.missing),'sender',s,'guided',guided);
  end if;
  if cmd = 'done' then
    if d.id is not null then update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id; end if;
    return json_build_object('command','done','draft_id',d.id,'status',d.status,'sender',s,'guided',guided,
      'empty', d.id is null or (coalesce(d.raw_text,'') = '' and jsonb_array_length(d.photos) = 0));
  end if;

  -- a fresh listing (text opening with للبيع/للإيجار/مطلوب) while the previous one was already read: it opens its own
  -- draft; the previous one keeps waiting (panel review / sender confirmation). Photos that follow join the newest draft.
  if d.id is not null and kind = 'text' and d.status in ('review','ready','needs_info') and coalesce(d.raw_text,'') <> ''
     and cmdtx ~* '^\s*#?\s*(للبيع|للإيجار|للايجار|للأجار|للاجار|للآجار|مطلوب)(\s|$|،|:|_)' then
    insert into intake_log (draft_id, chat_id, event, detail) values (d.id, p_chat_id, 'next_listing', jsonb_build_object('left_status', d.status));
    d := null;
  end if;

  cc := coalesce(nullif(upper(p_country),''), s->>'country_code', 'SY');
  if d.id is null then
    if kind = 'text' and tx <> '' and cmd is null and not soft_no and length(tx) < 160
       and cmdtx !~* '(للبيع|للإيجار|للايجار|للأجار|للاجار|للآجار|مطلوب|بدي |أبحث|ابحث|أريد|اريد|looking|wanted|for sale|for rent)'
       and (cmdtx !~* '(شقة|شقه|بيت|منزل|أرض|ارض|محل|فيلا|مكتب|مزرعة|مستودع|معمل|بناء|شاليه|عيادة|فندق|صالة|كازية|ورشة|مطعم|مكاتب)' or array_length(regexp_split_to_array(trim(cmdtx), '\s+'), 1) <= 5) then
      select * into prev from intake_drafts where source = p_source and chat_id = p_chat_id order by created_at desc limit 1;
      if prev.id is not null and prev.status = 'published' and prev.listing_id is not null and prev.published_at > now() - interval '60 minutes'
         and not exists (select 1 from intake_log l where l.chat_id = p_chat_id and l.event = 'new_by_sender' and l.created_at > prev.published_at)
         and exists (select 1 from listings where id = prev.listing_id and status in ('live','pending')) then
        update intake_messages set draft_id = prev.id where source = p_source and external_id = p_external_id;
        insert into intake_log (draft_id, chat_id, event, detail) values (prev.id, p_chat_id, 'fix_by_sender', jsonb_build_object('text', left(tx, 300)));
        return json_build_object('command','fix_published','draft_id',prev.id,'listing_id',prev.listing_id,'ref',(select ref from listings where id = prev.listing_id),'text',tx,'sender',s,'guided',guided);
      end if;
    end if;
    if kind in ('photo','video') and tx = '' then
      select * into prev from intake_drafts where source = p_source and chat_id = p_chat_id order by created_at desc limit 1;
      if prev.id is not null and prev.status = 'published' and prev.listing_id is not null and prev.published_at > now() - interval '5 minutes' and not exists (select 1 from intake_log l where l.chat_id = p_chat_id and l.event = 'new_by_sender' and l.created_at > prev.published_at) then
        update intake_messages set draft_id = prev.id where source = p_source and external_id = p_external_id;
        replied := exists (select 1 from intake_log where draft_id = prev.id and event = 'photo_attached' and created_at > now() - interval '90 seconds');
        insert into intake_log (draft_id, chat_id, event, detail) values (prev.id, p_chat_id, 'photo_attached', jsonb_build_object('listing_id', prev.listing_id));
        return json_build_object('attach_listing', prev.listing_id, 'draft_id', prev.id, 'replied_recently', replied, 'sender', s, 'guided', guided,
          'ref', (select ref from listings where id = prev.listing_id));
      elsif prev.id is not null and prev.status = 'review' and prev.updated_at > now() - interval '10 minutes' and coalesce(prev.fields->>'chat_closed','') <> '1' and not exists (select 1 from intake_log l where l.chat_id = p_chat_id and l.event = 'new_by_sender' and l.created_at > prev.updated_at) then
        update intake_messages set draft_id = prev.id where source = p_source and external_id = p_external_id;
        replied := exists (select 1 from intake_log where draft_id = prev.id and event = 'photo_to_review' and created_at > now() - interval '90 seconds');
        insert into intake_log (draft_id, chat_id, event) values (prev.id, p_chat_id, 'photo_to_review');
        return json_build_object('draft_id', prev.id, 'status', prev.status, 'attach_review', true, 'replied_recently', replied, 'is_new', false, 'sender', s,
          'country_code', prev.country_code, 'photo_count', jsonb_array_length(prev.photos), 'has_text', prev.raw_text <> '', 'guided', guided);
      end if;
    end if;
    select count(*) into n_today from intake_drafts where source = p_source and chat_id = p_chat_id and created_at > now() - interval '24 hours';
    -- admin, agency and broker chats are never rate-limited (they send whole batches); the cap is for plain members
    if n_today >= coalesce(bk_intake_int(cfg->>'intake_daily_limit'), 30) and not coalesce((s->>'is_admin')::boolean, false) and s->>'agency_id' is null and coalesce(s->>'account_type','member') not in ('broker','agency') then
      insert into intake_log (chat_id, event, detail) values (p_chat_id, 'daily_limit', jsonb_build_object('n', n_today));
      return json_build_object('reason','limit','sender',s,'guided',guided);
    end if;
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
