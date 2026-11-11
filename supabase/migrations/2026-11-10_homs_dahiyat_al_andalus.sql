-- 2026-11-10 (owner: «ضاحية الأندلس» add to Homs). The place was already in the list from OSM as
-- «الأندلس (قطينة)» (id 9904, 0 listings). Renamed to the name people and Google Maps use, on Google's point.
-- Already run on the live database; kept here as a record.
update areas set name_ar='ضاحية الأندلس', name_en='Dahiyat al-Andalus', slug='dahiyat-al-andalus',
  old_slugs=array['al-andalus'], lat=34.5924899, lng=36.7024618
 where id=9904 and governorate_id=5 and name_ar='الأندلس (قطينة)';
-- undo:
-- update areas set name_ar='الأندلس (قطينة)', name_en='Al-Andalus (Quteina)', slug='al-andalus', old_slugs='{}', lat=34.59278, lng=36.70256 where id=9904;
