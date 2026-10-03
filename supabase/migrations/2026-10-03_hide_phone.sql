-- 2026-10-03 · "hide my number" (owner's rule): ONE switch on the member's account page. When on, the number is gone
-- from every listing of theirs, from their agency page/card and from what the bot publishes; visitors reach them
-- through a visit/contact request that lands in the member's notifications, on Telegram (if linked) and on WhatsApp
-- (sent by Balkoun's own number, so the member's number never shows). The admin panel still sees everything.
--
-- Why a private column instead of a view filter: anon can SELECT live rows of `listings` straight from the table
-- (policy p_listing_read), so the public column itself has to be empty. A BEFORE trigger keeps it that way for every
-- insert/update while the switch is on, and the switch RPC moves numbers back when it is turned off.

alter table users    add column if not exists hide_phone boolean not null default false;
alter table listings add column if not exists contact_phone_private text;
alter table listings alter column contact_phone drop not null;   -- empty in public while the owner hides (the number sits in _private)
alter table inquiries add column if not exists to_user uuid references users(id) on delete cascade;
alter table inquiries alter column property_id drop not null;
-- the table dates from the first prototype (properties / profiles): it now points at listings / users
alter table inquiries drop constraint if exists inquiries_property_id_fkey;
alter table inquiries drop constraint if exists inquiries_from_user_fkey;
alter table inquiries add constraint inquiries_property_id_fkey foreign key (property_id) references listings(id) on delete cascade;
alter table inquiries add constraint inquiries_from_user_fkey foreign key (from_user) references users(id) on delete set null;

-- the trigger: while the owner hides, the public phone column stays empty and the real number lives in _private
create or replace function public.bk_trg_listing_hide_phone() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.user_id is not null and exists (select 1 from users u where u.id = new.user_id and u.hide_phone) then
    if new.contact_phone is not null then new.contact_phone_private := new.contact_phone; end if;
    new.contact_phone := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_listing_hide_phone on listings;
create trigger trg_listing_hide_phone before insert or update of contact_phone, user_id on listings
  for each row execute function public.bk_trg_listing_hide_phone();

-- the switch (member token required)
create or replace function public.bk_set_hide_phone(p_token text, p_on boolean) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; n int;
begin
  uid := bk_member_uid(p_token);
  if uid is null then return json_build_object('error','unauthorised'); end if;
  update users set hide_phone = coalesce(p_on,false) where id = uid;
  if coalesce(p_on,false) then
    update listings set contact_phone_private = coalesce(contact_phone, contact_phone_private), contact_phone = null
     where user_id = uid and contact_phone is not null;
  else
    update listings set contact_phone = coalesce(contact_phone, contact_phone_private, (select phone from users where id = uid))
     where user_id = uid and contact_phone is null;
  end if;
  get diagnostics n = row_count;
  return json_build_object('ok', true, 'hide_phone', coalesce(p_on,false), 'listings', n);
end $$;

-- the member's own row carries the flag
CREATE OR REPLACE FUNCTION public.bk_me(p_id uuid, p_token text DEFAULT NULL::text)
 RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
declare u users; uid uuid;
begin
  uid := bk_member_uid(p_token);
  if uid is null or uid <> p_id then return json_build_object('error','nouser'); end if;
  select * into u from users where id = uid and not blocked;
  if u.id is null then return json_build_object('error','nouser'); end if;
  update member_sessions set expires_at = now() + interval '30 days' where token = p_token;
  update users set last_seen_at = now() where id = u.id;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'phone_verified',u.phone_verified,'member_no',u.member_no,
    'email',u.email,'email_verified',u.email_verified,'account_type',u.account_type,'hide_phone',coalesce(u.hide_phone,false),'token',p_token);
end $function$;

