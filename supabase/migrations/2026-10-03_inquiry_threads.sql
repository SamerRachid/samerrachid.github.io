-- 2026-10-03 · visit / message requests become conversations in «رسائلي» for both sides (owner, 2026-10-03: a member
-- with no phone — e.g. the house accounts — must still be able to send a request). Rules:
--   • a signed-in member can send without a phone number; a guest still has to leave one
--   • the owner sees the request in رسائلي (and the bell / Telegram / WhatsApp as before) and replies there; the
--     requester (if a member) sees the thread in their own رسائلي and can reply back; each reply rings the other side
--   • message_followups carries the thread with sender 'owner' / 'requester'
alter table message_followups drop constraint if exists message_followups_kind_check;
alter table message_followups add constraint message_followups_kind_check check (kind = any (array['report','feedback','inquiry']));
alter table message_followups drop constraint if exists message_followups_sender_check;
alter table message_followups add constraint message_followups_sender_check check (sender = any (array['member','admin','owner','requester']));
alter table inquiries add column if not exists kind text not null default 'visit';

create or replace function public.bk_inquiry_send(p_listing bigint, p_to_user uuid, p_name text, p_phone text, p_message text,
                                                   p_kind text default 'visit', p_user uuid default null, p_token text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare l listings; owner uuid; vis_phone text; body text; title text; link text; c contacts; camp uuid; n_today int; cc text;
        owner_tg text; visitor_name text; kind_ar text; inq_id bigint; member_no_txt text;
begin
  if p_user is not null then perform bk_require_member(p_token, p_user); end if;
  vis_phone := nullif(regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g'), '');
  if vis_phone is not null and length(vis_phone) < 8 then return json_build_object('error','phone'); end if;
  if vis_phone is null and p_user is null then return json_build_object('error','phone'); end if;   -- a guest must leave a number
  visitor_name := left(trim(coalesce(p_name,'')), 80);
  if visitor_name = '' and p_user is not null then select trim(coalesce(name,'')||' '||coalesce(family_name,'')) into visitor_name from users where id = p_user; end if;
  if coalesce(visitor_name,'') = '' then return json_build_object('error','name'); end if;
  if p_listing is not null then
    select * into l from listings where id = p_listing and status in ('live','pending');
    if l.id is null then return json_build_object('error','nolisting'); end if;
    owner := l.user_id;
  else
    owner := p_to_user;
  end if;
  if owner is null then return json_build_object('error','noowner'); end if;
  if owner = p_user then return json_build_object('error','self'); end if;
  select count(*) into n_today from inquiries where (phone = vis_phone or (p_user is not null and from_user = p_user)) and coalesce(property_id,0) = coalesce(p_listing,0) and created_at > now() - interval '24 hours';
  if n_today >= 3 then return json_build_object('error','limit'); end if;
  insert into inquiries (property_id, to_user, from_user, name, phone, message, status, kind)
    values (p_listing, owner, p_user, visitor_name, vis_phone, left(trim(coalesce(p_message,'')), 1000), 'new', case when p_kind = 'message' then 'message' else 'visit' end)
    returning id into inq_id;
  cc := lower(coalesce(l.country_code, (select country from users where id = owner), 'SY'));
  link := '/#/msgs?inquiry=' || inq_id;
  kind_ar := case when p_kind = 'message' then 'رسالة' else 'طلب معاينة' end;
  title := case when l.id is not null then kind_ar || ' على إعلانك ' || coalesce(l.ref, '') else kind_ar || ' من زائر' end;
  if p_user is not null then select member_no into member_no_txt from users where id = p_user; end if;
  body := visitor_name || case when member_no_txt is not null then ' (عضو ' || member_no_txt || ')' else '' end
          || case when vis_phone is not null then ' · ' || vis_phone else '' end
          || case when coalesce(trim(p_message),'') <> '' then E'\n' || left(trim(p_message), 600) else '' end
          || case when l.id is not null then E'\n' || 'https://balkoun.com' || case when cc = 'sy' then '' else '/' || cc end || '/listing/' || l.id else '' end
          || E'\n' || 'للرد: https://balkoun.com/#/msgs';
  -- 1) the bell on the site
  insert into notifications (user_id, type, title, body, link) values (owner, 'admin_msg', title, body, link);
  -- 2) Telegram + 3) WhatsApp, through the campaign queue the bot flushes every minute ("direct: " = no footer)
  select * into c from contacts where user_id = owner order by created_at limit 1;
  if c.id is not null then
    if c.tg_chat_id is null then
      select tg_chat_id into owner_tg from users where id = owner;
      if owner_tg is not null then update contacts set tg_chat_id = owner_tg, updated_at = now() where id = c.id; c.tg_chat_id := owner_tg; end if;
    end if;
    insert into campaigns (title, kind, channels, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
      values ('direct: inquiry ' || coalesce(l.ref, ''), 'manual', array['whatsapp','telegram'], '📩 ' || title || E'\n' || body, '📩 ' || title || E'\n' || body, upper(cc), false, 'sending', owner, now())
      returning id into camp;
    if c.tg_chat_id is not null then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c.id, 'telegram', 'queued'); end if;
    if coalesce(c.phone,'') <> '' then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c.id, 'whatsapp', 'queued'); end if;
  end if;
  return json_build_object('ok', true, 'id', inq_id);
