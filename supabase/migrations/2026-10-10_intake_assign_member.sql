-- 2026-10-10: a bot/admin intake draft can be attached to ANY member, not only to an approved agency.
-- A draft publishes under intake_drafts.user_id (bk_intake_publish); agency_id only marks "not by owner" and names the
-- office. The admin UI could only pick an agency (bk_admin_intake returned agencies alone, bk_admin_intake_set only
-- understood agency_id), so a listing the owner forwarded to the bot on behalf of a plain member had nowhere to go.
--   bk_admin_intake      → also returns 'members' (every non-blocked user, with the approved agency they own, if any)
--   bk_admin_intake_set  → accepts p_patch.user_id (uuid or "" to clear); sets user_id and the member's own agency_id

CREATE OR REPLACE FUNCTION public.bk_admin_intake(p_token text, p_country text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 200)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; sc text; al text[]; cfg jsonb;
begin
  uid := bk_admin_uid(p_token);
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  cfg := bk_intake_cfg();
  return json_build_object(
    'cfg', cfg,
    'counts', (select json_build_object(
        'collecting', count(*) filter (where status in ('collecting','reading')),
        'ready', count(*) filter (where status in ('ready','needs_info')),
        'review', count(*) filter (where status = 'review'),
        'published', count(*) filter (where status = 'published'),
        'failed', count(*) filter (where status = 'failed'),
        'today', count(*) filter (where created_at > now() - interval '24 hours'),
        'cost_month', coalesce(sum(cost_usd) filter (where created_at > date_trunc('month', now())), 0)
          + (select coalesce(sum(cost_usd) filter (where created_at > date_trunc('month', now())), 0) from ai_search_log where bk_scope_ok(country_code, sc, al)),
        'cost_total', coalesce(sum(cost_usd), 0)
          + (select coalesce(sum(cost_usd), 0) from ai_search_log where bk_scope_ok(country_code, sc, al)),
        'search_today', (select count(*) from ai_search_log where bk_scope_ok(country_code, sc, al) and created_at > now() - interval '24 hours'),
        'search_total', (select count(*) from ai_search_log where bk_scope_ok(country_code, sc, al)))
      from intake_drafts where bk_scope_ok(country_code, sc, al)),
    'drafts', coalesce((select json_agg(row_to_json(x)) from (
        select d.id, d.source, d.chat_id, d.sender_name, d.agency_id, d.user_id, d.by_admin, d.country_code, d.status,
               d.raw_text, d.fields, d.missing, d.summary, d.photos, d.listing_id, d.error, d.model, d.tokens_in, d.tokens_out, d.cost_usd,
               d.reads, d.created_at, d.updated_at, d.last_message_at, d.processed_at, d.published_at,
               a.name as agency_name, a.intake_trusted, l.ref as listing_ref, l.status as listing_status,
               (select count(*) from intake_messages m where m.draft_id = d.id) as messages
          from intake_drafts d left join agencies a on a.id = d.agency_id left join listings l on l.id = d.listing_id
         where bk_scope_ok(d.country_code, sc, al) and (p_status is null or d.status = p_status)
         order by d.created_at desc limit greatest(1, least(coalesce(p_limit,200), 500))) x), '[]'::json),
    'agencies', coalesce((select json_agg(row_to_json(x)) from (
        select a.id, a.name, a.status, a.country_code, a.intake_enabled, a.intake_trusted, a.intake_phone, a.intake_telegram, a.intake_telegram_name, a.intake_code, a.intake_paired_at, a.whatsapp, a.phone, a.user_id
          from agencies a where a.status = 'approved' and bk_scope_ok(coalesce(a.country_code,'SY'), sc, al) order by a.name) x), '[]'::json),
    'members', coalesce((select json_agg(row_to_json(x)) from (
        select u.id, u.name, u.family_name, u.phone, u.member_no, u.account_type,
               (select a.id from agencies a where a.user_id = u.id and a.status = 'approved' order by a.id limit 1) as agency_id
          from users u where coalesce(u.blocked, false) = false order by u.name, u.family_name) x), '[]'::json),
    'log', coalesce((select json_agg(row_to_json(x)) from (
        select id, draft_id, chat_id, level, event, detail, created_at from intake_log order by created_at desc limit 80) x), '[]'::json));
