do $do$
declare def text;
begin
  def := pg_get_functiondef('bk_intake_publish'::regproc);
  def := replace(def, $r$rental_period, published_at, country_code, price_unit, price_unit_value)$r$, $r$rental_period, published_at, country_code)$r$);
  def := replace(def, $r$case when st = 'live' then now() end, cc,
      case when not rent and f->>'price_unit' in ('m2','dunam') then f->>'price_unit' end,
      case when not rent and f->>'price_unit' in ('m2','dunam') then bk_intake_num(f->>'price_unit_value') end)$r$, $r$case when st = 'live' then now() end, cc)$r$);
  execute def;
end $do$;
