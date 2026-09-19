-- Balkoun · 2026-09-18 · admin can issue a new Telegram link code for an agency (p_newcode)
-- The old code stops working immediately (the bot looks the agency up by intake_code).
-- Applied to the live project as migration "agency_intake_new_code"; this file is the record.

create or replace function public.bk_admin_agency_set(
  p_token text, p_id bigint, p_status text default null, p_verified boolean default null,
  p_intake boolean default null, p_trusted boolean default null, p_intake_phone text default null,
  p_unpair boolean default null, p_newcode boolean default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; a agencies;
begin
  uid := bk_admin_uid(p_token);
  select * into a from agencies where id = p_id;
  if a.id is null then return json_build_object('error','noagency'); end if;
  if not bk_admin_country_ok(uid, a.country_code) then raise exception 'unauthorised'; end if;
  update agencies set status = coalesce(p_status, status), verified = coalesce(p_verified, verified),
         intake_enabled = coalesce(p_intake, intake_enabled), intake_trusted = coalesce(p_trusted, intake_trusted),
         intake_phone = case when p_intake_phone is null then intake_phone when trim(p_intake_phone) = '' then null else bk_intake_norm_phone(p_intake_phone) end,
         intake_telegram = case when coalesce(p_unpair,false) then null else intake_telegram end,
         intake_telegram_name = case when coalesce(p_unpair,false) then null else intake_telegram_name end,
         intake_code = case when coalesce(p_newcode,false) or (coalesce(p_intake,false) and intake_code is null) then upper(substr(encode(gen_random_bytes(6),'hex'),1,8)) else intake_code end,
         updated_at = now()
   where id = p_id returning * into a;
  if p_status = 'approved' then update users set card_logo = true where id = a.user_id; end if;
  if coalesce(p_newcode,false) then insert into intake_log (chat_id, event, detail) values (null, 'agency_new_code', jsonb_build_object('agency_id', a.id, 'by', uid)); end if;
  return json_build_object('ok', true, 'intake_enabled', a.intake_enabled, 'intake_trusted', a.intake_trusted, 'intake_code', a.intake_code);
end $$;
