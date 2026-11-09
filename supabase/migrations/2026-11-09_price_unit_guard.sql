-- A per-unit price (listings.price_unit / price_unit_value, 2026-11-08) is shown only while it still matches the total:
-- when a later change (admin edit, the bot's correction, a member's edit without the unit) leaves price ≠ unit × size by
-- more than 2%, the unit is dropped and the listing shows its total as before. Units: m2 × area_m2, dunam × area_m2/1000;
-- the figure is in the listing's own currency (price_local when price_cur is set, else price_usd).
create or replace function bk_price_unit_guard() returns trigger language plpgsql as $$
declare expected numeric; actual numeric;
begin
  if new.price_unit is null and new.price_unit_value is null then return new; end if;
  expected := new.price_unit_value * case new.price_unit when 'm2' then new.area_m2 when 'dunam' then new.area_m2 / 1000.0 end;
  actual := case when new.price_cur is not null and new.price_local > 0 then new.price_local else new.price_usd end;
  if new.price_unit is null or new.price_unit_value is null or new.deal = 'rent' or expected is null or actual is null or actual <= 0
     or abs(expected - actual) > 0.02 * actual then
    new.price_unit := null; new.price_unit_value := null;
  end if;
  return new;
end $$;
drop trigger if exists price_unit_guard on listings;
create trigger price_unit_guard before insert or update of price_usd, price_local, price_cur, area_m2, deal, price_unit, price_unit_value
  on listings for each row execute function bk_price_unit_guard();
