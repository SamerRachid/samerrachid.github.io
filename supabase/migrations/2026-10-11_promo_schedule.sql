-- 2026-10-11: dedicated "promote to social media" admin page — due-to-promote scheduling behind it.
-- A listing that goes live gets one pending promo_schedule row, due after site_content.extras.promo.due_hours
-- (default 24) hours; the admin dashboard shows these as clickable cards. Marking "done" (or the listing leaving
-- live) clears it. Group URLs + the due-hours setting live in site_content.extras.promo (reuses the existing
-- per-country jsonb "extras" column — no new settings table needed).

create table if not exists public.promo_schedule (
  id bigserial primary key,
  listing_id bigint not null references public.listings(id) on delete cascade,
  due_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','done')),
  created_at timestamptz not null default now()
);
create index if not exists promo_schedule_due_idx on public.promo_schedule(status, due_at);
create unique index if not exists promo_schedule_listing_pending_idx on public.promo_schedule(listing_id) where status='pending';
alter table public.promo_schedule enable row level security;

CREATE OR REPLACE FUNCTION public.bk_trg_listing_live_promo_schedule() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare hrs int;
begin
  if new.status='live' and (tg_op='INSERT' or old.status is distinct from 'live') then
    select coalesce((extras->'promo'->>'due_hours')::int, 24) into hrs
      from site_content where country_code=coalesce(new.country_code,'SY');
    if hrs is null then hrs:=24; end if;
    insert into promo_schedule(listing_id, due_at) values (new.id, now() + (hrs||' hours')::interval)
      on conflict (listing_id) where status='pending' do update set due_at=excluded.due_at;
  elsif new.status<>'live' and old.status is distinct from new.status then
    update promo_schedule set status='done' where listing_id=new.id and status='pending';
  end if;
  return new;
end $function$;
drop trigger if exists bk_trg_listing_live_promo on public.listings;
create trigger bk_trg_listing_live_promo after insert or update on public.listings
for each row execute function public.bk_trg_listing_live_promo_schedule();

CREATE OR REPLACE FUNCTION public.bk_admin_promo_due(p_token text) RETURNS json
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); if uid is null then raise exception 'not admin'; end if;
  return coalesce((select json_agg(json_build_object(
      'listing_id', l.id, 'ref', l.ref, 'property_type', l.property_type, 'area_m2', l.area_m2,
      'gov', g.name_ar, 'price_usd', l.price_usd, 'due_at', ps.due_at,
      'cover', (select coalesce(nullif(p.thumb_url,''), p.url) from listing_photos p
                 where p.listing_id=l.id and coalesce(p.kind,'photo')='photo' order by p.sort_order, p.id limit 1)
    ) order by ps.due_at)
    from promo_schedule ps join listings l on l.id=ps.listing_id join governorates g on g.id=l.governorate_id
    where ps.status='pending' and ps.due_at<=now() and l.status='live' limit 50), '[]'::json);
end $function$;

CREATE OR REPLACE FUNCTION public.bk_admin_promo_mark_done(p_token text, p_listing_id bigint) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token); if uid is null then raise exception 'not admin'; end if;
  update promo_schedule set status='done' where listing_id=p_listing_id and status='pending';
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.bk_admin_promo_settings_get(p_token text, p_country text default null) RETURNS json
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare uid uuid; v_c text := coalesce(nullif(upper(p_country),''),'SY');
begin
  uid := bk_admin_uid(p_token); if uid is null then raise exception 'not admin'; end if;
  return coalesce((select extras->'promo' from site_content where country_code=v_c), '{}'::json);
end $function$;

CREATE OR REPLACE FUNCTION public.bk_admin_promo_settings_set(p_token text, p_settings jsonb, p_country text default null) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $function$
declare uid uuid; v_c text := coalesce(nullif(upper(p_country),''),'SY');
begin
  uid := bk_admin_uid(p_token); if uid is null then raise exception 'not admin'; end if;
  update site_content set extras = coalesce(extras,'{}'::jsonb) || jsonb_build_object('promo', p_settings) where country_code=v_c;
  return true;
end $function$;
