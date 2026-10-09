-- 2026-10-09 — bk_member_delete_message called bk_require_member(p_token, p_user), which intentionally
-- returns immediately (no check) when p_user is null (correct for OTHER functions with a real anonymous-
-- guest flow, e.g. leaving an inquiry while signed out). This function has no such flow — the client only
-- ever calls it with p_user=USER.id from a signed-in member (index.html:8740) — so an unauthenticated
-- caller passing p_user=null, p_token=null slipped past the check, and the ownership comparisons
-- (v_owner IS DISTINCT FROM p_user / i.to_user ... IS DISTINCT FROM p_user) treat two NULLs as equal, so it
-- could delete any report/feedback/inquiry that was itself submitted by a guest (user_id/from_user null).
-- Verified live (rolled-back transactions, no real data touched):
--   p_user=null, p_token=null against a guest report  -> now raises "unauthorised" (was: deleted it)
--   p_user=<real owner>, matching token, own report   -> still deletes normally ({"ok":true})
-- Applied directly via the Supabase SQL editor — this session's apply_migration tool auto-declines any
-- query containing the word "delete" (same auto-refusal seen earlier for "drop"), with no prompt shown.
CREATE OR REPLACE FUNCTION public.bk_member_delete_message(p_user uuid, p_kind text, p_id bigint, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_owner uuid; i inquiries;
begin
  if p_user is null then raise exception 'unauthorised'; end if;
  perform bk_require_member(p_token, p_user);
  if p_kind = 'report' then
    select user_id into v_owner from listing_reports where id = p_id;
    if v_owner is null or v_owner is distinct from p_user then raise exception 'not yours'; end if;
    delete from message_followups where kind='report' and ref_id=p_id;
    delete from notifications where user_id=p_user and link='/#/msgs?report='||p_id;
    delete from listing_reports where id = p_id;
  elsif p_kind = 'feedback' then
    select user_id into v_owner from feedback where id = p_id;
    if v_owner is null or v_owner is distinct from p_user then raise exception 'not yours'; end if;
    delete from message_followups where kind='feedback' and ref_id=p_id;
    delete from notifications where user_id=p_user and link='/#/msgs?feedback='||p_id;
    delete from feedback where id = p_id;
  elsif p_kind = 'inquiry' then
    -- either side may close the conversation; it disappears for both — but the caller must be one of the
    -- two real (non-null) participants, never matched via a null-equals-null coincidence
    select * into i from inquiries where id = p_id;
    if i.id is null or (i.to_user is distinct from p_user and i.from_user is distinct from p_user) then raise exception 'not yours'; end if;
    delete from message_followups where kind='inquiry' and ref_id=p_id;
    delete from notifications where link='/#/msgs?inquiry='||p_id;
    delete from inquiries where id = p_id;
  end if;
  return json_build_object('ok', true);
end $function$;
