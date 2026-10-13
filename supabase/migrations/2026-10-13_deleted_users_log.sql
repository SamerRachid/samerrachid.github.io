-- 2026-10-13: keep a record of deleted accounts, and who deleted them.
-- Until now a purged account vanished without trace (bk_user_purge hard-deletes the users row). A BEFORE DELETE
-- trigger on users now writes one row to deleted_users for every deletion, whatever the path. bk_user_purge
-- tells the trigger who asked (transaction-local settings): 'self' from bk_delete_account, 'admin' + the admin's
-- id from bk_admin_delete_user; any other path (danger-zone resets, manual SQL) is recorded as 'system'.
-- The listings count is captured by the purge before it deletes them. Only the admin panel reads the log
-- (bk_admin_deleted_users, country-scoped like every other admin list).

create table if not exists public.deleted_users (
  id bigserial primary key,
  user_id uuid not null,
  member_no text, name text, family_name text, phone text, email text, country text, city text,
  account_type text, level text, is_house boolean not null default false,
  joined_at timestamptz, last_seen_at timestamptz,
  listings_count int not null default 0,
  deleted_at timestamptz not null default now(),
  deleted_by text not null default 'system',      -- 'self' | 'admin' | 'system'
  admin_id uuid, admin_name text
);
alter table public.deleted_users enable row level security;   -- no policies: security-definer functions only
create index if not exists deleted_users_deleted_at_idx on public.deleted_users (deleted_at desc);

create or replace function public.bk_trg_user_deleted() returns trigger
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare v_by text := nullif(current_setting('bk.del_by', true), ''); v_admin uuid; v_cnt int;
begin
  begin v_admin := nullif(current_setting('bk.del_admin', true), '')::uuid; exception when others then v_admin := null; end;
  begin v_cnt := nullif(current_setting('bk.del_listings', true), '')::int; exception when others then v_cnt := null; end;
  if v_cnt is null then select count(*) into v_cnt from listings where user_id = old.id; end if;
  insert into deleted_users (user_id, member_no, name, family_name, phone, email, country, city, account_type, level, is_house,
                             joined_at, last_seen_at, listings_count, deleted_by, admin_id, admin_name)
  values (old.id, old.member_no, old.name, old.family_name, old.phone, old.email, old.country, old.city, old.account_type, old.level,
          coalesce(old.is_house, false), old.created_at, old.last_seen_at, coalesce(v_cnt, 0), coalesce(v_by, 'system'), v_admin,
          (select nullif(trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')), '') from users u where u.id = v_admin));
  return old;
end $$;

drop trigger if exists trg_user_deleted on public.users;
create trigger trg_user_deleted before delete on public.users
  for each row execute function public.bk_trg_user_deleted();

-- the purge now says who asked; the old one-argument form goes (both callers are replaced below)
drop function if exists public.bk_user_purge(uuid);
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
  delete from listings where user_id = p_uid;
  delete from intake_drafts where user_id = p_uid;
  delete from contacts where user_id = p_uid and source = 'member';
  update contacts set wa_consent = 'unsubscribed', tg_consent = 'unsubscribed', email_consent = 'unsubscribed', user_id = null, updated_at = now()
   where user_id = p_uid or (ph is not null and ph <> '' and phone = ph) or (em is not null and em <> '' and lower(email) = lower(em));
  delete from users where id = p_uid;
  return json_build_object('ok', true, 'listing_ids', to_json(ids), 'avatar_url', av);
end $$;

create or replace function public.bk_delete_account(p_token text, p_pass text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; u users;
begin
  uid := bk_member_uid(p_token);
  if uid is null then return json_build_object('error', 'unauthorised'); end if;
  select * into u from users where id = uid;
  if u.id is null then return json_build_object('error', 'nouser'); end if;
  if u.role = 'admin' then return json_build_object('error', 'admin'); end if;
  if u.pass_hash is not null and (p_pass is null or u.pass_hash <> crypt(p_pass, u.pass_hash)) then
    return json_build_object('error', 'badpass');
  end if;
  return bk_user_purge(uid, 'self', null);
end $$;

create or replace function public.bk_admin_delete_user(p_token text, p_user uuid) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; u users;
begin
  uid := bk_admin_uid(p_token);
  if not bk_admin_is_super(uid) then return json_build_object('error', 'super admin only'); end if;
  if p_user = uid then return json_build_object('error', 'self'); end if;
  select * into u from users where id = p_user;
  if u.id is null then return json_build_object('error', 'nouser'); end if;
  if u.role = 'admin' then return json_build_object('error', 'isadmin'); end if;
  perform bk_admin_guard(uid, u.country);
  return bk_user_purge(p_user, 'admin', uid);
end $$;

create or replace function public.bk_admin_deleted_users(p_token text, p_country text default null) returns json
 language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(x) from (
    select d.id, d.user_id, d.member_no, d.name, d.family_name, d.phone, d.email, d.country, d.city, d.account_type, d.level, d.is_house,
           d.joined_at, d.last_seen_at, d.listings_count, d.deleted_at, d.deleted_by, d.admin_id, d.admin_name
      from deleted_users d
     where bk_scope_ok(coalesce(d.country, 'SY'), sc, al)
     order by d.deleted_at desc
     limit 500
  ) x), '[]'::json);
end $$;

select tgname from pg_trigger where tgrelid = 'public.users'::regclass and tgname = 'trg_user_deleted';
