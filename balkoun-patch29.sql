-- balkoun-patch29.sql
-- Additive. Safe to re-run.
-- The edit form was missing the amenities checklist, the bills/
-- furnished checkboxes for rentals, and incorrectly showed the title
-- deed field for rentals (deed status isn't relevant when renting).
-- bills_included/furnished were already supported by bk_edit;
-- amenities was not — this adds it. Every other line below is
-- copied verbatim from the current, verified version in patch22.sql.

create or replace function bk_edit(p_user uuid, p_id bigint, p_patch jsonb)
returns json language plpgsql security definer as $$
declare l listings; v_old_price int; v_new_price int;
begin
  select * into l from listings where id = p_id;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  if l.user_id is distinct from p_user then return json_build_object('error','notyours'); end if;
  v_old_price := l.price_usd;
  v_new_price := coalesce((p_patch->>'price_usd')::int, l.price_usd);

  update listings set
    price_usd   = v_new_price,
    area_m2     = coalesce((p_patch->>'area_m2')::int,     area_m2),
    rooms       = case when p_patch ? 'rooms'       then (p_patch->>'rooms')::int       else rooms end,
    baths       = case when p_patch ? 'baths'       then (p_patch->>'baths')::int       else baths end,
    floor       = case when p_patch ? 'floor'       then (p_patch->>'floor')::int       else floor end,
    year_built  = case when p_patch ? 'year_built'  then (p_patch->>'year_built')::int  else year_built end,
    power_hours = case when p_patch ? 'power_hours' then (p_patch->>'power_hours')::int else power_hours end,
    tabu        = coalesce(p_patch->>'tabu',        tabu),
    condition   = coalesce(p_patch->>'condition',   condition),
    description = coalesce(p_patch->>'description', description),
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
end $$;
grant execute on function bk_edit(uuid,bigint,jsonb) to anon, authenticated;

select pg_notification_queue_usage();
