-- 2026-10-13 (audit follow-up): anyone with the public key could upload into the "photos" bucket (100 MB per
-- file, no cap on files) — storage cost and a free host for foreign content. Uploads now go through the
-- bk-storage edge function's sign-upload action (member or admin session token, ownership checked per path),
-- which hands the browser a signed upload URL; the storage server accepts those again on this project.
-- The public INSERT policy is therefore dropped. Reads stay public; the og-share rewrite stays service-role.
drop policy if exists p_photos_upload on storage.objects;

select count(*) as public_insert_policies_left from pg_policies
 where schemaname = 'storage' and tablename = 'objects' and cmd = 'INSERT' and 'public' = any(roles);
