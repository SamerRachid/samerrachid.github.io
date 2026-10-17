-- Lebanon property types (35, with section and German) and ownership statuses (9) from research on Lebanese portals and law (2026-10-17);
-- the intake taxonomy files a country's own land/commercial codes by their «sec». Syria (countries.types null) is unaffected.
begin;
update countries set types='[{"code":"apartment","ar":"شقة","en":"Apartment","fr":"Appartement","de":"Wohnung","sec":"homes"},{"code":"gardenapt","ar":"شقة مع حديقة (أرضي)","en":"Garden apartment","fr":"Appartement avec jardin (rez-de-jardin)","de":"Gartenwohnung","sec":"homes"},{"code":"duplex","ar":"دوبلكس","en":"Duplex","fr":"Duplex","de":"Maisonette","sec":"homes"},{"code":"triplex","ar":"تريبلكس","en":"Triplex","fr":"Triplex","de":"Triplex-Wohnung","sec":"homes"},{"code":"terrace","ar":"روف (شقة على السطح مع تراس)","en":"Rooftop apartment (roof)","fr":"Appartement sur le toit (roof)","de":"Dachterrassenwohnung","sec":"homes"},{"code":"penthouse","ar":"بنتهاوس","en":"Penthouse","fr":"Penthouse","de":"Penthouse","sec":"homes"},{"code":"studio","ar":"استوديو","en":"Studio","fr":"Studio","de":"Einzimmerwohnung (Studio)","sec":"homes"},{"code":"hotelapt","ar":"شقة مفروشة فندقية","en":"Serviced apartment","fr":"Appartement hôtelier meublé","de":"Serviced-Apartment","sec":"homes"},{"code":"room","ar":"غرفة","en":"Room","fr":"Chambre","de":"Zimmer","sec":"homes"},{"code":"floor","ar":"طابق كامل","en":"Whole floor","fr":"Étage entier","de":"Ganze Etage","sec":"homes"},{"code":"house","ar":"بيت مستقل","en":"Detached house","fr":"Maison individuelle","de":"Einfamilienhaus","sec":"homes"},{"code":"arab","ar":"بيت لبناني تراثي (قرميد وقناطر)","en":"Traditional Lebanese house","fr":"Maison libanaise traditionnelle","de":"Traditionelles libanesisches Haus","sec":"homes"},{"code":"villa","ar":"فيلا","en":"Villa","fr":"Villa","de":"Villa","sec":"homes"},{"code":"chalet","ar":"شاليه (بحري أو جبلي)","en":"Chalet (beach or mountain)","fr":"Chalet (bord de mer ou montagne)","de":"Chalet (Strand oder Berg)","sec":"homes"},{"code":"building","ar":"بناية كاملة","en":"Whole building","fr":"Immeuble entier","de":"Ganzes Gebäude","sec":"homes"},{"code":"shop","ar":"محل تجاري","en":"Shop","fr":"Local commercial (magasin)","de":"Ladenlokal","sec":"commercial"},{"code":"office","ar":"مكتب","en":"Office","fr":"Bureau","de":"Büro","sec":"commercial"},{"code":"clinic","ar":"عيادة / مركز طبي","en":"Clinic / medical centre","fr":"Cabinet médical / centre médical","de":"Praxis / Ärztezentrum","sec":"commercial"},{"code":"restaurant","ar":"مطعم / مقهى / ملهى","en":"Restaurant, café or pub","fr":"Restaurant, café ou bar","de":"Restaurant, Café oder Bar","sec":"commercial"},{"code":"hotel","ar":"فندق / بيت ضيافة / منتجع","en":"Hotel, guesthouse or resort","fr":"Hôtel, maison d''hôtes ou complexe","de":"Hotel, Gästehaus oder Resort","sec":"commercial"},{"code":"hall","ar":"صالة أفراح ومناسبات","en":"Event hall","fr":"Salle des fêtes","de":"Festsaal","sec":"commercial"},{"code":"showroom","ar":"صالة عرض","en":"Showroom","fr":"Salle d''exposition (showroom)","de":"Ausstellungsraum","sec":"commercial"},{"code":"warehouse","ar":"مستودع","en":"Warehouse","fr":"Entrepôt (dépôt)","de":"Lagerhalle","sec":"commercial"},{"code":"workshop","ar":"ورشة","en":"Workshop","fr":"Atelier","de":"Werkstatt","sec":"commercial"},{"code":"factory","ar":"مصنع / معمل","en":"Factory","fr":"Usine","de":"Fabrik","sec":"commercial"},{"code":"parking","ar":"موقف سيارات / كاراج","en":"Parking space or garage","fr":"Parking ou garage","de":"Stellplatz oder Garage","sec":"commercial"},{"code":"school","ar":"مدرسة / حضانة","en":"School or nursery","fr":"École ou crèche","de":"Schule oder Kita","sec":"commercial"},{"code":"station","ar":"محطة وقود","en":"Fuel station","fr":"Station-service","de":"Tankstelle","sec":"commercial"},{"code":"plot","ar":"أرض","en":"Land","fr":"Terrain","de":"Grundstück","sec":"land"},{"code":"resid","ar":"أرض سكنية","en":"Residential land","fr":"Terrain résidentiel","de":"Wohngrundstück","sec":"land"},{"code":"agri","ar":"أرض زراعية","en":"Agricultural land","fr":"Terrain agricole","de":"Agrarland","sec":"land"},{"code":"comm","ar":"أرض تجارية","en":"Commercial land","fr":"Terrain commercial","de":"Gewerbegrundstück","sec":"land"},{"code":"indust","ar":"أرض صناعية","en":"Industrial land","fr":"Terrain industriel","de":"Industriegrundstück","sec":"land"},{"code":"tourist","ar":"أرض سياحية","en":"Tourism land","fr":"Terrain touristique","de":"Tourismusgrundstück","sec":"land"},{"code":"farm","ar":"بستان / مزرعة","en":"Orchard or farm","fr":"Verger ou ferme","de":"Obstgarten oder Hof","sec":"land"}]'::jsonb, updated_at=now() where code='LB';
delete from deed_types where country_code='LB';
insert into deed_types(country_code,code,name_ar,name_en,name_de,name_fr,is_strong,enabled,sort_order) values
('LB','title','سند أخضر مفرز (سند تمليك باسم البائع)','Green title deed (registered, own unit/plot)','Grüner Eigentumstitel (eingetragen, eigene Einheit)','Titre vert (titre de propriété enregistré, lot séparé)',true,true,1),
('LB','shares','أسهم في عقار غير مفرز (على الشيوع)','Shares in an undivided property','Miteigentumsanteile an ungeteiltem Grundstück','Parts indivises (sur 2400 parts)',false,true,2),
('LB','ifraz','قيد الإفراز (بناء جديد، السند المفرز قيد الإصدار)','Partition in progress (new building, unit title pending)','Teilung läuft (Neubau, Einzeltitel ausstehend)','En cours de « ifraz » (division en lots, titre en attente)',false,true,3),
('LB','promise','وعد بالبيع مسجّل (قيد احتياطي)','Sale promise with provisional registration','Kaufversprechen mit Vormerkung','Promesse de vente inscrite (inscription provisoire)',false,true,4),
('LB','contract','عقد بيع لدى الكاتب العدل (غير مسجّل بعد)','Notarised sale contract (not yet registered)','Notarieller Kaufvertrag (noch nicht eingetragen)','Contrat de vente notarié (non encore inscrit)',false,true,5),
('LB','poa','وكالة بيع غير قابلة للعزل','Irrevocable power of attorney','Unwiderrufliche Verkaufsvollmacht','Procuration irrévocable',false,true,6),
('LB','inherit','إرث غير مسجّل (بحاجة لحصر إرث وقيد انتقال)','Inherited, not yet registered to heirs','Geerbt, noch nicht auf die Erben eingetragen','Bien hérité, succession non inscrite',false,true,7),
('LB','ilm','منطقة غير ممسوحة (علم وخبر من المختار)','Unsurveyed area (mukhtar certificate)','Nicht vermessenes Gebiet (Bescheinigung des Mukhtar)','Zone non cadastrée (certificat du moukhtar)',false,true,8),
('LB','none','بدون سند (بناء مخالف أو وضع يد)','No title (unlicensed building or squatting)','Ohne Titel (Schwarzbau oder Besetzung)','Sans titre (construction illégale ou occupation)',false,true,9);
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
  if jsonb_array_length(types) > 0 then   -- a country's own list: its «sec» files new codes (parking, school…) and re-files farm/restaurant
    select coalesce(jsonb_agg(x),'[]'::jsonb) into land_t from (select jsonb_array_elements(land_t) x union select to_jsonb(r->>'code') from jsonb_array_elements(types) r where r->>'sec'='land') s where not exists (select 1 from jsonb_array_elements(types) r where r->>'code'=s.x#>>'{}' and coalesce(r->>'sec','land')<>'land');
    select coalesce(jsonb_agg(x),'[]'::jsonb) into comm_t from (select jsonb_array_elements(comm_t) x union select to_jsonb(r->>'code') from jsonb_array_elements(types) r where r->>'sec'='commercial') s where not exists (select 1 from jsonb_array_elements(types) r where r->>'code'=s.x#>>'{}' and coalesce(r->>'sec','commercial')<>'commercial');
  end if;
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
end $function$
;
commit;
