-- 2026-10-09 — bk_intake_listing_add_photo had no auth check and was executable by PUBLIC/anon/authenticated
-- (proacl showed "=X/postgres", the PUBLIC grant, plus explicit anon/authenticated grants from
-- 2026-09-28_intake_guide_flow.sql). Anyone with the site's public anon key could attach arbitrary
-- photo/video URLs to any live listing id. Only the intake bot calls this (bk-intake/index.ts:564,594)
-- and it uses the service-role key, so revoking the other roles does not affect it.
revoke execute on function public.bk_intake_listing_add_photo(bigint, jsonb) from public, anon, authenticated;
