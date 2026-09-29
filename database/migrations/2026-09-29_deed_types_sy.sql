-- Balkoun · 2026-09-29 · three more Syrian deed types after comparing with the guides the owner found (عقارك، دليلو، غرس القانوني):
--   agri    طابو زراعي         (shares on agricultural / unpartitioned land — "سند 25", "مشاع زراعي")
--   coop    تنازل جمعية سكنية  (housing-cooperative transfer / "سجل مؤقت")
--   housing طابو إسكان         (General Housing Establishment)
-- "بدون طابو" stays for informal contracts (عقد عرفي) and مخالفات areas, moved to the end of the list.
-- The site's Syrian deed options come from D.TABU in index.html (extended in the same commit); other countries read deed_types.
update deed_types set sort_order = 9 where country_code='SY' and code='none';
insert into deed_types (country_code, code, name_ar, name_en, name_de, name_fr, sort_order, enabled, is_strong)
select * from (values
  ('SY','agri','طابو زراعي','Agricultural tabu (shares)','Landwirtschaftliches Grundbuch','Tabou agricole',6,true,false),
  ('SY','coop','تنازل جمعية سكنية','Housing cooperative transfer','Wohnungsgenossenschaft-Abtretung','Cession de coopérative',7,true,false),
  ('SY','housing','طابو إسكان','Housing establishment tabu','Wohnungsbau-Grundbuch','Tabou logement (Iskan)',8,true,false)
) v(country_code, code, name_ar, name_en, name_de, name_fr, sort_order, enabled, is_strong)
where not exists (select 1 from deed_types d where d.country_code = v.country_code and d.code = v.code);

-- same day: bk_intake_message() no longer applies intake_daily_limit (default 30 drafts per chat per day) to admin chats —
-- the owner forwards whole agency batches from his own Telegram and hit the cap. Applied live with regexp_replace:
--   if n_today >= coalesce(bk_intake_int(cfg->>'intake_daily_limit'), 30) and not coalesce((s->>'is_admin')::boolean, false) then
-- later the same day: the daily draft cap is lifted for agencies and brokers too (owner's request) — it now applies only to
-- plain members. bk_intake_sender() returns 'account_type' (users.account_type) and the condition became:
--   ... and not coalesce((s->>'is_admin')::boolean,false) and s->>'agency_id' is null
--       and coalesce(s->>'account_type','member') not in ('broker','agency') then
