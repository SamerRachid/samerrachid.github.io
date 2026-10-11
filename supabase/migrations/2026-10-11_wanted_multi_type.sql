-- 2026-10-11: a "wanted" (مطلوب) request can now ask for several property types at once (e.g. "apartment OR
-- house"), the same way it already lets someone pick several areas. New array column `property_types`; the old
-- single `property_type` column is kept and kept in sync (first chosen type) for anything that still reads it,
-- but matching/display now run on the array. Empty array = any type (same convention as gov_name/area_names).

alter table public.wanted add column if not exists property_types text[] not null default '{}'::text[];
update public.wanted set property_types = array[property_type] where property_type is not null and cardinality(property_types) = 0;

CREATE OR REPLACE FUNCTION public.bk_wanted_row(w wanted)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
  select json_build_object(
    'id', w.id, 'user_id', w.user_id, 'deal', w.deal, 'property_type', w.property_type,
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
       and (cardinality(w.property_types)=0 or l.property_type = any(w.property_types))
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
         and (cardinality(w.property_types)=0 or new.property_type = any(w.property_types))
         and (w.budget_max is null or w.currency<>'USD' or new.price_usd is null or new.price_usd <= w.budget_max*1.1)
         and (cardinality(w.area_names)=0 or exists (select 1 from areas a where a.id=new.area_id and a.name_ar = any(w.area_names)))
       limit 200
    loop
      perform bk_wanted_ping(m.id, new.id);
    end loop;
  end if;
  return new;
end $function$;
