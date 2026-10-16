-- WhatsApp safety for notifications (owner, 2026-10-16)
--  • Telegram first: a notification (campaign titled "direct: …" or "reward: …") that has both a Telegram and a WhatsApp
--    copy for the same person goes to Telegram first; the WhatsApp copy is dropped once Telegram delivered it
--    (status 'skipped_telegram'), and sent only if Telegram failed. Marketing campaigns, where the admin picks the
--    channels himself, are unchanged.
--  • Messages to listing owners about a request ("direct: wanted match (owner)…") on WhatsApp: at most 15 a day
--    (Damascus day) and at least one minute apart; the rest stay queued and go out the next days, 15 a day.
--    Telegram copies are not limited (no ban risk there).
alter table campaign_sends drop constraint if exists campaign_sends_status_check;
alter table campaign_sends add constraint campaign_sends_status_check
  check (status = any (array['queued','sent','failed','skipped_no_consent','skipped_no_contact_info','skipped_telegram']));

create or replace function public.bk_campaign_sends_pending(p_limit integer default 200)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
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
       and not exists (select 1 from campaign_sends t where t.campaign_id = s.campaign_id and t.contact_id = s.contact_id
                        and t.channel = 'telegram' and t.status = 'queued')
     order by s.created_at limit 1;
  end if;

  with picked as (
    select s.id from campaign_sends s left join campaigns c on c.id = s.campaign_id
     where s.status = 'queued' and s.claimed_at is null
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
end $function$;
revoke all on function public.bk_campaign_sends_pending(integer) from public, anon, authenticated;

-- a campaign is finished when nothing of it is still queued (a WhatsApp copy skipped for Telegram counts as done)
-- (bk_campaign_sends_mark already looks only for 'queued', so nothing to change there)