-- the public listing rows say whether the owner hides (the page then shows the request button instead of "no number")
create or replace view public.v_listings as
 SELECT l.id, l.ref, l.user_id, l.status, l.section, l.deal, l.property_type, l.governorate_id, l.area_id, l.landmark, l.lat, l.lng,
    l.price_usd, l.orig_price, l.closed_reason, l.price_negotiable, l.area_m2, l.rooms, l.baths, l.floor, l.floors_total, l.year_built,
    l.tabu, l.deed_doc_url, l.condition, l.power_hours, l.generator_amps, l.water_schedule, l.heating, l.finish_level, l.furnished,
    l.lease_months, l.advance_months, l.deposit_usd, l.bills_included, l.amenities, l.description,
    case when coalesce(u.hide_phone,false) then null else l.contact_phone end as contact_phone,
    l.contact_name, l.accepts_whatsapp, l.by_owner, l.views, l.saves, l.created_at, l.updated_at, l.published_at, l.expires_at, l.closed_at,
    l.direction, l.rental_period, l.is_featured, l.featured_from, l.featured_until, l.living_rooms,
    g.name_ar AS governorate_ar, g.name_en AS governorate_en, a.name_ar AS area_ar,
    TRIM(BOTH FROM (COALESCE(u.name, ''::text) || ' '::text) || COALESCE(u.family_name, ''::text)) AS owner_name,
    u.city AS owner_city, u.country AS owner_country, u.username AS owner_username, u.avatar_url AS owner_avatar, u.level AS owner_level,
    round(l.price_usd::numeric / NULLIF(l.area_m2, 0)::numeric) AS price_per_m2,
    ( SELECT count(*) FROM price_history h WHERE h.listing_id = l.id) AS price_changes,
    COALESCE(( SELECT COALESCE(p.thumb_url, p.url) FROM listing_photos p WHERE p.listing_id = l.id AND p.kind = 'photo'::text ORDER BY p.sort_order LIMIT 1),
             ( SELECT p.thumb_url FROM listing_photos p WHERE p.listing_id = l.id AND p.kind = 'video'::text AND COALESCE(p.thumb_url, ''::text) <> ''::text ORDER BY p.sort_order LIMIT 1)) AS cover_url,
    ( SELECT count(*) FROM listing_photos p WHERE p.listing_id = l.id AND p.kind = 'photo'::text) AS photo_count,
    ( SELECT round(avg(r.stars), 1) FROM reviews r WHERE r.target_user = l.user_id) AS owner_rating_avg,
    ( SELECT count(*) FROM reviews r WHERE r.target_user = l.user_id) AS owner_rating_count,
    u.created_at AS owner_created_at, u.card_logo AS owner_card_logo,
    COALESCE(l.country_code, g.country_code) AS country_code,
    ( SELECT count(*) FROM listing_photos p WHERE p.listing_id = l.id AND p.kind = 'video'::text) AS video_count,
    u.account_type AS owner_type,
    ( SELECT ag.id FROM agencies ag WHERE ag.user_id = l.user_id AND ag.status = 'approved'::text LIMIT 1) AS owner_agency_id,
    ( SELECT ag.name FROM agencies ag WHERE ag.user_id = l.user_id AND ag.status = 'approved'::text LIMIT 1) AS owner_agency_name,
    ( SELECT ag.verified FROM agencies ag WHERE ag.user_id = l.user_id AND ag.status = 'approved'::text LIMIT 1) AS owner_agency_verified,
    ( SELECT ag.contact_person FROM agencies ag WHERE ag.user_id = l.user_id AND ag.status = 'approved'::text LIMIT 1) AS owner_agency_person,
    coalesce(u.hide_phone,false) AS owner_hide_phone
   FROM listings l
     JOIN governorates g ON g.id = l.governorate_id
     LEFT JOIN areas a ON a.id = l.area_id
     LEFT JOIN users u ON u.id = l.user_id
  WHERE (l.status = ANY (ARRAY['live'::text, 'pending'::text])) OR (l.status = ANY (ARRAY['sold'::text, 'rented'::text])) AND l.closed_at > (now() - '7 days'::interval);

-- agency directory + page: no phone / WhatsApp when the owner hides; the flag rides along
CREATE OR REPLACE FUNCTION public.bk_public_agencies(p_country text DEFAULT NULL::text)
 RETURNS json LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
  select coalesce(json_agg(row_to_json(x) order by x.verified desc, x.live desc, x.name), '[]'::json) from (
    select a.id, a.user_id, a.name, a.description,
           case when coalesce(u.hide_phone,false) then null else a.phone end as phone,
           case when coalesce(u.hide_phone,false) then null else a.whatsapp end as whatsapp,
           a.email, a.website, a.address, a.gov_names, a.area_names, a.specialties, a.verified, a.created_at, a.country_code,
           u.avatar_url as logo_url, coalesce(u.hide_phone,false) as hide_phone,
           (select count(*) from listings l where l.user_id=a.user_id and l.status='live') as live
      from agencies a join users u on u.id=a.user_id
     where a.status='approved' and not u.blocked and (p_country is null or a.country_code = p_country)) x;
