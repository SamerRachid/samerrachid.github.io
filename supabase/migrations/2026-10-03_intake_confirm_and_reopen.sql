-- 2026-10-03 · bot flow (owner's rules):
--   • after the read: the summary, then the question نعم / لا / تصحيح / إضافة — nothing publishes before «نعم»
--     («تصحيح» → cmd fix_ask, «إضافة» → cmd add_ask; the next message joins the draft and it is re-read as before)
--   • after the publish: NO one-hour window any more (no fix-by-short-text, no «إلغاء» of the listing, no photo glue);
--     any text opens a new listing; «جديد» at any time opens a new one
--   • to edit / add photos / delete a published listing the sender sends ITS NUMBER (SY10281, "10281", "رقم الإعلان 10281"):
--     the bot opens it (intake_log listing_opened, 30-minute session) and offers 1 تعديل · 2 إضافة صور/فيديو · 3 حذف · لا خروج;
--     inside the session texts are corrections (fix_published), photos/videos are attached (attach_listing), «تم»/«لا»/
--     «جديد» or a new listing text close it (listing_closed). Admin chats can open any listing; members only their own.
CREATE OR REPLACE FUNCTION public.bk_intake_message(p_source text, p_external_id text, p_chat_id text, p_kind text, p_text text, p_media jsonb DEFAULT NULL::jsonb, p_payload jsonb DEFAULT NULL::jsonb, p_sender_name text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cfg jsonb; s json; d intake_drafts; prev intake_drafts; cmd text; cmd_after text; tx text; cmdtx text; ins int; is_new boolean := false; cc text;
        n_today int; replied boolean; was text; kind text; soft_no boolean := false; guided boolean; expired jsonb; new_status text; merged boolean := false;
        sess jsonb; lid bigint; lref text; ldraft bigint; lmode text; lrow listings; mcc text; mnum text;
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
    when cmdtx ~* '^(2|إلغاء|الغاء|الغي|ألغي|الغيه|ألغيه|الغه|لا تنشر|حذف|احذف|إحذف|شطب|cancel|delete|remove|x|❌)[.!]?$' then 'cancel'
    when cmdtx ~* '^(تم|تمام|انتهيت|خلص|خلاص|done|end|finish)[.!]?$' then 'done'
    when cmdtx ~* '^(جديد|إعلان جديد|اعلان جديد|new|/new)$' then 'new'
    when cmdtx ~* '^(مساعدة|help|/help|\?|؟)$' then 'help'
    when cmdtx ~* '^(رجع|رجّع|رجعه|رجّعه|تراجع|رجوع|undo|back)[.!]?$' then 'undo'
    when cmdtx ~* '^(تخطي|تخطى|تجاوز|skip|/skip)[.!]?$' then 'skip'
    when cmdtx ~* '^(تصحيح|تعديل|صحح|صحّح|عدل|عدّل|correct|correction|edit|fix)[.!]?$' then 'fix'
    when cmdtx ~* '^(إضافة|اضافة|أضف|اضف|زيادة|add|more)[.!]?$' then 'add'
    else null end;
  -- «تصحيح السعر 45 ألف» on one line: the word is dropped, the rest is the correction text
  if kind = 'text' and cmd is null and cmdtx ~* '^(تصحيح|تعديل|صحح|صحّح|عدل|عدّل|correction|correct|edit|fix)[\s:،,.\-]+\S' then
    tx := regexp_replace(tx, '^(تصحيح|تعديل|صحح|صحّح|عدل|عدّل|correction|correct|edit|fix)[\s:،,.\-]+', '', 'i');
    cmdtx := regexp_replace(cmdtx, '^(تصحيح|تعديل|صحح|صحّح|عدل|عدّل|correction|correct|edit|fix)[\s:،,.\-]+', '', 'i');
  end if;
  soft_no := cmd is null and kind = 'text' and cmdtx ~* '^(لا|لأ|كلا|no|nope)[.!]?$';
  if cmd is not null and kind <> 'text' then cmd_after := cmd; cmd := null; end if;

  -- ── an opened published listing (the sender sent its number within 30 minutes): the session takes every message ──
  select l.detail into sess from intake_log l
   where l.chat_id = p_chat_id and l.event = 'listing_opened' and l.created_at > now() - interval '30 minutes'
     and not exists (select 1 from intake_log c where c.chat_id = p_chat_id and c.event = 'listing_closed' and c.id > l.id)
   order by l.id desc limit 1;
  if sess is not null then
    lid := (sess->>'listing_id')::bigint; lref := sess->>'ref'; ldraft := (sess->>'draft_id')::bigint; lmode := sess->>'mode';
    -- the menu answers come first: "1" is option 1 here, not the «نعم» of a draft
    if lmode is null and kind = 'text' and cmdtx ~* '^(1|١|تعديل|تعديل المعلومات|عدل|عدّل|تصحيح|صحح|صحّح|edit|fix|correct)[.!]?$' then
      update intake_messages set draft_id = ldraft where source = p_source and external_id = p_external_id;
      insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'listing_opened', sess || '{"mode":"edit"}'::jsonb);
      return json_build_object('command','listing_edit_ask','listing_id',lid,'ref',lref,'draft_id',ldraft,'sender',s,'guided',guided);
    elsif lmode is null and (kind in ('photo','video') or (kind = 'text' and cmdtx ~* '^(2|٢|إضافة|اضافة|أضف|اضف|صور|صورة|فيديو|add|photos|photo|video)[.!]?$')) then
      update intake_messages set draft_id = ldraft where source = p_source and external_id = p_external_id;
      insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'listing_opened', sess || '{"mode":"add"}'::jsonb);
      if kind in ('photo','video') then
        insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'photo_attached', jsonb_build_object('listing_id', lid));
        return json_build_object('attach_listing', lid, 'draft_id', ldraft, 'ref', lref, 'replied_recently', false, 'sender', s, 'guided', guided);
      end if;
      return json_build_object('command','listing_add_ask','listing_id',lid,'ref',lref,'draft_id',ldraft,'sender',s,'guided',guided);
    elsif lmode is null and kind = 'text' and cmdtx ~* '^(3|٣|حذف|احذف|إحذف|شطب|delete|remove)[.!]?$' then
      update intake_messages set draft_id = ldraft where source = p_source and external_id = p_external_id;
      update listings set status = 'hidden', updated_at = now() where id = lid and status in ('live','pending');
      insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'listing_removed_by_sender', jsonb_build_object('listing_id', lid));
      insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'listing_closed', jsonb_build_object('listing_id', lid, 'by', 'delete'));
      return json_build_object('command','cancel_published','listing_id',lid,'ref',lref,'draft_id',ldraft,'sender',s,'guided',guided);
    elsif kind = 'text' and (cmd in ('new','done','cancel','help','confirm') or soft_no or cmdtx ~* '^(خروج|رجوع|اغلاق|إغلاق|exit|close)[.!]?$') then
      insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'listing_closed', jsonb_build_object('listing_id', lid, 'by', coalesce(cmd, 'no')));
      if cmd = 'help' then sess := null;                                     -- the how-to still goes out
      elsif cmd = 'new' then
        -- «جديد» closes the opened listing AND starts fresh (an open draft, if any, is cancelled below as usual)
        sess := null;
      else
        update intake_messages set draft_id = ldraft where source = p_source and external_id = p_external_id;
        return json_build_object('command','listing_closed','listing_id',lid,'ref',lref,'draft_id',ldraft,'sender',s,'guided',guided);
      end if;
    elsif length(cmdtx) >= 20 and cmdtx ~* '(للبيع|للإيجار|للايجار|للأجار|للاجار|للآجار|مطلوب|for sale|for rent)' then
      -- a new listing text ("شقة للبيع في المزة …") ends the session; the text goes on to open its own draft
      insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'listing_closed', jsonb_build_object('listing_id', lid, 'by', 'new_listing_text'));
      sess := null;
    elsif lmode is null then
      -- anything else before an option was picked: the menu again
      update intake_messages set draft_id = ldraft where source = p_source and external_id = p_external_id;
      return json_build_object('command','listing_menu','listing_id',lid,'ref',lref,'draft_id',ldraft,'country_code',(select country_code from listings where id = lid),'sender',s,'guided',guided);
    else
      -- mode edit / add: a text is a correction, a photo or video is added to the listing
      update intake_messages set draft_id = ldraft where source = p_source and external_id = p_external_id;
      if kind in ('photo','video') then
        replied := exists (select 1 from intake_log where draft_id = ldraft and event = 'photo_attached' and created_at > now() - interval '90 seconds');
        insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'photo_attached', jsonb_build_object('listing_id', lid));
        return json_build_object('attach_listing', lid, 'draft_id', ldraft, 'ref', lref, 'replied_recently', replied, 'sender', s, 'guided', guided);
      end if;
      if kind = 'text' and tx <> '' then
        insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'fix_by_sender', jsonb_build_object('text', left(tx, 300)));
        return json_build_object('command','fix_published','listing_id',lid,'ref',lref,'draft_id',ldraft,'text',tx,'sender',s,'guided',guided);
      end if;
      return json_build_object('command','listing_menu','listing_id',lid,'ref',lref,'draft_id',ldraft,'country_code',(select country_code from listings where id = lid),'sender',s,'guided',guided);
    end if;
  end if;

  select * into d from intake_drafts
   where source = p_source and chat_id = p_chat_id
     and ((status in ('collecting','reading') and last_message_at > now() - interval '12 hours')
       or (status in ('ready','needs_info') and updated_at > now() - interval '24 hours')
       or (status = 'review' and updated_at > now() - interval '10 minutes' and coalesce(fields->>'chat_closed','') <> '1'))
   order by created_at desc limit 1;
  was := d.status;

  -- ── a listing number ("SY10281", "10281", "رقم الإعلان 10281"): open that listing for editing. A bare number counts only
  --    when no draft is on the table (while a summary waits, "10281" could be a price correction) ──
  if kind = 'text' and cmd is null and not soft_no
     and cmdtx ~* '^\s*#?\s*(?:رقم\s*)?(?:الإعلان\s*|الاعلان\s*|اعلان\s*|إعلان\s*|listing\s*|ad\s*)?(?:[a-z]{2}\s*-?\s*)?\d{4,7}\s*$'
     and (cmdtx ~* '[a-z]{2}\s*-?\s*\d{4,7}' or d.id is null) then
    mcc := upper(substring(cmdtx from '([a-zA-Z]{2})\s*-?\s*\d{4,7}'));
    mnum := substring(cmdtx from '(\d{4,7})\s*$');
    lref := coalesce(mcc, upper(coalesce(s->>'country_code','SY'))) || mnum;
    select * into lrow from listings
     where ref = lref and status in ('live','pending')
       and (coalesce((s->>'is_admin')::boolean,false) or (s->>'user_id' is not null and user_id = (s->>'user_id')::uuid));
    if lrow.id is null then
      return json_build_object('command','listing_notfound','ref',lref,'sender',s,'guided',guided);
    end if;
    select id into ldraft from intake_drafts where listing_id = lrow.id order by id desc limit 1;
    if ldraft is null then
      -- a listing posted from the site: a shadow draft carries its text so corrections can be read against it
      insert into intake_drafts (source, chat_id, sender_name, agency_id, user_id, by_admin, country_code, raw_text, status, fields, listing_id, published_at, last_message_at)
        values (p_source, p_chat_id, p_sender_name, (s->>'agency_id')::bigint, lrow.user_id, false, lrow.country_code, coalesce(lrow.description,''), 'published', '{}'::jsonb, lrow.id, coalesce(lrow.published_at, lrow.created_at), now())
        returning id into ldraft;
    end if;
    update intake_messages set draft_id = ldraft where source = p_source and external_id = p_external_id;
    insert into intake_log (draft_id, chat_id, event, detail) values (ldraft, p_chat_id, 'listing_opened', jsonb_build_object('listing_id', lrow.id, 'ref', lref, 'draft_id', ldraft));
    return json_build_object('command','listing_menu','listing_id',lrow.id,'ref',lref,'draft_id',ldraft,'country_code',lrow.country_code,'sender',s,'guided',guided);
  end if;

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
  -- «تصحيح» / «إضافة» while a summary (or a question) is on the table: a short prompt; what comes next joins the draft
  if cmd in ('fix','add') then
    if d.id is not null then update intake_messages set draft_id = d.id where source = p_source and external_id = p_external_id; end if;
    return json_build_object('command', cmd || '_ask', 'draft_id', case when d.status in ('ready','needs_info','collecting','reading') then d.id end, 'status', d.status, 'sender', s, 'guided', guided);
  end if;
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
      -- every review draft of this chat lets go, not only the newest: otherwise the next message falls back to an older one
      update intake_drafts set fields = coalesce(fields,'{}'::jsonb) || '{"chat_closed":"1"}'::jsonb
       where source = p_source and chat_id = p_chat_id and status = 'review' and coalesce(fields->>'chat_closed','') <> '1';
      insert into intake_log (draft_id, chat_id, event, detail) values (d.id, p_chat_id, 'new_by_sender', '{"kept_review":true}'::jsonb);
    elsif d.id is not null then
      update intake_drafts set status = 'cancelled', error = null, updated_at = now() where id = d.id;
      insert into intake_log (draft_id, chat_id, event) values (d.id, p_chat_id, 'new_by_sender');
    end if;
    if d.id is null then insert into intake_log (chat_id, event) values (p_chat_id, 'new_by_sender'); end if;
    return json_build_object('command','new','draft_id',null,'sender',s,'guided',guided);
  end if;
  if cmd = 'undo' then
    -- a listing the sender deleted (option 3) a moment ago comes back
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
  -- (a photo or video whose caption is the listing text counts the same as a text; decorations before the word —
  --  "🔥 #للبيع شقة…" — do not hide it: the offer word just has to be near the start of a message of some length)
  if d.id is not null and tx <> '' and d.status in ('review','ready','needs_info') and coalesce(d.raw_text,'') <> ''
     and length(cmdtx) >= 30 and left(cmdtx, 30) ~* '(للبيع|للإيجار|للايجار|للأجار|للاجار|للآجار|مطلوب)(\s|$|،|:|_)' then
    insert into intake_log (draft_id, chat_id, event, detail) values (d.id, p_chat_id, 'next_listing', jsonb_build_object('left_status', d.status));
    d := null;
  end if;

  cc := coalesce(nullif(upper(p_country),''), s->>'country_code', 'SY');
  if d.id is null then
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
