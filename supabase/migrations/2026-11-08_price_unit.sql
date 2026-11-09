-- 2026-11-08 price per metre / per dunam (owner: "ok do it")
-- The seller's figure stays as typed (price_unit_value, in the listing's currency) with its unit;
-- price_usd keeps the computed total, so search, filters, sort and the area averages are unchanged.
-- Old listings: price_unit null (= whole), price_unit_value null → shown exactly as today.
-- Nullable on purpose: bk_post_listing builds the row with jsonb_populate_record(null::listings, …),
-- so a NOT NULL column the form doesn't send would fail every new post.

alter table listings
  add column if not exists price_unit text
    check (price_unit is null or price_unit in ('whole','m2','dunam')),
  add column if not exists price_unit_value numeric
    check (price_unit_value is null or price_unit_value > 0);

-- v_listings: the two new columns at the end (create or replace may only append)
do $m$
declare d text := pg_get_viewdef('v_listings'::regclass);
begin
  if position('price_unit' in d) = 0 then
    d := replace(d, E'l.price_cur\n   FROM', E'l.price_cur,\n    l.price_unit,\n    l.price_unit_value\n   FROM');
    if position('price_unit' in d) = 0 then raise exception 'v_listings anchor not found'; end if;
    execute 'create or replace view v_listings as ' || d;
  end if;
end $m$;

-- bk_edit: accept the two keys (everything else in the function unchanged)
do $m$
declare d text := pg_get_functiondef('bk_edit'::regproc);
begin
  if position('price_unit' in d) = 0 then
    d := replace(d, E'    price_cur   = case when p_patch ? ''price_cur'' then nullif(p_patch->>''price_cur'','''') else price_cur end,',
      E'    price_cur   = case when p_patch ? ''price_cur'' then nullif(p_patch->>''price_cur'','''') else price_cur end,\r\n'
   || E'    price_unit  = case when p_patch->>''price_unit'' in (''whole'',''m2'',''dunam'') then p_patch->>''price_unit'' else price_unit end,\r\n'
   || E'    price_unit_value = case when p_patch ? ''price_unit_value'' then nullif(p_patch->>''price_unit_value'','''')::numeric else price_unit_value end,');
    if position('price_unit' in d) = 0 then raise exception 'bk_edit anchor not found'; end if;
    execute d;
  end if;
end $m$;
