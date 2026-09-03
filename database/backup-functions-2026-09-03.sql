-- Backup of every public.bk_* function as it existed on the live Balkoun database on 2026-09-03,
-- taken before the security migrations. Re-run this file to restore the old definitions.

CREATE OR REPLACE FUNCTION public.bk_admin_backup(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_data jsonb;
begin
  uid := bk_admin_uid(p_token);
  select jsonb_build_object(
    'exported_at', now(),
    'listings', (select coalesce(jsonb_agg(l), '[]'::jsonb) from listings l),
    'listing_photos', (select coalesce(jsonb_agg(p), '[]'::jsonb) from listing_photos p),
    'site_content', (select coalesce(jsonb_agg(s), '[]'::jsonb) from site_content s),
    'ad_slots', (select coalesce(jsonb_agg(a), '[]'::jsonb) from ad_slots a)
  ) into v_data;
  return v_data::json;
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_block_user(p_token text, p_user uuid, p_blocked boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update users set blocked = p_blocked where id = p_user and role <> 'admin';
  return json_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_change_own_password(p_token text, p_old text, p_new text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; u users;
begin
  uid := bk_admin_uid(p_token);
  select * into u from users where id = uid;
  if u.pass_hash is null or u.pass_hash <> crypt(p_old, u.pass_hash) then
    return json_build_object('error','badpass');
  end if;
  if length(p_new) < 6 then raise exception 'password too short'; end if;
  update users set pass_hash = crypt(encode(digest('balkoun:'||p_new,'sha256'),'hex'), gen_salt('bf'))
  where id = uid;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_clear_avatar(p_token text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update users set avatar_url = null where id = p_user;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_clear_bio(p_token text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update users set bio = null where id = p_user;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_create_admin(p_token text, p_phone text, p_name text, p_family text, p_pass text, p_permissions text[])
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_super boolean; new_id uuid;
begin
  uid := bk_admin_uid(p_token);
  select is_super_admin into v_super from users where id = uid;
  if not coalesce(v_super,false) then raise exception 'super admin only'; end if;
  if length(p_pass) < 6 then raise exception 'password too short'; end if;
  if exists (select 1 from users where phone = p_phone) then
    raise exception 'phone already registered';
  end if;
  insert into users (phone, name, family_name, role, permissions, pass_hash, phone_verified)
  values (p_phone, p_name, p_family, 'admin', coalesce(p_permissions,'{}'),
    crypt(encode(digest('balkoun:'||p_pass,'sha256'),'hex'), gen_salt('bf')), true)
  returning id into new_id;
  return json_build_object('ok', true, 'id', new_id);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_data(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return json_build_object(
    'me', (select json_build_object('id',id,'name',name,'family_name',family_name,
             'permissions',coalesce(to_jsonb(permissions),'[]'::jsonb),
             'is_super_admin',is_super_admin) from users where id = uid),

    'stats', (select json_build_object(
        'listings',   (select count(*) from listings),
        'live',       (select count(*) from listings where status='live'),
        'pending',    (select count(*) from listings where status='pending'),
        'sold',       (select count(*) from listings where status in ('sold','rented')),
        'expired',    (select count(*) from listings where status='expired'),
        'green',      (select count(*) from listings where tabu='green'),
        'users',      (select count(*) from users where role <> 'admin'),
        'photos',     (select count(*) from listing_photos),
        'reviews',    (select count(*) from reviews),
        'openReports',  (select count(*) from listing_reports where not resolved),
        'openFeedback', (select count(*) from feedback where not handled),
        'week',       (select count(*) from listings where created_at > now() - interval '7 days'),
        'value',      (select coalesce(sum(price_usd),0) from listings where status='live' and deal='sale'))),

    'listings', coalesce((select json_agg(x) from (
        select l.id, l.ref, l.status, l.deal, l.property_type, l.price_usd, l.area_m2,
               l.tabu, l.condition, l.contact_name, l.contact_phone, l.created_at, l.is_featured,
               g.name_ar as gov, a.name_ar as area,
               trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name,
               u.phone as poster_phone, u.id as poster_id,
               (select count(*) from listing_photos p where p.listing_id=l.id) as photos
          from listings l
          join governorates g on g.id=l.governorate_id
          left join areas a on a.id=l.area_id
          left join users u on u.id=l.user_id
         order by l.created_at desc limit 500) x), '[]'::json),

    'users', coalesce((select json_agg(x) from (
        select u.id, u.name, u.family_name, u.phone, u.role, u.level, u.blocked, u.skip_review,
               u.avatar_url, u.bio, u.created_at,
               (select count(*) from listings l where l.user_id=u.id) as listings,
               (select round(avg(stars)::numeric,1) from reviews where target_user=u.id) as rating
          from users u where u.role <> 'admin' order by u.created_at desc limit 500) x), '[]'::json),

    'reports', coalesce((select json_agg(x) from (
        select r.id, r.listing_id, r.reason, r.note, r.resolved, r.admin_reply, r.priority,
               r.replied_at, r.created_at,
               l.ref as listing_ref,
               trim(coalesce(ru.name,'')||' '||coalesce(ru.family_name,'')) as reporter_name,
               ru.phone as reporter_phone, ru.id as reporter_id,
               coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at)
                 from message_followups m where m.kind='report' and m.ref_id=r.id), '[]'::json) as thread
          from listing_reports r
          left join listings l on l.id = r.listing_id
          left join users ru on ru.id = r.user_id
         order by r.created_at desc limit 500) x), '[]'::json),

    'feedback', coalesce((select json_agg(x) from (
        select f.id, f.kind, f.body, f.handled, f.admin_reply, f.priority,
               f.replied_at, f.created_at,
               coalesce(trim(coalesce(fu.name,'')||' '||coalesce(fu.family_name,'')), f.name) as sender_name,
               coalesce(fu.phone, f.contact) as sender_contact, fu.id as sender_id,
               coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at)
                 from message_followups m where m.kind='feedback' and m.ref_id=f.id), '[]'::json) as thread
          from feedback f
          left join users fu on fu.id = f.user_id
         order by f.created_at desc limit 500) x), '[]'::json));
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_delete_ad(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  delete from ad_slots where id = p_id;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_delete_alert(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  delete from notifications where id=p_id and user_id=uid;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_delete_feedback(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  delete from message_followups where kind='feedback' and ref_id=p_id;
  delete from feedback where id=p_id;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_delete_listing(p_token text, p_listing bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  delete from listings where id = p_listing;
  return json_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_delete_report(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  delete from message_followups where kind='report' and ref_id=p_id;
  delete from listing_reports where id=p_id;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_delete_review(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  delete from reviews where id = p_id;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_edit_listing(p_token text, p_id bigint, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; l listings; v_old_price int; v_new_price int;
begin
  uid := bk_admin_uid(p_token);
  select * into l from listings where id = p_id;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  v_old_price := l.price_usd;
  v_new_price := coalesce((p_patch->>'price_usd')::int, l.price_usd);

  update listings set
    price_usd   = v_new_price,
    area_m2     = coalesce((p_patch->>'area_m2')::int,     area_m2),
    rooms       = case when p_patch ? 'rooms'       then (p_patch->>'rooms')::int       else rooms end,
    baths       = case when p_patch ? 'baths'       then (p_patch->>'baths')::int       else baths end,
    living_rooms = case when p_patch ? 'living_rooms' then (p_patch->>'living_rooms')::int else living_rooms end,
    floor       = case when p_patch ? 'floor'       then (p_patch->>'floor')::int       else floor end,
    year_built  = case when p_patch ? 'year_built'  then (p_patch->>'year_built')::int  else year_built end,
    power_hours = case when p_patch ? 'power_hours' then (p_patch->>'power_hours')::int else power_hours end,
    tabu        = coalesce(p_patch->>'tabu',        tabu),
    condition   = coalesce(p_patch->>'condition',   condition),
    description = coalesce(p_patch->>'description', description),
    landmark    = case when p_patch ? 'landmark' then p_patch->>'landmark' else landmark end,
    lat         = case when p_patch ? 'lat' then (p_patch->>'lat')::numeric else lat end,
    lng         = case when p_patch ? 'lng' then (p_patch->>'lng')::numeric else lng end,
    lease_months   = case when p_patch ? 'lease_months'   then (p_patch->>'lease_months')::int   else lease_months end,
    advance_months = case when p_patch ? 'advance_months' then (p_patch->>'advance_months')::int else advance_months end,
    deposit_usd    = case when p_patch ? 'deposit_usd'    then (p_patch->>'deposit_usd')::int    else deposit_usd end,
    bills_included = case when p_patch ? 'bills_included' then (p_patch->>'bills_included')::boolean else bills_included end,
    furnished      = case when p_patch ? 'furnished'      then (p_patch->>'furnished')::boolean      else furnished end,
    direction      = case when p_patch ? 'direction'      then nullif(p_patch->>'direction','')      else direction end,
    rental_period  = case when p_patch ? 'rental_period'  then nullif(p_patch->>'rental_period','')  else rental_period end,
    amenities      = case when p_patch ? 'amenities'
                          then (select coalesce(array_agg(x), '{}') from jsonb_array_elements_text(p_patch->'amenities') x)
                          else amenities end,
    contact_phone = coalesce(p_patch->>'contact_phone', contact_phone)
  where id = p_id;

  if v_new_price is distinct from v_old_price then
    insert into notifications (user_id, type, title, body, link)
    select sl.user_id, 'price', 'price_change', l.ref, '/#/listing/'||p_id
      from saved_listings sl where sl.listing_id = p_id;
  end if;

  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_feature_listing(p_token text, p_listing bigint, p_from timestamp with time zone, p_days integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  if p_days is null or p_days < 1 then raise exception 'invalid duration'; end if;
  update listings set featured_from = p_from, featured_until = p_from + (p_days || ' days')::interval
    where id = p_listing;
  perform bk_recompute_featured(p_listing);
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_get_settings(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return (select json_build_object('require_approval', require_approval) from site_settings where id=1);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_list_admins(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_super boolean;
begin
  uid := bk_admin_uid(p_token);
  select is_super_admin into v_super from users where id = uid;
  if not coalesce(v_super,false) then raise exception 'super admin only'; end if;
  return coalesce((select json_agg(x) from (
    select id, phone, name, family_name, permissions, is_super_admin, created_at
      from users where role = 'admin' order by created_at) x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_list_ads(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return coalesce((select json_agg(x order by x.position) from (
    select id, position, image_url, link_url, label, enabled, media_type,
           linked_listing_id, image_urls, video_embed_url,
           sponsor_name, starts_at, expires_at, overlay_top, overlay_bottom from ad_slots) x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_list_featured(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update listings set is_featured = (
    featured_from is not null and featured_until is not null
    and now() between featured_from and featured_until
  ) where featured_until is not null and featured_until > now() - interval '1 day';
  return coalesce((select json_agg(x order by x.featured_from) from (
    select l.id, l.ref, l.price_usd, l.featured_from, l.featured_until, l.is_featured,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name
      from listings l
      left join users u on u.id = l.user_id
     where l.featured_until is not null and l.featured_until > now() - interval '1 day') x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_listing(p_token text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; l record;
begin
  uid := bk_admin_uid(p_token);
  select ll.*, g.name_ar as gov, a.name_ar as area,
         trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as poster_name,
         u.phone as poster_phone
    into l
    from listings ll
    join governorates g on g.id = ll.governorate_id
    left join areas a on a.id = ll.area_id
    left join users u on u.id = ll.user_id
   where ll.id = p_id;
  if l.id is null then return json_build_object('error','notfound'); end if;
  return to_json(l);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_login(p_phone text, p_hash text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users; tok text;
begin
  select * into u from users where phone = p_phone;
  if u.id is null or u.role <> 'admin' then return json_build_object('error','notadmin'); end if;
  if u.pass_hash is null or u.pass_hash <> crypt(p_hash, u.pass_hash) then
    return json_build_object('error','badpass');
  end if;
  tok := encode(gen_random_bytes(24),'hex');
  insert into admin_sessions (token, user_id) values (tok, u.id);
  return json_build_object('token',tok,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,
    'bio',u.bio,'role',u.role,'permissions',coalesce(to_jsonb(u.permissions),'[]'::jsonb),
    'is_super_admin',u.is_super_admin);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_logout(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin delete from admin_sessions where token = p_token; return json_build_object('ok',true); end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_mark_notifications_read(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update notifications set is_read = true where user_id = uid and not is_read;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_move_ad(p_token text, p_id bigint, p_dir text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_pos int; v_other_id bigint; v_other_pos int;
begin
  uid := bk_admin_uid(p_token);
  select position into v_pos from ad_slots where id = p_id;
  if v_pos is null then raise exception 'not found'; end if;
  if p_dir = 'up' then
    select id, position into v_other_id, v_other_pos from ad_slots
      where position < v_pos order by position desc limit 1;
  else
    select id, position into v_other_id, v_other_pos from ad_slots
      where position > v_pos order by position asc limit 1;
  end if;
  if v_other_id is null then return json_build_object('ok', true); end if;
  update ad_slots set position = v_other_pos where id = p_id;
  update ad_slots set position = v_pos where id = v_other_id;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_notifications(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return json_build_object(
    'items', coalesce((select json_agg(x) from (
        select id, type, title, body, link, is_read, created_at
          from notifications where user_id = uid
         order by created_at desc limit 50) x), '[]'::json),
    'unread', (select count(*) from notifications where user_id = uid and not is_read));
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_photo_del(p_token text, p_photo bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  delete from listing_photos where id = p_photo;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_remove_admin(p_token text, p_admin uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_super boolean; v_target_super boolean;
begin
  uid := bk_admin_uid(p_token);
  select is_super_admin into v_super from users where id = uid;
  if not coalesce(v_super,false) then raise exception 'super admin only'; end if;
  select is_super_admin into v_target_super from users where id = p_admin;
  if coalesce(v_target_super,false) then raise exception 'cannot remove a super admin'; end if;
  update users set role = 'owner', permissions = '{}' where id = p_admin;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_reply(p_token text, p_kind text, p_id bigint, p_reply text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_user uuid;
begin
  uid := bk_admin_uid(p_token);
  if p_kind = 'feedback' then
    update feedback set admin_reply=p_reply, replied_at=now() where id=p_id
      returning user_id into v_user;
    insert into message_followups (kind, ref_id, sender, body) values ('feedback', p_id, 'admin', p_reply);
    if v_user is not null then
      insert into notifications (user_id, type, title, body, link)
      values (v_user, 'reply', 'reply_feedback', p_reply, '/#/msgs?feedback='||p_id);
    end if;
  elsif p_kind = 'report' then
    update listing_reports set admin_reply=p_reply, replied_at=now() where id=p_id
      returning user_id into v_user;
    insert into message_followups (kind, ref_id, sender, body) values ('report', p_id, 'admin', p_reply);
    if v_user is not null then
      insert into notifications (user_id, type, title, body, link)
      values (v_user, 'reply', 'reply_report', p_reply, '/#/msgs?report='||p_id);
    end if;
  end if;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_reset_ads(p_token text, p_confirm text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_safety jsonb; v_count int;
begin
  uid := bk_admin_uid(p_token);
  if p_confirm is distinct from 'DELETE ALL AD SQUARES' then
    raise exception 'confirmation phrase did not match';
  end if;

  select count(*) into v_count from ad_slots;
  select jsonb_build_object('ad_slots', coalesce(jsonb_agg(a), '[]'::jsonb)) into v_safety from ad_slots a;
  insert into backup_snapshots (created_by, reason, data)
    values (uid, 'auto-backup before bk_admin_reset_ads', v_safety);

  truncate table ad_slots;

  return json_build_object('ok', true, 'deleted', v_count);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_reset_listings(p_token text, p_confirm text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_backup jsonb; v_count int;
begin
  uid := bk_admin_uid(p_token);
  if p_confirm is distinct from 'DELETE ALL LISTINGS' then
    raise exception 'confirmation phrase did not match';
  end if;

  select count(*) into v_count from listings;

  select jsonb_build_object(
    'listings', (select coalesce(jsonb_agg(l), '[]'::jsonb) from listings l),
    'listing_photos', (select coalesce(jsonb_agg(p), '[]'::jsonb) from listing_photos p)
  ) into v_backup;
  insert into backup_snapshots (created_by, reason, data)
    values (uid, 'auto-backup before bk_admin_reset_listings', v_backup);

  delete from ad_slots where linked_listing_id is not null;
  truncate table listing_photos, listing_reports, saved_listings, contact_events, price_history, listings;

  return json_build_object('ok', true, 'deleted', v_count);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_reset_password(p_token text, p_user uuid, p_new_pass text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_admin uuid;
begin
  v_admin := bk_admin_uid(p_token);
  if length(p_new_pass) < 6 then raise exception 'password too short'; end if;
  update users set pass_hash = crypt(encode(digest('balkoun:'||p_new_pass,'sha256'),'hex'), gen_salt('bf'))
  where id = p_user;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_reset_users(p_token text, p_confirm text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_safety jsonb; v_count int;
begin
  uid := bk_admin_uid(p_token);
  if p_confirm is distinct from 'DELETE ALL USERS' then
    raise exception 'confirmation phrase did not match';
  end if;

  select count(*) into v_count from users where role is distinct from 'admin';
  select jsonb_build_object('users', coalesce(jsonb_agg(u), '[]'::jsonb))
    into v_safety from users u where role is distinct from 'admin';
  insert into backup_snapshots (created_by, reason, data)
    values (uid, 'auto-backup before bk_admin_reset_users', v_safety);

  delete from users where role is distinct from 'admin';

  return json_build_object('ok', true, 'deleted', v_count);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_restore_backup(p_token text, p_data jsonb, p_confirm text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_safety jsonb; v_listing_count int;
begin
  uid := bk_admin_uid(p_token);
  if p_confirm is distinct from 'RESTORE FROM BACKUP' then
    raise exception 'confirmation phrase did not match';
  end if;
  if p_data is null or not (p_data ? 'listings') then
    raise exception 'this does not look like a valid Balkoun backup file';
  end if;

  select jsonb_build_object(
    'listings', (select coalesce(jsonb_agg(l), '[]'::jsonb) from listings l),
    'listing_photos', (select coalesce(jsonb_agg(p), '[]'::jsonb) from listing_photos p),
    'ad_slots', (select coalesce(jsonb_agg(a), '[]'::jsonb) from ad_slots a)
  ) into v_safety;
  insert into backup_snapshots (created_by, reason, data)
    values (uid, 'auto-backup before bk_admin_restore_backup', v_safety);

  truncate table listing_photos, listing_reports, saved_listings, contact_events, price_history, listings, ad_slots;

  insert into listings select * from jsonb_populate_recordset(null::listings, p_data->'listings');
  if p_data ? 'listing_photos' then
    insert into listing_photos select * from jsonb_populate_recordset(null::listing_photos, p_data->'listing_photos');
  end if;
  if p_data ? 'ad_slots' then
    insert into ad_slots select * from jsonb_populate_recordset(null::ad_slots, p_data->'ad_slots');
  end if;
  if p_data ? 'site_content' and jsonb_array_length(p_data->'site_content') > 0 then
    update site_content sc set (
      hero_enabled, hero_ar, hero_en, hero_de, hero_sub_ar, hero_sub_en, hero_sub_de,
      stats_enabled, stats_areas_num, stats_listings_num, stats_use_real_count,
      stats1_ar, stats1_en, stats1_de, stats2_ar, stats2_en, stats2_de,
      fb_url, ig_url, yt_url, tiktok_url, wa_number, phone_number, email_address,
      ad_tag_enabled, ad_tag_size, ad_tag_ar, ad_tag_en, ad_tag_de,
      ad_square_size, ad_use_icons, ad_roominfo_size, ad_location_enabled, ad_location_size,
      ad_text_color, ad_shade_color, featured_badge_enabled, featured_badge_ar, featured_badge_en,
      featured_badge_de, featured_brightness, card_min_width, new_badge_hours, storage_limit_mb
    ) = (
      select r.hero_enabled, r.hero_ar, r.hero_en, r.hero_de, r.hero_sub_ar, r.hero_sub_en, r.hero_sub_de,
        r.stats_enabled, r.stats_areas_num, r.stats_listings_num, r.stats_use_real_count,
        r.stats1_ar, r.stats1_en, r.stats1_de, r.stats2_ar, r.stats2_en, r.stats2_de,
        r.fb_url, r.ig_url, r.yt_url, r.tiktok_url, r.wa_number, r.phone_number, r.email_address,
        r.ad_tag_enabled, r.ad_tag_size, r.ad_tag_ar, r.ad_tag_en, r.ad_tag_de,
        r.ad_square_size, r.ad_use_icons, r.ad_roominfo_size, r.ad_location_enabled, r.ad_location_size,
        r.ad_text_color, r.ad_shade_color, r.featured_badge_enabled, r.featured_badge_ar, r.featured_badge_en,
        r.featured_badge_de, r.featured_brightness, r.card_min_width, r.new_badge_hours, r.storage_limit_mb
      from jsonb_populate_record(null::site_content, p_data->'site_content'->0) r
    )
    where sc.id = 1;
  end if;

  perform setval(pg_get_serial_sequence('listings','id'), coalesce((select max(id) from listings),1));
  perform setval(pg_get_serial_sequence('listing_photos','id'), coalesce((select max(id) from listing_photos),1));
  perform setval(pg_get_serial_sequence('ad_slots','id'), coalesce((select max(id) from ad_slots),1));

  select count(*) into v_listing_count from listings;
  return json_build_object('ok', true, 'restored_listings', v_listing_count);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_review_set(p_token text, p_target uuid, p_stars integer, p_body text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_admin uuid;
begin
  v_admin := bk_admin_uid(p_token);
  if p_stars < 1 or p_stars > 5 then raise exception 'bad rating'; end if;
  insert into reviews (target_user, author_user, stars, body)
  values (p_target, v_admin, p_stars, p_body)
  on conflict (target_user, author_user)
  do update set stars=excluded.stars, body=excluded.body, created_at=now();
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_reviews(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  return coalesce((select json_agg(x) from (
    select r.id, r.stars, r.body, r.created_at,
           trim(coalesce(au.name,'')||' '||coalesce(au.family_name,'')) as author_name,
           au.phone as author_phone,
           trim(coalesce(tu.name,'')||' '||coalesce(tu.family_name,'')) as target_name,
           tu.phone as target_phone
      from reviews r
      join users au on au.id = r.author_user
      join users tu on tu.id = r.target_user
     order by r.created_at desc limit 300) x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_save_ad(p_token text, p_id bigint, p_position integer, p_image_url text, p_link_url text, p_label text, p_enabled boolean, p_media_type text, p_linked_listing_id bigint, p_image_urls jsonb, p_video_embed_url text, p_sponsor_name text DEFAULT NULL::text, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_overlay_top text DEFAULT NULL::text, p_overlay_bottom text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_id bigint; v_pos int;
begin
  uid := bk_admin_uid(p_token);
  if p_id is null then
    select coalesce(max(position),0)+1 into v_pos from ad_slots;
    insert into ad_slots (position, image_url, link_url, label, enabled, media_type,
        linked_listing_id, image_urls, video_embed_url, sponsor_name, starts_at, expires_at,
        overlay_top, overlay_bottom)
      values (v_pos, p_image_url, p_link_url, p_label, coalesce(p_enabled,true),
        coalesce(p_media_type,'image'), p_linked_listing_id,
        coalesce(p_image_urls,'[]'::jsonb), p_video_embed_url, p_sponsor_name, p_starts_at, p_expires_at,
        p_overlay_top, p_overlay_bottom)
      returning id into v_id;
  else
    update ad_slots set image_url=p_image_url, link_url=p_link_url,
      label=p_label, enabled=coalesce(p_enabled,true), media_type=coalesce(p_media_type,'image'),
      linked_listing_id=p_linked_listing_id, image_urls=coalesce(p_image_urls,'[]'::jsonb),
      video_embed_url=p_video_embed_url, sponsor_name=p_sponsor_name,
      starts_at=p_starts_at, expires_at=p_expires_at,
      overlay_top=p_overlay_top, overlay_bottom=p_overlay_bottom where id=p_id;
    v_id := p_id;
  end if;
  return json_build_object('ok', true, 'id', v_id);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_send_notification(p_token text, p_user uuid, p_all boolean, p_title text, p_body text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_count int;
begin
  uid := bk_admin_uid(p_token);
  if coalesce(p_all,false) then
    insert into notifications (user_id, type, title, body)
    select id, 'admin_msg', p_title, p_body from users where role <> 'admin';
    get diagnostics v_count = row_count;
  else
    insert into notifications (user_id, type, title, body) values (p_user, 'admin_msg', p_title, p_body);
    v_count := 1;
  end if;
  return json_build_object('ok', true, 'sent', v_count);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_set_approval_mode(p_token text, p_require boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update site_settings set require_approval = p_require where id = 1;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_set_content(p_token text, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update site_content set
    hero_enabled       = coalesce((p_patch->>'hero_enabled')::boolean, hero_enabled),
    hero_ar             = coalesce(p_patch->>'hero_ar', hero_ar),
    hero_en             = coalesce(p_patch->>'hero_en', hero_en),
    hero_de             = coalesce(p_patch->>'hero_de', hero_de),
    hero_sub_ar         = coalesce(p_patch->>'hero_sub_ar', hero_sub_ar),
    hero_sub_en         = coalesce(p_patch->>'hero_sub_en', hero_sub_en),
    hero_sub_de         = coalesce(p_patch->>'hero_sub_de', hero_sub_de),
    hero_bg_type        = coalesce(p_patch->>'hero_bg_type', hero_bg_type),
    hero_bg_video_url   = coalesce(p_patch->>'hero_bg_video_url', hero_bg_video_url),
    hero_bg_photo_url   = coalesce(p_patch->>'hero_bg_photo_url', hero_bg_photo_url),
    hero_gap            = coalesce((p_patch->>'hero_gap')::int, hero_gap),
    hero_bg_video_speed = coalesce((p_patch->>'hero_bg_video_speed')::int, hero_bg_video_speed),
    hero_title_size     = coalesce(p_patch->>'hero_title_size', hero_title_size),
    hero_title_color    = coalesce(p_patch->>'hero_title_color', hero_title_color),
    hero_sub_color      = coalesce(p_patch->>'hero_sub_color', hero_sub_color),
    banner_enabled      = coalesce((p_patch->>'banner_enabled')::boolean, banner_enabled),
    banner_media_type   = coalesce(p_patch->>'banner_media_type', banner_media_type),
    banner_image_url    = coalesce(p_patch->>'banner_image_url', banner_image_url),
    banner_video_url    = coalesce(p_patch->>'banner_video_url', banner_video_url),
    banner_link_url     = coalesce(p_patch->>'banner_link_url', banner_link_url),
    banner_items        = coalesce(p_patch->>'banner_items', banner_items),
    banners_config      = coalesce(p_patch->>'banners_config', banners_config),
    banner_rotation_seconds = coalesce((p_patch->>'banner_rotation_seconds')::int, banner_rotation_seconds),
    banner_transition   = coalesce(p_patch->>'banner_transition', banner_transition),
    banner_size         = coalesce(p_patch->>'banner_size', banner_size),
    banner_custom_w     = coalesce((p_patch->>'banner_custom_w')::int, banner_custom_w),
    banner_custom_h     = coalesce((p_patch->>'banner_custom_h')::int, banner_custom_h),
    banner_gap          = coalesce((p_patch->>'banner_gap')::int, banner_gap),
    banner_text_enabled = coalesce((p_patch->>'banner_text_enabled')::boolean, banner_text_enabled),
    banner_text_size    = coalesce((p_patch->>'banner_text_size')::int, banner_text_size),
    banner_text_color   = coalesce(p_patch->>'banner_text_color', banner_text_color),
    banner_text_ar      = coalesce(p_patch->>'banner_text_ar', banner_text_ar),
    banner_text_en      = coalesce(p_patch->>'banner_text_en', banner_text_en),
    banner_text_de      = coalesce(p_patch->>'banner_text_de', banner_text_de),
    stats_enabled       = coalesce((p_patch->>'stats_enabled')::boolean, stats_enabled),
    stats_areas_num     = coalesce(p_patch->>'stats_areas_num', stats_areas_num),
    stats_listings_num  = coalesce(p_patch->>'stats_listings_num', stats_listings_num),
    stats_use_real_count = coalesce((p_patch->>'stats_use_real_count')::boolean, stats_use_real_count),
    stats1_ar = coalesce(p_patch->>'stats1_ar', stats1_ar),
    stats1_en = coalesce(p_patch->>'stats1_en', stats1_en),
    stats1_de = coalesce(p_patch->>'stats1_de', stats1_de),
    stats2_ar = coalesce(p_patch->>'stats2_ar', stats2_ar),
    stats2_en = coalesce(p_patch->>'stats2_en', stats2_en),
    stats2_de = coalesce(p_patch->>'stats2_de', stats2_de),
    fb_url = coalesce(p_patch->>'fb_url', fb_url),
    ig_url = coalesce(p_patch->>'ig_url', ig_url),
    yt_url = coalesce(p_patch->>'yt_url', yt_url),
    fb_name = coalesce(p_patch->>'fb_name', fb_name),
    ig_name = coalesce(p_patch->>'ig_name', ig_name),
    yt_name = coalesce(p_patch->>'yt_name', yt_name),
    tiktok_name = coalesce(p_patch->>'tiktok_name', tiktok_name),
    tiktok_url = coalesce(p_patch->>'tiktok_url', tiktok_url),
    wa_number = coalesce(p_patch->>'wa_number', wa_number),
    phone_number = coalesce(p_patch->>'phone_number', phone_number),
    email_address = coalesce(p_patch->>'email_address', email_address),
    ad_tag_enabled = coalesce((p_patch->>'ad_tag_enabled')::boolean, ad_tag_enabled),
    ad_tag_size = coalesce((p_patch->>'ad_tag_size')::int, ad_tag_size),
    ad_tag_ar = coalesce(p_patch->>'ad_tag_ar', ad_tag_ar),
    ad_tag_en = coalesce(p_patch->>'ad_tag_en', ad_tag_en),
    ad_tag_de = coalesce(p_patch->>'ad_tag_de', ad_tag_de),
    ad_square_size = coalesce((p_patch->>'ad_square_size')::int, ad_square_size),
    ad_carousel_seconds = coalesce((p_patch->>'ad_carousel_seconds')::numeric, ad_carousel_seconds),
    ad_carousel_direction = coalesce(p_patch->>'ad_carousel_direction', ad_carousel_direction),
    ad_carousel_gap = coalesce((p_patch->>'ad_carousel_gap')::int, ad_carousel_gap),
    ad_use_icons = coalesce((p_patch->>'ad_use_icons')::boolean, ad_use_icons),
    ad_roominfo_size = coalesce((p_patch->>'ad_roominfo_size')::int, ad_roominfo_size),
    ad_location_enabled = coalesce((p_patch->>'ad_location_enabled')::boolean, ad_location_enabled),
    ad_location_size = coalesce((p_patch->>'ad_location_size')::int, ad_location_size),
    ad_text_color = coalesce(p_patch->>'ad_text_color', ad_text_color),
    ad_shade_color = coalesce(p_patch->>'ad_shade_color', ad_shade_color),
    featured_badge_enabled = coalesce((p_patch->>'featured_badge_enabled')::boolean, featured_badge_enabled),
    featured_badge_ar = coalesce(p_patch->>'featured_badge_ar', featured_badge_ar),
    featured_badge_en = coalesce(p_patch->>'featured_badge_en', featured_badge_en),
    featured_badge_de = coalesce(p_patch->>'featured_badge_de', featured_badge_de),
    featured_brightness = coalesce((p_patch->>'featured_brightness')::int, featured_brightness),
    card_min_width = coalesce((p_patch->>'card_min_width')::int, card_min_width),
    card_min_width_mobile = coalesce((p_patch->>'card_min_width_mobile')::int, card_min_width_mobile),
    new_badge_hours = coalesce((p_patch->>'new_badge_hours')::int, new_badge_hours),
    storage_limit_mb = coalesce((p_patch->>'storage_limit_mb')::int, storage_limit_mb),
    syp_rate = coalesce((p_patch->>'syp_rate')::int, syp_rate)
  where id = 1;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_set_level(p_token text, p_user uuid, p_level text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update users set level = p_level where id = p_user and role <> 'admin';
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_set_permissions(p_token text, p_admin uuid, p_permissions text[])
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_super boolean;
begin
  uid := bk_admin_uid(p_token);
  select is_super_admin into v_super from users where id = uid;
  if not coalesce(v_super,false) then raise exception 'super admin only'; end if;
  update users set permissions = coalesce(p_permissions,'{}') where id = p_admin and role = 'admin';
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_set_priority(p_token text, p_kind text, p_id bigint, p_priority text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  if p_priority not in ('low','normal','high','urgent') then raise exception 'bad priority'; end if;
  if p_kind = 'feedback' then
    update feedback set priority = p_priority where id = p_id;
  elsif p_kind = 'report' then
    update listing_reports set priority = p_priority where id = p_id;
  end if;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_set_skip_review(p_token text, p_user uuid, p_skip boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update users set skip_review = p_skip where id = p_user;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_set_solved(p_token text, p_kind text, p_id bigint, p_solved boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  if p_kind = 'feedback' then
    update feedback set handled = p_solved where id = p_id;
  elsif p_kind = 'report' then
    update listing_reports set resolved = p_solved where id = p_id;
  end if;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_set_status(p_token text, p_listing bigint, p_status text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update listings set status = p_status,
         published_at = case when p_status='live' then now() else published_at end
   where id = p_listing;
  return json_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_stats(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_admin uuid;
begin
  v_admin := bk_admin_uid(p_token);
  return json_build_object(
    'views_today',    (select count(*) from page_views where created_at > current_date),
    'views_week',     (select count(*) from page_views where created_at > now() - interval '7 days'),
    'views_total',    (select count(*) from page_views),
    'visitors_week',  (select count(distinct coalesce(user_id::text, path||date_trunc('day',created_at)::text))
                        from page_views where created_at > now() - interval '7 days'),
    'members_total',  (select count(*) from users where role <> 'admin'),
    'members_week',   (select count(*) from users where created_at > now() - interval '7 days'),
    'online_now',     (select count(*) from online_presence where last_seen > now() - interval '5 minutes'),
    'online_list',    coalesce((select json_agg(x) from (
                        select trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as name,
                               u.id, p.last_seen
                          from online_presence p join users u on u.id = p.user_id
                         where p.last_seen > now() - interval '5 minutes'
                         order by p.last_seen desc limit 50) x), '[]'::json),
    'by_country',     coalesce((select json_object_agg(country, n) from (
                        select coalesce(country,'unknown') country, count(*) n from page_views
                         where created_at > now() - interval '30 days'
                         group by 1 order by 2 desc limit 15) x), '{}'::json),
    'by_view',        coalesce((select json_object_agg(view, n) from (
                        select coalesce(view,'home') view, count(*) n from page_views
                         where created_at > now() - interval '30 days'
                         group by 1 order by 2 desc limit 15) y), '{}'::json));
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_storage_usage(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; v_bytes bigint; v_count int;
begin
  uid := bk_admin_uid(p_token);
  select coalesce(sum((metadata->>'size')::bigint), 0), count(*)
    into v_bytes, v_count
    from storage.objects where bucket_id = 'photos';
  return json_build_object('bytes', v_bytes, 'files', v_count);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_switch_to_user(p_token text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid; u users;
begin
  uid := bk_admin_uid(p_token);
  select * into u from users where id = uid;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,
                           'family_name',u.family_name,'role',u.role);
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_uid(p_token text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  delete from admin_sessions where expires_at < now();
  select s.user_id into uid from admin_sessions s
    join users u on u.id = s.user_id
   where s.token = p_token and s.expires_at > now() and u.role = 'admin';
  if uid is null then raise exception 'unauthorised'; end if;
  return uid;
end $function$


CREATE OR REPLACE FUNCTION public.bk_admin_unfeature_listing(p_token text, p_listing bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update listings set featured_from = null, featured_until = null, is_featured = false
    where id = p_listing;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_by_user(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return coalesce((select json_agg(x) from (
    select l.*, g.name_ar as governorate_ar, a.name_ar as area_ar,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as owner_name,
           (select coalesce(thumb_url,url) from listing_photos p
             where p.listing_id=l.id order by sort_order limit 1) as cover_url
      from listings l
      join governorates g on g.id=l.governorate_id
      left join areas a on a.id=l.area_id
      left join users u on u.id=l.user_id
     where l.user_id = p_user
       and (l.status='live'
            or (l.status in ('sold','rented') and l.closed_at > now() - interval '7 days'))
     order by l.created_at desc) x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_change_password(p_id uuid, p_old text, p_new text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  select * into u from users where id = p_id;
  if u.id is null then return json_build_object('error','nouser'); end if;
  if u.pass_hash is null or u.pass_hash <> crypt(p_old, u.pass_hash) then
    return json_build_object('error','badpass');
  end if;
  update users set pass_hash = crypt(p_new, gen_salt('bf')) where id = p_id;
  return json_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_change_phone(p_id uuid, p_pass text, p_new_phone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  select * into u from users where id = p_id;
  if u.id is null then return json_build_object('error','nouser'); end if;
  if u.pass_hash is null or u.pass_hash <> crypt(p_pass, u.pass_hash) then
    return json_build_object('error','badpass');
  end if;
  if exists (select 1 from users where phone = p_new_phone and id <> p_id) then
    return json_build_object('error','exists');
  end if;
  update users set phone = p_new_phone where id = p_id;
  select * into u from users where id = p_id;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,
                           'family_name',u.family_name,'role',u.role);
end $function$


CREATE OR REPLACE FUNCTION public.bk_contact(p_listing bigint, p_user uuid, p_kind text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  insert into contact_events (listing_id, user_id, kind) values (p_listing, p_user, p_kind);
  update listings set views = views + 1 where id = p_listing;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_counts()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return json_build_object(
    'total',  (select count(*) from listings where status='live'),
    'green',  (select count(*) from listings where status='live' and tabu='green'),
    'owner',  (select count(*) from listings where status='live' and by_owner=true),
    'week',   (select count(*) from listings where status='live'
                and created_at > now() - interval '7 days'),
    'byType', coalesce((select json_object_agg(property_type, n) from (
                select property_type, count(*) n from listings
                 where status='live' group by property_type) x), '{}'::json),
    'byGov',  coalesce((select json_object_agg(name_ar, n) from (
                select g.name_ar, count(*) n from listings l
                  join governorates g on g.id=l.governorate_id
                 where l.status='live' group by g.name_ar) y), '{}'::json),
    'byDeal', coalesce((select json_object_agg(deal, n) from (
                select deal, count(*) n from listings
                 where status='live' group by deal) z), '{}'::json),
    'byTypeDeal', coalesce((select json_object_agg(key, n) from (
                select property_type||':'||deal as key, count(*) n from listings
                 where status='live' group by property_type, deal) w), '{}'::json));
end $function$


CREATE OR REPLACE FUNCTION public.bk_edit(p_user uuid, p_id bigint, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare l listings; v_old_price int; v_new_price int;
begin
  select * into l from listings where id = p_id;
  if l.id is null then return json_build_object('error','nolisting'); end if;
  if l.user_id is distinct from p_user then return json_build_object('error','notyours'); end if;
  v_old_price := l.price_usd;
  v_new_price := coalesce((p_patch->>'price_usd')::int, l.price_usd);

  update listings set
    price_usd   = v_new_price,
    area_m2     = coalesce((p_patch->>'area_m2')::int,     area_m2),
    rooms       = case when p_patch ? 'rooms'       then (p_patch->>'rooms')::int       else rooms end,
    baths       = case when p_patch ? 'baths'       then (p_patch->>'baths')::int       else baths end,
    living_rooms = case when p_patch ? 'living_rooms' then (p_patch->>'living_rooms')::int else living_rooms end,
    floor       = case when p_patch ? 'floor'       then (p_patch->>'floor')::int       else floor end,
    year_built  = case when p_patch ? 'year_built'  then (p_patch->>'year_built')::int  else year_built end,
    power_hours = case when p_patch ? 'power_hours' then (p_patch->>'power_hours')::int else power_hours end,
    tabu        = coalesce(p_patch->>'tabu',        tabu),
    condition   = coalesce(p_patch->>'condition',   condition),
    description = coalesce(p_patch->>'description', description),
    landmark    = case when p_patch ? 'landmark' then p_patch->>'landmark' else landmark end,
    lat         = case when p_patch ? 'lat' then (p_patch->>'lat')::numeric else lat end,
    lng         = case when p_patch ? 'lng' then (p_patch->>'lng')::numeric else lng end,
    lease_months   = case when p_patch ? 'lease_months'   then (p_patch->>'lease_months')::int   else lease_months end,
    advance_months = case when p_patch ? 'advance_months' then (p_patch->>'advance_months')::int else advance_months end,
    deposit_usd    = case when p_patch ? 'deposit_usd'    then (p_patch->>'deposit_usd')::int    else deposit_usd end,
    bills_included = case when p_patch ? 'bills_included' then (p_patch->>'bills_included')::boolean else bills_included end,
    furnished      = case when p_patch ? 'furnished'      then (p_patch->>'furnished')::boolean      else furnished end,
    direction      = case when p_patch ? 'direction'      then nullif(p_patch->>'direction','')      else direction end,
    rental_period  = case when p_patch ? 'rental_period'  then nullif(p_patch->>'rental_period','')  else rental_period end,
    amenities      = case when p_patch ? 'amenities'
                          then (select coalesce(array_agg(x), '{}') from jsonb_array_elements_text(p_patch->'amenities') x)
                          else amenities end,
    contact_phone = coalesce(p_patch->>'contact_phone', contact_phone)
  where id = p_id;

  if v_new_price is distinct from v_old_price then
    insert into notifications (user_id, type, title, body, link)
    select sl.user_id, 'price', 'price_change', l.ref, '/#/listing/'||p_id
      from saved_listings sl where sl.listing_id = p_id;
  end if;

  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_feedback(p_kind text, p_name text, p_contact text, p_body text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_id bigint;
begin
  insert into feedback (kind, name, contact, body, user_id)
    values (p_kind, p_name, p_contact, p_body, p_user)
    returning id into v_id;
  insert into notifications (user_id, type, title, body, link)
  select id, 'admin_alert', 'new_feedback', p_body, '/#/admin:feedback'
    from users where role = 'admin';
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_heartbeat(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if p_user is null then return; end if;
  insert into online_presence (user_id, last_seen) values (p_user, now())
    on conflict (user_id) do update set last_seen = now();
end $function$


CREATE OR REPLACE FUNCTION public.bk_log_view(p_path text, p_view text, p_user uuid, p_country text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  insert into page_views (path, view, user_id, country) values (p_path, p_view, p_user, p_country);
end $function$


CREATE OR REPLACE FUNCTION public.bk_login(p_phone text, p_hash text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  select * into u from users where phone = p_phone;
  if u.id is null then return json_build_object('error','nouser'); end if;
  if u.pass_hash is null or u.pass_hash <> crypt(p_hash, u.pass_hash) then
    return json_build_object('error','badpass');
  end if;
  update users set last_seen_at = now() where id = u.id;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role,'preferred_currency',u.preferred_currency);
end $function$


CREATE OR REPLACE FUNCTION public.bk_mark_notifications_read(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  update notifications set is_read = true where user_id = p_user and not is_read;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_me(p_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  select * into u from users where id = p_id and not blocked;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,
                           'family_name',u.family_name,'role',u.role);
end $function$


CREATE OR REPLACE FUNCTION public.bk_member_delete_message(p_user uuid, p_kind text, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_owner uuid;
begin
  if p_kind = 'report' then
    select user_id into v_owner from listing_reports where id = p_id;
    if v_owner is distinct from p_user then raise exception 'not yours'; end if;
    delete from message_followups where kind='report' and ref_id=p_id;
    delete from notifications where user_id=p_user and link='/#/msgs?report='||p_id;
    delete from listing_reports where id = p_id;
  elsif p_kind = 'feedback' then
    select user_id into v_owner from feedback where id = p_id;
    if v_owner is distinct from p_user then raise exception 'not yours'; end if;
    delete from message_followups where kind='feedback' and ref_id=p_id;
    delete from notifications where user_id=p_user and link='/#/msgs?feedback='||p_id;
    delete from feedback where id = p_id;
  end if;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_member_reply(p_user uuid, p_kind text, p_id bigint, p_body text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_owner uuid;
begin
  if p_user is null then raise exception 'not logged in'; end if;
  if length(trim(p_body)) < 1 then raise exception 'empty message'; end if;
  if p_kind = 'report' then
    select user_id into v_owner from listing_reports where id = p_id;
  elsif p_kind = 'feedback' then
    select user_id into v_owner from feedback where id = p_id;
  else
    raise exception 'bad kind';
  end if;
  if v_owner is distinct from p_user then raise exception 'not yours'; end if;
  insert into message_followups (kind, ref_id, sender, body) values (p_kind, p_id, 'member', p_body);
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_my_messages(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if p_user is null then return json_build_object('reports','[]'::json,'feedback','[]'::json); end if;
  return json_build_object(
    'reports', coalesce((select json_agg(x) from (
        select r.id, r.listing_id, r.reason, r.note, r.resolved,
               r.admin_reply, r.replied_at, r.created_at,
               l.ref as listing_ref,
               coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at)
                 from message_followups m where m.kind='report' and m.ref_id=r.id), '[]'::json) as thread
          from listing_reports r
          left join listings l on l.id = r.listing_id
         where r.user_id = p_user
         order by r.created_at desc) x), '[]'::json),
    'feedback', coalesce((select json_agg(x) from (
        select f.id, f.kind, f.body, f.handled, f.admin_reply, f.replied_at, f.created_at,
               coalesce((select json_agg(json_build_object('sender',m.sender,'body',m.body,'created_at',m.created_at) order by m.created_at)
                 from message_followups m where m.kind='feedback' and m.ref_id=f.id), '[]'::json) as thread
          from feedback f
         where f.user_id = p_user
         order by f.created_at desc) x), '[]'::json));
end $function$


CREATE OR REPLACE FUNCTION public.bk_my_notifications(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if p_user is null then return json_build_object('items','[]'::json,'unread',0); end if;
  return json_build_object(
    'items', coalesce((select json_agg(x) from (
        select id, type, title, body, link, is_read, created_at
          from notifications where user_id = p_user
         order by created_at desc limit 50) x), '[]'::json),
    'unread', (select count(*) from notifications where user_id = p_user and not is_read));
end $function$


CREATE OR REPLACE FUNCTION public.bk_own_delete(p_user uuid, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if not exists (select 1 from listings where id=p_id and user_id=p_user) then
    return json_build_object('error','notyours');
  end if;
  delete from listings where id = p_id;   -- photos and saves cascade
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_own_status(p_user uuid, p_id bigint, p_status text, p_reason text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare l listings;
begin
  select * into l from listings where id = p_id;
  if l.id is null or l.user_id is distinct from p_user then
    return json_build_object('error','notyours');
  end if;
  update listings set status = p_status, closed_reason = p_reason, closed_at = now()
    where id = p_id;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_photo_add(p_user uuid, p_listing bigint, p_url text, p_thumb text, p_sort integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if not exists (select 1 from listings where id=p_listing and user_id=p_user) then
    return json_build_object('error','notyours');
  end if;
  insert into listing_photos (listing_id,url,thumb_url,sort_order)
    values (p_listing,p_url,p_thumb,p_sort);
  return json_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_photo_del(p_user uuid, p_photo bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  delete from listing_photos p using listings l
   where p.id=p_photo and l.id=p.listing_id and l.user_id=p_user;
  return json_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_photos(p_listing bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return coalesce((select json_agg(x) from (
    select id, url, thumb_url, sort_order from listing_photos
     where listing_id=p_listing order by sort_order) x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_profile(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  select * into u from users where id = p_user;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object(
    'id',u.id,'name',u.name,'family_name',u.family_name,
    'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'deed_verified',u.deed_verified,'role',u.role,'level',u.level,
    'created_at',u.created_at,
    'live',  (select count(*) from listings l where l.user_id=u.id and l.status='live'),
    'sold',  (select count(*) from listings l where l.user_id=u.id and l.status in ('sold','rented')),
    'total', (select count(*) from listings l where l.user_id=u.id),
    'reviews', (select bk_reviews_for(u.id)));
end $function$


CREATE OR REPLACE FUNCTION public.bk_public_ad_slots()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return coalesce((select json_agg(x order by x.position) from (
    select a.id, a.position, a.image_url, a.link_url, a.label, a.media_type,
           a.linked_listing_id, a.image_urls, a.video_embed_url, a.sponsor_name,
           a.overlay_top, a.overlay_bottom,
           l.ref as l_ref, l.rooms as l_rooms, l.baths as l_baths, l.area_m2 as l_area,
           g.name_ar as l_gov, ar.name_ar as l_area_name,
           coalesce((select json_agg(p.url order by p.sort_order)
                     from listing_photos p where p.listing_id = l.id), '[]'::json) as l_photos
      from ad_slots a
      left join listings l on l.id = a.linked_listing_id and l.status = 'live'
      left join governorates g on g.id = l.governorate_id
      left join areas ar on ar.id = l.area_id
     where a.enabled = true
       and (a.starts_at is null or a.starts_at <= now())
       and (a.expires_at is null or a.expires_at >= now())) x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_public_featured_ids()
 RETURNS json
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
  select coalesce(json_agg(id), '[]'::json) from listings
    where is_featured = true and status = 'live';
$function$


CREATE OR REPLACE FUNCTION public.bk_recompute_featured(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  update listings set is_featured = (
    featured_from is not null and featured_until is not null
    and now() between featured_from and featured_until
  ) where id = p_id;
end $function$


CREATE OR REPLACE FUNCTION public.bk_register(p_phone text, p_name text, p_family text, p_hash text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  if exists (select 1 from users where phone = p_phone) then
    return json_build_object('error','exists');
  end if;
  insert into users (phone, name, family_name, pass_hash, phone_verified)
    values (p_phone, p_name, p_family, crypt(p_hash, gen_salt('bf')), true)
    returning * into u;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name);
end $function$


CREATE OR REPLACE FUNCTION public.bk_register(p_phone text, p_name text, p_family text, p_hash text, p_username text DEFAULT NULL::text, p_city text DEFAULT NULL::text, p_country text DEFAULT NULL::text, p_currency text DEFAULT 'SYP'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users; v_currency text;
begin
  if exists (select 1 from users where phone = p_phone) then
    return json_build_object('error','exists');
  end if;
  if p_username is not null and exists
     (select 1 from users where lower(username) = lower(p_username)) then
    return json_build_object('error','usertaken');
  end if;
  v_currency := case when p_currency in ('USD','SYP') then p_currency else 'SYP' end;
  insert into users (phone, username, name, family_name, pass_hash, phone_verified, city, country, preferred_currency)
    values (p_phone, p_username, p_name, p_family, crypt(p_hash, gen_salt('bf')), true, p_city, p_country, v_currency)
    returning * into u;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
                           'city',u.city,'country',u.country,'preferred_currency',u.preferred_currency);
end $function$


CREATE OR REPLACE FUNCTION public.bk_report(p_listing bigint, p_reason text, p_note text, p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  insert into listing_reports (listing_id, reason, note, user_id)
    values (p_listing, p_reason, p_note, p_user);
  insert into notifications (user_id, type, title, body, link)
  select id, 'admin_alert', 'new_report', coalesce(p_note,''), '/#/admin:reports'
    from users where role = 'admin';
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_review_set(p_author uuid, p_target uuid, p_stars integer, p_body text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if p_author = p_target then return json_build_object('error','self'); end if;
  if p_stars < 1 or p_stars > 5 then return json_build_object('error','range'); end if;
  insert into reviews (target_user, author_user, stars, body)
    values (p_target, p_author, p_stars, p_body)
  on conflict (target_user, author_user)
    do update set stars = excluded.stars, body = excluded.body, created_at = now();
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_reviews_for(p_target uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return json_build_object(
    'avg',   (select round(avg(stars)::numeric,1) from reviews where target_user=p_target),
    'count', (select count(*) from reviews where target_user=p_target),
    'mine',  null,
    'list',  coalesce((select json_agg(x) from (
       select r.stars, r.body, r.created_at,
              trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as author_name,
              u.avatar_url as author_avatar
         from reviews r join users u on u.id = r.author_user
        where r.target_user = p_target
        order by r.created_at desc limit 30) x), '[]'::json));
end $function$


CREATE OR REPLACE FUNCTION public.bk_save(p_user uuid, p_listing bigint, p_on boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if p_on then
    insert into saved_listings (user_id, listing_id) values (p_user, p_listing)
      on conflict do nothing;
    update listings set saves = saves + 1 where id = p_listing;
  else
    delete from saved_listings where user_id = p_user and listing_id = p_listing;
    update listings set saves = greatest(saves - 1, 0) where id = p_listing;
  end if;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_saved(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return coalesce((select json_agg(listing_id) from saved_listings where user_id = p_user), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_saved_full(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return coalesce((select json_agg(x) from (
    select l.*, g.name_ar as governorate_ar, a.name_ar as area_ar,
           trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as owner_name,
           (select coalesce(thumb_url,url) from listing_photos p where p.listing_id=l.id
             order by sort_order limit 1) as cover_url
      from saved_listings s
      join listings l on l.id = s.listing_id
      join governorates g on g.id = l.governorate_id
      left join areas a on a.id = l.area_id
      left join users u on u.id = l.user_id
     where s.user_id = p_user
     order by s.created_at desc) x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_search_del(p_user uuid, p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  delete from saved_searches where id = p_id and user_id = p_user;
  return json_build_object('ok',true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_search_list(p_user uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return coalesce((select json_agg(x) from (
    select id, label, filters, alerts, created_at
      from saved_searches where user_id = p_user order by created_at desc) x), '[]'::json);
end $function$


CREATE OR REPLACE FUNCTION public.bk_search_save(p_user uuid, p_label text, p_filters jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare r saved_searches;
begin
  insert into saved_searches (user_id, label, filters) values (p_user, p_label, p_filters)
    returning * into r;
  return json_build_object('id',r.id);
end $function$


CREATE OR REPLACE FUNCTION public.bk_set_avatar(p_id uuid, p_url text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  update users set avatar_url = p_url where id = p_id returning * into u;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,
    'family_name',u.family_name,'city',u.city,'country',u.country,
    'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role,'level',u.level);
end $function$


CREATE OR REPLACE FUNCTION public.bk_set_bio(p_id uuid, p_bio text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  update users set bio = p_bio where id = p_id returning * into u;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,
    'family_name',u.family_name,'city',u.city,'country',u.country,
    'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role,'level',u.level);
end $function$


CREATE OR REPLACE FUNCTION public.bk_set_currency(p_id uuid, p_currency text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  if p_currency not in ('USD','SYP') then
    raise exception 'invalid currency';
  end if;
  update users set preferred_currency = p_currency where id = p_id;
  return json_build_object('ok', true);
end $function$


CREATE OR REPLACE FUNCTION public.bk_set_password(p_phone text, p_hash text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  select * into u from users where phone = p_phone;
  if u.id is null then return json_build_object('error','nouser'); end if;
  update users set pass_hash = crypt(p_hash, gen_salt('bf')) where id = u.id;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role,'preferred_currency',u.preferred_currency);
end $function$


CREATE OR REPLACE FUNCTION public.bk_trg_listing_autopublish()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_skip boolean; v_require boolean;
begin
  select skip_review into v_skip from users where id = new.user_id;
  select require_approval into v_require from site_settings where id = 1;
  if coalesce(v_skip,false) = true or coalesce(v_require,true) = false then
    new.status := 'live';
  end if;
  return new;
end $function$


CREATE OR REPLACE FUNCTION public.bk_update_profile(p_id uuid, p_name text, p_family text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  update users set name = p_name, family_name = p_family
    where id = p_id returning * into u;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name);
end $function$


CREATE OR REPLACE FUNCTION public.bk_update_profile(p_id uuid, p_name text, p_family text, p_city text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  update users set name = p_name, family_name = p_family,
                   city = coalesce(p_city,city), country = coalesce(p_country,country)
    where id = p_id returning * into u;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role);
end $function$


CREATE OR REPLACE FUNCTION public.bk_username_free(p_username text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  return json_build_object('free',
    not exists (select 1 from users where lower(username)=lower(p_username)));
end $function$

