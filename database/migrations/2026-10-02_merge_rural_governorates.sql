-- Balkoun · 2026-10-02 · merging a "rural" governorate into its city governorate (owner's decision: official
-- administration has one governorate per city; Damascus / Rif Dimashq stay separate because they really are two).
-- One governorate at a time, at night in Syria. Nothing is deleted: the rural row stays, disabled, pointing at the
-- city row (merged_into) so its old URLs can redirect.
--
-- bk_admin_merge_gov(rural, city):
--   areas        → governorate_id = city; kind becomes 'city' for towns, 'village' for villages (from the OSM/Wikidata
--                  place tag kept in area_suggestions), untouched otherwise. A rural area whose name already exists in
--                  the city governorate is folded into it (its listings re-pointed, the duplicate area disabled).
--   listings, contacts, campaigns, area_suggestions → governorate_id = city
--   wanted.gov_name, projects.gov_name → city name;  agencies.gov_names → rural name replaced by city name (deduped)
--   governorates(rural) → enabled = false, merged_into = city
-- DONE 2026-10-02: حماة (8→7) first, then حلب 4→3, حمص 6→5, اللاذقية 10→9, طرطوس 12→11, إدلب 14→13, درعا 16→15,
-- دير الزور 20→19, الرقة 22→21, الحسكة 24→23. Damascus (1) and Rif Dimashq (2) untouched by the owner's choice.
-- Suggested areas approved for every merged governorate + السويداء and القنيطرة (Damascus/Rif suggestions left pending).
alter table public.governorates add column if not exists merged_into int references governorates(id);

create or replace function public.bk_admin_merge_gov(p_token text, p_rural int, p_city int) returns json
language plpgsql security definer set search_path to 'public' as $$
declare uid uuid; r governorates; c governorates; a record; dup_id int; n_areas int := 0; n_dup int := 0; n_list int := 0; n_ag int := 0; n_w int := 0; n_p int := 0; n_s int := 0; n_c int := 0;
begin
  uid := bk_admin_uid(p_token);
  select * into r from governorates where id = p_rural; select * into c from governorates where id = p_city;
  if r.id is null or c.id is null or r.country_code <> c.country_code or r.id = c.id then return json_build_object('error','badpair'); end if;
  perform bk_admin_guard(uid, c.country_code);
  if r.merged_into is not null then return json_build_object('error','already','into',r.merged_into); end if;
  -- areas: fold duplicates, move the rest
  for a in select * from areas where governorate_id = p_rural loop
    select id into dup_id from areas where governorate_id = p_city and bk_area_norm(name_ar) = bk_area_norm(a.name_ar) limit 1;
    if dup_id is not null then
      update listings set area_id = dup_id where area_id = a.id;
      update contacts set area_id = dup_id where area_id = a.id;
      update area_suggestions set area_id = dup_id where area_id = a.id;
      update areas set lat = coalesce(lat, a.lat), lng = coalesce(lng, a.lng) where id = dup_id;
      update areas set enabled = false, governorate_id = p_city, slug = slug || '-merged-' || a.id where id = a.id;
      n_dup := n_dup + 1;
    else
      update areas set governorate_id = p_city,
        kind = case when kind = 'city' then 'city'
                    when exists (select 1 from area_suggestions s where s.area_id = a.id and s.place in ('town','city')) then 'city'
                    when exists (select 1 from area_suggestions s where s.area_id = a.id and s.place in ('village','hamlet')) then 'village'
                    when kind = 'area' then 'village' else kind end
       where id = a.id;
      -- a slug clash inside the city list gets a suffix
      if exists (select 1 from areas x where x.governorate_id = p_city and x.slug = a.slug and x.id <> a.id) then update areas set slug = slug || '-' || a.id where id = a.id; end if;
      n_areas := n_areas + 1;
    end if;
  end loop;
  update listings set governorate_id = p_city where governorate_id = p_rural; get diagnostics n_list = row_count;
  update contacts set governorate_id = p_city where governorate_id = p_rural; get diagnostics n_c = row_count;
  update campaigns set governorate_id = p_city where governorate_id = p_rural;
  update wanted set gov_name = c.name_ar where gov_name = r.name_ar; get diagnostics n_w = row_count;
  update projects set gov_name = c.name_ar where gov_name = r.name_ar; get diagnostics n_p = row_count;
  update agencies set gov_names = (select array_agg(distinct x order by x) from unnest(array_replace(gov_names, r.name_ar, c.name_ar)) x) where r.name_ar = any(gov_names); get diagnostics n_ag = row_count;
  -- pending suggestions move too; a suggested name now present in the city list is dropped
  update area_suggestions set governorate_id = p_city where governorate_id = p_rural and status = 'pending'; get diagnostics n_s = row_count;
  update area_suggestions s set status = 'rejected', updated_at = now() where s.status = 'pending' and s.kind = 'new' and s.governorate_id = p_city
     and exists (select 1 from areas x where x.governorate_id = p_city and x.enabled and bk_area_norm(x.name_ar) = bk_area_norm(s.name_ar));
  update governorates set enabled = false, merged_into = p_city where id = p_rural;
  return json_build_object('ok', true, 'areas_moved', n_areas, 'areas_folded', n_dup, 'listings', n_list, 'agencies', n_ag, 'wanted', n_w, 'projects', n_p, 'contacts', n_c, 'suggestions', n_s);
end $$;
grant execute on function public.bk_admin_merge_gov(text, int, int) to anon, authenticated;

-- bk_geo: the public geo payload also lists merged slugs so the site can redirect /for-sale/rural-hama/ → /for-sale/hama/
create or replace function public.bk_geo(p_country text default 'SY') returns json
language sql stable security definer set search_path to 'public' as $$
  select json_build_object(
    'g', (select coalesce(json_agg(json_build_array(g.id, g.name_ar, g.name_en, g.slug, g.lat, g.lng) order by g.sort_order, g.id), '[]'::json) from governorates g where g.enabled and g.country_code = coalesce(p_country,'SY')),
    'a', (select coalesce(json_agg(json_build_array(a.id, a.governorate_id, a.name_ar, a.name_en, a.slug, a.kind, a.lat, a.lng) order by a.governorate_id, a.sort_order, a.id), '[]'::json) from areas a join governorates g on g.id=a.governorate_id where a.enabled and g.enabled and g.country_code = coalesce(p_country,'SY')),
    'm', (select coalesce(json_object_agg(r.slug, json_build_array(c.slug, r.name_ar, c.name_ar)), '{}'::json) from governorates r join governorates c on c.id = r.merged_into where r.country_code = coalesce(p_country,'SY')),
    'country', coalesce(p_country,'SY'))
$$;
