-- 2026-10-26: publishing from the site failed with «null value in column "contacts"». bk_post_listing builds the row with
-- jsonb_populate_record, so a column it does not set is null, not its default. The new contacts counter starts at 0.
do $m$
declare d text := pg_get_functiondef('public.bk_post_listing'::regproc);
begin
  if position('l.contacts := 0' in d) = 0 then
    execute replace(d, 'l.views := 0; l.saves := 0;', 'l.views := 0; l.saves := 0; l.contacts := 0;');
  end if;
end $m$;

-- safety net for any other path that inserts a whole row (backup restore of an older backup, future code)
create or replace function bk_listing_counters_default() returns trigger language plpgsql as $$
begin
  new.contacts := coalesce(new.contacts, 0);
  new.views := coalesce(new.views, 0);
  new.saves := coalesce(new.saves, 0);
  return new;
end $$;
drop trigger if exists t_counters_default on listings;
create trigger t_counters_default before insert on listings for each row execute function bk_listing_counters_default();
