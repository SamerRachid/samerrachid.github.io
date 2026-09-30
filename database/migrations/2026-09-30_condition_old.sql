-- 2026-09-30: new condition code "old" = إكساء قديم (old but usable finishing). Applied live via replace() on the function bodies.
-- bk_intake_taxonomy: conditions now [intact, old, repair, shell, (stripped SY only), damaged]
-- bk_intake_publish: cond whitelist now ('intact','old','repair','shell','stripped','damaged')
-- Site: index.html D.COND "old": ["إكساء قديم","Old finishing","Alte Ausstattung"]; bot SYSTEM rule maps "إكساء قديم"/"كسوة قديمة" to old.

-- listings_condition_check was missing old AND stripped (معفش never saved). Re-created:
-- check (condition = any (array['intact','old','repair','shell','stripped','damaged','empty','built','fenced','planted']))
