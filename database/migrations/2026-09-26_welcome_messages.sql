-- Balkoun · 2026-09-26 · welcome messages for new members, through the existing campaign_sends queue:
--   • WhatsApp + email: queued the moment the account's phone is verified (signup, or a later verification)
--   • Telegram: queued the moment the account gets a Telegram chat (verified via Telegram at signup, "share my
--     number" in the bot, or the account-page deep link)
-- One welcome per contact per channel, ever. Texts + on/off live in site_content.extras (intake_welcome_*), read
-- by the Edge Function's campaignFlush() which builds the message (trigger_type = 'welcome'); the admin edits them
-- in the panel's "post by message" settings. Consent: a welcome is transactional, it is skipped only for a contact
-- who explicitly unsubscribed from that channel.

alter table campaign_sends drop constraint if exists campaign_sends_trigger_type_check;
alter table campaign_sends add constraint campaign_sends_trigger_type_check
  check (trigger_type = any (array['manual'::text, 'auto_new_listing'::text, 'welcome'::text]));

create or replace function public.bk_campaign_sends_pending(p_limit integer default 200) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  return coalesce((select json_agg(row_to_json(x)) from (
    select s.id, s.channel, s.trigger_type, c.id as contact_id, c.phone, c.email, c.tg_chat_id, c.tg_consent, c.unsub_token,
           c.name as contact_name, coalesce(u.lang, 'ar') as lang,
           coalesce(camp.body_ar, '') as body_ar, coalesce(camp.body_en, '') as body_en, camp.subject,
           l.id as listing_id, l.ref as listing_ref, l.price_usd as listing_price, l.description as listing_description
      from campaign_sends s
      join contacts c on c.id = s.contact_id
      left join users u on u.id = c.user_id
      left join campaigns camp on camp.id = s.campaign_id
      left join listings l on l.id = s.listing_id
     where s.status = 'queued'
     order by s.created_at limit p_limit) x), '[]'::json);
end $function$;

create or replace function public.bk_trg_welcome_member() returns trigger
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare c contacts; x jsonb; phone_now boolean; tg_now boolean;
begin
  select coalesce(extras, '{}'::jsonb) into x from site_content where id = 1;
  if coalesce(x->>'intake_welcome_on', 'true') = 'false' then return new; end if;
  select * into c from contacts where user_id = new.id limit 1;
  if c.id is null then return new; end if;   -- the sync trigger (trg_sync_member_contact, fires first) had a hiccup

  phone_now := coalesce(new.phone_verified, false) and (tg_op = 'INSERT' or not coalesce(old.phone_verified, false));
  tg_now := new.tg_chat_id is not null and (tg_op = 'INSERT' or old.tg_chat_id is null);

  if phone_now then
    if coalesce(c.phone, '') <> '' and c.wa_consent <> 'unsubscribed'
       and not exists (select 1 from campaign_sends where contact_id = c.id and channel = 'whatsapp' and trigger_type = 'welcome') then
      insert into campaign_sends (trigger_type, contact_id, channel, status) values ('welcome', c.id, 'whatsapp', 'queued');
    end if;
    if coalesce(c.email, '') <> '' and c.email_consent <> 'unsubscribed'
       and not exists (select 1 from campaign_sends where contact_id = c.id and channel = 'email' and trigger_type = 'welcome') then
      insert into campaign_sends (trigger_type, contact_id, channel, status) values ('welcome', c.id, 'email', 'queued');
    end if;
  end if;

  if tg_now then
    update contacts set tg_chat_id = coalesce(tg_chat_id, new.tg_chat_id), updated_at = now() where id = c.id;
    if c.tg_consent <> 'unsubscribed'
       and not exists (select 1 from campaign_sends where contact_id = c.id and channel = 'telegram' and trigger_type = 'welcome') then
      insert into campaign_sends (trigger_type, contact_id, channel, status) values ('welcome', c.id, 'telegram', 'queued');
    end if;
  end if;
  return new;
exception when others then return new;   -- a welcome must never break a signup or a profile save
end $function$;

drop trigger if exists trg_welcome_member on users;
create trigger trg_welcome_member after insert or update of phone_verified, tg_chat_id on users
  for each row execute function bk_trg_welcome_member();