end $$;
grant execute on function public.bk_inquiry_send(bigint, uuid, text, text, text, text, uuid, text) to anon, authenticated;

-- رسائلي: reports, feedback and now the inquiry threads (as owner or as requester)
CREATE OR REPLACE FUNCTION public.bk_my_messages(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  if p_user is null then return json_build_object('reports','[]'::json,'feedback','[]'::json,'inquiries','[]'::json); end if;
  return json_build_object(
    'reports', coalesce((select json_agg(x) from (
        select r.id, r.listing_id, r.reason, r.note, r.resolved,
               r.admin_reply, r.replied_at, r.created_at,
               l.ref as listing_ref,
               coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at)
                 from message_followups m where m.kind='report' and m.ref_id=r.id), '[]'::json) as thread
          from listing_reports r
          left join listings l on l.id = r.listing_id
         where r.user_id = p_user
         order by r.created_at desc) x), '[]'::json),
    'feedback', coalesce((select json_agg(x) from (
        select f.id, f.kind, f.body, f.handled, f.admin_reply, f.replied_at, f.created_at,
               coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at)
                 from message_followups m where m.kind='feedback' and m.ref_id=f.id), '[]'::json) as thread
          from feedback f
         where f.user_id = p_user
         order by f.created_at desc) x), '[]'::json),
    'inquiries', coalesce((select json_agg(x) from (
        select i.id, i.property_id as listing_id, l.ref as listing_ref, i.kind, i.name, i.phone, i.message, i.status, i.created_at,
               case when i.to_user = p_user then 'owner' else 'requester' end as role,
               case when i.to_user = p_user then i.name else coalesce(nullif(trim(coalesce(o.name,'')||' '||coalesce(o.family_name,'')),''), 'المعلن') end as other_name,
               case when i.to_user = p_user then i.from_user else i.to_user end as other_user,
               case when i.to_user = p_user then i.phone else (case when coalesce(o.hide_phone,false) then null else o.phone end) end as other_phone,
               coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at)
                 from message_followups m where m.kind='inquiry' and m.ref_id=i.id), '[]'::json) as thread
          from inquiries i
          left join listings l on l.id = i.property_id
          left join users o on o.id = i.to_user
         where i.to_user = p_user or i.from_user = p_user
         order by i.created_at desc) x), '[]'::json));
end $function$;

-- a reply inside a thread; for inquiries either side may answer, and the other side is rung
CREATE OR REPLACE FUNCTION public.bk_member_reply(p_user uuid, p_kind text, p_id bigint, p_body text, p_token text DEFAULT NULL::text)
 RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
