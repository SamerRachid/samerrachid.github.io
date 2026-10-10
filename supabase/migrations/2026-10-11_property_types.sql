-- 2026-10-11: property types editable from the admin (tab «أنواع العقارات»), kept as one JSON array in
-- site_content.extras.property_types (global row): [{code, ar, en, de, fr, sec, order, on}].
-- The intake bot's taxonomy (bk_intake_taxonomy) reads that list for Syria instead of its hard-coded copy, so a type the
-- owner adds (duplex today) is understood by the bot at once; land_types / commercial_types grow with the new type's
-- section. Non-Syrian countries keep their own countries.types list. Also adds "duplex" to the hard-coded fallback.

CREATE OR REPLACE FUNCTION public.bk_intake_taxonomy(p_country text DEFAULT 'SY'::text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare cc text; c countries; types jsonb; rates jsonb; syp int; pt jsonb;
        land_t jsonb := '["plot","resid","agri","comm","indust","tourist"]'::jsonb;
        comm_t jsonb := '["shop","office","factory","warehouse","clinic","hotel","hall","showroom","station","workshop"]'::jsonb;
        base_codes text[] := array['apartment','arab','villa','duplex','floor','building','chalet','restaurant','farm','plot','resid','agri','comm','shop','office','factory','warehouse','hotelapt','clinic','hotel','indust','tourist','house','terrace','hall','showroom','station','workshop'];
begin
  cc := coalesce(nullif(upper(p_country),''), 'SY');
  select * into c from countries where code = cc;
  if c.code is null then select * into c from countries where code = 'SY'; cc := 'SY'; end if;
  types := coalesce(c.types, '[]'::jsonb);
  if jsonb_array_length(types) = 0 then
    -- the admin's list (shown types only, in its order)
    select coalesce(jsonb_agg(jsonb_build_object('code', r->>'code', 'ar', r->>'ar', 'en', coalesce(nullif(r->>'en',''), r->>'ar')) order by coalesce((r->>'order')::numeric, 0)), '[]'::jsonb)
      into pt
      from site_content s, jsonb_array_elements(case when jsonb_typeof(s.extras->'property_types') = 'array' then s.extras->'property_types' else '[]'::jsonb end) r
     where s.id = 1 and coalesce(r->>'on','true') <> 'false' and coalesce(r->>'code','') <> '' and coalesce(r->>'ar','') <> '';
    if pt is not null and jsonb_array_length(pt) > 0 then
      types := pt;
      -- a type the admin added joins the land / commercial family of its section
      select land_t || coalesce(jsonb_agg(to_jsonb(r->>'code')), '[]'::jsonb) into land_t
        from site_content s, jsonb_array_elements(s.extras->'property_types') r
       where s.id = 1 and r->>'sec' = 'land' and not (r->>'code' = any(base_codes)) and coalesce(r->>'on','true') <> 'false';
      select comm_t || coalesce(jsonb_agg(to_jsonb(r->>'code')), '[]'::jsonb) into comm_t
        from site_content s, jsonb_array_elements(s.extras->'property_types') r
       where s.id = 1 and r->>'sec' = 'commercial' and not (r->>'code' = any(base_codes)) and coalesce(r->>'on','true') <> 'false';
    else
      types := '[{"code":"apartment","ar":"شقة","en":"Apartment"},{"code":"arab","ar":"بيت عربي","en":"Arab courtyard house"},{"code":"villa","ar":"فيلا","en":"Villa"},{"code":"duplex","ar":"دوبلكس","en":"Duplex"},{"code":"floor","ar":"طابق كامل","en":"Whole floor"},{"code":"building","ar":"بناء كامل","en":"Whole building"},{"code":"chalet","ar":"شاليه","en":"Chalet"},{"code":"restaurant","ar":"مطعم","en":"Restaurant"},{"code":"farm","ar":"مزرعة","en":"Farm"},{"code":"plot","ar":"أرض","en":"Land"},{"code":"resid","ar":"أرض سكنية","en":"Residential land"},{"code":"agri","ar":"أرض زراعية","en":"Agricultural land"},{"code":"comm","ar":"أرض تجارية","en":"Commercial land"},{"code":"shop","ar":"محل تجاري","en":"Shop"},{"code":"office","ar":"مكتب","en":"Office"},{"code":"factory","ar":"مصنع","en":"Factory"},{"code":"warehouse","ar":"مستودع","en":"Warehouse"},{"code":"hotelapt","ar":"شقة مفروشة فندقية","en":"Serviced apartment"},{"code":"clinic","ar":"عيادة","en":"Clinic"},{"code":"hotel","ar":"فندق ومنشأة سياحية","en":"Hotel & tourism facility"},{"code":"indust","ar":"أرض صناعية","en":"Industrial land"},{"code":"tourist","ar":"أرض سياحية","en":"Tourism land"},{"code":"house","ar":"منزل","en":"House"},{"code":"terrace","ar":"تراس","en":"Terrace apartment"},{"code":"hall","ar":"صالة أفراح ومناسبات","en":"Event hall"},{"code":"showroom","ar":"صالة عرض","en":"Showroom"},{"code":"station","ar":"محطة وقود","en":"Fuel station"},{"code":"workshop","ar":"ورشة","en":"Workshop"}]'::jsonb;
    end if;
  end if;
  rates := coalesce(c.rates, '{}'::jsonb);
  if cc = 'SY' then select syp_rate into syp from site_content where id = 1; if syp > 0 then rates := rates || jsonb_build_object('SYP', syp); end if; end if;
  return json_build_object(
    'country', json_build_object('code', cc, 'name_ar', c.name_ar, 'name_en', c.name_en, 'currencies', c.currencies, 'rates', rates, 'phone_code', c.phone_code),
    'governorates', coalesce((select json_agg(json_build_object('id', g.id, 'ar', g.name_ar, 'en', g.name_en,
        'areas', coalesce((select json_agg(json_build_array(a.id, a.name_ar, a.name_en) order by a.sort_order, a.id) from areas a where a.governorate_id = g.id and coalesce(a.enabled,true)), '[]'::json)) order by g.sort_order, g.id)
        from governorates g where g.country_code = cc and coalesce(g.enabled,true)), '[]'::json),
    'types', types,
    'deeds', coalesce((select json_agg(json_build_object('code', d.code, 'ar', d.name_ar, 'en', d.name_en, 'strong', d.is_strong) order by d.sort_order) from deed_types d where d.country_code = cc and coalesce(d.enabled,true)), '[]'::json),
    'conditions', case when cc = 'SY'
        then '[{"code":"intact","ar":"سليم"},{"code":"deluxe","ar":"ديلوكس"},{"code":"superdeluxe","ar":"سوبر ديلوكس"},{"code":"old","ar":"إكساء قديم"},{"code":"repair","ar":"يحتاج ترميم"},{"code":"shell","ar":"على العظم"},{"code":"stripped","ar":"معفش"},{"code":"damaged","ar":"متضرر"}]'::json
        else '[{"code":"intact","ar":"سليم"},{"code":"deluxe","ar":"ديلوكس"},{"code":"superdeluxe","ar":"سوبر ديلوكس"},{"code":"old","ar":"إكساء قديم"},{"code":"repair","ar":"يحتاج ترميم"},{"code":"shell","ar":"على العظم"},{"code":"damaged","ar":"متضرر"}]'::json end,
    'land_conditions', '[{"code":"empty","ar":"أرض فارغة"},{"code":"built","ar":"عليها بناء"},{"code":"fenced","ar":"مسوّرة"},{"code":"planted","ar":"مزروعة"}]'::json,
    'amenities', '["مصعد","موقف سيارات","تدفئة مركزية","خزّان مياه","اشتراك مولّدة","حارس","إنترنت","باب أمان","شرفة","تكييف","طاقة بديلة"]'::json,
    'land_amenities', '["سور","بئر ماء","كهرباء واصلة","ماء واصل","طريق معبّد","أرض مستوية","داخل التنظيم","مفرزة","إطلالة","قريبة من الطريق العام"]'::json,
    'directions', '[{"code":"s","ar":"قبلي (جنوبي)"},{"code":"n","ar":"شمالي"},{"code":"e","ar":"شرقي"},{"code":"w","ar":"غربي"},{"code":"se","ar":"قبلي شرقي"},{"code":"sw","ar":"قبلي غربي"},{"code":"ne","ar":"شمالي شرقي"},{"code":"nw","ar":"شمالي غربي"}]'::json,
    'rental_periods', '["yearly","monthly","weekly","daily"]'::json,
    'land_types', land_t,
    'commercial_types', comm_t);
end $function$;
