-- The bot's listings keep a per-m² / per-dunam price as the seller wrote it (fields.price_unit / price_unit_value,
-- set by the free reader when it multiplied «سعر المتر 170$» by the size). price_unit_guard drops it if it does not
-- match the total. Patched in place: two replace()s on the live body, each checked.
do $do$
declare def text; n0 int;
begin
  def := pg_get_functiondef('bk_intake_publish'::regproc);
  if position('price_unit' in def) > 0 then return; end if;
  n0 := length(def);
  def := replace(def, $r$rental_period, published_at, country_code)$r$, $r$rental_period, published_at, country_code, price_unit, price_unit_value)$r$);
  def := replace(def, $r$case when st = 'live' then now() end, cc)$r$,
    $r$case when st = 'live' then now() end, cc,
      case when not rent and f->>'price_unit' in ('m2','dunam') then f->>'price_unit' end,
      case when not rent and f->>'price_unit' in ('m2','dunam') then bk_intake_num(f->>'price_unit_value') end)$r$);
  if (length(def) - length(replace(def, 'price_unit', ''))) / 10 <> 6 then raise exception 'bk_intake_publish: insert not found as expected'; end if;
  execute def;
end $do$;
