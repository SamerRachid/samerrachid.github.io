-- Balkoun · 2026-09-29 · open publishing (owner's request): anyone who signs up and confirms their phone can post at once.
-- 1. listings: site_settings.require_approval = false — the existing trigger bk_trg_listing_autopublish then makes every new
--    listing live (site form and message bot alike); the panel switch is النظام → الإعدادات → "مراجعة كل إعلان قبل نشره".
update site_settings set require_approval = false where id = 1;
-- 2. agencies: new column + trigger — a new agency row is approved on insert while the switch is on.
alter table site_settings add column if not exists agency_auto_approve boolean not null default true;
create or replace function public.bk_trg_agency_autoapprove() returns trigger language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare v_auto boolean;
begin
  select agency_auto_approve into v_auto from site_settings where id = 1;
  if coalesce(v_auto, false) and (new.status is null or new.status = 'pending') then new.status := 'approved'; end if;
  return new;
end $function$;
drop trigger if exists trg_agency_autoapprove on agencies;
create trigger trg_agency_autoapprove before insert on agencies for each row execute function bk_trg_agency_autoapprove();
-- bk_admin_get_settings() also returns agency_auto_approve; bk_admin_set_agency_auto(p_token, p_on) flips it (panel checkbox #aAgencyAuto).
