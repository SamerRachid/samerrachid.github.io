-- 2026-10-11: "مطلوب" matching — notify BOTH sides of a match (not just the counterpart that already existed), and
-- deliver by WhatsApp/Telegram too, not only the in-site bell. A shared helper (bk_wanted_ping) does both directions
-- + queues the campaign-send rows the bot already flushes every minute — same queue bk_inquiry_send uses, so no
-- new delivery code, just the same proven path. Idempotent: a pair that was already pinged is skipped.
--   bk_wanted_ping(p_wanted_id, p_listing_id)   one matched pair → bell + WhatsApp/Telegram to both sides
--   bk_wanted_notify(p_id)                      a wanted request was just posted → ping every matching live listing
--   bk_trg_listing_live_wanted                  a listing just went live → ping every matching open wanted request

create or replace function public.bk_wanted_ping(p_wanted_id bigint, p_listing_id bigint) returns boolean
language plpgsql security definer set search_path = public as $function$
declare w wanted; l listings; wtitle text; link_w text; link_l text; c_owner contacts; c_seeker contacts; camp uuid;
begin
  select * into w from wanted where id = p_wanted_id;
  select * into l from listings where id = p_listing_id;
  if w.id is null or l.id is null or w.status <> 'open' or l.status <> 'live' or w.user_id = l.user_id then return false; end if;
  link_w := '/wanted/'||w.id; link_l := '/listing/'||l.id;
  -- idempotent: this exact pair already pinged (checked on the owner side, which both inserts below always write)
  if exists (select 1 from notifications where user_id = l.user_id and type = 'wanted_match' and link = link_w) then return false; end if;
  wtitle := coalesce(w.title, 'مطلوب '||case w.deal when 'rent' then 'للإيجار' else 'للشراء' end||' في '||coalesce(w.gov_name,''));

  -- 1) the bell, both sides
  insert into notifications (user_id, type, title, body, link) values (l.user_id, 'wanted_match', 'طلب جديد يطابق إعلانك', wtitle, link_w);
  insert into notifications (user_id, type, title, body, link) values (w.user_id, 'wanted_listing', 'إعلان جديد يطابق طلبك', coalesce(l.ref,''), link_l);

  -- 2) WhatsApp / Telegram — same queue + "direct: " convention bk_inquiry_send uses (no marketing footer, not consent-gated)
  select * into c_owner from contacts where user_id = l.user_id order by created_at limit 1;
  if c_owner.id is not null and (c_owner.tg_chat_id is not null or coalesce(c_owner.phone,'') <> '') then
    insert into campaigns (title, kind, channels, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
      values ('direct: wanted match (owner) w'||w.id||'/l'||l.id, 'manual', array['whatsapp','telegram'],
        '📋 يوجد طلب شراء/إيجار يطابق إعلانك '||coalesce(l.ref,'')||E'\n'||wtitle||E'\n\n'||'شاهد التفاصيل: https://balkoun.com'||link_w,
        '📋 A matching buy/rent request for your listing '||coalesce(l.ref,'')||E'\n'||wtitle||E'\n\n'||'View it: https://balkoun.com'||link_w,
        coalesce(c_owner.country_code, l.country_code, 'SY'), false, 'sending', l.user_id, now())
      returning id into camp;
    if c_owner.tg_chat_id is not null then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c_owner.id, 'telegram', 'queued'); end if;
    if coalesce(c_owner.phone,'') <> '' then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c_owner.id, 'whatsapp', 'queued'); end if;
  end if;

  select * into c_seeker from contacts where user_id = w.user_id order by created_at limit 1;
  if c_seeker.id is not null and (c_seeker.tg_chat_id is not null or coalesce(c_seeker.phone,'') <> '') then
    insert into campaigns (title, kind, channels, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
      values ('direct: wanted match (seeker) w'||w.id||'/l'||l.id, 'manual', array['whatsapp','telegram'],
        '🏠 يوجد إعلان يطابق طلبك'||(case when wtitle<>'' then ' («'||wtitle||'»)' else '' end)||E'\n'||'شاهده: https://balkoun.com'||link_l,
        '🏠 A listing matches your request'||E'\n'||'View it: https://balkoun.com'||link_l,
        coalesce(c_seeker.country_code, w.country_code, 'SY'), false, 'sending', w.user_id, now())
      returning id into camp;
    if c_seeker.tg_chat_id is not null then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c_seeker.id, 'telegram', 'queued'); end if;
    if coalesce(c_seeker.phone,'') <> '' then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c_seeker.id, 'whatsapp', 'queued'); end if;
  end if;

  return true;
end $function$;
revoke all on function public.bk_wanted_ping(bigint, bigint) from public;

CREATE OR REPLACE FUNCTION public.bk_wanted_notify(p_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare w wanted; m record; n int := 0;
begin
  select * into w from wanted where id=p_id;
  if w.id is null or w.status<>'open' then return 0; end if;
  for m in
    select l.id from listings l join governorates g on g.id=l.governorate_id
     where l.status='live' and l.user_id<>w.user_id and l.deal=w.deal
       and (w.gov_name is null or g.name_ar=w.gov_name)
       and (w.property_type is null or l.property_type=w.property_type)
       and (w.budget_max is null or w.currency<>'USD' or l.price_usd is null or l.price_usd <= w.budget_max*1.1)
       and (cardinality(w.area_names)=0 or exists (select 1 from areas a where a.id=l.area_id and a.name_ar = any(w.area_names)))
     limit 200
  loop
    if bk_wanted_ping(w.id, m.id) then n := n + 1; end if;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.bk_trg_listing_live_wanted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare m record;
begin
  if new.status='live' and (tg_op='INSERT' or old.status is distinct from 'live') then
    for m in
      select w.id from wanted w join governorates g on g.name_ar=w.gov_name
       where w.status='open' and w.expires_at > now() and w.user_id<>new.user_id and w.deal=new.deal and g.id=new.governorate_id
         and (w.property_type is null or w.property_type=new.property_type)
         and (w.budget_max is null or w.currency<>'USD' or new.price_usd is null or new.price_usd <= w.budget_max*1.1)
         and (cardinality(w.area_names)=0 or exists (select 1 from areas a where a.id=new.area_id and a.name_ar = any(w.area_names)))
       limit 200
    loop
      perform bk_wanted_ping(m.id, new.id);
    end loop;
  end if;
  return new;
end $function$;
