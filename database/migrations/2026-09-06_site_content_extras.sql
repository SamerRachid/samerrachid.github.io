-- 2026-09-06 · site_content.extras: one JSON column for every new admin setting, so the admin panel can
-- grow without a schema change per setting. bk_admin_set_content merges p_patch->'extras' into it.
alter table public.site_content add column if not exists extras jsonb not null default '{}'::jsonb;

CREATE OR REPLACE FUNCTION public.bk_admin_set_content(p_token text, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
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
    syp_rate = coalesce((p_patch->>'syp_rate')::int, syp_rate),
    -- new: any key under "extras" is merged into the JSON store (a key set to null removes it)
    extras = jsonb_strip_nulls(coalesce(extras, '{}'::jsonb) || coalesce(p_patch->'extras', '{}'::jsonb))
  where id = 1;
  return json_build_object('ok', true);
end $function$;
