-- Listing SY10029 (id 37): its 13th photo row pointed at a file of the deleted listing 36 that no longer exists anywhere
-- (not in storage, not in the trash), so it loaded as a broken image (HTTP 400). Owner said do it, 2026-10-23.
-- The row as it was, for the record:
--   listing_photos id 71, listing_id 37, kind photo, sort_order 100,
--   url       .../public/photos/photos/listings/36/1790614756273-1-ffbq8.jpg
--   thumb_url .../public/photos/photos/listings/36/1790614756273-1-ffbq8-t.jpg
delete from listing_photos
 where id = 71 and listing_id = 37 and url like '%/photos/listings/36/1790614756273-1-ffbq8.jpg'
   and not exists (select 1 from storage.objects o where o.bucket_id = 'photos' and o.name like '%1790614756273-1-ffbq8%');
