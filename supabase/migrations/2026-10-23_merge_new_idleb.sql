-- «ادلب الجديدة» was added twice to Idlib (owner said merge, 2026-10-23): 8493 (slug new-idleb, no listings) and 8494
-- (slug idleb, one listing). Everything attached to 8493 moves to 8494, 8493 goes, and 8494 takes the right address
-- new-idleb; its old address idleb is kept in old_slugs so the page generator leaves a redirect there.
begin;
update listings set area_id = 8494 where area_id = 8493;
update properties set area_id = 8494 where area_id = 8493;
update contacts set area_id = 8494 where area_id = 8493;
update campaigns set area_id = 8494 where area_id = 8493;
update area_suggestions set area_id = 8494 where area_id = 8493;
delete from intake_places where area_id = 8493 and exists (select 1 from intake_places p2 where p2.area_id = 8494);
update intake_places set area_id = 8494 where area_id = 8493;
delete from areas where id = 8493 and name_ar = 'ادلب الجديدة';
update areas set slug = 'new-idleb', name_en = 'New Idleb',
       old_slugs = case when 'idleb' = any(old_slugs) then old_slugs else old_slugs || 'idleb'::text end
 where id = 8494 and name_ar = 'ادلب الجديدة';
commit;
