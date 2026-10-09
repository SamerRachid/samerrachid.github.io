-- 2026-10-09 — bk_edit and bk_admin_edit_listing both computed the new price as
-- coalesce((p_patch->>'price_usd')::int, l.price_usd) — every OTHER field in these same functions already
-- uses the "was the key even present" pattern (case when p_patch ? 'x' then ... else x end), but price_usd
-- used coalesce, which falls back to the OLD value whenever the new one is null. So a member/admin clearing
-- the price field back to "price on request" silently kept the old price (the client never even sent
-- price_usd=null either — the empty-field branch skipped setting the key entirely; fixed in the same commit,
-- see index.html #eSave). Separately, the live admin UI was observed sending price_usd=0 for "no price",
-- which the listings_price_usd_check constraint (price_usd IS NULL OR price_usd > 0) rejects outright — a
-- real 400 today; the client fix sends null instead.
-- Verified live (rolled-back transactions, no real account touched): clearing to null now persists through
-- a later unrelated-field edit instead of reverting; no constraint violation.
CREATE OR REPLACE FUNCTION public.bk_edit(p_user uuid, p_id bigint, p_patch jsonb, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare l listings; v_old_price int; v_new_price int; v_gid int; v_aid int;
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
  v_old_price := l.price_usd;
  v_new_price := case when p_patch ? 'price_usd' then nullif(p_patch->>'price_usd','')::int else l.price_usd end;

  update listings set
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
    rental_period  = case when p_patch ? 'rental_period'  then nullif(p_patch->>'rental_period','')  else rental_period end,
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

CREATE OR REPLACE FUNCTION public.bk_admin_edit_listing(p_token text, p_id bigint, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; l listings; v_old_price int; v_new_price int; begin uid := bk_admin_uid(p_token); perform bk_admin_guard(uid, (select country_code from listings where id = p_id)); select * into l from listings where id = p_id; if l.id is null then return json_build_object('error','nolisting'); end if; v_old_price := l.price_usd; v_new_price := case when p_patch ? 'price_usd' then nullif(p_patch->>'price_usd','')::int else l.price_usd end; update listings set price_usd = v_new_price, price_local = case when p_patch ? 'price_local' then nullif(p_patch->>'price_local','')::numeric else price_local end, price_cur = case when p_patch ? 'price_cur' then nullif(p_patch->>'price_cur','') else price_cur end, area_m2 = coalesce((p_patch->>'area_m2')::int, area_m2), rooms = case when p_patch ? 'rooms' then (p_patch->>'rooms')::int else rooms end, baths = case when p_patch ? 'baths' then (p_patch->>'baths')::int else baths end, living_rooms = case when p_patch ? 'living_rooms' then (p_patch->>'living_rooms')::int else living_rooms end, floor = case when p_patch ? 'floor' then (p_patch->>'floor')::int else floor end, year_built = case when p_patch ? 'year_built' then (p_patch->>'year_built')::int else year_built end, power_hours = case when p_patch ? 'power_hours' then (p_patch->>'power_hours')::int else power_hours end, tabu = coalesce(p_patch->>'tabu', tabu), condition = coalesce(p_patch->>'condition', condition), description = coalesce(p_patch->>'description', description), landmark = case when p_patch ? 'landmark' then p_patch->>'landmark' else landmark end, lat = case when p_patch ? 'lat' then (p_patch->>'lat')::numeric else lat end, lng = case when p_patch ? 'lng' then (p_patch->>'lng')::numeric else lng end, lease_months = case when p_patch ? 'lease_months' then (p_patch->>'lease_months')::int else lease_months end, advance_months = case when p_patch ? 'advance_months' then (p_patch->>'advance_months')::int else advance_months end, deposit_usd = case when p_patch ? 'deposit_usd' then (p_patch->>'deposit_usd')::int else deposit_usd end, bills_included = case when p_patch ? 'bills_included' then (p_patch->>'bills_included')::boolean else bills_included end, furnished = case when p_patch ? 'furnished' then (p_patch->>'furnished')::boolean else furnished end, direction = case when p_patch ? 'direction' then nullif(p_patch->>'direction','') else direction end, rental_period = case when p_patch ? 'rental_period' then nullif(p_patch->>'rental_period','') else rental_period end, amenities = case when p_patch ? 'amenities' then (select coalesce(array_agg(x), '{}') from jsonb_array_elements_text(p_patch->'amenities') x) else amenities end, contact_phone = coalesce(p_patch->>'contact_phone', contact_phone),
    deal = case when p_patch->>'deal' in ('sale','rent') then p_patch->>'deal' else deal end,
    property_type = case when coalesce(p_patch->>'property_type','') <> '' then p_patch->>'property_type' else property_type end,
    section = case when coalesce(p_patch->>'property_type','') <> '' then (case when p_patch->>'property_type' in ('plot','resid','agri','comm','indust','tourist') then 'land' when p_patch->>'property_type' in ('shop','office','factory','warehouse','clinic','hotel','hall','showroom','station','workshop') then 'commercial' else 'homes' end) else section end,
    governorate_id = case when p_patch ? 'governorate_id' then (p_patch->>'governorate_id')::int else governorate_id end,
    area_id = case when p_patch ? 'area_id' then nullif(p_patch->>'area_id','')::int else area_id end,
    user_id = case when p_patch ? 'user_id' and exists (select 1 from users u2 where u2.id = (p_patch->>'user_id')::uuid) then (p_patch->>'user_id')::uuid else user_id end,
    contact_name = case when p_patch ? 'user_id' then coalesce((select ag.name from agencies ag where ag.user_id = (p_patch->>'user_id')::uuid and ag.status = 'approved' limit 1), (select trim(coalesce(u3.name,'')||' '||coalesce(u3.family_name,'')) from users u3 where u3.id = (p_patch->>'user_id')::uuid), contact_name) else contact_name end
  where id = p_id; if v_new_price is distinct from v_old_price then insert into notifications (user_id, type, title, body, link) select sl.user_id, 'price', 'price_change', l.ref, '/#/listing/'||p_id from saved_listings sl where sl.listing_id = p_id; end if; return json_build_object('ok', true); end $function$;
