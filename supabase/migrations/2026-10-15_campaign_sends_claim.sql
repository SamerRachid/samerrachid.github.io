-- Duplicate WhatsApp messages (2026-10-15): bk_campaign_sends_pending only SELECTed the queued rows, and the rows were
-- marked 'sent' only after the whole batch had gone out. Two senders running at once (the admin panel's immediate
-- "tick" after creating an account + the per-minute cron) both read the same rows and both sent them.
-- Now each row is claimed atomically (FOR UPDATE SKIP LOCKED + claimed_at) by the sender that reads it; a second
-- sender skips it. Status values are unchanged ('queued' until marked), so every other reader of the queue is unaffected.
-- A claim is never handed out again: a row still unmarked 30 minutes after its claim (the sender died mid-batch) is
-- marked failed 'interrupted' rather than re-sent, because it may already have reached the person.

alter table campaign_sends add column if not exists claimed_at timestamptz;

create or replace function public.bk_campaign_sends_pending(p_limit integer default 200)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare ids bigint[];
begin
  update campaign_sends set status = 'failed', error = 'interrupted'
   where status = 'queued' and claimed_at is not null and claimed_at < now() - interval '30 minutes';

  with picked as (
    select id from campaign_sends
     where status = 'queued' and claimed_at is null
     order by created_at
     limit p_limit
     for update skip locked
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

-- same grants as before: the function was service-role only (called by the bk-intake edge function)
revoke all on function public.bk_campaign_sends_pending(integer) from public, anon, authenticated;
