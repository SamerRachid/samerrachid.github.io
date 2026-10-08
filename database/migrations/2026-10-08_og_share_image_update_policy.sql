-- allow the public (anon) key to overwrite an already-generated OG share-card, narrowly scoped to
-- that exact filename pattern only (not arbitrary listing photos) — needed because p_photos_upload
-- only covers INSERT, and the build script re-uploads (x-upsert) when regenerating a card.
create policy "p_photos_og_share_update" on storage.objects
  for update
  using (bucket_id = 'photos' and name ~~ 'photos/listings/%/og-share.jpg')
  with check (bucket_id = 'photos' and name ~~ 'photos/listings/%/og-share.jpg');
