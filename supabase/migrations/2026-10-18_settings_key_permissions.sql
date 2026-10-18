begin;
-- every setting belongs to one part of the panel: saving it needs that part's permission (owner, 2026-10-18).
-- The site-settings call used to accept any of the site permissions for every key.
create or replace function public.bk_admin_key_perms(p_key text, p_extra boolean)
 returns text[] language sql immutable set search_path to 'public','extensions' as $fn$
  select case
    when p_extra and p_key ~ '^reward_' then array['rewards']
    when p_key ~ '^(ad_|ads_)' then array['ads']
    when p_extra and p_key ~ '^(auto_notify_|camp)' then array['campaigns']
    when p_extra and p_key ~ '^verify_' then array['settings','verify']
    when p_extra and p_key ~ '^(maintenance_|legal_|notify_|video_)' then array['settings']
    when p_extra and p_key ~ '^(intake_|bot_|ik_)' then array['bot_cfg']
    when p_extra and p_key = 'property_types' then array['types']
    when p_extra and p_key = 'listing_counts_on' then array['listings_edit']
    when p_key in ('plan_name','storage_limit_mb') then array['storage']
    when p_key in ('country_chooser','syp_rate') then array['settings']
    when p_extra and p_key = 'map_area_fallback_on' then array['geo']
    when p_extra and p_key ~ '^(promo_|social_)' then array['social']
    when p_key ~ '^(banner|banners_)' then array['homepage']
    when p_key in ('phone_number','wa_number','email_address','fb_url','fb_name','ig_url','ig_name','yt_url','yt_name','tiktok_url','tiktok_name') or (p_extra and p_key ~ '^(contact_|social_link|whatsapp_|telegram_)') then array['contact']
    when p_key ~ '^(card_|featured_|new_badge|nav_|results_|logo_|cursor_dot)' or p_key in ('search_page_size','similar_count') then array['design']
    else array['homepage']
  end $fn$;
create or replace function public.bk_admin_patch_need(p_uid uuid, p_patch jsonb)
 returns void language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare su boolean; pm text[]; k text; need text[];
begin
  select coalesce(is_super_admin,false), coalesce(permissions,'{}'::text[]) into su, pm from users where id = p_uid;
  if su or p_patch is null or jsonb_typeof(p_patch) <> 'object' then return; end if;
  for k in select jsonb_object_keys(p_patch) loop
    continue when k = 'extras';
    need := bk_admin_key_perms(k, false);
    if not pm && need then raise exception 'forbidden: missing permission % (%)', array_to_string(need,'|'), k; end if;
  end loop;
  if jsonb_typeof(p_patch->'extras') = 'object' then
    for k in select jsonb_object_keys(p_patch->'extras') loop
      need := bk_admin_key_perms(k, true);
      if not pm && need then raise exception 'forbidden: missing permission % (%)', array_to_string(need,'|'), k; end if;
    end loop;
  end if;
