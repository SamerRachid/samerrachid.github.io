-- A member can change his own listing's property type from the edit page (owner, 2026-11-02), on top of the
-- sale ⇄ rent switch from earlier today. The section (homes / commercial / land) comes from the page with the type;
-- a let-only type (hotelapt, room) turns the listing into a rental.
CREATE OR REPLACE FUNCTION public.bk_edit(p_user uuid, p_id bigint, p_patch jsonb, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare l listings; v_old_price int; v_new_price int; v_gid int; v_aid int; v_deal text; v_type text; v_sec text;
begin
  perform bk_require_member(p_token, p_user);
  select * into l from listings where id = p_id;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  if l.user_id is distinct from p_user then return json_build_object('error','notyours'); end if;
  v_gid := l.governorate_id; v_aid := l.area_id;
  if p_patch ? 'governorate_id' then
    v_gid := (p_patch->>'governorate_id')::int;
    if not exists (select 1 from governorates g where g.id = v_gid and coalesce(g.country_code,'SY') = coalesce(l.country_code,'SY')) then return json_build_object('error','badgov'); end if;
    v_aid := null;
  end if;
  if p_patch ? 'area_id' then
    v_aid := nullif(p_patch->>'area_id','')::int;
    if v_aid is not null and not exists (select 1 from areas a where a.id = v_aid and a.governorate_id = v_gid) then return json_build_object('error','badarea'); end if;
  end if;
  v_type := l.property_type; v_sec := l.section;
  if coalesce(p_patch->>'property_type','') ~ '^[a-z_]{2,24}$' then
    v_type := p_patch->>'property_type';
    if p_patch->>'section' in ('homes','commercial','land') then v_sec := p_patch->>'section'; end if;
  end if;
  v_deal := l.deal;
  if p_patch ? 'deal' and p_patch->>'deal' in ('sale','rent') then v_deal := p_patch->>'deal'; end if;
  if v_type in ('hotelapt','room') then v_deal := 'rent'; end if;
  v_old_price := l.price_usd;
  v_new_price := case when p_patch ? 'price_usd' then nullif(p_patch->>'price_usd','')::int else l.price_usd end;

  update listings set
    deal        = v_deal,
    property_type = v_type,
    section     = v_sec,
    price_usd   = v_new_price,
    price_local = case when p_patch ? 'price_local' then nullif(p_patch->>'price_local','')::numeric else price_local end,
    price_cur   = case when p_patch ? 'price_cur' then nullif(p_patch->>'price_cur','') else price_cur end,
    area_m2     = coalesce((p_patch->>'area_m2')::int,     area_m2),
    rooms       = case when p_patch ? 'rooms'       then (p_patch->>'rooms')::int       else rooms end,
    baths       = case when p_patch ? 'baths'       then (p_patch->>'baths')::int       else baths end,
    living_rooms = case when p_patch ? 'living_rooms' then (p_patch->>'living_rooms')::int else living_rooms end,
    floor       = case when p_patch ? 'floor'       then (p_patch->>'floor')::int       else floor end,
    year_built  = case when p_patch ? 'year_built'  then (p_patch->>'year_built')::int  else year_built end,
    power_hours = case when p_patch ? 'power_hours' then (p_patch->>'power_hours')::int else power_hours end,
    tabu        = coalesce(p_patch->>'tabu',        tabu),
    condition   = coalesce(p_patch->>'condition',   condition),
    description = coalesce(p_patch->>'description', description),
    governorate_id = v_gid,
    area_id        = v_aid,
    landmark    = case when p_patch ? 'landmark' then p_patch->>'landmark' else landmark end,
    lat         = case when p_patch ? 'lat' then (p_patch->>'lat')::numeric else lat end,
    lng         = case when p_patch ? 'lng' then (p_patch->>'lng')::numeric else lng end,
    lease_months   = case when p_patch ? 'lease_months'   then (p_patch->>'lease_months')::int   else lease_months end,
    advance_months = case when p_patch ? 'advance_months' then (p_patch->>'advance_months')::int else advance_months end,
    deposit_usd    = case when p_patch ? 'deposit_usd'    then (p_patch->>'deposit_usd')::int    else deposit_usd end,
    bills_included = case when p_patch ? 'bills_included' then (p_patch->>'bills_included')::boolean else bills_included end,
    furnished      = case when p_patch ? 'furnished'      then (p_patch->>'furnished')::boolean      else furnished end,
    direction      = case when p_patch ? 'direction'      then nullif(p_patch->>'direction','')      else direction end,
    rental_period  = case when p_patch ? 'rental_period'  then nullif(p_patch->>'rental_period','')
                          when v_deal = 'rent' and l.deal <> 'rent' and rental_period is null then 'monthly'
                          else rental_period end,
    amenities      = case when p_patch ? 'amenities'
                          then (select coalesce(array_agg(x), '{}') from jsonb_array_elements_text(p_patch->'amenities') x)
                          else amenities end,
    contact_phone = coalesce(p_patch->>'contact_phone', contact_phone)
  where id = p_id;

  if v_new_price is distinct from v_old_price then
    insert into notifications (user_id, type, title, body, link)
    select sl.user_id, 'price', 'price_change', l.ref, '/#/listing/'||p_id
      from saved_listings sl where sl.listing_id = p_id;
  end if;

  return json_build_object('ok', true);
end $function$;

select pg_get_functiondef('public.bk_edit(uuid,bigint,jsonb,text)'::regprocedure) like '%v_type%' as type_ready;
