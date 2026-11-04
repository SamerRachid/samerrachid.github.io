-- «الخضر» for Homs (owner 2026-11-04), point from Google Maps «الخضر، حمص». Run via MCP the same day.
insert into areas (governorate_id, name_ar, name_en, slug, lat, lng, kind)
select 5, 'الخضر', 'Al-Khodr', 'al-khodr', 34.71906, 36.71402, 'area'
where not exists (select 1 from areas where governorate_id = 5 and name_ar = 'الخضر');
