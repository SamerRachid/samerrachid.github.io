-- «مركز المدينة» for Homs (owner 2026-11-04), point on ساحة الساعة الجديدة (Google Maps). Run via MCP the same day.
-- SY10439 (أول طريق حماة) and SY10741 (أول طريق الشام) had no area and were not on the map.
insert into areas (governorate_id, name_ar, name_en, slug, lat, lng, kind)
select 5, 'مركز المدينة', 'City Centre', 'homs-city-centre', 34.73075, 36.70929, 'area'
where not exists (select 1 from areas where governorate_id = 5 and name_ar = 'مركز المدينة');

update listings set area_id = (select id from areas where governorate_id = 5 and name_ar = 'مركز المدينة')
where ref in ('SY10439','SY10741') and area_id is null;
