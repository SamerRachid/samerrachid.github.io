-- 2026-10-11: bk_intake_publish refused any property type outside a hard-coded list ('badtype' on «دوبلكس» and on every
-- type the admin adds). It now validates against bk_intake_taxonomy(country) — the same live list the bot reads —
-- and derives the section from the taxonomy's land_types / commercial_types.

CREATE OR REPLACE FUNCTION public.bk_intake_publish(p_draft bigint, p_force_status text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare d intake_drafts; f jsonb; a agencies; u users; tax json; l listings; gid int; aid int; cc text;
        ptype text; sec text; deal text; price numeric; ptxt text; cur text; rate numeric; usd int; m2 int; descr text;
        cond text; tabu text; st text; ph jsonb; i int; phone text; pc text; amen text[]; gname text; aname text;
        rent boolean; deed_ok boolean; ph_int int;
begin
  select * into d from intake_drafts where id = p_draft for update;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if d.listing_id is not null then return json_build_object('error','already','listing_id',d.listing_id,'status',d.status); end if;
  if d.user_id is null then return json_build_object('error','noagency'); end if;
  select * into u from users where id = d.user_id;
  if u.id is null or u.blocked then return json_build_object('error','nouser'); end if;
  if d.agency_id is not null then select * into a from agencies where id = d.agency_id; end if;
  f := coalesce(d.fields, '{}'::jsonb);
  cc := coalesce(nullif(upper(f->>'country_code'),''), d.country_code, 'SY');

  deal := lower(coalesce(f->>'deal','sale')); if deal not in ('sale','rent') then deal := 'sale'; end if;
  rent := deal = 'rent';
  ptype := lower(coalesce(f->>'property_type','apartment'));
  -- the live type list (admin tab «أنواع العقارات» for Syria, countries.types elsewhere), never a hard-coded copy
  tax := bk_intake_taxonomy(cc);
  if not exists (select 1 from json_array_elements(tax->'types') t where t->>'code' = ptype) then
    return json_build_object('error','badtype','value',ptype); end if;
  sec := case when exists (select 1 from json_array_elements_text(tax->'land_types') x where x = ptype) then 'land'
              when exists (select 1 from json_array_elements_text(tax->'commercial_types') x where x = ptype) then 'commercial' else 'homes' end; if ptype = 'hotelapt' then deal := 'rent'; rent := true; end if;

  gid := bk_intake_int(f->>'governorate_id');
  if gid is not null and not exists (select 1 from governorates where id = gid and country_code = cc) then gid := null; end if;
  gname := coalesce(f->>'governorate', f->>'gov');
  if gid is null and gname is not null then
    select id into gid from governorates where country_code = cc and (name_ar = gname or lower(name_en) = lower(gname)) limit 1;
    if gid is null then select id into gid from governorates where country_code = cc and (name_ar like '%'||gname||'%' or gname like '%'||name_ar||'%') order by length(name_ar) limit 1; end if;
  end if;
  if gid is null then return json_build_object('error','nogov'); end if;
  aid := bk_intake_int(f->>'area_id');
  if aid is not null and not exists (select 1 from areas where id = aid and governorate_id = gid) then aid := null; end if;
  aname := f->>'area';
  if aid is null and aname is not null then
    select id into aid from areas where governorate_id = gid and (name_ar = aname or lower(coalesce(name_en,'')) = lower(aname)) limit 1;
    if aid is null then select id into aid from areas where governorate_id = gid and (name_ar like '%'||aname||'%' or aname like '%'||name_ar||'%') order by length(name_ar) limit 1; end if;
  end if;

  ptxt := regexp_replace(coalesce(f->>'price',''), '[^0-9.,]', '', 'g');
  if ptxt ~ '^\d{1,3}(\.\d{3})+$' then ptxt := replace(ptxt, '.', ''); end if;
  ptxt := replace(ptxt, ',', '');
  price := bk_intake_num(ptxt);
  cur := upper(coalesce(nullif(f->>'currency',''), 'USD')); if price is null or price <= 0 then usd := null; elsif cur = 'USD' then usd := round(price);
  else
    tax := bk_intake_taxonomy(cc);
    rate := bk_intake_num(tax->'country'->'rates'->>cur);
    if rate is null or rate <= 0 then return json_build_object('error','norate','currency',cur); end if;
    usd := greatest(1, round(price / rate));
  end if;
  m2 := bk_intake_int(f->>'area_m2');
  if m2 is not null and m2 <= 0 then m2 := null; end if;   -- size optional since 2026-10-02 («تخطي»); shown as "غير مذكورة"

  descr := trim(coalesce(f->>'description',''));
  if length(descr) < 30 then descr := trim(descr || E'\n' || coalesce(d.raw_text,'')); end if;
  if length(descr) < 30 then descr := rpad(descr || ' ' || coalesce(f->>'title',''), 30, '.'); end if;
  descr := left(descr, 1200);

  cond := lower(coalesce(f->>'condition',''));
  if sec = 'land' then if cond not in ('empty','built','fenced','planted') then cond := 'empty'; end if;
  else if cond not in ('intact','deluxe','superdeluxe','old','repair','shell','stripped','damaged') or (cond = 'stripped' and cc <> 'SY') then cond := 'intact'; end if; end if;
  tabu := lower(coalesce(f->>'tabu',''));
  if rent then tabu := null;
  else
    deed_ok := tabu <> '' and exists (select 1 from deed_types dt where dt.country_code = cc and dt.code = tabu);
    if not deed_ok then tabu := null; end if;
  end if;
  select regexp_replace(coalesce(phone_code,''), '\D', '', 'g') into pc from countries where code = cc;
  phone := coalesce(nullif(bk_intake_norm_phone(f->>'contact_phone'),''), bk_intake_norm_phone(a.whatsapp), bk_intake_norm_phone(a.phone), bk_intake_norm_phone(u.phone));
  if phone is null then return json_build_object('error','nophone'); end if;
  if phone ~ '^0' or length(phone) <= 10 then
    phone := regexp_replace(phone, '^0+', '');
    if coalesce(pc,'') <> '' and phone !~ ('^' || pc) then phone := pc || phone; end if;
  end if;
  phone := '+' || phone;
  amen := case when jsonb_typeof(f->'amenities') = 'array' then (select array_agg(x) from jsonb_array_elements_text(f->'amenities') x) else '{}'::text[] end;
  ph_int := bk_intake_int(f->>'power_hours');

  st := coalesce(p_force_status, case when coalesce(u.skip_review,true) or (u.id is null and coalesce(a.intake_trusted,true)) then 'live' else 'pending' end);
  if st not in ('pending','live') then st := 'pending'; end if;

  insert into listings (user_id, status, section, deal, property_type, governorate_id, area_id, landmark, lat, lng,
      price_usd, price_local, price_cur, price_negotiable, area_m2, rooms, baths, living_rooms, floor, floors_total, year_built, tabu, condition,
      power_hours, generator_amps, heating, furnished, lease_months, advance_months, deposit_usd, bills_included, amenities,
      description, contact_phone, contact_name, accepts_whatsapp, by_owner, direction, rental_period, published_at, country_code)
  values (u.id, st, sec, deal, ptype, gid, aid, left(nullif(f->>'landmark',''), 120), bk_intake_num(f->>'lat'), bk_intake_num(f->>'lng'),
      usd, case when cur <> 'USD' and price > 0 then price else null end, case when cur <> 'USD' and price > 0 then cur else null end, bk_intake_bool(f->>'negotiable', true), m2,
      case when sec = 'land' then null else bk_intake_int(f->>'rooms') end,
      case when sec = 'land' then null else bk_intake_int(f->>'baths') end,
      case when ptype in ('apartment','arab','villa') then bk_intake_int(f->>'living_rooms') else null end,
      bk_intake_int(f->>'floor'), bk_intake_int(f->>'floors_total'), bk_intake_int(f->>'year_built'), tabu, cond,
      case when ph_int is null then null else least(24, greatest(0, ph_int)) end, bk_intake_int(f->>'generator_amps'), left(nullif(f->>'heating',''), 60),
      bk_intake_bool(f->>'furnished', false),
      case when rent then bk_intake_int(f->>'lease_months') end, case when rent then bk_intake_int(f->>'advance_months') end,
      case when rent then bk_intake_int(f->>'deposit_usd') end, bk_intake_bool(f->>'bills_included', false), coalesce(amen, '{}'),
      descr, phone, coalesce(a.name, nullif(trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),'')),
      bk_intake_bool(f->>'accepts_whatsapp', true), (d.agency_id is null),
      case when lower(f->>'direction') in ('n','s','e','w','ne','nw','se','sw') then lower(f->>'direction') end,
      case when rent then (case when lower(f->>'rental_period') in ('daily','weekly','monthly','yearly') then lower(f->>'rental_period') else 'yearly' end) end,
      case when st = 'live' then now() end, cc)
  returning * into l;

  ph := coalesce(d.photos, '[]'::jsonb); i := 0;
  for i in 0 .. jsonb_array_length(ph) - 1 loop
    insert into listing_photos (listing_id, url, thumb_url, sort_order, kind, size_bytes, duration_s) values (l.id, ph->i->>'url', ph->i->>'thumb_url', i, coalesce(ph->i->>'kind','photo'), bk_intake_int(ph->i->>'bytes'), bk_intake_int(ph->i->>'duration'));
  end loop;
  update intake_drafts set status = 'published', listing_id = l.id, published_at = now(), updated_at = now(), error = null where id = d.id;
  insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'published', jsonb_build_object('listing_id', l.id, 'ref', l.ref, 'status', l.status, 'photos', jsonb_array_length(ph)));
  return json_build_object('ok', true, 'listing_id', l.id, 'ref', l.ref, 'status', l.status, 'user_id', l.user_id, 'country_code', l.country_code, 'photos', jsonb_array_length(ph));
