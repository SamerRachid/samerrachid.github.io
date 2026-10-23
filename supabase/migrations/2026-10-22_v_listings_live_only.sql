-- v_listings returned listings still awaiting review (status 'pending') to anyone holding the public key; the site
-- only hid them in the browser (pending item 14, owner said do it 2026-10-22). The view now shows what the listings
-- table's own read policy shows: live, plus sold / rented for 7 days. Owners still see their own pending listings
-- through bk_my_listings (the site falls back to it when a listing is not in the public list).
-- Only the WHERE changes; the column list is taken from the live definition so nothing else moves.
do $$
declare d text;
begin
  d := pg_get_viewdef('public.v_listings'::regclass);
  d := replace(d, '(l.status = ANY (ARRAY[''live''::text, ''pending''::text]))', '(l.status = ''live''::text)');
  if position('pending' in d) > 0 then raise exception 'v_listings: pending clause not found, nothing changed'; end if;
  execute 'create or replace view public.v_listings as ' || d;
end $$;
