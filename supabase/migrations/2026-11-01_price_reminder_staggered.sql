-- 2026-11-01 · owner: the price reminders go out slowly, one every 30 minutes.
-- 1) the send queue skips a message whose time has not come yet (created_at in the future). Every message queued
--    the normal way has created_at = now(), so nothing else changes.
create or replace function public.bk_campaign_sends_pending(p_limit integer default 200) returns json
language plpgsql security definer set search_path = public, extensions as $fn$
declare ids bigint[]; day0 timestamptz; owner_today int; owner_recent boolean; owner_next bigint;
begin
  update campaign_sends set status = 'failed', error = 'interrupted'
   where status = 'queued' and claimed_at is not null and claimed_at < now() - interval '30 minutes';

  -- Telegram first: the WhatsApp copy of a notification Telegram already delivered is not sent
  update campaign_sends s set status = 'skipped_telegram', error = 'delivered on Telegram'
    from campaigns c
   where s.status = 'queued' and s.claimed_at is null and s.channel = 'whatsapp' and c.id = s.campaign_id
     and (c.title like 'direct: %' or c.title like 'reward: %')
     and exists (select 1 from campaign_sends t where t.campaign_id = s.campaign_id and t.contact_id = s.contact_id
                  and t.channel = 'telegram' and t.status = 'sent');

  -- owners on WhatsApp: 15 a Damascus day, one a minute
  day0 := date_trunc('day', now() at time zone 'Asia/Damascus') at time zone 'Asia/Damascus';
  select count(*) into owner_today from campaign_sends s join campaigns c on c.id = s.campaign_id
   where s.channel = 'whatsapp' and c.title like 'direct: wanted match (owner)%' and s.claimed_at >= day0;
  select exists (select 1 from campaign_sends s join campaigns c on c.id = s.campaign_id
                  where s.channel = 'whatsapp' and c.title like 'direct: wanted match (owner)%' and s.claimed_at > now() - interval '60 seconds')
    into owner_recent;
  owner_next := null;
  if owner_today < 15 and not owner_recent then
    select s.id into owner_next from campaign_sends s join campaigns c on c.id = s.campaign_id
     where s.status = 'queued' and s.claimed_at is null and s.channel = 'whatsapp' and c.title like 'direct: wanted match (owner)%'
       and s.created_at <= now()
       and not exists (select 1 from campaign_sends t where t.campaign_id = s.campaign_id and t.contact_id = s.contact_id
                        and t.channel = 'telegram' and t.status = 'queued')
     order by s.created_at limit 1;
  end if;

  with picked as (
    select s.id from campaign_sends s left join campaigns c on c.id = s.campaign_id
     where s.status = 'queued' and s.claimed_at is null
       and s.created_at <= now()   -- a message scheduled for later waits for its minute
       -- a notification's WhatsApp copy waits while its Telegram copy is still on the way
       and not (s.channel = 'whatsapp' and (c.title like 'direct: %' or c.title like 'reward: %')
                and exists (select 1 from campaign_sends t where t.campaign_id = s.campaign_id and t.contact_id = s.contact_id
                             and t.channel = 'telegram' and t.status = 'queued'))
       -- owners on WhatsApp: only the one this round allows
       and (not (s.channel = 'whatsapp' and coalesce(c.title,'') like 'direct: wanted match (owner)%') or s.id = owner_next)
     order by s.created_at
     limit p_limit
     for update of s skip locked
  ), claimed as (
    update campaign_sends s set claimed_at = now() from picked where s.id = picked.id returning s.id
  )
  select coalesce(array_agg(id), '{}') into ids from claimed;

  if array_length(ids, 1) is null then return '[]'::json; end if;

  return coalesce((select json_agg(row_to_json(x)) from (
    select s.id, s.channel, s.trigger_type, c.id as contact_id, c.phone, c.email, c.tg_chat_id, c.tg_consent, c.unsub_token,
           c.name as contact_name, coalesce(u.lang, 'ar') as lang,
           camp.title, coalesce(camp.body_ar, '') as body_ar, coalesce(camp.body_en, '') as body_en, camp.subject,
           l.id as listing_id, l.ref as listing_ref, l.price_usd as listing_price, l.description as listing_description
      from campaign_sends s
      join contacts c on c.id = s.contact_id
      left join users u on u.id = c.user_id
      left join campaigns camp on camp.id = s.campaign_id
      left join listings l on l.id = s.listing_id
     where s.id = any(ids)
     order by s.created_at) x), '[]'::json);
end $fn$;

-- 2) the reminders: one per member still without a real price, 30 minutes apart, never at night
do $do$
declare r record; camp uuid; body text; at_ts timestamptz := now(); loc timestamp;
begin
  for r in
    with sent as (
      select distinct on (cs.contact_id) cs.contact_id, substring(c.title from 11) who, c.country_code
        from campaigns c join campaign_sends cs on cs.campaign_id = c.id
       where c.title like 'price48h: %' and cs.status = 'sent'
       order by cs.contact_id, c.created_at
    )
    select s.contact_id, s.who, s.country_code,
           string_agg(l.ref || ' — https://balkoun.com/listing/' || l.id || '/', E'\n' order by l.ref) links
      from sent s
      join contacts ct on ct.id = s.contact_id
      join listings l on l.user_id = ct.user_id
     where l.status = 'live'
       and (l.price_usd is null or l.price_usd <= 15 or l.price_usd in (123, 123456))
       and not exists (select 1 from campaigns x where x.title = 'priceReminder: ' || s.who)
     group by s.contact_id, s.who, s.country_code
     order by s.who
  loop
    body := 'مرحباً ' || r.who || ' 🌿' || E'\n' ||
      'تذكير لطيف من فريق بلكون: ما زالت هذه الإعلانات بحاجة إلى سعر حقيقي:' || E'\n' || r.links || E'\n\n' ||
      'الإعلانات التي فيها سعر تحصل على مشاهدات واتصالات أكثر بكثير، والسعر يوفّر وقت الباحثين ويوصلهم إليكم أسرع.' || E'\n\n' ||
      'يمكنكم إضافة السعر بتعديل الإعلان من حسابكم في الموقع، أو أرسلوا لنا الأسعار هنا ونعدّلها عنكم.' || E'\n\n' ||
      'شكراً لتعاونكم 🙏' || E'\n' || 'فريق بلكون';
    insert into campaigns (title, kind, channels, subject, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
      values ('priceReminder: ' || r.who, 'manual', array['whatsapp'], null, body, body, coalesce(r.country_code, 'SY'), false, 'sending',
              '6ec60333-3cca-47b6-bf83-7f62cb76bb42', now())
      returning id into camp;
    -- no message between 22:00 and 10:00 Syria time: the rest wait for tomorrow 10:00, still 30 minutes apart
    loc := at_ts at time zone 'Asia/Damascus';
    if loc::time >= time '22:00' then at_ts := (date_trunc('day', loc) + interval '1 day 10 hours') at time zone 'Asia/Damascus';
    elsif loc::time < time '10:00' then at_ts := (date_trunc('day', loc) + interval '10 hours') at time zone 'Asia/Damascus'; end if;
    insert into campaign_sends (campaign_id, trigger_type, contact_id, channel, status, created_at)
      values (camp, 'manual', r.contact_id, 'whatsapp', 'queued', at_ts);
    at_ts := at_ts + interval '30 minutes';
  end loop;
end $do$;

select count(*) as reminders_queued, min(s.created_at) as first_at, max(s.created_at) as last_at
  from campaigns c join campaign_sends s on s.campaign_id = c.id where c.title like 'priceReminder: %';