declare v_owner uuid; i inquiries; me text; other uuid; who text; c contacts; camp uuid;
begin
  perform bk_require_member(p_token, p_user);
  if p_user is null then raise exception 'not logged in'; end if;
  if length(trim(p_body)) < 1 then raise exception 'empty message'; end if;
  if p_kind = 'inquiry' then
    select * into i from inquiries where id = p_id;
    if i.id is null then raise exception 'not found'; end if;
    if i.to_user = p_user then me := 'owner'; other := i.from_user;
    elsif i.from_user = p_user then me := 'requester'; other := i.to_user;
    else raise exception 'not yours'; end if;
    insert into message_followups (kind, ref_id, sender, body) values ('inquiry', p_id, me, left(trim(p_body), 1000));
    if me = 'owner' then update inquiries set status = 'replied' where id = p_id; end if;
    if other is not null then
      select trim(coalesce(name,'')||' '||coalesce(family_name,'')) into who from users where id = p_user;
      insert into notifications (user_id, type, title, body, link)
        values (other, 'admin_msg', 'رد من ' || coalesce(nullif(who,''), 'عضو') || case when i.property_id is not null then ' على ' || (case when me='owner' then 'طلبك' else 'طلب المعاينة' end) else '' end,
                left(trim(p_body), 600) || E'\n' || 'للرد: https://balkoun.com/#/msgs', '/#/msgs?inquiry=' || p_id);
      -- the other side's Telegram / WhatsApp too, when they have them (same queue, "direct: " = no footer)
      select * into c from contacts where user_id = other order by created_at limit 1;
      if c.id is not null and (c.tg_chat_id is not null or coalesce(c.phone,'') <> '') then
        insert into campaigns (title, kind, channels, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
          values ('direct: inquiry reply ' || p_id, 'manual', array['whatsapp','telegram'],
                  '💬 رد من ' || coalesce(nullif(who,''), 'عضو') || ' في بلكون:' || E'\n' || left(trim(p_body), 600) || E'\n' || 'للرد: https://balkoun.com/#/msgs',
                  '💬 رد من ' || coalesce(nullif(who,''), 'عضو') || ' في بلكون:' || E'\n' || left(trim(p_body), 600) || E'\n' || 'للرد: https://balkoun.com/#/msgs',
                  c.country_code, false, 'sending', p_user, now()) returning id into camp;
        if c.tg_chat_id is not null then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', i.property_id, c.id, 'telegram', 'queued'); end if;
        if coalesce(c.phone,'') <> '' then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', i.property_id, c.id, 'whatsapp', 'queued'); end if;
      end if;
    end if;
    return json_build_object('ok', true);
  end if;
  if p_kind = 'report' then
    select user_id into v_owner from listing_reports where id = p_id;
  elsif p_kind = 'feedback' then
    select user_id into v_owner from feedback where id = p_id;
  else
    raise exception 'bad kind';
  end if;
  if v_owner is distinct from p_user then raise exception 'not yours'; end if;
  insert into message_followups (kind, ref_id, sender, body) values (p_kind, p_id, 'member', p_body);
  return json_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.bk_member_delete_message(p_user uuid, p_kind text, p_id bigint, p_token text DEFAULT NULL::text)
 RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
declare v_owner uuid; i inquiries;
begin
  perform bk_require_member(p_token, p_user);
  if p_kind = 'report' then
    select user_id into v_owner from listing_reports where id = p_id;
    if v_owner is distinct from p_user then raise exception 'not yours'; end if;
    delete from message_followups where kind='report' and ref_id=p_id;
    delete from notifications where user_id=p_user and link='/#/msgs?report='||p_id;
    delete from listing_reports where id = p_id;
  elsif p_kind = 'feedback' then
    select user_id into v_owner from feedback where id = p_id;
    if v_owner is distinct from p_user then raise exception 'not yours'; end if;
    delete from message_followups where kind='feedback' and ref_id=p_id;
    delete from notifications where user_id=p_user and link='/#/msgs?feedback='||p_id;
    delete from feedback where id = p_id;
  elsif p_kind = 'inquiry' then
    -- either side may close the conversation; it disappears for both
    select * into i from inquiries where id = p_id;
    if i.id is null or (i.to_user is distinct from p_user and i.from_user is distinct from p_user) then raise exception 'not yours'; end if;
    delete from message_followups where kind='inquiry' and ref_id=p_id;
    delete from notifications where link='/#/msgs?inquiry='||p_id;
    delete from inquiries where id = p_id;
  end if;
  return json_build_object('ok', true);
end $function$;
