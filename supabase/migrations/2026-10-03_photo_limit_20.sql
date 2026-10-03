-- 2026-10-03 · photos per listing from the site form / edit page: 20 (the client enforces it too; the bot has its own
-- intake_max_photos). Overridable without a deploy through site_content.extras.photo_max.
CREATE OR REPLACE FUNCTION public.bk_photo_add(p_user uuid, p_listing bigint, p_url text, p_thumb text, p_sort integer, p_token text DEFAULT NULL::text, p_kind text DEFAULT 'photo'::text, p_duration integer DEFAULT NULL::integer, p_size bigint DEFAULT NULL::bigint)
 RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
declare v_max int; v_on boolean; p_max int;
begin
  perform bk_require_member(p_token, p_user);
  if not exists (select 1 from listings where id=p_listing and user_id=p_user) then
    return json_build_object('error','notyours');
  end if;
  if coalesce(p_kind,'photo')='video' then
    select coalesce((extras->>'video_enabled')::boolean, true), coalesce((extras->>'video_max')::int, 1) into v_on, v_max from site_content where id=1;
    if not coalesce(v_on,true) then return json_build_object('error','video_off'); end if;
    if (select count(*) from listing_photos where listing_id=p_listing and kind='video') >= coalesce(v_max,1) then return json_build_object('error','video_limit'); end if;
  else
    select coalesce(nullif(extras->>'photo_max','')::int, 20) into p_max from site_content where id=1;
    if (select count(*) from listing_photos where listing_id=p_listing and kind='photo') >= coalesce(p_max,20) then return json_build_object('error','photo_limit'); end if;
  end if;
  insert into listing_photos (listing_id,url,thumb_url,sort_order,kind,duration_s,size_bytes)
    values (p_listing,p_url,p_thumb,p_sort,coalesce(p_kind,'photo'),p_duration,p_size);
  return json_build_object('ok',true);
end $function$;
