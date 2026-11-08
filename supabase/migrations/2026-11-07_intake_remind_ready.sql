-- 2026-11-07 (owner said yes): one reminder to a sender whose ready summary has waited 20 hours without «نعم».
-- 20 h keeps it inside WhatsApp's 24-hour window. Marked in fields.reminded_at (updated_at untouched, so the 3-day
-- move to «بانتظارك» keeps its clock). Panel-made drafts and the test (house) accounts never get one. Called by bk-intake's tick.
create or replace function public.bk_intake_remind_due()
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare out json;
begin
  with c as (
    select d.id from intake_drafts d
     where d.status = 'ready' and d.source in ('whatsapp','telegram') and not coalesce(d.by_admin, false)
       and d.updated_at < now() - interval '20 hours' and d.updated_at > now() - interval '3 days'
       and coalesce(d.fields->>'reminded_at', '') = ''
       and not exists (select 1 from users u where u.id = d.user_id and coalesce(u.is_house, false))
     order by d.updated_at limit 10 for update skip locked),
  u as (
    update intake_drafts d set fields = coalesce(d.fields, '{}'::jsonb) || jsonb_build_object('reminded_at', now())
      from c where d.id = c.id
    returning d.id, d.source, d.chat_id, d.fields->>'title' as title),
  l as (insert into intake_log (draft_id, chat_id, event) select id, chat_id, 'reminded' from u)
  select coalesce(json_agg(row_to_json(u)), '[]'::json) into out from u;
  return out;
end $function$;
revoke all on function public.bk_intake_remind_due() from public, anon, authenticated;
grant execute on function public.bk_intake_remind_due() to service_role;
