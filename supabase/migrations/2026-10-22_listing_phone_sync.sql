-- A member's listings and the account's number (owner, 2026-10-22): changing the account's number used to leave every
-- listing on the old one (a member who moved from a German to a Syrian number kept 4 listings on the German one).
-- bk_own_phone_sync counts the member's listings whose contact number differs from the account's, and with p_apply
-- puts the account's number on them (a hidden number goes to contact_phone_private through trg_listing_hide_phone).
begin;
create or replace function public.bk_own_phone_sync(p_user uuid, p_apply boolean default false, p_token text default null)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare ph text; n int; done int := 0;
begin
  perform bk_require_member(p_token, p_user);
  select phone into ph from users where id = p_user;
  if ph is null then return json_build_object('count', 0, 'updated', 0); end if;
  select count(*) into n from listings
   where user_id = p_user and status not in ('deleted')
     and regexp_replace(coalesce(contact_phone, contact_phone_private, ''), '\D', '', 'g') <> regexp_replace(ph, '\D', '', 'g');
  if p_apply and n > 0 then
    update listings set contact_phone = ph
     where user_id = p_user and status not in ('deleted')
       and regexp_replace(coalesce(contact_phone, contact_phone_private, ''), '\D', '', 'g') <> regexp_replace(ph, '\D', '', 'g');
    get diagnostics done = row_count;
  end if;
  return json_build_object('count', n, 'updated', done, 'phone', ph);
end $fn$;
revoke all on function public.bk_own_phone_sync(uuid, boolean, text) from public;
grant execute on function public.bk_own_phone_sync(uuid, boolean, text) to anon, authenticated;
commit;
