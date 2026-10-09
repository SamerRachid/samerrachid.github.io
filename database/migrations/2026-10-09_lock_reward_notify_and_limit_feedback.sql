-- 2026-10-09 — two anon-writable functions with no real limit, from the audit's security/anon-writes findings.

-- (1) bk_reward_notify(p_uid uuid, p_kind text, p_points int, p_every int): executable by anon/authenticated
-- with no owner/permission check at all — queues a real WhatsApp/Telegram/email "reward" message to ANY
-- member by uuid. The only real caller is the internal trigger bk_trg_reward_point (SECURITY DEFINER, owned
-- by postgres — verified live it needs no anon/authenticated grant, since it executes with the owner's
-- privileges). Revoking public access here has zero effect on the reward feature.
-- Verified live: has_function_privilege('anon', ..., 'execute') -> false, has_function_privilege('postgres', ...) -> true.
revoke execute on function public.bk_reward_notify(uuid, text, integer, integer) from public, anon, authenticated;

-- (2) bk_feedback: used by the real signed-out "contact us" form (index.html:8571, 8581), so it must stay
-- anon-callable, but had no limit at all — unlimited anonymous inserts each fan out to one notification row
-- per admin. Added a simple global cooldown (20 submissions / 10 minutes, site-wide): enough headroom for
-- real traffic, enough to stop an automated flood. No schema change needed, uses the table's own created_at.
-- Verified live (rolled-back transactions): 21st call within the window -> {"error":"rate_limited"}, no row
-- inserted; a normal call under the limit -> inserts as before.
CREATE OR REPLACE FUNCTION public.bk_feedback(p_kind text, p_name text, p_contact text, p_body text, p_user uuid, p_token text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_id bigint;
begin
  perform bk_require_member(p_token, p_user);
  if (select count(*) from feedback where created_at > now() - interval '10 minutes') >= 20 then
    return json_build_object('error', 'rate_limited');
  end if;
  insert into feedback (kind, name, contact, body, user_id, country_code) values (p_kind, p_name, p_contact, p_body, p_user, (select code from countries where code = upper(nullif(trim(p_country),'')) limit 1)) returning id into v_id;
  insert into notifications (user_id, type, title, body, link) select id, 'admin_alert', 'new_feedback', p_body, '/#/admin:feedback' from users where role = 'admin';
  return json_build_object('ok', true);
end $function$;