$function$;

CREATE OR REPLACE FUNCTION public.bk_agency_get(p_id bigint)
 RETURNS json LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
  select row_to_json(x) from (
    select a.id, a.user_id, a.name, a.description,
           case when coalesce(u.hide_phone,false) then null else a.phone end as phone,
           case when coalesce(u.hide_phone,false) then null else a.whatsapp end as whatsapp,
           a.email, a.website, a.address, a.gov_names, a.area_names, a.specialties, a.verified, a.created_at, a.contact_person,
           u.avatar_url as logo_url, u.created_at as member_since, coalesce(u.hide_phone,false) as hide_phone,
           (select count(*) from listings l where l.user_id=a.user_id and l.status='live') as live,
           (select count(*) from listings l where l.user_id=a.user_id and l.status in ('sold','rented')) as closed,
           (select bk_reviews_for(u.id)) as reviews
      from agencies a join users u on u.id=a.user_id
     where a.id=p_id and a.status='approved' and not u.blocked) x;
$function$;

-- the bot knows the sender hides (numbers are then stripped from the published text)
CREATE OR REPLACE FUNCTION public.bk_intake_sender(p_source text, p_chat_id text)
 RETURNS json LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
declare cfg jsonb; a agencies; u users; is_admin boolean := false; digits text; wa text; cc text; member_ok boolean := false; member_on boolean;
begin
  cfg := bk_intake_cfg();
  member_on := coalesce(cfg->>'intake_member_listing_on','false') = 'true';
  if p_source = 'telegram' then
    if p_chat_id ~ '^-?\d+$' then select * into a from agencies where intake_telegram = p_chat_id::bigint; end if;
    is_admin := coalesce(cfg->'intake_admin_chats'->'telegram', '[]'::jsonb) ? p_chat_id or exists (select 1 from users where role = 'admin' and tg_chat_id = p_chat_id);
    if a.id is null and not is_admin and member_on then
      select * into u from users
       where tg_chat_id = p_chat_id and role <> 'admin' and coalesce(blocked,false) = false and coalesce(phone_verified,false) = true
       order by tg_paired_at desc nulls last limit 1;
      member_ok := u.id is not null;
      if member_ok then select code into cc from countries where code = upper(u.country); end if;
    end if;
  elsif p_source = 'whatsapp' then
    digits := bk_intake_norm_phone(p_chat_id);
    if digits is not null then
      select ag.* into a from agencies ag
        left join users us on us.id = ag.user_id
        left join countries co on co.code = coalesce(ag.country_code,'SY')
       where ag.status = 'approved' and (
             bk_intake_norm_phone(ag.intake_phone) = digits
          or bk_intake_norm_phone(ag.whatsapp) = digits or bk_intake_norm_phone(ag.phone) = digits
          or bk_intake_norm_phone(us.phone) = digits
          or (length(digits) >= 9 and digits like (regexp_replace(coalesce(co.phone_code,''), '\D', '', 'g') || '%')
              and ((coalesce(ag.whatsapp,'') ~ '^\s*0' or length(bk_intake_norm_phone(ag.whatsapp)) <= 10) and right(bk_intake_norm_phone(ag.whatsapp), 9) = right(digits, 9)
                or (coalesce(ag.phone,'') ~ '^\s*0' or length(bk_intake_norm_phone(ag.phone)) <= 10) and right(bk_intake_norm_phone(ag.phone), 9) = right(digits, 9))))
       order by (bk_intake_norm_phone(ag.intake_phone) = digits) desc nulls last, ag.id limit 1;
      select bk_intake_norm_phone(wa_number) into wa from site_content where id = 1;
      is_admin := (wa is not null and wa = digits)
               or coalesce(cfg->'intake_admin_chats'->'whatsapp', '[]'::jsonb) ? digits
               or exists (select 1 from users where role = 'admin' and bk_intake_norm_phone(phone) = digits);
      if a.id is null and not is_admin and member_on then
        select * into u from users
         where bk_intake_norm_phone(phone) = digits and coalesce(blocked,false) = false and coalesce(phone_verified,false) = true
         order by created_at desc nulls last limit 1;
        member_ok := u.id is not null;
        if member_ok then
          select co.code into cc from countries co
           where co.phone_code is not null and digits like (regexp_replace(co.phone_code, '\D', '', 'g') || '%')
           order by length(regexp_replace(co.phone_code, '\D', '', 'g')) desc limit 1;
        end if;
      end if;
    end if;
  elsif p_source = 'web' then
    select * into u from users where id::text = p_chat_id;
    if u.id is not null then select * into a from agencies where user_id = u.id; is_admin := u.role = 'admin'; end if;
  end if;
  if a.id is not null then select * into u from users where id = a.user_id; end if;
  return json_build_object(
    'agency_id', a.id, 'agency_name', a.name, 'agency_status', a.status,
    'user_id', coalesce(a.user_id, u.id), 'user_name', trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),
    'enabled', coalesce(a.status = 'approved' and a.intake_enabled, false) or is_admin or member_ok,
    'trusted', coalesce(a.intake_trusted, false), 'is_admin', is_admin, 'blocked', coalesce(u.blocked, false),
    'country_code', coalesce(a.country_code, cc, 'SY'), 'lang', coalesce(u.lang, 'ar'), 'member_listing', member_on, 'account_type', u.account_type,
    'hide_phone', coalesce(u.hide_phone, false));
