-- 2026-09-30: "نشر تلقائي" per user is ON by default; admin switches it OFF for untrusted members/agencies.
alter table users alter column skip_review set default true;
update users set skip_review = true where skip_review is distinct from true;
-- bk_trg_listing_autopublish: only touches rows arriving as 'pending'; live when coalesce(skip_review, not require_approval)
-- bk_intake_publish: st := case when coalesce(u.skip_review,true) or (u.id is null and coalesce(a.intake_trusted,true)) then 'live' else 'pending' end
