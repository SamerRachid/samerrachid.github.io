-- Balkoun · 2026-09-26 · "راسل" from the admin panel: one direct message to one person (member or contact) on
-- WhatsApp (Balkoun's number via WAHA), Telegram (if linked) or email. It rides on the campaign pipeline: a tiny
-- one-recipient campaign + one campaign_sends row, sent by the next tick (the panel triggers it right away), so
-- every direct message is logged like any other send.

create or replace function public.bk_admin_contact_channels(p_token text, p_contact_id uuid default null, p_user_id uuid default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; c contacts; utg text;
begin
  begin uid := bk_admin_uid(p_token); exception when others then uid := null; end;
  if uid is null then return json_build_object('error','unauthorised'); end if;
  select * into c from contacts where (p_contact_id is not null and id = p_contact_id) or (p_user_id is not null and user_id = p_user_id) order by created_at limit 1;
  if c.id is null then return json_build_object('error','nocontact'); end if;
  if c.tg_chat_id is null and c.user_id is not null then
    select tg_chat_id into utg from users where id = c.user_id;
    if utg is not null then update contacts set tg_chat_id = utg, updated_at = now() where id = c.id; c.tg_chat_id := utg; end if;
  end if;
  return json_build_object('id', c.id, 'name', c.name, 'phone', c.phone, 'email', c.email, 'tg', c.tg_chat_id is not null,
    'wa_consent', c.wa_consent, 'tg_consent', c.tg_consent, 'email_consent', c.email_consent);
end $function$;

create or replace function public.bk_admin_message_contact(p_token text, p_contact_id uuid default null, p_user_id uuid default null, p_channel text default 'whatsapp', p_text text default '', p_subject text default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; c contacts; camp uuid; sid bigint; utg text;
begin
  begin uid := bk_admin_uid(p_token); exception when others then uid := null; end;
  if uid is null then return json_build_object('error','unauthorised'); end if;
  if p_channel not in ('whatsapp','telegram','email') then return json_build_object('error','badchannel'); end if;
  if length(trim(coalesce(p_text,''))) < 2 then return json_build_object('error','empty'); end if;
  select * into c from contacts where (p_contact_id is not null and id = p_contact_id) or (p_user_id is not null and user_id = p_user_id) order by created_at limit 1;
  if c.id is null then return json_build_object('error','nocontact'); end if;
  if p_channel = 'telegram' and c.tg_chat_id is null and c.user_id is not null then
    select tg_chat_id into utg from users where id = c.user_id;
    if utg is not null then update contacts set tg_chat_id = utg, updated_at = now() where id = c.id; c.tg_chat_id := utg; end if;
  end if;
  if p_channel = 'whatsapp' and coalesce(c.phone,'') = '' then return json_build_object('error','nophone'); end if;
  if p_channel = 'telegram' and c.tg_chat_id is null then return json_build_object('error','notg'); end if;
  if p_channel = 'email' and coalesce(c.email,'') = '' then return json_build_object('error','noemail'); end if;
  insert into campaigns (title, kind, channels, subject, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
    values ('direct: ' || coalesce(nullif(c.name,''), c.phone, c.email, ''), 'manual', array[p_channel], p_subject, trim(p_text), trim(p_text), c.country_code, false, 'sending', uid, now())
    returning id into camp;
  insert into campaign_sends (campaign_id, trigger_type, contact_id, channel, status) values (camp, 'manual', c.id, p_channel, 'queued') returning id into sid;
  return json_build_object('ok', true, 'send_id', sid, 'campaign_id', camp);
end $function$;

revoke execute on function public.bk_admin_contact_channels(text, uuid, uuid) from public, anon;
grant execute on function public.bk_admin_contact_channels(text, uuid, uuid) to anon;   -- the panel calls it with the admin token like every other bk_admin_* RPC
revoke execute on function public.bk_admin_message_contact(text, uuid, uuid, text, text, text) from public;
grant execute on function public.bk_admin_message_contact(text, uuid, uuid, text, text, text) to anon;

create or replace function public.bk_admin_direct_messages(p_token text, p_contact_id uuid default null, p_user_id uuid default null)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; cid uuid;
begin
  begin uid := bk_admin_uid(p_token); exception when others then uid := null; end;
  if uid is null then return json_build_object('error','unauthorised'); end if;
  select id into cid from contacts where (p_contact_id is not null and id = p_contact_id) or (p_user_id is not null and user_id = p_user_id) order by created_at limit 1;
  return coalesce((select json_agg(json_build_object('id', s.id, 'channel', s.channel, 'status', s.status, 'error', s.error, 'text', left(coalesce(k.body_ar, ''), 400), 'at', s.created_at, 'sent_at', s.sent_at) order by s.created_at desc)
    from campaign_sends s join campaigns k on k.id = s.campaign_id where s.contact_id = cid and k.title like 'direct: %' ), '[]'::json);
end $function$;
grant execute on function public.bk_admin_direct_messages(text, uuid, uuid) to anon;