end $function$;

-- the visitor's request: saved, then put in front of the owner three ways (site bell, Telegram, WhatsApp from Balkoun's
-- number). The owner's own number is never part of what the visitor sees. Capped: 3 per listing per visitor phone per day.
create or replace function public.bk_inquiry_send(p_listing bigint, p_to_user uuid, p_name text, p_phone text, p_message text,
                                                   p_kind text default 'visit', p_user uuid default null, p_token text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare l listings; owner uuid; vis_phone text; body text; title text; link text; c contacts; camp uuid; n_today int; cc text;
        owner_tg text; visitor_name text; kind_ar text;
begin
  if p_user is not null then perform bk_require_member(p_token, p_user); end if;
  vis_phone := nullif(regexp_replace(coalesce(p_phone,''), '[^0-9+]', '', 'g'), '');
  if vis_phone is null or length(vis_phone) < 8 then return json_build_object('error','phone'); end if;
  visitor_name := left(trim(coalesce(p_name,'')), 80);
  if visitor_name = '' then return json_build_object('error','name'); end if;
  if p_listing is not null then
    select * into l from listings where id = p_listing and status in ('live','pending');
    if l.id is null then return json_build_object('error','nolisting'); end if;
    owner := l.user_id;
  else
    owner := p_to_user;
  end if;
  if owner is null then return json_build_object('error','noowner'); end if;
  select count(*) into n_today from inquiries where phone = vis_phone and coalesce(property_id,0) = coalesce(p_listing,0) and created_at > now() - interval '24 hours';
  if n_today >= 3 then return json_build_object('error','limit'); end if;
  insert into inquiries (property_id, to_user, from_user, name, phone, message, status)
    values (p_listing, owner, p_user, visitor_name, vis_phone, left(trim(coalesce(p_message,'')), 1000), 'new');
  cc := lower(coalesce(l.country_code, (select country from users where id = owner), 'SY'));
  link := case when l.id is not null then '/listing/' || l.id else null end;
  kind_ar := case when p_kind = 'visit' then 'طلب معاينة' else 'رسالة' end;
  title := case when l.id is not null then kind_ar || ' على إعلانك ' || coalesce(l.ref, '') else kind_ar || ' من زائر' end;
  body := visitor_name || ' · ' || vis_phone || case when coalesce(trim(p_message),'') <> '' then E'\n' || left(trim(p_message), 600) else '' end
          || case when l.id is not null then E'\n' || 'https://balkoun.com' || case when cc = 'sy' then '' else '/' || cc end || '/listing/' || l.id else '' end;
  -- 1) the bell on the site
  insert into notifications (user_id, type, title, body, link) values (owner, 'admin_msg', title, body, link);   -- 'admin_msg' = shown with its own title/body (type list is a check constraint)
  -- 2) Telegram + 3) WhatsApp, through the campaign queue the bot already flushes every minute ("direct: " = no footer)
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
  return json_build_object('ok', true);
end $$;
grant execute on function public.bk_inquiry_send(bigint, uuid, text, text, text, text, uuid, text) to anon, authenticated;
grant execute on function public.bk_set_hide_phone(text, boolean) to anon, authenticated;
