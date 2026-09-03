drop function if exists public.bk_change_password(p_id uuid, p_old text, p_new text);
CREATE OR REPLACE FUNCTION public.bk_change_password(p_id uuid, p_old text, p_new text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  perform bk_require_member(p_token, p_id);
  select * into u from users where id = p_id;
  if u.id is null then return json_build_object('error','nouser'); end if;
  if u.pass_hash is null or u.pass_hash <> crypt(p_old, u.pass_hash) then
    return json_build_object('error','badpass');
  end if;
  update users set pass_hash = crypt(p_new, gen_salt('bf')) where id = p_id;
  return json_build_object('ok',true);
end $function$;
grant execute on function public.bk_change_password(p_id uuid, p_old text, p_new text, text) to anon, authenticated;

drop function if exists public.bk_change_phone(p_id uuid, p_pass text, p_new_phone text);
CREATE OR REPLACE FUNCTION public.bk_change_phone(p_id uuid, p_pass text, p_new_phone text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  perform bk_require_member(p_token, p_id);
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
end $function$;
grant execute on function public.bk_change_phone(p_id uuid, p_pass text, p_new_phone text, text) to anon, authenticated;

drop function if exists public.bk_contact(p_listing bigint, p_user uuid, p_kind text);
CREATE OR REPLACE FUNCTION public.bk_contact(p_listing bigint, p_user uuid, p_kind text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  insert into contact_events (listing_id, user_id, kind) values (p_listing, p_user, p_kind);
  update listings set views = views + 1 where id = p_listing;
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_contact(p_listing bigint, p_user uuid, p_kind text, text) to anon, authenticated;

drop function if exists public.bk_edit(p_user uuid, p_id bigint, p_patch jsonb);
CREATE OR REPLACE FUNCTION public.bk_edit(p_user uuid, p_id bigint, p_patch jsonb, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare l listings; v_old_price int; v_new_price int;
begin
  perform bk_require_member(p_token, p_user);
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
end $function$;
grant execute on function public.bk_edit(p_user uuid, p_id bigint, p_patch jsonb, text) to anon, authenticated;

drop function if exists public.bk_feedback(p_kind text, p_name text, p_contact text, p_body text, p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_feedback(p_kind text, p_name text, p_contact text, p_body text, p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_id bigint;
begin
  perform bk_require_member(p_token, p_user);
  insert into feedback (kind, name, contact, body, user_id)
    values (p_kind, p_name, p_contact, p_body, p_user)
    returning id into v_id;
  insert into notifications (user_id, type, title, body, link)
  select id, 'admin_alert', 'new_feedback', p_body, '/#/admin:feedback'
    from users where role = 'admin';
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_feedback(p_kind text, p_name text, p_contact text, p_body text, p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_heartbeat(p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_heartbeat(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  if p_user is null then return; end if;
  insert into online_presence (user_id, last_seen) values (p_user, now())
    on conflict (user_id) do update set last_seen = now();
end $function$;
grant execute on function public.bk_heartbeat(p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_log_view(p_path text, p_view text, p_user uuid, p_country text);
CREATE OR REPLACE FUNCTION public.bk_log_view(p_path text, p_view text, p_user uuid, p_country text, p_token text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  insert into page_views (path, view, user_id, country) values (p_path, p_view, p_user, p_country);
end $function$;
grant execute on function public.bk_log_view(p_path text, p_view text, p_user uuid, p_country text, text) to anon, authenticated;

drop function if exists public.bk_mark_notifications_read(p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_mark_notifications_read(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  update notifications set is_read = true where user_id = p_user and not is_read;
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_mark_notifications_read(p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_member_delete_message(p_user uuid, p_kind text, p_id bigint);
CREATE OR REPLACE FUNCTION public.bk_member_delete_message(p_user uuid, p_kind text, p_id bigint, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_owner uuid;
begin
  perform bk_require_member(p_token, p_user);
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
end $function$;
grant execute on function public.bk_member_delete_message(p_user uuid, p_kind text, p_id bigint, text) to anon, authenticated;

drop function if exists public.bk_member_reply(p_user uuid, p_kind text, p_id bigint, p_body text);
CREATE OR REPLACE FUNCTION public.bk_member_reply(p_user uuid, p_kind text, p_id bigint, p_body text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare v_owner uuid;
begin
  perform bk_require_member(p_token, p_user);
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
end $function$;
grant execute on function public.bk_member_reply(p_user uuid, p_kind text, p_id bigint, p_body text, text) to anon, authenticated;

drop function if exists public.bk_my_messages(p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_my_messages(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
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
end $function$;
grant execute on function public.bk_my_messages(p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_my_notifications(p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_my_notifications(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  if p_user is null then return json_build_object('items','[]'::json,'unread',0); end if;
  return json_build_object(
    'items', coalesce((select json_agg(x) from (
        select id, type, title, body, link, is_read, created_at
          from notifications where user_id = p_user
         order by created_at desc limit 50) x), '[]'::json),
    'unread', (select count(*) from notifications where user_id = p_user and not is_read));
end $function$;
grant execute on function public.bk_my_notifications(p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_own_delete(p_user uuid, p_id bigint);
CREATE OR REPLACE FUNCTION public.bk_own_delete(p_user uuid, p_id bigint, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  if not exists (select 1 from listings where id=p_id and user_id=p_user) then
    return json_build_object('error','notyours');
  end if;
  delete from listings where id = p_id;   -- photos and saves cascade
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_own_delete(p_user uuid, p_id bigint, text) to anon, authenticated;

drop function if exists public.bk_own_status(p_user uuid, p_id bigint, p_status text, p_reason text);
CREATE OR REPLACE FUNCTION public.bk_own_status(p_user uuid, p_id bigint, p_status text, p_reason text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare l listings;
begin
  perform bk_require_member(p_token, p_user);
  select * into l from listings where id = p_id;
  if l.id is null or l.user_id is distinct from p_user then
    return json_build_object('error','notyours');
  end if;
  update listings set status = p_status, closed_reason = p_reason, closed_at = now()
    where id = p_id;
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_own_status(p_user uuid, p_id bigint, p_status text, p_reason text, text) to anon, authenticated;

drop function if exists public.bk_photo_add(p_user uuid, p_listing bigint, p_url text, p_thumb text, p_sort integer);
CREATE OR REPLACE FUNCTION public.bk_photo_add(p_user uuid, p_listing bigint, p_url text, p_thumb text, p_sort integer, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  if not exists (select 1 from listings where id=p_listing and user_id=p_user) then
    return json_build_object('error','notyours');
  end if;
  insert into listing_photos (listing_id,url,thumb_url,sort_order)
    values (p_listing,p_url,p_thumb,p_sort);
  return json_build_object('ok',true);
end $function$;
grant execute on function public.bk_photo_add(p_user uuid, p_listing bigint, p_url text, p_thumb text, p_sort integer, text) to anon, authenticated;

drop function if exists public.bk_photo_del(p_user uuid, p_photo bigint);
CREATE OR REPLACE FUNCTION public.bk_photo_del(p_user uuid, p_photo bigint, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  delete from listing_photos p using listings l
   where p.id=p_photo and l.id=p.listing_id and l.user_id=p_user;
  return json_build_object('ok',true);
end $function$;
grant execute on function public.bk_photo_del(p_user uuid, p_photo bigint, text) to anon, authenticated;

drop function if exists public.bk_report(p_listing bigint, p_reason text, p_note text, p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_report(p_listing bigint, p_reason text, p_note text, p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  insert into listing_reports (listing_id, reason, note, user_id)
    values (p_listing, p_reason, p_note, p_user);
  insert into notifications (user_id, type, title, body, link)
  select id, 'admin_alert', 'new_report', coalesce(p_note,''), '/#/admin:reports'
    from users where role = 'admin';
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_report(p_listing bigint, p_reason text, p_note text, p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_review_set(p_author uuid, p_target uuid, p_stars integer, p_body text);
CREATE OR REPLACE FUNCTION public.bk_review_set(p_author uuid, p_target uuid, p_stars integer, p_body text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_author);
  if p_author = p_target then return json_build_object('error','self'); end if;
  if p_stars < 1 or p_stars > 5 then return json_build_object('error','range'); end if;
  insert into reviews (target_user, author_user, stars, body)
    values (p_target, p_author, p_stars, p_body)
  on conflict (target_user, author_user)
    do update set stars = excluded.stars, body = excluded.body, created_at = now();
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_review_set(p_author uuid, p_target uuid, p_stars integer, p_body text, text) to anon, authenticated;

drop function if exists public.bk_save(p_user uuid, p_listing bigint, p_on boolean);
CREATE OR REPLACE FUNCTION public.bk_save(p_user uuid, p_listing bigint, p_on boolean, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  if p_on then
    insert into saved_listings (user_id, listing_id) values (p_user, p_listing)
      on conflict do nothing;
    update listings set saves = saves + 1 where id = p_listing;
  else
    delete from saved_listings where user_id = p_user and listing_id = p_listing;
    update listings set saves = greatest(saves - 1, 0) where id = p_listing;
  end if;
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_save(p_user uuid, p_listing bigint, p_on boolean, text) to anon, authenticated;

drop function if exists public.bk_saved(p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_saved(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  return coalesce((select json_agg(listing_id) from saved_listings where user_id = p_user), '[]'::json);
end $function$;
grant execute on function public.bk_saved(p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_saved_full(p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_saved_full(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
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
end $function$;
grant execute on function public.bk_saved_full(p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_search_del(p_user uuid, p_id bigint);
CREATE OR REPLACE FUNCTION public.bk_search_del(p_user uuid, p_id bigint, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  delete from saved_searches where id = p_id and user_id = p_user;
  return json_build_object('ok',true);
end $function$;
grant execute on function public.bk_search_del(p_user uuid, p_id bigint, text) to anon, authenticated;

drop function if exists public.bk_search_list(p_user uuid);
CREATE OR REPLACE FUNCTION public.bk_search_list(p_user uuid, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_user);
  return coalesce((select json_agg(x) from (
    select id, label, filters, alerts, created_at
      from saved_searches where user_id = p_user order by created_at desc) x), '[]'::json);
end $function$;
grant execute on function public.bk_search_list(p_user uuid, text) to anon, authenticated;

drop function if exists public.bk_search_save(p_user uuid, p_label text, p_filters jsonb);
CREATE OR REPLACE FUNCTION public.bk_search_save(p_user uuid, p_label text, p_filters jsonb, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare r saved_searches;
begin
  perform bk_require_member(p_token, p_user);
  insert into saved_searches (user_id, label, filters) values (p_user, p_label, p_filters)
    returning * into r;
  return json_build_object('id',r.id);
end $function$;
grant execute on function public.bk_search_save(p_user uuid, p_label text, p_filters jsonb, text) to anon, authenticated;

drop function if exists public.bk_set_avatar(p_id uuid, p_url text);
CREATE OR REPLACE FUNCTION public.bk_set_avatar(p_id uuid, p_url text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  perform bk_require_member(p_token, p_id);
  update users set avatar_url = p_url where id = p_id returning * into u;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,
    'family_name',u.family_name,'city',u.city,'country',u.country,
    'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role,'level',u.level);
end $function$;
grant execute on function public.bk_set_avatar(p_id uuid, p_url text, text) to anon, authenticated;

drop function if exists public.bk_set_bio(p_id uuid, p_bio text);
CREATE OR REPLACE FUNCTION public.bk_set_bio(p_id uuid, p_bio text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  perform bk_require_member(p_token, p_id);
  update users set bio = p_bio where id = p_id returning * into u;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,
    'family_name',u.family_name,'city',u.city,'country',u.country,
    'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role,'level',u.level);
end $function$;
grant execute on function public.bk_set_bio(p_id uuid, p_bio text, text) to anon, authenticated;

drop function if exists public.bk_set_currency(p_id uuid, p_currency text);
CREATE OR REPLACE FUNCTION public.bk_set_currency(p_id uuid, p_currency text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  perform bk_require_member(p_token, p_id);
  if p_currency not in ('USD','SYP') then
    raise exception 'invalid currency';
  end if;
  update users set preferred_currency = p_currency where id = p_id;
  return json_build_object('ok', true);
end $function$;
grant execute on function public.bk_set_currency(p_id uuid, p_currency text, text) to anon, authenticated;

drop function if exists public.bk_update_profile(p_id uuid, p_name text, p_family text, p_city text, p_country text);
CREATE OR REPLACE FUNCTION public.bk_update_profile(p_id uuid, p_name text, p_family text, p_city text DEFAULT NULL::text, p_country text DEFAULT NULL::text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare u users;
begin
  perform bk_require_member(p_token, p_id);
  update users set name = p_name, family_name = p_family,
                   city = coalesce(p_city,city), country = coalesce(p_country,country)
    where id = p_id returning * into u;
  if u.id is null then return json_build_object('error','nouser'); end if;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,'role',u.role);
end $function$;
grant execute on function public.bk_update_profile(p_id uuid, p_name text, p_family text, p_city text, p_country text, text) to anon, authenticated;

