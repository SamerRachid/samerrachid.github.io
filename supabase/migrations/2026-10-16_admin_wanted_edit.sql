-- The admin edits a request from the panel (owner, 2026-10-16): deal, types, governorate, areas, budget, rooms, size,
-- deed, title and text. Same checks as the member's own save (deal and governorate required). Editing never sends a
-- message: new matches are announced when new listings go live, as for any open request.
create or replace function public.bk_admin_wanted_edit(p_token text, p_id bigint, p_data jsonb)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare uid uuid; w wanted; v_types text[]; v_deal text; v_gov text;
begin
  uid := bk_admin_uid(p_token);
  select * into w from wanted where id = p_id;
  if w.id is null then raise exception 'not found'; end if;
  perform bk_admin_guard(uid, w.country_code);
  v_deal := p_data->>'deal';
  if v_deal not in ('sale','rent') then raise exception 'deal required'; end if;
  v_gov := nullif(trim(coalesce(p_data->>'gov_name','')),'');
  if v_gov is null then raise exception 'gov required'; end if;
  v_types := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_data->'property_types','[]'::jsonb)) x), '{}');
  update wanted set
    deal = v_deal, property_types = v_types, property_type = v_types[1], gov_name = v_gov,
    area_names = coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p_data->'area_names','[]'::jsonb)) x), '{}'),
    budget_min = nullif(p_data->>'budget_min','')::numeric, budget_max = nullif(p_data->>'budget_max','')::numeric,
    currency = coalesce(nullif(p_data->>'currency',''), currency, 'USD'),
    rooms_min = nullif(p_data->>'rooms_min','')::int, area_min = nullif(nullif(p_data->>'area_min','')::numeric, 0),
    tabu = case when v_deal = 'rent' then null else nullif(p_data->>'tabu','') end,
    title = nullif(trim(coalesce(p_data->>'title','')),''), description = nullif(trim(coalesce(p_data->>'description','')),''),
    updated_at = now()
  where id = p_id returning * into w;
  return bk_wanted_row(w);
end $f$;
revoke all on function public.bk_admin_wanted_edit(text, bigint, jsonb) from public;
grant execute on function public.bk_admin_wanted_edit(text, bigint, jsonb) to anon, authenticated;
