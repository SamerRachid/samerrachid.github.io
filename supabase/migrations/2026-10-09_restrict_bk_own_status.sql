-- 2026-10-09 — bk_own_status(p_user,p_id,p_status,p_reason,p_token) accepted ANY text for p_status with only
-- an ownership check, so a member could call it directly (bypassing the UI, which only ever sends 'sold'/'rented')
-- with p_status='live' and silently republish their own rejected/hidden/removed listing, skipping admin review
-- entirely. The client UI (index.html:8488) only ever sends 'sold' or 'rented' ("mark sold/rented" button), so
-- that is the only legitimate use of this RPC; restrict the server to match, and require the listing to currently
-- be live/pending before it can be closed this way.
-- Verified live (throwaway test user + listing inside a rolled-back transaction, no real account touched):
--   p_status='live'  -> {"error":"badstatus"}, status unchanged
--   p_status='sold'  -> {"ok":true}, status actually changed to 'sold'
CREATE OR REPLACE FUNCTION public.bk_own_status(p_user uuid, p_id bigint, p_status text, p_reason text, p_token text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare l listings;
begin
  perform bk_require_member(p_token, p_user);
  if p_status not in ('sold','rented') then
    return json_build_object('error','badstatus');
  end if;
  select * into l from listings where id = p_id;
  if l.id is null or l.user_id is distinct from p_user then
    return json_build_object('error','notyours');
  end if;
  if l.status not in ('live','pending') then
    return json_build_object('error','badstatus');
  end if;
  update listings set status = p_status, closed_reason = p_reason, closed_at = now()
    where id = p_id;
  return json_build_object('ok', true);
end $function$;
