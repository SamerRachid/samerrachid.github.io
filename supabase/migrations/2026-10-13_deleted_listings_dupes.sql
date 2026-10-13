-- 2026-10-13: (1) a log of deleted listings with who deleted them and why, (2) a duplicate-listing finder for the
-- admin panel, (3) last_listing_at in the admin user-activity feed (for the "abandoned accounts" view).
--
-- (1) A BEFORE DELETE trigger on listings writes one row to deleted_listings for every deletion, whatever the path.
--     The callers say who asked through transaction-local settings: bk_own_delete → 'owner' + the member's reason
--     and note, bk_admin_delete_listing → 'admin' + the admin's id and an optional note, bk_user_purge → 'account'
--     (the listings went with the account). Anything else is 'system'. The log must never block a deletion.

create table if not exists public.deleted_listings (
  id bigserial primary key,
  listing_id bigint not null, ref text, user_id uuid, poster_name text, poster_phone text,
  country_code text, gov text, area text, property_type text, deal text, price_usd integer, area_m2 integer, rooms integer,
  status text, views integer, saves integer, posted_at timestamptz,
  deleted_at timestamptz not null default now(),
  deleted_by text not null default 'system',    -- 'owner' | 'admin' | 'account' | 'system'
  admin_id uuid, admin_name text,
  reason text, note text
);
alter table public.deleted_listings enable row level security;   -- no policies: security-definer functions only
create index if not exists deleted_listings_deleted_at_idx on public.deleted_listings (deleted_at desc);

