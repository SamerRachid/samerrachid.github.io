-- The free «املأ الحقول» reader on the post page uses the places the bot has learned ("جامع المصطفى" → الصناعة).
-- Read-only, phrases + governorate + area names only (no ids, no counts, no who-sent-it). Anyone may call it.
create or replace function public.bk_intake_places_public(p_country text default 'SY') returns json
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(json_agg(json_build_array(p.phrase, g.name_ar, a.name_ar) order by p.hits desc, p.id), '[]'::json)
    from intake_places p
    join governorates g on g.id = p.governorate_id
    join areas a on a.id = p.area_id and a.enabled
   where p.country_code = upper(coalesce(nullif(p_country, ''), 'SY'))
     and length(p.phrase) between 3 and 80;
$$;
revoke all on function public.bk_intake_places_public(text) from public;
grant execute on function public.bk_intake_places_public(text) to anon, authenticated;
select json_array_length(public.bk_intake_places_public('SY')) as learned_places;
