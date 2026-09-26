-- Balkoun · 2026-09-26 · the campaign queue also returns the campaign title, so the Edge Function can tell the
-- admin's one-to-one "direct: …" messages apart (no Telegram nudge / unsubscribe footer on those).

create or replace function public.bk_campaign_sends_pending(p_limit integer default 200) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  return coalesce((select json_agg(row_to_json(x)) from (
    select s.id, s.channel, s.trigger_type, c.id as contact_id, c.phone, c.email, c.tg_chat_id, c.tg_consent, c.unsub_token,
           c.name as contact_name, coalesce(u.lang, 'ar') as lang,
           camp.title, coalesce(camp.body_ar, '') as body_ar, coalesce(camp.body_en, '') as body_en, camp.subject,
           l.id as listing_id, l.ref as listing_ref, l.price_usd as listing_price, l.description as listing_description
      from campaign_sends s
      join contacts c on c.id = s.contact_id
      left join users u on u.id = c.user_id
      left join campaigns camp on camp.id = s.campaign_id
      left join listings l on l.id = s.listing_id
     where s.status = 'queued'
     order by s.created_at limit p_limit) x), '[]'::json);
end $function$;
