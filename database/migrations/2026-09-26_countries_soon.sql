-- Balkoun · 2026-09-26 · the public country list also names the countries that are not open yet ("soon"), so a
-- visitor from one of them is greeted with "Balkoun for the Arab world — now in X, soon in your country" instead
-- of a page that looks Syria-only. Enabled countries are unchanged.

create or replace function public.bk_public_countries() returns json
language sql stable security definer set search_path to 'public' as $function$
  select json_build_object(
    'list', coalesce((select json_agg(json_build_object('code',code,'name_ar',name_ar,'name_en',name_en,'name_de',name_de,'name_fr',name_fr,'name_tr',name_tr,'enabled',enabled,'is_default',is_default,'currencies',currencies,'rates',rates,'phone_code',phone_code,'tz',tz,'lat',lat,'lng',lng,'zoom',zoom,'languages',languages,'types',types,'map_outline',map_outline,'map_box',map_box,
      'deeds',(select coalesce(json_agg(json_build_object('code',d.code,'ar',d.name_ar,'en',d.name_en,'de',d.name_de,'fr',d.name_fr,'strong',d.is_strong) order by d.sort_order),'[]'::json) from deed_types d where d.country_code=c.code and d.enabled)) order by sort_order) from countries c where c.enabled), '[]'::json),
    'soon', coalesce((select json_agg(json_build_object('code',code,'name_ar',name_ar,'name_en',name_en,'name_de',name_de,'name_fr',name_fr,'tz',tz) order by sort_order) from countries c where not c.enabled), '[]'::json),
    'chooser', coalesce((select extras->>'country_chooser' from site_content where id=1), 'auto'));
$function$;
