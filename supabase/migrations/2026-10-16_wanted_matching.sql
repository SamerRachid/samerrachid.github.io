-- Request matching, reworked (owner, 2026-10-16)
--  1. One rule for "this listing fits this request" (bk_wanted_fits), used by the listing trigger and by the scan that
--     runs when a request opens; the site's own list (wantedMatches in index.html) applies the same rule.
--     Same deal; the request's governorate (now required); its types, areas, minimum rooms, minimum size and deed when
--     given; price within budget + 10% in any currency (converted to USD with the country's rate). A listing that does
--     not state its rooms or size does not count as matching a request that asks for them.
--  2. Each (request, listing) pair is told once, recorded in wanted_matches — the old check keyed on the listing OWNER,
--     so a second matching listing from the same office was never announced to anyone.
--  3. When a request opens with many matches, the requester gets ONE message listing them (it was one per listing:
--     SYW1037 got 12), and each listing owner one message for all of theirs. New listings afterwards: one each, as before.
--  4. A request must name its governorate (all 39 existing ones do).

create table if not exists wanted_matches (
  wanted_id  bigint not null references wanted(id) on delete cascade,
  listing_id bigint not null references listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (wanted_id, listing_id)
);
alter table wanted_matches enable row level security;   -- no policies: only the security-definer functions below touch it

-- pairs already announced under the old rule, so nobody is told twice
insert into wanted_matches (wanted_id, listing_id)
select distinct substring(c.title from 'w([0-9]+)/')::bigint, substring(c.title from '/l([0-9]+)')::bigint
  from campaigns c
 where c.title like 'direct: wanted match%' and c.title ~ 'w[0-9]+/l[0-9]+'
   and exists (select 1 from wanted w where w.id = substring(c.title from 'w([0-9]+)/')::bigint)
   and exists (select 1 from listings l where l.id = substring(c.title from '/l([0-9]+)')::bigint)
on conflict do nothing;

-- USD per unit of a request's currency, from the country's rates (Syria: the site's SYP rate as a fallback)
create or replace function public.bk_wanted_rate(p_cc text, p_cur text) returns numeric
language sql stable security definer set search_path to 'public' as $f$
  select case when coalesce(p_cur,'USD') = 'USD' then 1::numeric else
    coalesce(nullif((select (c.rates->>p_cur)::numeric from countries c where c.code = coalesce(p_cc,'SY')), 0),
             case when p_cur = 'SYP' then nullif((select s.syp_rate::numeric from site_content s where s.id = 1), 0) end) end
$f$;

create or replace function public.bk_wanted_fits(w wanted, l listings) returns boolean
language sql stable security definer set search_path to 'public' as $f$
  select w.id is not null and l.id is not null
     and w.status = 'open' and w.expires_at > now() and l.status = 'live'
     and l.user_id <> w.user_id and l.deal = w.deal
     and coalesce(w.gov_name,'') <> ''
     and exists (select 1 from governorates g where g.id = l.governorate_id and g.name_ar = w.gov_name
                   and (w.country_code is null or g.country_code = w.country_code))
     and (cardinality(coalesce(w.property_types,'{}')) = 0 or l.property_type = any(w.property_types))
     and (cardinality(coalesce(w.area_names,'{}')) = 0 or exists (select 1 from areas a where a.id = l.area_id and a.name_ar = any(w.area_names)))
     and (w.rooms_min is null or (l.rooms is not null and l.rooms >= w.rooms_min))
     and (w.area_min is null or (l.area_m2 is not null and l.area_m2 >= w.area_min))
     and (w.tabu is null or w.deal = 'rent' or l.tabu = w.tabu)
     and (w.budget_max is null or l.price_usd is null or bk_wanted_rate(w.country_code, w.currency) is null
          or l.price_usd <= (w.budget_max / bk_wanted_rate(w.country_code, w.currency)) * 1.1)
$f$;

-- one WhatsApp/Telegram message to a member (the same queue and "direct: " convention as before: no marketing footer)
create or replace function public.bk_wanted_msg(p_user uuid, p_title text, p_ar text, p_en text, p_cc text, p_listing bigint)
returns void language plpgsql security definer set search_path to 'public' as $f$
declare c contacts; camp uuid;
begin
  select * into c from contacts where user_id = p_user order by created_at limit 1;
  if c.id is null or (c.tg_chat_id is null and coalesce(c.phone,'') = '') then return; end if;
  insert into campaigns (title, kind, channels, body_ar, body_en, country_code, consent_required, status, created_by, sent_at)
    values (p_title, 'manual', array['whatsapp','telegram'], p_ar, p_en, coalesce(c.country_code, p_cc, 'SY'), false, 'sending', p_user, now())
    returning id into camp;
  if c.tg_chat_id is not null then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', p_listing, c.id, 'telegram', 'queued'); end if;
  if coalesce(c.phone,'') <> '' then insert into campaign_sends (campaign_id, trigger_type, listing_id, contact_id, channel, status) values (camp, 'manual', p_listing, c.id, 'whatsapp', 'queued'); end if;
end $f$;

-- one pair: recorded once; the bell for both sides (the requester's bell can be left to a bundle), and optionally the
-- WhatsApp/Telegram message to each side
drop function if exists public.bk_wanted_ping(bigint, bigint);
create or replace function public.bk_wanted_ping(p_wanted_id bigint, p_listing_id bigint, p_owner_msg boolean default true, p_seeker boolean default true)
returns boolean language plpgsql security definer set search_path to 'public' as $f$
declare w wanted; l listings; wtitle text; link_w text; link_l text;
begin
  select * into w from wanted where id = p_wanted_id;
  select * into l from listings where id = p_listing_id;
  if not coalesce(bk_wanted_fits(w, l), false) then return false; end if;
  insert into wanted_matches (wanted_id, listing_id) values (w.id, l.id) on conflict do nothing;
  if not found then return false; end if;   -- this pair was already announced
  link_w := '/wanted/'||w.id; link_l := '/listing/'||l.id;
  wtitle := coalesce(w.title, 'مطلوب '||case w.deal when 'rent' then 'للإيجار' else 'للشراء' end||' في '||coalesce(w.gov_name,''));

  insert into notifications (user_id, type, title, body, link) values (l.user_id, 'wanted_match', 'طلب جديد يطابق إعلانك', wtitle||coalesce(' · '||w.ref,''), link_w);
  if p_owner_msg then
    perform bk_wanted_msg(l.user_id, 'direct: wanted match (owner) w'||w.id||'/l'||l.id,
      '📋 يوجد طلب شراء/إيجار يطابق إعلانك '||coalesce(l.ref,'')||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'شاهد التفاصيل: https://balkoun.com'||link_w,
      '📋 A matching buy/rent request for your listing '||coalesce(l.ref,'')||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'View it: https://balkoun.com'||link_w,
      coalesce(l.country_code,'SY'), l.id);
  end if;
  if p_seeker then
    insert into notifications (user_id, type, title, body, link) values (w.user_id, 'wanted_listing', 'إعلان جديد يطابق طلبك', coalesce(l.ref,''), link_l);
    perform bk_wanted_msg(w.user_id, 'direct: wanted match (seeker) w'||w.id||'/l'||l.id,
      '🏠 يوجد إعلان يطابق طلبك'||coalesce(' '||w.ref,'')||(case when wtitle<>'' then ' («'||wtitle||'»)' else '' end)||E'\n'||'شاهده: https://balkoun.com'||link_l,
      '🏠 A listing matches your request'||coalesce(' '||w.ref,'')||E'\n'||'View it: https://balkoun.com'||link_l,
      coalesce(w.country_code,'SY'), l.id);
  end if;
  return true;
end $f$;

-- a request opening: every fitting live listing is recorded; ONE message to the requester, ONE per listing owner
create or replace function public.bk_wanted_notify(p_id bigint)
returns integer language plpgsql security definer set search_path to 'public' as $f$
declare w wanted; m record; o record; n int := 0; ids bigint[] := '{}'; lines text := ''; wtitle text; k int := 0;
begin
  select * into w from wanted where id = p_id;
  if w.id is null or w.status <> 'open' then return 0; end if;
  wtitle := coalesce(w.title, 'مطلوب '||case w.deal when 'rent' then 'للإيجار' else 'للشراء' end||' في '||coalesce(w.gov_name,''));
  for m in select l.id from listings l where l.status = 'live' and l.deal = w.deal and bk_wanted_fits(w, l) order by l.created_at desc limit 200 loop
    if bk_wanted_ping(w.id, m.id, false, false) then n := n + 1; ids := ids || m.id; end if;
  end loop;
  if n = 0 then return 0; end if;

  -- the requester: one bell and one message with up to 5 links, then the request page for the rest
  for m in select l.id, l.ref from listings l where l.id = any(ids) order by l.created_at desc limit 5 loop
    lines := lines || E'\n' || '• ' || coalesce(m.ref,'') || ' https://balkoun.com/listing/' || m.id;
  end loop;
  insert into notifications (user_id, type, title, body, link)
    values (w.user_id, 'wanted_listing', n||' إعلان يطابق طلبك', coalesce(w.ref,'')||' · '||wtitle, '/wanted/'||w.id);
  perform bk_wanted_msg(w.user_id, 'direct: wanted match (seeker) w'||w.id||'/bundle',
    '🏠 وجدنا '||n||' إعلان يطابق طلبك'||coalesce(' '||w.ref,'')||' («'||wtitle||'»):'||lines||
      (case when n > 5 then E'\n\n'||'وكل الإعلانات المطابقة هنا: https://balkoun.com/wanted/'||w.id else '' end)||
      E'\n\n'||'وسنرسل لك كل إعلان جديد يطابق طلبك.',
    '🏠 '||n||' listings match your request'||coalesce(' '||w.ref,'')||':'||lines||
      (case when n > 5 then E'\n\n'||'All of them: https://balkoun.com/wanted/'||w.id else '' end),
    coalesce(w.country_code,'SY'), null);

  -- each listing owner: one message naming all their listings that fit
  for o in select l.user_id, string_agg(coalesce(l.ref,'#'||l.id), '، ' order by l.id) refs, count(*) c, min(l.id) first_id, max(l.country_code) cc
             from listings l where l.id = any(ids) group by l.user_id loop
    perform bk_wanted_msg(o.user_id, 'direct: wanted match (owner) w'||w.id||'/bundle',
      '📋 يوجد طلب شراء/إيجار يطابق '||(case when o.c > 1 then 'إعلاناتك ' else 'إعلانك ' end)||o.refs||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'شاهد التفاصيل: https://balkoun.com/wanted/'||w.id,
      '📋 A matching buy/rent request for your listing(s) '||o.refs||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'View it: https://balkoun.com/wanted/'||w.id,
      coalesce(o.cc,'SY'), o.first_id);
  end loop;
  return n;
end $f$;

-- a listing going live: every open request it fits, one pair at a time (both sides told, as before)
create or replace function public.bk_trg_listing_live_wanted()
returns trigger language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare m record;
begin
  if new.status = 'live' and (tg_op = 'INSERT' or old.status is distinct from 'live') then
    for m in select w.id from wanted w where w.status = 'open' and w.expires_at > now() and w.deal = new.deal and bk_wanted_fits(w, new) limit 200 loop
      perform bk_wanted_ping(m.id, new.id);
    end loop;
  end if;
  return new;
end $f$;

-- internal only (the save/approve functions are security definer and call them themselves)
revoke all on function public.bk_wanted_ping(bigint, bigint, boolean, boolean) from public, anon, authenticated;
revoke all on function public.bk_wanted_notify(bigint) from public, anon, authenticated;
revoke all on function public.bk_wanted_msg(uuid, text, text, text, text, bigint) from public, anon, authenticated;
revoke all on function public.bk_wanted_fits(wanted, listings) from public, anon, authenticated;
revoke all on function public.bk_wanted_rate(text, text) from public, anon, authenticated;

-- the governorate is required when a request is saved (the form asks for it too)
CREATE OR REPLACE FUNCTION public.bk_wanted_save(p_token text, p_id bigint, p_data jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; w wanted; v_skip boolean; v_mode text; v_status text; v_c text := nullif(upper(p_data->>'country_code'),'');
        v_types text[];
begin
  uid := bk_member_uid(p_token);
  if uid is null then raise exception 'not signed in'; end if; perform bk_require_verified(uid);
  if p_data->>'deal' not in ('sale','rent') then raise exception 'deal required'; end if;
  if coalesce(trim(p_data->>'gov_name'),'') = '' then raise exception 'gov required'; end if;   -- 2026-10-16: a request names its governorate
  v_types := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_data->'property_types','[]'::jsonb)) x), '{}');
  if cardinality(v_types) = 0 and coalesce(p_data->>'property_type','') <> '' then v_types := array[p_data->>'property_type']; end if;   -- old callers
  select skip_review into v_skip from users where id=uid;
  select extras->>'wanted_approval' into v_mode from site_content where country_code=coalesce(v_c,'SY');
  if v_mode is null then select extras->>'wanted_approval' into v_mode from site_content where id=1; end if;
  v_status := case when coalesce(v_skip,false) or coalesce(v_mode,'auto')='auto' then 'open' else 'pending' end;
  if p_id is null then
    if (select count(*) from wanted where user_id=uid and status in ('open','pending')) >= 5 then raise exception 'limit: 5 open requests'; end if;
    insert into wanted (user_id, deal, property_type, property_types, gov_name, area_names, budget_min, budget_max, currency, rooms_min, area_min, tabu, title, description, contact, status, country_code)
    values (uid, p_data->>'deal', v_types[1], v_types, nullif(p_data->>'gov_name',''),
            coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_data->'area_names','[]'::jsonb)) x), '{}'),
            nullif(p_data->>'budget_min','')::int, nullif(p_data->>'budget_max','')::int, coalesce(nullif(upper(p_data->>'currency'),''),'USD'),
            nullif(p_data->>'rooms_min','')::int, nullif(p_data->>'area_min','')::int, nullif(p_data->>'tabu',''),
            nullif(p_data->>'title',''), nullif(p_data->>'description',''), coalesce(nullif(p_data->>'contact',''),'both'), v_status, coalesce(v_c,'SY'))
    returning * into w;
  else
    update wanted set deal=p_data->>'deal', property_type=v_types[1], property_types=v_types, gov_name=nullif(p_data->>'gov_name',''),
      area_names=coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_data->'area_names','[]'::jsonb)) x), '{}'),
      budget_min=nullif(p_data->>'budget_min','')::int, budget_max=nullif(p_data->>'budget_max','')::int, currency=coalesce(nullif(upper(p_data->>'currency'),''),'USD'),
      rooms_min=nullif(p_data->>'rooms_min','')::int, area_min=nullif(p_data->>'area_min','')::int, tabu=nullif(p_data->>'tabu',''),
      title=nullif(p_data->>'title',''), description=nullif(p_data->>'description',''), contact=coalesce(nullif(p_data->>'contact',''),'both'),
      status = case when status in ('open','hidden','fulfilled') then status else v_status end, updated_at=now(), country_code=coalesce(v_c,country_code)
    where id=p_id and user_id=uid returning * into w;
    if w.id is null then raise exception 'not found'; end if;
  end if;
  if w.status='open' then perform bk_wanted_notify(w.id); end if;
  return bk_wanted_row(w);
end $function$;
