-- Request numbers (owner, 2026-10-16): every request gets a reference like SYW1037 — the country code, W for «مطلوب»,
-- then 1000 + its id — so it never looks like a listing number (SY10455) to people or to the bot. Addresses stay /wanted/<id>.
alter table wanted add column if not exists ref text;
update wanted set ref = coalesce(nullif(upper(country_code),''), 'SY') || 'W' || (1000 + id) where ref is null;
create unique index if not exists wanted_ref_key on wanted (ref);

-- new requests: numbered on insert, after trg_wanted_country has set the country (BEFORE triggers run in name order)
create or replace function public.bk_trg_wanted_ref() returns trigger language plpgsql set search_path to 'public' as $f$
begin
  if new.ref is null then new.ref := coalesce(nullif(upper(new.country_code),''), 'SY') || 'W' || (1000 + new.id); end if;
  return new;
end $f$;
drop trigger if exists trg_wanted_ref on wanted;
create trigger trg_wanted_ref before insert on wanted for each row execute function bk_trg_wanted_ref();

-- the number travels with every request the site and the panel read
CREATE OR REPLACE FUNCTION public.bk_wanted_row(w wanted)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select json_build_object(
    'id', w.id, 'ref', w.ref, 'user_id', w.user_id, 'deal', w.deal, 'property_type', w.property_type,
    'property_types', coalesce(w.property_types, case when w.property_type is not null then array[w.property_type] else '{}' end),
    'gov_name', w.gov_name, 'area_names', w.area_names,
    'budget_min', w.budget_min, 'budget_max', w.budget_max, 'currency', w.currency, 'rooms_min', w.rooms_min, 'area_min', w.area_min, 'tabu', w.tabu,
    'title', w.title, 'description', w.description, 'contact', w.contact, 'status', w.status, 'featured', w.featured, 'views', w.views,
    'expires_at', w.expires_at, 'created_at', w.created_at,
    'user_name', (select trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) from users u where u.id=w.user_id),
    'user_avatar', (select u.avatar_url from users u where u.id=w.user_id),
    'phone', case when w.contact in ('phone','both') then (select u.phone from users u where u.id=w.user_id) end,
    'whatsapp', case when w.contact in ('whatsapp','both') then (select u.phone from users u where u.id=w.user_id) end,
    'phone_verified', (select u.phone_verified from users u where u.id=w.user_id)
  );
$function$;

-- and appears in the match messages
CREATE OR REPLACE FUNCTION public.bk_wanted_ping(p_wanted_id bigint, p_listing_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        '📋 يوجد طلب شراء/إيجار يطابق إعلانك '||coalesce(l.ref,'')||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'شاهد التفاصيل: https://balkoun.com'||link_w,
        '📋 A matching buy/rent request for your listing '||coalesce(l.ref,'')||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'View it: https://balkoun.com'||link_w,
        coalesce(c_owner.country_code, l.country_code, 'SY'), false, 'sending', l.user_id, now())
      returning id into camp;
    if c_owner.tg_chat_id is not null then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c_owner.id, 'telegram', 'queued'); end if;
    if coalesce(c_owner.phone,'') <> '' then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c_owner.id, 'whatsapp', 'queued'); end if;
  end if;

  select * into c_seeker from contacts where user_id = w.user_id order by created_at limit 1;
  if c_seeker.id is not null and (c_seeker.tg_chat_id is not null or coalesce(c_seeker.phone,'') <> '') then
    insert into campaigns (title, kind, channels, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
      values ('direct: wanted match (seeker) w'||w.id||'/l'||l.id, 'manual', array['whatsapp','telegram'],
        '🏠 يوجد إعلان يطابق طلبك'||coalesce(' '||w.ref,'')||(case when wtitle<>'' then ' («'||wtitle||'»)' else '' end)||E'\n'||'شاهده: https://balkoun.com'||link_l,
        '🏠 A listing matches your request'||E'\n'||'View it: https://balkoun.com'||link_l,
        coalesce(c_seeker.country_code, w.country_code, 'SY'), false, 'sending', w.user_id, now())
      returning id into camp;
    if c_seeker.tg_chat_id is not null then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c_seeker.id, 'telegram', 'queued'); end if;
    if coalesce(c_seeker.phone,'') <> '' then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', l.id, c_seeker.id, 'whatsapp', 'queued'); end if;
  end if;

  return true;
end $function$;
