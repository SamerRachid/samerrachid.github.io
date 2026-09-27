-- Balkoun · 2026-09-27 · deleting a member: from the admin panel (super admin only) and by the member themself
-- ("delete my account" on the account page, password required). Both call the same internal purge, which removes the
-- member's listings (photos, reports, saves and price history cascade), drafts, sessions, saved searches, wanted
-- requests, reviews, notifications, agency page and the notebook row that mirrored the member — and, for any contact
-- row that still carries the same phone or email (an admin import, for instance), switches every channel to
-- "unsubscribed" so no message ever reaches that person again. Storage files are moved to the trash by the client
-- afterwards using the ids this returns (the buckets are not reachable from SQL).

-- campaigns created by an admin must not block deleting that admin's account later
alter table public.campaigns drop constraint if exists campaigns_created_by_fkey;
alter table public.campaigns add constraint campaigns_created_by_fkey foreign key (created_by) references public.users(id) on delete set null;

create or replace function public.bk_user_purge(p_uid uuid) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare ids bigint[]; av text; ph text; em text;
begin
  select avatar_url, phone, email into av, ph, em from users where id = p_uid;
  if not found then return json_build_object('error', 'nouser'); end if;
  select coalesce(array_agg(id order by id), '{}') into ids from listings where user_id = p_uid;
  delete from listings where user_id = p_uid;
  delete from intake_drafts where user_id = p_uid;
  delete from contacts where user_id = p_uid and source = 'member';
  update contacts set wa_consent = 'unsubscribed', tg_consent = 'unsubscribed', email_consent = 'unsubscribed', user_id = null, updated_at = now()
   where user_id = p_uid or (ph is not null and ph <> '' and phone = ph) or (em is not null and em <> '' and lower(email) = lower(em));
  delete from users where id = p_uid;
  return json_build_object('ok', true, 'listing_ids', to_json(ids), 'avatar_url', av);
end $function$;
revoke execute on function public.bk_user_purge(uuid) from public, anon, authenticated;

-- admin panel: super admin only, never oneself, never another admin (remove the admin role first)
create or replace function public.bk_admin_delete_user(p_token text, p_user uuid) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; u users;
begin
  uid := bk_admin_uid(p_token);
  if not bk_admin_is_super(uid) then return json_build_object('error', 'super admin only'); end if;
  if p_user = uid then return json_build_object('error', 'self'); end if;
  select * into u from users where id = p_user;
  if u.id is null then return json_build_object('error', 'nouser'); end if;
  if u.role = 'admin' then return json_build_object('error', 'isadmin'); end if;
  perform bk_admin_guard(uid, u.country);
  return bk_user_purge(p_user);
end $function$;
grant execute on function public.bk_admin_delete_user(text, uuid) to anon;

-- the member themself: valid session + current password (p_pass arrives hashed like every other password call)
create or replace function public.bk_delete_account(p_token text, p_pass text default null) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
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
  return bk_user_purge(uid);
end $function$;
grant execute on function public.bk_delete_account(text, text) to anon;
