-- Search: chosen areas narrow only their own governorate (owner 2026-11-07).
-- «دمشق + حمص» with «الميدان» chosen used to return Midan only and drop all of Homs; now it is Midan plus all of Homs.
-- Area names repeat across governorates (الميدان ×4, الصناعة ×6), so the area menu sends where each was picked: apick «دمشق|الميدان».
-- gfree = the chosen governorates that have none of the chosen areas (app.html govsFree() / areaPass() do the same).
alter type public.bk_srch_p add attribute gfree text[];
alter type public.bk_srch_p add attribute apick text[];

create or replace function public.bk_srch_parse(p_f jsonb, p_land text[], p_comm text[], p_rooms_max integer)
 returns bk_srch_p
 language plpgsql
 stable
 set search_path to 'public', 'extensions'
as $function$
declare f jsonb := coalesce(p_f, '{}'::jsonb); p public.bk_srch_p;
begin
  p.govs  := case when jsonb_typeof(f->'govs')='array'  and jsonb_array_length(f->'govs')>0  then array(select jsonb_array_elements_text(f->'govs'))
                  when nullif(f->>'g','') is not null then array[f->>'g'] end;
  p.areas := case when jsonb_typeof(f->'areas')='array' and jsonb_array_length(f->'areas')>0 then array(select jsonb_array_elements_text(f->'areas'))
                  when nullif(f->>'a','') is not null then array[f->>'a'] end;
  p.apick := case when jsonb_typeof(f->'apick')='array' and jsonb_array_length(f->'apick')>0 then array(select jsonb_array_elements_text(f->'apick')) end;
  if p.govs is not null and p.areas is not null then
    -- an area counts for the governorate it was picked under; one without a pick counts wherever that name exists
    p.gfree := array(select g from unnest(p.govs) g
                      where not exists (select 1 from unnest(p.areas) an
                                         where case when exists (select 1 from unnest(coalesce(p.apick,'{}')) k where split_part(k,'|',2) = an)
                                                    then (g||'|'||an) = any(p.apick)
                                                    else exists (select 1 from public.areas a join public.governorates gv on gv.id = a.governorate_id
                                                                  where gv.name_ar = g and a.name_ar = an) end));
  end if;
  p.tbs   := case when jsonb_typeof(f->'tbs')='array'   and jsonb_array_length(f->'tbs')>0   then array(select jsonb_array_elements_text(f->'tbs'))
                  when nullif(f->>'tb','') is not null then array[f->>'tb'] end;
  p.tlist := case when jsonb_typeof(f->'types')='array' and jsonb_array_length(f->'types')>0 then array(select jsonb_array_elements_text(f->'types'))
                  when nullif(f->>'t','') is not null then array[f->>'t'] end;
  p.rsel  := case when jsonb_typeof(f->'rooms')='array' and jsonb_array_length(f->'rooms')>0 then array(select (jsonb_array_elements_text(f->'rooms'))::int) end;
  p.deal := nullif(f->>'deal',''); p.sec := nullif(f->>'sec',''); p.cd := nullif(f->>'cd','');
  p.furn := nullif(f->>'furn',''); p.rper := nullif(f->>'rentalPeriod','');
  p.pmin := nullif(nullif(f->>'pmin',''),'0')::numeric; p.pmax := nullif(nullif(f->>'pmax',''),'0')::numeric;
  p.own_only := coalesce((f->>'ownerOnly')::boolean, false); p.share_only := coalesce((f->>'shareOnly')::boolean, false);
  p.words := case when nullif(btrim(coalesce(f->>'kw','')),'') is not null then bk_kw_words(f->>'kw') end;
  if p.words is not null and cardinality(p.words) = 0 then p.words := null; end if;
  p.land := coalesce(p_land, '{}'); p.comm := coalesce(p_comm, '{}'); p.rooms_max := coalesce(p_rooms_max, 7);
  -- not search-page filters: an office's listings, featured only, one listing left out (similar), popular (views > 0)
  p.uid := nullif(f->>'uid','')::uuid; p.feat := coalesce((f->>'featured')::boolean, false);
  p.excl := nullif(f->>'exclude','')::bigint; p.min_views := nullif(f->>'minViews','')::int;
  return p;
end $function$;

create or replace function public.bk_srch_ok(v v_listings, p bk_srch_p)
 returns boolean
 language sql
 stable parallel safe
 set search_path to 'public', 'extensions'
as $function$
  select (p.govs  is null or v.governorate_ar = any(p.govs))
     and (p.areas is null or v.governorate_ar = any(coalesce(p.gfree,'{}'))
          or (coalesce(v.area_ar,'') = any(p.areas)
              and (not exists (select 1 from unnest(coalesce(p.apick,'{}')) k where split_part(k,'|',2) = v.area_ar)
                   or (v.governorate_ar||'|'||v.area_ar) = any(p.apick))))
     and (p.tbs   is null or p.deal = 'rent' or v.tabu = any(p.tbs))
     and (p.cd    is null or v.condition = p.cd)
     and (p.furn  is null or p.deal is distinct from 'rent' or (p.furn = 'yes' and coalesce(v.furnished,false)) or (p.furn = 'no' and not coalesce(v.furnished,false)) or p.furn not in ('yes','no'))
     and (p.rper  is null or p.deal is distinct from 'rent' or coalesce(v.rental_period,'yearly') = p.rper)
     and (p.tlist is null or v.property_type = any(p.tlist) or ('land' = any(p.tlist) and v.property_type = any(p.land)))
     and (p.sec   is null or (p.sec = 'land' and v.property_type = any(p.land)) or (p.sec = 'commercial' and v.property_type = any(p.comm))
                          or (p.sec = 'homes' and not (v.property_type = any(p.land)) and not (v.property_type = any(p.comm))))
     and (p.deal  is null or v.deal = p.deal)
     and (p.pmin  is null or (v.price_usd is not null and v.price_usd >= p.pmin))
     and (p.pmax  is null or (v.price_usd is not null and v.price_usd <= p.pmax))
     and (p.rsel  is null or coalesce(v.rooms,0) = any(p.rsel) or (p.rooms_max = any(p.rsel) and coalesce(v.rooms,0) >= p.rooms_max))
     and (not p.own_only or coalesce(v.by_owner,false))
     and (not p.share_only or 'متاح للمشاركة' = any(coalesce(v.amenities,'{}')))
     and (p.uid is null or v.user_id = p.uid)
     and (not p.feat or coalesce(v.is_featured,false))
     and (p.excl is null or v.id <> p.excl)
     and (p.min_views is null or coalesce(v.views,0) >= p.min_views)
     and (p.words is null or bk_kw_hit(bk_kw_norm(coalesce(v.description,'')||' '||coalesce(v.landmark,'')||' '||coalesce(v.area_ar,'')||' '||coalesce(v.governorate_ar,'')||' '||
                                                    coalesce(array_to_string(v.amenities,' '),'')||' '||coalesce(nullif(v.contact_name,''), v.owner_name, '')), p.words))
$function$;
