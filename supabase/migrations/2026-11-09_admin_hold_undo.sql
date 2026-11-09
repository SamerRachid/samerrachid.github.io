-- Undo 2026-11-09_admin_hold.sql: held drafts wait for the owner as 'review', the hold table and its functions go,
-- and bk_intake_quiet / bk_intake_claim / bk_intake_remind_due / bk_admin_intake return to their 2026-11-08 bodies.
update intake_drafts set status = 'review', error = 'جُمع أثناء تولّي المشرف للمحادثة', updated_at = now() where status = 'held';
drop function if exists bk_admin_intake_holds(text);
drop function if exists bk_admin_intake_hold(text, text, boolean);
drop function if exists bk_intake_hold_expire();
drop function if exists bk_intake_held(text);
drop function if exists bk_intake_hold_take(text);
drop function if exists bk_intake_hold_collect(text, text, text, text, jsonb, jsonb, text);
drop function if exists bk_intake_hold_set(text, boolean, text, int);
drop table if exists intake_hold;
alter table intake_drafts drop constraint intake_drafts_status_check;
alter table intake_drafts add constraint intake_drafts_status_check
  check (status = any (array['collecting','reading','ready','needs_info','review','published','cancelled','failed']));

create or replace function public.bk_intake_quiet(p_chat_id text)
 returns json language plpgsql stable security definer set search_path to 'public', 'extensions'
as $function$
declare digits text; hrs int; u users;
begin
  digits := bk_intake_norm_phone(p_chat_id);
  if digits is null then return json_build_object('quiet', false); end if;
  select * into u from users where bk_intake_norm_phone(phone) = digits and coalesce(bot_off,false) order by created_at desc limit 1;
  if u.id is not null then return json_build_object('quiet', true, 'reason', 'member', 'user_id', u.id); end if;
  select coalesce(nullif(extras->>'intake_quiet_after_dm_hours','')::int, 48) into hrs from site_content where id = 1;
  if coalesce(hrs, 48) > 0 and exists (
       select 1 from campaign_sends s join campaigns cp on cp.id = s.campaign_id join contacts c on c.id = s.contact_id
        where s.trigger_type = 'manual' and cp.kind = 'manual' and s.channel = 'whatsapp' and s.status = 'sent'
          and s.sent_at > now() - make_interval(hours => coalesce(hrs, 48))
          and bk_intake_norm_phone(c.phone) = digits) then
    return json_build_object('quiet', true, 'reason', 'direct_message');
  end if;
  return json_build_object('quiet', false);
end $function$;

create or replace function public.bk_intake_claim(p_draft bigint)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare d intake_drafts;
begin
  update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
   where id = p_draft and status in ('collecting','ready','needs_info','failed','review') and reads < 15 returning * into d;
  if d.id is null then return null; end if;
  return row_to_json(d);
end $function$;

create or replace function public.bk_intake_remind_due()
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
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

do $do$
declare def text;
begin
  def := pg_get_functiondef('bk_admin_intake'::regproc);
  def := replace(def, $r$'held', count(*) filter (where status = 'held'),
        'review', count(*) filter (where status = 'review'),$r$, $r$'review', count(*) filter (where status = 'review'),$r$);
  execute def;
end $do$;

do $do$
declare def text;
begin
  def := pg_get_functiondef('bk_intake_save_read'::regproc);
  def := replace(def, $r$, 'held_by_admin', d.fields->'held_by_admin'))$r$, $r$)$r$);
  execute def;
end $do$;
