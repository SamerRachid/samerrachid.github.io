-- 2026-11-09 panel › خدمات العقار showed «cannot execute DELETE in a read-only transaction» and listed nothing.
-- PostgREST runs a STABLE function inside a READ ONLY transaction, and bk_admin_services (STABLE) starts with
-- bk_admin_uid, which deletes expired admin sessions; bk_service_mine (STABLE, a member's own service page) has the
-- same trap through bk_member_uid. Two layers so it cannot come back:
--  1. both callers become VOLATILE like every other function that checks a token;
--  2. the two token checks only tidy expired sessions when the transaction may write, so a STABLE caller written
--     later reads fine instead of failing (the tidy-up still happens on the next ordinary call).
-- Undo: 2026-11-09_readonly_rpc_fix_undo.sql

alter function public.bk_admin_services(text, text) volatile;
alter function public.bk_service_mine(text) volatile;

create or replace function public.bk_admin_uid(p_token text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare uid uuid;
begin
  if current_setting('transaction_read_only') = 'off' then
    delete from admin_sessions where expires_at < now();
  end if;
  select s.user_id into uid from admin_sessions s
    join users u on u.id = s.user_id
   where s.token = p_token and s.expires_at > now() and u.role = 'admin';
  if uid is null then raise exception 'unauthorised'; end if;
  return uid;
end $function$;

create or replace function public.bk_member_uid(p_token text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare uid uuid;
begin
  if p_token is null or length(p_token) < 20 then return null; end if;
  if current_setting('transaction_read_only') = 'off' then
    delete from member_sessions where expires_at < now();
  end if;
  select s.user_id into uid from member_sessions s
    join users u on u.id = s.user_id
   where s.token = p_token and s.expires_at > now() and not u.blocked;
  return uid;
end $function$;
