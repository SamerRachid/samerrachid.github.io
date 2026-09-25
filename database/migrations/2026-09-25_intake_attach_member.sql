-- Balkoun · 2026-09-25 · an admin-forwarded draft that carries a membership number (SYM1007 …) is attributed
-- to that member automatically: user_id (+ the member's approved agency, if any) so the panel's publish lands
-- the listing under their account and name. Silent feature (not advertised on the site) — the Edge Function
-- calls this from readDraft() for by_admin drafts only; the admin can still re-pick an agency in the panel.

create or replace function public.bk_intake_attach_member(p_draft bigint, p_member_no text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare d intake_drafts; u users; a agencies; mno text;
begin
  mno := upper(regexp_replace(coalesce(p_member_no,''), '\s', '', 'g'));
  if mno = '' then return json_build_object('error','nomember'); end if;
  select * into d from intake_drafts where id = p_draft;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  select * into u from users where upper(member_no) = mno and coalesce(blocked,false) = false limit 1;
  if u.id is null then return json_build_object('error','nomember'); end if;
  select * into a from agencies where user_id = u.id and status = 'approved' limit 1;
  update intake_drafts set user_id = u.id, agency_id = a.id, country_code = coalesce(a.country_code, d.country_code), updated_at = now() where id = d.id;
  insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'attached_member', jsonb_build_object('user_id', u.id, 'member_no', u.member_no, 'agency_id', a.id));
  return json_build_object('ok', true, 'member_no', u.member_no, 'user_id', u.id, 'agency_id', a.id, 'agency_name', a.name,
    'name', coalesce(a.name, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,''))));
end $function$;
revoke execute on function public.bk_intake_attach_member(bigint, text) from public, anon, authenticated;
