-- Balkoun · 2026-09-19 · cron safety net for the message intake (applied as migration "intake_cron_tick")
-- Every minute: if a draft is due for reading (sender quiet for intake_wait_s) or stuck in 'reading' > 10 min,
-- POST https://<project>.supabase.co/functions/v1/bk-intake/tick with x-intake-key = vault secret intake_tick_secret.
-- The SAME value must be pasted as the Edge Function secret INTAKE_TICK_SECRET (Supabase → Edge Functions → Secrets).
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

do $$ begin
  if not exists (select 1 from vault.secrets where name = 'intake_tick_secret') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(24), 'hex'), 'intake_tick_secret', 'x-intake-key for bk-intake /tick (cron safety net)');
  end if;
end $$;

create or replace function public.bk_intake_cron_tick()
returns void language plpgsql security definer set search_path = public, extensions as $$
declare k text; due boolean;
begin
  select exists (
    select 1 from intake_drafts
     where (status = 'collecting' and (raw_text <> '' or jsonb_array_length(photos) > 0)
            and last_message_at < now() - make_interval(secs => coalesce(bk_intake_int(bk_intake_cfg()->>'intake_wait_s'), 90)))
        or (status = 'reading' and claimed_at < now() - interval '10 minutes')
  ) into due;
  if not due then return; end if;
  select decrypted_secret into k from vault.decrypted_secrets where name = 'intake_tick_secret';
  if k is null then return; end if;
  perform net.http_post(
    url := 'https://coajrqynjrptujmzjjdh.supabase.co/functions/v1/bk-intake/tick',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-intake-key', k),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000);
end $$;
revoke execute on function public.bk_intake_cron_tick() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'bk-intake-tick';
select cron.schedule('bk-intake-tick', '* * * * *', 'select public.bk_intake_cron_tick()');
