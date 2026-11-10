-- undo 2026-11-09_readonly_rpc_fix.sql (brings the read-only error back on panel › خدمات العقار)
alter function public.bk_admin_services(text, text) stable;
alter function public.bk_service_mine(text) stable;

create or replace function public.bk_admin_uid(p_token text)
 returns uuid
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare uid uuid;
begin
  delete from admin_sessions where expires_at < now();
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
  delete from member_sessions where expires_at < now();
  select s.user_id into uid from member_sessions s
    join users u on u.id = s.user_id
   where s.token = p_token and s.expires_at > now() and not u.blocked;
  return uid;
end $function$;