end $function$
;

-- the same for edits a sender makes through the bot after publishing
CREATE OR REPLACE FUNCTION public.bk_intake_patch_listing(p_draft bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare d intake_drafts; f jsonb; l listings; v_cc text; v_type text; v_sec text; v_deal text; v_rent boolean; ptxt text; v_price numeric; cur text; rate numeric; v_usd int; tax json;
        v_m2 int; v_tabu text; v_cond text; v_aid int; v_descr text;
begin
  select * into d from intake_drafts where id = p_draft;
  if d.id is null or d.listing_id is null then return json_build_object('error','nodraft'); end if;
  select * into l from listings where id = d.listing_id for update;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  f := coalesce(d.fields, '{}'::jsonb); v_cc := coalesce(l.country_code, 'SY');
  v_deal := lower(coalesce(f->>'deal', l.deal)); if v_deal not in ('sale','rent') then v_deal := l.deal; end if; v_rent := v_deal = 'rent';
  v_type := lower(coalesce(f->>'property_type', l.property_type));
  -- the live type list (bk_intake_taxonomy), never a hard-coded copy
  tax := bk_intake_taxonomy(v_cc);
  if not exists (select 1 from json_array_elements(tax->'types') t where t->>'code' = v_type) then v_type := l.property_type; end if;
  v_sec := case when exists (select 1 from json_array_elements_text(tax->'land_types') x where x = v_type) then 'land'
                when exists (select 1 from json_array_elements_text(tax->'commercial_types') x where x = v_type) then 'commercial' else 'homes' end;
  if v_type = 'hotelapt' then v_deal := 'rent'; v_rent := true; end if;
  ptxt := regexp_replace(coalesce(f->>'price',''), '[^0-9.,]', '', 'g');
  if ptxt ~ '^\d{1,3}(\.\d{3})+$' then ptxt := replace(ptxt, '.', ''); end if;
  ptxt := replace(ptxt, ',', ''); v_price := bk_intake_num(ptxt);
  cur := upper(coalesce(nullif(f->>'currency',''), 'USD'));
  if v_price is null or v_price <= 0 then v_usd := null;
  elsif cur = 'USD' then v_usd := round(v_price);
  else tax := bk_intake_taxonomy(v_cc); rate := bk_intake_num(tax->'country'->'rates'->>cur); if rate is null or rate <= 0 then v_usd := l.price_usd; else v_usd := greatest(1, round(v_price / rate)); end if; end if;
  v_m2 := bk_intake_int(f->>'area_m2'); if v_m2 is null or v_m2 <= 0 then v_m2 := l.area_m2; end if;
  v_tabu := lower(coalesce(f->>'tabu',''));
  if v_rent then v_tabu := null; elsif v_tabu = '' or not exists (select 1 from deed_types dt where dt.country_code = v_cc and dt.code = v_tabu) then v_tabu := null; end if;
  v_cond := lower(coalesce(f->>'condition', l.condition, ''));
  if v_sec = 'land' then if v_cond not in ('empty','built','fenced','planted') then v_cond := 'empty'; end if;
  else if v_cond not in ('intact','deluxe','superdeluxe','old','repair','shell','stripped','damaged') or (v_cond = 'stripped' and v_cc <> 'SY') then v_cond := 'intact'; end if; end if;
  v_aid := bk_intake_int(f->>'area_id'); if v_aid is not null and not exists (select 1 from areas where id = v_aid and governorate_id = l.governorate_id) then v_aid := null; end if;
  v_descr := trim(coalesce(f->>'description','')); if length(v_descr) < 30 then v_descr := l.description; end if;
  update listings x set
    section = v_sec, deal = v_deal, property_type = v_type, price_usd = v_usd, price_local = case when cur <> 'USD' and v_price > 0 then v_price else null end, price_cur = case when cur <> 'USD' and v_price > 0 then cur else null end, price_negotiable = bk_intake_bool(f->>'negotiable', l.price_negotiable), area_m2 = v_m2,
    rooms = case when v_sec = 'land' then null else coalesce(bk_intake_int(f->>'rooms'), l.rooms) end,
    baths = case when v_sec = 'land' then null else coalesce(bk_intake_int(f->>'baths'), l.baths) end,
    living_rooms = case when v_type in ('apartment','arab','villa') then coalesce(bk_intake_int(f->>'living_rooms'), l.living_rooms) else null end,
    floor = coalesce(bk_intake_int(f->>'floor'), l.floor), floors_total = coalesce(bk_intake_int(f->>'floors_total'), l.floors_total),
    tabu = v_tabu, condition = v_cond, furnished = bk_intake_bool(f->>'furnished', l.furnished),
    rental_period = case when v_rent then (case when lower(f->>'rental_period') in ('daily','weekly','monthly','yearly') then lower(f->>'rental_period') else coalesce(l.rental_period, 'yearly') end) else null end,
    area_id = coalesce(v_aid, l.area_id), landmark = coalesce(left(nullif(f->>'landmark',''), 120), l.landmark),
    description = left(v_descr, 1200), updated_at = now()
   where x.id = l.id returning * into l;
  insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'listing_patched', jsonb_build_object('listing_id', l.id));
  return json_build_object('ok', true, 'listing_id', l.id, 'ref', l.ref, 'status', l.status, 'country_code', l.country_code);
end $function$
;
