-- 2026-11-15 (owner: «the edit page gets every option of the post page»)
-- The edit page now sends price_negotiable, accepts_whatsapp and by_owner; neither edit function stored them
-- (year_built was already accepted by both). The admin function also ignored price_unit / price_unit_value, so a
-- per-metre price edited by the admin fell back to a whole price (bk_price_unit_guard cleared the stale pair).
--
-- Both functions are long and change often, so this patches the live definitions in place instead of repeating
-- them: the new assignments go right after the contact_phone line, which each function has exactly once.
-- It refuses to run when that line is missing or the columns are already handled. Grants are untouched.
do $mig$
declare
  d text;
  a constant text := 'contact_phone = coalesce(p_patch->>''contact_phone'', contact_phone)';
  flags constant text := E',\n'
    || E'    price_negotiable = case when p_patch ? ''price_negotiable'' then coalesce((p_patch->>''price_negotiable'')::boolean, price_negotiable) else price_negotiable end,\n'
    || E'    accepts_whatsapp = case when p_patch ? ''accepts_whatsapp'' then coalesce((p_patch->>''accepts_whatsapp'')::boolean, accepts_whatsapp) else accepts_whatsapp end,\n'
    || E'    by_owner = case when p_patch ? ''by_owner'' then coalesce((p_patch->>''by_owner'')::boolean, by_owner) else by_owner end';
  unit constant text := E',\n'
    || E'    price_unit = case when p_patch ? ''price_unit'' then (case when p_patch->>''price_unit'' in (''m2'',''dunam'') then p_patch->>''price_unit'' else null end) else price_unit end,\n'
    || E'    price_unit_value = case when p_patch ? ''price_unit_value'' then nullif(p_patch->>''price_unit_value'','''')::numeric else price_unit_value end';
begin
  -- the member's own edit
  d := pg_get_functiondef('public.bk_edit(uuid,bigint,jsonb,text)'::regprocedure);
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 or position('price_negotiable' in d) > 0 then
    raise exception 'bk_edit: not the definition this migration expects';
  end if;
  execute replace(d, a, a || flags);

  -- the admin's edit: the same three flags, plus the per-metre / per-dunam price the form already sends
  d := pg_get_functiondef('public.bk_admin_edit_listing(text,bigint,jsonb)'::regprocedure);
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 or position('price_negotiable' in d) > 0 or position('price_unit' in d) > 0 then
    raise exception 'bk_admin_edit_listing: not the definition this migration expects';
  end if;
  execute replace(d, a, a || flags || unit);
end
$mig$;
