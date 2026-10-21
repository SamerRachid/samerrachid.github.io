-- Server-side search, step 1 (owner, 2026-10-21): the site loads at most the newest 1,000 listings per country into the
-- browser and filters them there (passesFilter / rsResults in index.html). bk_search does the same filtering, sorting
-- and paging in the database so the site can grow to 100,000+ listings. NOTHING on the site calls it yet: it is built
-- alongside the current path and compared result-for-result before any page switches to it.
--
-- p_f carries the site's filter object F as-is (govs/g, areas/a, tbs/tb, cd, furn, rentalPeriod, types/t, sec, deal,
-- pmin, pmax, rooms, ownerOnly, shareOnly, kw). p_land / p_comm are the country's land and commercial type codes as the
-- site has them (built-ins + the panel's own types), so «أراضٍ» and the sections mean exactly what they mean on the page.
begin;

-- the same text folding as kwNorm() on the page: no harakat / tatweel, أإآ→ا, ة→ه, ى→ي, lower case, single spaces
create or replace function public.bk_kw_norm(s text)
 returns text language sql immutable parallel safe set search_path to 'public','extensions' as $fn$
  select btrim(regexp_replace(lower(translate(regexp_replace(coalesce(s,''), '[ً-ْـ]', '', 'g'), 'أإآةى', 'اااهي')), '\s+', ' ', 'g'))
$fn$;

-- every search word must appear in the listing's text (or the word without a leading و / ب / ل / ال …), like kwMatch()
create or replace function public.bk_kw_words(q text)
 returns text[] language sql immutable parallel safe set search_path to 'public','extensions' as $fn$
  select coalesce(array_agg(w), '{}') from unnest(string_to_array(bk_kw_norm(q), ' ')) w
   where length(w) > 1 and w !~ '^(في|من|على|قرب|بجانب|جنب|عند|حول|بين|مع|near|in|at|by|the|of|to)$'
$fn$;

create or replace function public.bk_kw_hit(hay text, words text[])
 returns boolean language sql immutable parallel safe set search_path to 'public','extensions' as $fn$
  select not exists (
    select 1 from unnest(words) w
     where not (strpos(hay, w) > 0
                or (length(regexp_replace(w, '^(وال|بال|لل|ال|و|ب|ل)', '')) > 1
                    and strpos(hay, regexp_replace(w, '^(وال|بال|لل|ال|و|ب|ل)', '')) > 0)))
$fn$;

create or replace function public.bk_search(
  p_country text, p_f jsonb, p_land text[], p_comm text[],
  p_sort text default 'new', p_offset integer default 0, p_limit integer default 24,
  p_user uuid default null, p_token text default null, p_rooms_max integer default 7)
returns json language plpgsql volatile security definer set search_path to 'public','extensions' as $fn$
#variable_conflict use_variable
declare
  f jsonb := coalesce(p_f, '{}'::jsonb);
  me uuid;
  govs text[]; areas text[]; tbs text[]; tlist text[]; rsel int[]; words text[];
  deal text := nullif(f->>'deal',''); sec text := nullif(f->>'sec','');
  cd text := nullif(f->>'cd',''); furn text := nullif(f->>'furn',''); rper text := nullif(f->>'rentalPeriod','');
  pmin numeric := nullif(nullif(f->>'pmin',''),'0')::numeric; pmax numeric := nullif(nullif(f->>'pmax',''),'0')::numeric;
  own_only boolean := coalesce((f->>'ownerOnly')::boolean, false); share_only boolean := coalesce((f->>'shareOnly')::boolean, false);
  land text[] := coalesce(p_land, '{}'); comm text[] := coalesce(p_comm, '{}');
  lim int := least(greatest(coalesce(p_limit, 24), 1), 200); off int := greatest(coalesce(p_offset, 0), 0);
  res json;
begin
  -- the poster's own pending listings show to them only, as on the page (a valid member session is required)
  if p_user is not null and p_token is not null then
    begin perform bk_require_member(p_token, p_user); me := p_user; exception when others then me := null; end;
  end if;
  govs  := case when jsonb_typeof(f->'govs')='array'  and jsonb_array_length(f->'govs')>0  then array(select jsonb_array_elements_text(f->'govs'))
                when nullif(f->>'g','') is not null then array[f->>'g'] end;
  areas := case when jsonb_typeof(f->'areas')='array' and jsonb_array_length(f->'areas')>0 then array(select jsonb_array_elements_text(f->'areas'))
                when nullif(f->>'a','') is not null then array[f->>'a'] end;
  tbs   := case when jsonb_typeof(f->'tbs')='array'   and jsonb_array_length(f->'tbs')>0   then array(select jsonb_array_elements_text(f->'tbs'))
                when nullif(f->>'tb','') is not null then array[f->>'tb'] end;
  tlist := case when jsonb_typeof(f->'types')='array' and jsonb_array_length(f->'types')>0 then array(select jsonb_array_elements_text(f->'types'))
                when nullif(f->>'t','') is not null then array[f->>'t'] end;
  rsel  := case when jsonb_typeof(f->'rooms')='array' and jsonb_array_length(f->'rooms')>0 then array(select (jsonb_array_elements_text(f->'rooms'))::int) end;
  words := case when nullif(btrim(coalesce(f->>'kw','')),'') is not null then bk_kw_words(f->>'kw') end;
  if words is not null and cardinality(words) = 0 then words := null; end if;

  with hit as (
    select v.* from v_listings v
     where v.country_code = coalesce(p_country,'SY')
       and (v.status = 'live' or (v.status = 'pending' and me is not null and v.user_id = me))
       and (govs  is null or v.governorate_ar = any(govs))
       and (areas is null or coalesce(v.area_ar,'') = any(areas))
       and (tbs   is null or deal = 'rent' or v.tabu = any(tbs))
       and (cd    is null or v.condition = cd)
       and (furn  is null or deal is distinct from 'rent' or (furn = 'yes' and coalesce(v.furnished,false)) or (furn = 'no' and not coalesce(v.furnished,false)) or furn not in ('yes','no'))
       and (rper  is null or deal is distinct from 'rent' or coalesce(v.rental_period,'yearly') = rper)
       and (tlist is null or v.property_type = any(tlist) or ('land' = any(tlist) and v.property_type = any(land)))
       and (sec   is null or (sec = 'land' and v.property_type = any(land)) or (sec = 'commercial' and v.property_type = any(comm))
                          or (sec = 'homes' and not (v.property_type = any(land)) and not (v.property_type = any(comm))))
       and (deal  is null or v.deal = deal)
       and (pmin  is null or (v.price_usd is not null and v.price_usd >= pmin))
       and (pmax  is null or (v.price_usd is not null and v.price_usd <= pmax))
       and (rsel  is null or coalesce(v.rooms,0) = any(rsel) or (p_rooms_max = any(rsel) and coalesce(v.rooms,0) >= p_rooms_max))
       and (not own_only or coalesce(v.by_owner,false))
       and (not share_only or 'متاح للمشاركة' = any(coalesce(v.amenities,'{}')))
       and (words is null or bk_kw_hit(bk_kw_norm(coalesce(v.description,'')||' '||coalesce(v.landmark,'')||' '||coalesce(v.area_ar,'')||' '||coalesce(v.governorate_ar,'')||' '||
                                                  coalesce(array_to_string(v.amenities,' '),'')||' '||coalesce(nullif(v.contact_name,''), v.owner_name, '')), words))
  ), page as (
    select h.* from hit h
     order by coalesce(h.is_featured,false) desc,
              case when p_sort = 'lo' then h.price_usd end asc nulls last,
              case when p_sort = 'hi' then h.price_usd end desc nulls last,
              case when p_sort = 'area' then h.area_m2 end desc nulls last,
              h.created_at desc, h.id desc
     offset off limit lim
  )
  select json_build_object('total', (select count(*) from hit), 'offset', off, 'limit', lim,
                           'rows', coalesce((select json_agg(row_to_json(p)) from page p), '[]'::json))
    into res;
  return res;
end $fn$;
revoke all on function public.bk_search(text,jsonb,text[],text[],text,integer,integer,uuid,text,integer) from public;
grant execute on function public.bk_search(text,jsonb,text[],text[],text,integer,integer,uuid,text,integer) to anon, authenticated;

-- the filters and sort the search uses most: country + status first, then the deal and the newest
create index if not exists listings_search_main_idx on public.listings (country_code, status, deal, created_at desc);
create index if not exists listings_search_type_idx on public.listings (country_code, status, property_type);
commit;
