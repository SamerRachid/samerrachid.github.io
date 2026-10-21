-- owner, 2026-10-21: «جديدة الشيباني» is the same village as «جديدة الوادي» (Wadi Barada, Qudsaya, Rif Dimashq).
-- One area, both names; the bot (withAreaAliases in bk-intake) and the site's read-text accept either name.
update areas set name_ar='جديدة الوادي/جديدة الشيباني', name_en='Judaydat al-Wadi/Jdeidet al-Shaybani' where id=6374;
