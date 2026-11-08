-- 2026-11-07 panel fixes (owner: "that shitty search thing in the panel"; drafts lost while «ready»)
-- 1) Members list: admins were left out of the list the panel loads (u.role <> 'admin'), so the member search
--    (client-side over that list) could never find the owner. The page already draws admin rows read-only.
-- 2) Contacts search: a phone written with spaces/dashes/00/Arabic digits («+1 514 809 0004») found nothing.
--    Digits now match on the last 9 digits, like the global search; the text is trimmed.
-- 3) A complete («ready») draft the sender never confirmed went silently to «ملغى» after 3 days.
--    It now goes to «بانتظارك» (review) so the team can publish it; needs_info / collecting still close.

do $$
declare d text; o text := 'from users u where u.role <> ''admin'' and bk_scope_ok(u.country,sc,al) order by u.created_at desc limit 500';
begin
  select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'bk_admin_data_core';
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'bk_admin_data_core: users list text not found exactly once'; end if;
  execute replace(d, o, 'from users u where bk_scope_ok(u.country,sc,al) order by u.created_at desc limit 500');
end $$;

CREATE OR REPLACE FUNCTION public.bk_admin_contacts(p_token text, p_country text DEFAULT NULL::text, p_q text DEFAULT NULL::text, p_consent text DEFAULT NULL::text, p_source text DEFAULT NULL::text, p_tag text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; q text; qd text;
begin
  uid := bk_admin_uid(p_token); perform public.bk_admin_need(uid, ARRAY['campaigns']::text[], 'bk_admin_contacts', null, false, left(coalesce(p_country::text,''),300), nullif(upper(p_country),'')); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  q := nullif(trim(translate(coalesce(p_q,''), '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789')), '');
  -- a phone however it is written: «+1 514 809 0004», «00963 988…», «0988…» → its last 9 digits
  qd := case when q ~ '^[0-9\s+()\-.]+$' and length(regexp_replace(q, '\D', '', 'g')) >= 6 then right(regexp_replace(q, '\D', '', 'g'), 9) end;
  return coalesce((select json_agg(row_to_json(x) order by x.created_at desc) from (
    select c.* from contacts c
     where bk_scope_ok(c.country_code, sc, al)
       and (q is null or c.phone ilike '%'||q||'%' or c.email ilike '%'||q||'%' or c.name ilike '%'||q||'%'
            or (qd is not null and regexp_replace(coalesce(c.phone,''), '\D', '', 'g') like '%'||qd||'%'))
       and (p_consent is null or c.wa_consent = p_consent or c.tg_consent = p_consent or c.email_consent = p_consent)
       and (p_source is null or c.source = p_source)
       and (p_tag is null or p_tag = any(c.tags))
     limit 2000) x), '[]'::json);
end $function$;

CREATE OR REPLACE FUNCTION public.bk_intake_due(p_wait_s integer DEFAULT NULL::integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare w int; out json;
begin
  w := coalesce(p_wait_s, bk_intake_int(bk_intake_cfg()->>'intake_wait_s'), 90);
  -- outage retry: a draft that failed only because the model API answered 5xx / network goes back to the queue
  -- every 10 minutes for two days, with its read budget reset, so nothing is lost while the service is down
  update intake_drafts set status = 'collecting', error = null, reads = 0, last_message_at = now() - make_interval(secs => w + 1), updated_at = now()
   where status = 'failed' and (error like 'claude 5%' or error like 'claude: network%' or error like 'claude: failed%')
     and updated_at < now() - interval '10 minutes' and created_at > now() - interval '2 days';
  update intake_drafts set status = 'collecting', updated_at = now() where status = 'reading' and claimed_at < now() - interval '10 minutes';
  -- a complete listing the sender never confirmed is not thrown away: after 3 days it waits for the team («بانتظارك»)
  with old as (update intake_drafts set status = 'review', updated_at = now(), error = 'جاهز ولم يؤكد المرسل خلال 3 أيام'
     where status = 'ready' and updated_at < now() - interval '3 days' returning id, chat_id)
  insert into intake_log (draft_id, chat_id, event) select id, chat_id, 'expired_to_review' from old;
  with old as (update intake_drafts set status = 'cancelled', updated_at = now(), error = coalesce(error,'') || ' expired'
     where (status = 'collecting' and last_message_at < now() - interval '2 days') or (status = 'needs_info' and updated_at < now() - interval '3 days') returning id, chat_id)
  insert into intake_log (draft_id, chat_id, event) select id, chat_id, 'expired' from old;
  with u as (
    update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
     where id in (select id from intake_drafts
                   where status = 'collecting' and last_message_at < now() - make_interval(secs => w)
                     and (raw_text <> '' or jsonb_array_length(photos) > 0) and reads < 6
                   order by last_message_at limit 5 for update skip locked)
     returning *)
  select coalesce(json_agg(row_to_json(u)), '[]'::json) into out from u;
  update intake_drafts set status = 'review', error = 'too many reads', updated_at = now() where status = 'collecting' and reads >= 6 and last_message_at < now() - make_interval(secs => w);
  return out;
end $function$;
