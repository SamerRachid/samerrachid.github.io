-- Balkoun · 2026-09-26 · WhatsApp (WAHA) session monitoring. The per-minute cron now also calls the Edge Function
-- every 5 minutes so tick() can run wahaHealth(): the session state is kept in site_content.extras.intake_waha_state
-- and two consecutive failures (~10 min) push a "waha_down" admin alert (Telegram queue + direct email); recovery
-- pushes a "waha_up" note. bk_intake_set_extra is the service-only writer for that state key.

create or replace function public.bk_intake_set_extra(p_key text, p_value jsonb) returns void
language sql security definer set search_path to 'public', 'extensions' as $$
  update site_content set extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object(p_key, p_value) where id = 1;
$$;
revoke execute on function public.bk_intake_set_extra(text, jsonb) from public, anon, authenticated;

create or replace function public.bk_intake_cron_tick() returns void
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare k text; due boolean;
begin
  select exists (
    select 1 from intake_drafts
     where (status = 'collecting' and (raw_text <> '' or jsonb_array_length(photos) > 0)
            and last_message_at < now() - make_interval(secs => coalesce(bk_intake_int(bk_intake_cfg()->>'intake_wait_s'), 90)))
        or (status = 'reading' and claimed_at < now() - interval '10 minutes')
  ) or (not bk_notify_quiet() and exists (select 1 from admin_notify_queue where sent_at is null and attempts < 5))
    or exists (select 1 from campaign_sends where status = 'queued')
    or extract(minute from now())::int % 5 = 0   -- WhatsApp session health check
    into due;
  if not due then return; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'intake_tick_secret';
  if k is null then return; end if;
  perform net.http_post(
    url := 'https://coajrqynjrptujmzjjdh.supabase.co/functions/v1/bk-intake/tick',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-intake-key', k),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000);
end $function$;
