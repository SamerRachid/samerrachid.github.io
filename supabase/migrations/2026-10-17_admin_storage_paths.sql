-- bk-storage (upload / delete / move to trash) asks this for each file an admin touches: the permission that owns the
-- folder, and for listing files the listing's country (or the admin's own listing) (owner, 2026-10-17).
-- Paths: photos|videos/<folder>/…, photos|videos/listings/<id>/…, legacy <id>/…, avatars/…, trash/…
create or replace function public.bk_admin_can_path(p_token text, p_path text)
 returns boolean language plpgsql volatile security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; su boolean; pm text[]; f1 text; f2 text; f3 text; folder text; lid text; cc text; own boolean := false; need text[];
begin
  begin uid := bk_admin_uid(p_token); exception when others then return false; end;
  select coalesce(is_super_admin,false), coalesce(permissions,'{}'::text[]) into su, pm from users where id = uid;
  f1 := split_part(p_path,'/',1); f2 := split_part(p_path,'/',2); f3 := split_part(p_path,'/',3);
  folder := case when f1 in ('photos','videos') then f2 else f1 end;
  if f1 = 'trash' then need := array['storage'];
  elsif f1 ~ '^[0-9]+$' or (f1 in ('photos','videos') and f2 = 'listings') then
    lid := case when f1 ~ '^[0-9]+$' then f1 else f3 end;
    need := array['listings_edit','listings_delete','storage'];
    select coalesce(country_code,'SY'), (user_id = uid) into cc, own from listings where id::text = lid;
    if coalesce(own,false) then return true; end if;   -- the admin's own listing, posted from the site
  elsif folder = 'ads' then need := array['ads','storage'];
  elsif folder in ('banners','banner','background','hero') then need := array['homepage','design','storage'];
  elsif folder = 'avatars' then
    if p_path like 'avatars/' || uid::text || '-%' then return true; end if;   -- the admin's own photo
    need := array['users_edit','storage'];
  elsif folder = 'projects' then need := array['projects','storage'];
  else need := array['storage','homepage','design','ads','listings_edit'];   -- the media library's other folders
  end if;
  return (su or pm && need) and (cc is null or bk_admin_country_ok(uid, cc));
end $fn$;
revoke all on function public.bk_admin_can_path(text,text) from public, anon, authenticated;
grant execute on function public.bk_admin_can_path(text,text) to service_role;
-- bk_admin_uid deletes expired sessions, so its callers cannot be STABLE (the call failed inside a read-only function)
alter function public.bk_admin_can(text,text[]) volatile;
