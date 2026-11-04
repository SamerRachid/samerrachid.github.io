-- البغطاسية (Homs) was missing from the areas list; the point is Google Maps' «البغطاسية، حمص».
-- SY10447 (shop «قرب السوق المسقوف») had no area, so it was not on the map; the owner says it is in البغطاسية.
insert into areas (governorate_id, name_ar, name_en, slug, lat, lng, kind)
select 5, 'البغطاسية', 'Al-Bughtasiyah', 'al-bughtasiyah', 34.72869, 36.70503, 'area'
where not exists (select 1 from areas where governorate_id = 5 and name_ar = 'البغطاسية');

update listings set area_id = (select id from areas where governorate_id = 5 and name_ar = 'البغطاسية')
where ref = 'SY10447' and area_id is null;

select l.ref, a.name_ar, a.lat, a.lng from listings l join areas a on a.id = l.area_id where l.ref = 'SY10447';
