-- «قيد الإكساء» (finishing) was added to the bot and the publish functions on 2026-10-21, but the listings check
-- constraint was never widened: publishing a draft with condition 'finishing' failed (draft 833, 2026-10-24)
alter table listings drop constraint listings_condition_check;
alter table listings add constraint listings_condition_check check (condition = any (array['intact','deluxe','superdeluxe','old','repair','shell','finishing','stripped','damaged','empty','built','fenced','planted']));