create or replace function public.bk_trg_listing_deleted() returns trigger
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare v_by text := nullif(current_setting('bk.ldel_by', true), ''); v_admin uuid;
begin
  begin v_admin := nullif(current_setting('bk.ldel_admin', true), '')::uuid; exception when others then v_admin := null; end;
  insert into deleted_listings (listing_id, ref, user_id, poster_name, poster_phone, country_code, gov, area, property_type, deal,
                                price_usd, area_m2, rooms, status, views, saves, posted_at, deleted_by, admin_id, admin_name, reason, note)
  select old.id, old.ref, old.user_id,
         coalesce(nullif(trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')), ''), old.contact_name),
         coalesce(u.phone, old.contact_phone),
         old.country_code, g.name_ar, a.name_ar, old.property_type, old.deal,
         old.price_usd, old.area_m2, old.rooms, old.status, old.views, old.saves, coalesce(old.published_at, old.created_at),
         coalesce(v_by, 'system'), v_admin,
         (select nullif(trim(coalesce(x.name,'')||' '||coalesce(x.family_name,'')), '') from users x where x.id = v_admin),
         nullif(left(current_setting('bk.ldel_reason', true), 60), ''),
         nullif(left(current_setting('bk.ldel_note', true), 300), '')
    from (select 1) _
    left join users u on u.id = old.user_id
    left join governorates g on g.id = old.governorate_id
    left join areas a on a.id = old.area_id;
  return old;
exception when others then return old;   -- the log must never block a deletion
end $$;

drop trigger if exists trg_listing_deleted on public.listings;
create trigger trg_listing_deleted before delete on public.listings
  for each row execute function public.bk_trg_listing_deleted();

-- the member's own delete now carries a reason (picked in the app) and an optional note
drop function if exists public.bk_own_delete(uuid, bigint, text);
create or replace function public.bk_own_delete(p_user uuid, p_id bigint, p_token text default null, p_reason text default null, p_note text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
begin
  perform bk_require_member(p_token, p_user);
  if not exists (select 1 from listings where id=p_id and user_id=p_user) then
    return json_build_object('error','notyours');
  end if;
  perform set_config('bk.ldel_by', 'owner', true);
  perform set_config('bk.ldel_admin', '', true);
  perform set_config('bk.ldel_reason', coalesce(p_reason, ''), true);
  perform set_config('bk.ldel_note', coalesce(p_note, ''), true);
  delete from listings where id = p_id;   -- photos and saves cascade
  return json_build_object('ok', true);
end $$;

-- the admin delete carries an optional note
drop function if exists public.bk_admin_delete_listing(text, bigint);
create or replace function public.bk_admin_delete_listing(p_token text, p_listing bigint, p_reason text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  perform bk_admin_guard(uid, (select country_code from listings where id = p_listing));
  perform set_config('bk.ldel_by', 'admin', true);
  perform set_config('bk.ldel_admin', uid::text, true);
  perform set_config('bk.ldel_reason', '', true);
  perform set_config('bk.ldel_note', coalesce(p_reason, ''), true);
  delete from listings where id = p_listing;
  return json_build_object('ok', true);
end $$;

-- an account purge: its listings are logged as deleted "with the account"
create or replace function public.bk_user_purge(p_uid uuid, p_by text default 'system', p_admin uuid default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare ids bigint[]; av text; ph text; em text;
begin
  select avatar_url, phone, email into av, ph, em from users where id = p_uid;
  if not found then return json_build_object('error', 'nouser'); end if;
  select coalesce(array_agg(id order by id), '{}') into ids from listings where user_id = p_uid;
  perform set_config('bk.del_by', coalesce(p_by, 'system'), true);
  perform set_config('bk.del_admin', coalesce(p_admin::text, ''), true);
  perform set_config('bk.del_listings', coalesce(array_length(ids, 1), 0)::text, true);
  perform set_config('bk.ldel_by', 'account', true);
  perform set_config('bk.ldel_admin', coalesce(p_admin::text, ''), true);
  perform set_config('bk.ldel_reason', 'account_' || coalesce(p_by, 'system'), true);
  perform set_config('bk.ldel_note', '', true);
  delete from listings where user_id = p_uid;
  delete from intake_drafts where user_id = p_uid;
  delete from contacts where user_id = p_uid and source = 'member';
  update contacts set wa_consent = 'unsubscribed', tg_consent = 'unsubscribed', email_consent = 'unsubscribed', user_id = null, updated_at = now()
   where user_id = p_uid or (ph is not null and ph <> '' and phone = ph) or (em is not null and em <> '' and lower(email) = lower(em));
  delete from users where id = p_uid;
  return json_build_object('ok', true, 'listing_ids', to_json(ids), 'avatar_url', av);
end $$;

create or replace function public.bk_admin_deleted_listings(p_token text, p_country text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select d.id, d.listing_id, d.ref, d.user_id, d.poster_name, d.poster_phone, d.country_code, d.gov, d.area, d.property_type, d.deal,
           d.price_usd, d.area_m2, d.rooms, d.status, d.views, d.saves, d.posted_at, d.deleted_at, d.deleted_by, d.admin_id, d.admin_name, d.reason, d.note
      from deleted_listings d
     where bk_scope_ok(coalesce(d.country_code, 'SY'), sc, al)
     order by d.deleted_at desc
     limit 500
  ) x), '[]'::json);
end $$;

-- (2) likely duplicates: pairs of (listing, key) where the key is shared by more than one listing. The panel clusters
--     them. Keys: same poster (or the same contact phone when there is no account) + type + deal + area + price;
--     the same but + size + rooms; or the same description text (first 160 characters, whitespace-normalised).
create or replace function public.bk_admin_duplicate_listings(p_token text, p_country text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    with L as (
      select l.id, coalesce(l.user_id::text, nullif(l.contact_phone, ''), '') as who, coalesce(l.property_type,'') as pt, coalesce(l.deal,'') as dl,
             coalesce(l.area_id::text, '') as ar, l.price_usd, l.area_m2, l.rooms,
             lower(regexp_replace(coalesce(l.description, ''), '\s+', ' ', 'g')) as dsc
        from listings l
       where l.status in ('live','pending','hidden') and bk_scope_ok(coalesce(l.country_code, 'SY'), sc, al)),
    K as (
      select id, 'poster' as kind, who||'|'||pt||'|'||dl||'|'||ar||'|p'||price_usd::text as key from L where who <> '' and price_usd is not null
      union all
      select id, 'poster', who||'|'||pt||'|'||dl||'|'||ar||'|m'||area_m2::text||'r'||coalesce(rooms::text, '') from L where who <> '' and area_m2 is not null
      union all
      select id, 'text', 'txt:'||md5(left(dsc, 160)) from L where length(dsc) >= 40)
    select k.id as listing_id, k.kind, k.key
      from K k
     where k.key in (select key from K group by key having count(distinct id) > 1)
     order by k.key, k.id
  ) x), '[]'::json);
end $$;

-- (3) when each member last posted, for the abandoned-accounts view
CREATE OR REPLACE FUNCTION public.bk_admin_user_activity(p_token text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select u.id, u.last_seen_at, u.phone_verified, u.lang, u.country, u.city,
           (select count(*) from listings l where l.user_id=u.id and l.status='live') as live_listings,
           (select max(l.created_at) from listings l where l.user_id=u.id) as last_listing_at,
           (select count(*) from saved_listings s where s.user_id=u.id) as saved,
           (select count(*) from contact_events c where c.user_id=u.id) as contacts_made,
           (select count(*) from page_views v where v.user_id=u.id and v.created_at > now()-interval '30 days') as views_30d
      from users u where u.role <> 'admin' and bk_scope_ok(coalesce(u.country,'SY'), sc, al)) x), '[]'::json);
end $function$;

select tgname from pg_trigger where tgrelid = 'public.listings'::regclass and tgname = 'trg_listing_deleted';
