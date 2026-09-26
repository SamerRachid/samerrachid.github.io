-- Balkoun · 2026-09-26 · every text message is now read right away (conversational intake), so one listing can
-- legitimately be read several times; the per-draft read cap goes from 8 to 15 (still a runaway guard).

create or replace function public.bk_intake_claim(p_draft bigint) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare d intake_drafts;
begin
  update intake_drafts set status = 'reading', reads = reads + 1, claimed_at = now(), updated_at = now()
   where id = p_draft and status in ('collecting','ready','needs_info','failed','review') and reads < 15 returning * into d;
  if d.id is null then return null; end if;
  return row_to_json(d);
end $function$;