end $fn$;
revoke all on function public.bk_admin_patch_need(uuid,jsonb) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.bk_admin_set_content(p_token text, p_patch jsonb, p_country text DEFAULT 'SY'::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare uid uuid; n int; begin uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['homepage','design','contact','settings','bot_cfg','types','social','verify','campaigns','listings_edit','storage','ads','rewards','geo']::text[], 'bk_admin_set_content', nullif(upper(p_country),''), true, left(coalesce(p_patch::text,''),300), nullif(upper(p_country),'')); perform public.bk_admin_patch_need(uid, p_patch); perform bk_admin_guard(uid, coalesce(p_country,'SY')); update site_content set hero_enabled = coalesce((p_patch->>'hero_enabled')::boolean, hero_enabled), hero_ar = coalesce(p_patch->>'hero_ar', hero_ar), hero_en = coalesce(p_patch->>'hero_en', hero_en), hero_de = coalesce(p_patch->>'hero_de', hero_de), hero_sub_ar = coalesce(p_patch->>'hero_sub_ar', hero_sub_ar), hero_sub_en = coalesce(p_patch->>'hero_sub_en', hero_sub_en), hero_sub_de = coalesce(p_patch->>'hero_sub_de', hero_sub_de), hero_bg_type = coalesce(p_patch->>'hero_bg_type', hero_bg_type), hero_bg_video_url = coalesce(p_patch->>'hero_bg_video_url', hero_bg_video_url), hero_bg_photo_url = coalesce(p_patch->>'hero_bg_photo_url', hero_bg_photo_url), hero_gap = coalesce((p_patch->>'hero_gap')::int, hero_gap), hero_bg_video_speed = coalesce((p_patch->>'hero_bg_video_speed')::int, hero_bg_video_speed), hero_title_size = coalesce(p_patch->>'hero_title_size', hero_title_size), hero_title_color = coalesce(p_patch->>'hero_title_color', hero_title_color), hero_sub_color = coalesce(p_patch->>'hero_sub_color', hero_sub_color), banner_enabled = coalesce((p_patch->>'banner_enabled')::boolean, banner_enabled), banner_media_type = coalesce(p_patch->>'banner_media_type', banner_media_type), banner_image_url = coalesce(p_patch->>'banner_image_url', banner_image_url), banner_video_url = coalesce(p_patch->>'banner_video_url', banner_video_url), banner_link_url = coalesce(p_patch->>'banner_link_url', banner_link_url), banner_items = coalesce(p_patch->>'banner_items', banner_items), banners_config = coalesce(p_patch->>'banners_config', banners_config), banner_rotation_seconds = coalesce((p_patch->>'banner_rotation_seconds')::int, banner_rotation_seconds), banner_transition = coalesce(p_patch->>'banner_transition', banner_transition), banner_size = coalesce(p_patch->>'banner_size', banner_size), banner_custom_w = coalesce((p_patch->>'banner_custom_w')::int, banner_custom_w), banner_custom_h = coalesce((p_patch->>'banner_custom_h')::int, banner_custom_h), banner_gap = coalesce((p_patch->>'banner_gap')::int, banner_gap), banner_text_enabled = coalesce((p_patch->>'banner_text_enabled')::boolean, banner_text_enabled), banner_text_size = coalesce((p_patch->>'banner_text_size')::int, banner_text_size), banner_text_color = coalesce(p_patch->>'banner_text_color', banner_text_color), banner_text_ar = coalesce(p_patch->>'banner_text_ar', banner_text_ar), banner_text_en = coalesce(p_patch->>'banner_text_en', banner_text_en), banner_text_de = coalesce(p_patch->>'banner_text_de', banner_text_de), stats_enabled = coalesce((p_patch->>'stats_enabled')::boolean, stats_enabled), stats_areas_num = coalesce(p_patch->>'stats_areas_num', stats_areas_num), stats_listings_num = coalesce(p_patch->>'stats_listings_num', stats_listings_num), stats_use_real_count = coalesce((p_patch->>'stats_use_real_count')::boolean, stats_use_real_count), stats1_ar = coalesce(p_patch->>'stats1_ar', stats1_ar), stats1_en = coalesce(p_patch->>'stats1_en', stats1_en), stats1_de = coalesce(p_patch->>'stats1_de', stats1_de), stats2_ar = coalesce(p_patch->>'stats2_ar', stats2_ar), stats2_en = coalesce(p_patch->>'stats2_en', stats2_en), stats2_de = coalesce(p_patch->>'stats2_de', stats2_de), fb_url = coalesce(p_patch->>'fb_url', fb_url), ig_url = coalesce(p_patch->>'ig_url', ig_url), yt_url = coalesce(p_patch->>'yt_url', yt_url), fb_name = coalesce(p_patch->>'fb_name', fb_name), ig_name = coalesce(p_patch->>'ig_name', ig_name), yt_name = coalesce(p_patch->>'yt_name', yt_name), tiktok_name = coalesce(p_patch->>'tiktok_name', tiktok_name), tiktok_url = coalesce(p_patch->>'tiktok_url', tiktok_url), wa_number = coalesce(p_patch->>'wa_number', wa_number), phone_number = coalesce(p_patch->>'phone_number', phone_number), email_address = coalesce(p_patch->>'email_address', email_address), ad_tag_enabled = coalesce((p_patch->>'ad_tag_enabled')::boolean, ad_tag_enabled), ad_tag_size = coalesce((p_patch->>'ad_tag_size')::int, ad_tag_size), ad_tag_ar = coalesce(p_patch->>'ad_tag_ar', ad_tag_ar), ad_tag_en = coalesce(p_patch->>'ad_tag_en', ad_tag_en), ad_tag_de = coalesce(p_patch->>'ad_tag_de', ad_tag_de), ad_square_size = coalesce((p_patch->>'ad_square_size')::int, ad_square_size), ad_carousel_seconds = coalesce((p_patch->>'ad_carousel_seconds')::numeric, ad_carousel_seconds), ad_carousel_direction = coalesce(p_patch->>'ad_carousel_direction', ad_carousel_direction), ad_carousel_gap = coalesce((p_patch->>'ad_carousel_gap')::int, ad_carousel_gap), ad_use_icons = coalesce((p_patch->>'ad_use_icons')::boolean, ad_use_icons), ad_roominfo_size = coalesce((p_patch->>'ad_roominfo_size')::int, ad_roominfo_size), ad_location_enabled = coalesce((p_patch->>'ad_location_enabled')::boolean, ad_location_enabled), ad_location_size = coalesce((p_patch->>'ad_location_size')::int, ad_location_size), ad_text_color = coalesce(p_patch->>'ad_text_color', ad_text_color), ad_shade_color = coalesce(p_patch->>'ad_shade_color', ad_shade_color), featured_badge_enabled = coalesce((p_patch->>'featured_badge_enabled')::boolean, featured_badge_enabled), featured_badge_ar = coalesce(p_patch->>'featured_badge_ar', featured_badge_ar), featured_badge_en = coalesce(p_patch->>'featured_badge_en', featured_badge_en), featured_badge_de = coalesce(p_patch->>'featured_badge_de', featured_badge_de), featured_brightness = coalesce((p_patch->>'featured_brightness')::int, featured_brightness), card_min_width = coalesce((p_patch->>'card_min_width')::int, card_min_width), card_min_width_mobile = coalesce((p_patch->>'card_min_width_mobile')::int, card_min_width_mobile), new_badge_hours = coalesce((p_patch->>'new_badge_hours')::int, new_badge_hours), storage_limit_mb = coalesce((p_patch->>'storage_limit_mb')::int, storage_limit_mb), syp_rate = coalesce((p_patch->>'syp_rate')::int, syp_rate), extras = jsonb_strip_nulls(coalesce(extras, '{}'::jsonb) || coalesce(p_patch->'extras', '{}'::jsonb)) where country_code = coalesce(p_country,'SY'); get diagnostics n = row_count; if n = 0 then raise exception 'no settings row for country %', p_country; end if; return json_build_object('ok', true); end $function$
;
commit;
