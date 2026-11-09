-- undo 2026-11-08_price_unit.sql: bk_edit and v_listings back to their earlier text, then drop the columns
do $m$
declare d text := pg_get_functiondef('bk_edit'::regproc);
begin
  d := regexp_replace(d, E'    price_unit  = [^\\n]*\\n    price_unit_value = [^\\n]*\\n', '');
  execute d;
end $m$;
do $m$
declare d text := pg_get_viewdef('v_listings'::regclass);
begin
  d := replace(d, E'l.price_cur,\n    l.price_unit,\n    l.price_unit_value\n   FROM', E'l.price_cur\n   FROM');
  execute 'drop view v_listings; create view v_listings as ' || d;
  grant select on v_listings to anon, authenticated;
end $m$;
alter table listings drop column if exists price_unit_value, drop column if exists price_unit;