end $function$;

CREATE OR REPLACE FUNCTION public.bk_admin_intake_set(p_token text, p_id bigint, p_patch jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; d intake_drafts; ag agencies; u users; st text; f jsonb; miss text[];
begin
  uid := bk_admin_uid(p_token);
  select * into d from intake_drafts where id = p_id;
  if d.id is null then return json_build_object('error','nodraft'); end if;
  if not bk_admin_country_ok(uid, d.country_code) then raise exception 'unauthorised'; end if;
  if p_patch ? 'agency_id' then
    if p_patch->>'agency_id' is null or p_patch->>'agency_id' = '' then d.agency_id := null;
    else
      select * into ag from agencies where id = (p_patch->>'agency_id')::bigint;
      if ag.id is null then return json_build_object('error','noagency'); end if;
      if not bk_admin_country_ok(uid, ag.country_code) then raise exception 'unauthorised'; end if;
      d.agency_id := ag.id; d.user_id := ag.user_id; d.country_code := coalesce(ag.country_code, d.country_code);
    end if;
  end if;
  -- a plain member as the listing's owner: user_id set directly; agency_id becomes the member's own approved agency (or none)
  if p_patch ? 'user_id' then
    if p_patch->>'user_id' is null or p_patch->>'user_id' = '' then d.user_id := null; d.agency_id := null;
    else
      select * into u from users where id = (p_patch->>'user_id')::uuid;
      if u.id is null then return json_build_object('error','nouser'); end if;
      d.user_id := u.id;
      select a.id into d.agency_id from agencies a where a.user_id = u.id and a.status = 'approved' order by a.id limit 1;
    end if;
  end if;
  if p_patch ? 'fields' then
    d.fields := jsonb_strip_nulls(coalesce(d.fields,'{}'::jsonb) || (p_patch->'fields'));
    f := d.fields; miss := coalesce(d.missing, '{}');
    if coalesce(f->>'deal','') in ('sale','rent') then miss := array_remove(miss, 'deal'); end if;
    if coalesce(f->>'property_type','') <> '' then miss := array_remove(miss, 'property_type'); end if;
    if coalesce(f->>'governorate','') <> '' or coalesce(f->>'governorate_id','') <> '' then miss := array_remove(miss, 'governorate'); end if;
    if coalesce(f->>'area','') <> '' or coalesce(f->>'area_id','') <> '' then miss := array_remove(miss, 'area'); end if;
    if coalesce(f->>'price','') <> '' then miss := array_remove(miss, 'price'); end if;
    if coalesce(f->>'area_m2','') <> '' then miss := array_remove(miss, 'area_m2'); end if;
    if coalesce(f->>'tabu','') <> '' or coalesce(f->>'deal','') = 'rent' then miss := array_remove(miss, 'tabu'); end if;
    d.missing := miss;
  end if;
  if p_patch ? 'country_code' then
    if not bk_admin_country_ok(uid, upper(p_patch->>'country_code')) then raise exception 'unauthorised'; end if;
    d.country_code := upper(p_patch->>'country_code');
  end if;
  if p_patch ? 'photos' then d.photos := p_patch->'photos'; if jsonb_array_length(d.photos) > 0 then d.missing := array_remove(coalesce(d.missing,'{}'), 'photos'); end if; end if;
  st := p_patch->>'status';
  if st is not null then
    if st not in ('cancelled','ready','review','collecting') then return json_build_object('error','badstatus'); end if;
    if d.status = 'published' then return json_build_object('error','already'); end if;
    d.status := st;
  end if;
  update intake_drafts set agency_id = d.agency_id, user_id = d.user_id, fields = d.fields, missing = d.missing, country_code = d.country_code,
         photos = d.photos, status = d.status, updated_at = now(), error = case when p_patch ? 'agency_id' or p_patch ? 'user_id' or st is not null then null else error end
   where id = p_id returning * into d;
  insert into intake_log (draft_id, chat_id, event, detail) values (d.id, d.chat_id, 'admin_edit', jsonb_build_object('keys', (select json_agg(k) from jsonb_object_keys(p_patch) k), 'by', uid));
  return ((row_to_json(d)::jsonb - 'error') || jsonb_build_object('err_text', d.error))::json;
end $function$;
