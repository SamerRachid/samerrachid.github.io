-- Photos (owner, 2026-10-19): the bot keeps the order the sender sent them in (each photo carries its message time and
-- message number: ts, seq), the sender picks the cover («غلاف 3»), and owners / admins reorder or pick the cover from
-- the listing's edit page. The first photo is the cover everywhere; nothing is picked automatically.
begin;

-- a draft's photos: the cover the sender chose first, then the sender's own order (time, then message number), then arrival
create or replace function public.bk_intake_sort_photos(p jsonb)
 returns jsonb language sql immutable set search_path to 'public','extensions' as $fn$
  select coalesce(jsonb_agg(e order by coalesce((e->>'cover')::boolean, false) desc,
                                      coalesce(nullif(e->>'ts','')::numeric, 1e18),
                                      coalesce(nullif(e->>'seq','')::numeric, 1e18), o), '[]'::jsonb)
    from jsonb_array_elements(coalesce(p, '[]'::jsonb)) with ordinality t(e, o)
$fn$;
revoke all on function public.bk_intake_sort_photos(jsonb) from public, anon, authenticated;

create or replace function public.bk_intake_add_photo(p_draft bigint, p_photo jsonb)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare n int; mx int; isv boolean; cfg jsonb;
begin
  cfg := bk_intake_cfg(); isv := coalesce(p_photo->>'kind','photo') = 'video';
  mx := case when isv then coalesce(bk_intake_int(cfg->>'intake_max_videos'), 1) else coalesce(bk_intake_int(cfg->>'intake_max_photos'), 12) end;
  select (select count(*) from jsonb_array_elements(photos) x where (coalesce(x->>'kind','photo') = 'video') = isv) into n from intake_drafts where id = p_draft for update;
  if n is null then return json_build_object('error','nodraft'); end if;
  if n >= mx then return json_build_object('ok', false, 'reason', 'max', 'n', n, 'max', mx, 'video', isv); end if;
  update intake_drafts set photos = bk_intake_sort_photos(photos || jsonb_build_array(p_photo)), last_message_at = now(), updated_at = now() where id = p_draft;
  return json_build_object('ok', true, 'n', n + 1, 'max', mx, 'video', isv);
end $fn$;

-- «غلاف 3» from the sender: photo 3 becomes the cover of the listing being prepared, or else of this chat's latest published one
create or replace function public.bk_intake_set_cover(p_source text, p_chat_id text, p_n integer)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare d intake_drafts; ph jsonb; only_ph jsonb; pick jsonb; total int; lid bigint; pid bigint;
begin
  select * into d from intake_drafts
   where source = p_source and chat_id = p_chat_id and status not in ('published','cancelled')
     and jsonb_array_length(coalesce(photos, '[]'::jsonb)) > 0 and coalesce(last_message_at, created_at) > now() - interval '3 days'
   order by coalesce(last_message_at, created_at) desc limit 1 for update;
  if d.id is not null then
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into only_ph
      from jsonb_array_elements(d.photos) with ordinality t(e, o) where coalesce(e->>'kind','photo') <> 'video';
    total := jsonb_array_length(only_ph);
    if total = 0 then return json_build_object('ok', false, 'reason', 'nophoto'); end if;
    if p_n < 1 or p_n > total then return json_build_object('ok', false, 'reason', 'range', 'total', total); end if;
    pick := only_ph->(p_n - 1);
    select coalesce(jsonb_agg(case when e = pick then (e - 'cover') || '{"cover":true}'::jsonb else e - 'cover' end order by o), '[]'::jsonb) into ph
      from jsonb_array_elements(d.photos) with ordinality t(e, o);
    update intake_drafts set photos = bk_intake_sort_photos(ph), updated_at = now() where id = d.id;
    return json_build_object('ok', true, 'where', 'draft', 'n', p_n, 'total', total);
  end if;
  -- nothing being prepared: this chat's latest published listing (last 30 days)
  select listing_id into lid from intake_drafts
   where source = p_source and chat_id = p_chat_id and status = 'published' and listing_id is not null
     and coalesce(published_at, updated_at) > now() - interval '30 days'
   order by coalesce(published_at, updated_at) desc limit 1;
  if lid is null then return json_build_object('ok', false, 'reason', 'nophoto'); end if;
  select count(*) into total from listing_photos where listing_id = lid and coalesce(kind,'photo') <> 'video';
  if total = 0 then return json_build_object('ok', false, 'reason', 'nophoto'); end if;
  if p_n < 1 or p_n > total then return json_build_object('ok', false, 'reason', 'range', 'total', total); end if;
  select id into pid from listing_photos where listing_id = lid and coalesce(kind,'photo') <> 'video' order by sort_order, id offset p_n - 1 limit 1;
  update listing_photos p set sort_order = x.rn - 1 from (
     select id, row_number() over (order by (id <> pid), sort_order, id) rn
       from listing_photos where listing_id = lid and coalesce(kind,'photo') <> 'video') x
   where p.id = x.id;
  return json_build_object('ok', true, 'where', 'listing', 'n', p_n, 'total', total, 'listing_id', lid);
end $fn$;
revoke all on function public.bk_intake_set_cover(text, text, integer) from public, anon, authenticated;
grant execute on function public.bk_intake_set_cover(text, text, integer) to service_role;

-- the edit page: the photos in the order given (the first is the cover); ids left out keep their order after them; videos untouched
create or replace function public.bk_photo_order_apply(p_listing bigint, p_ids bigint[])
 returns void language plpgsql security definer set search_path to 'public','extensions' as $fn$
begin
  update listing_photos p set sort_order = x.rn - 1 from (
     select id, row_number() over (order by coalesce(array_position(p_ids, id), 100000), sort_order, id) rn
       from listing_photos where listing_id = p_listing and coalesce(kind,'photo') <> 'video') x
   where p.id = x.id;
end $fn$;
revoke all on function public.bk_photo_order_apply(bigint, bigint[]) from public, anon, authenticated;

create or replace function public.bk_photo_order(p_user uuid, p_listing bigint, p_ids bigint[], p_token text default null)
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
begin
  perform bk_require_member(p_token, p_user);
  if not exists (select 1 from listings where id = p_listing and user_id = p_user) then raise exception 'forbidden'; end if;
  perform bk_photo_order_apply(p_listing, p_ids);
  return json_build_object('ok', true);
end $fn$;
revoke all on function public.bk_photo_order(uuid, bigint, bigint[], text) from public;
grant execute on function public.bk_photo_order(uuid, bigint, bigint[], text) to anon, authenticated;

create or replace function public.bk_admin_photo_order(p_token text, p_listing bigint, p_ids bigint[])
 returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; lcc text;
begin
  uid := bk_admin_uid(p_token);
  select coalesce(country_code, 'SY') into lcc from listings where id = p_listing;
  perform public.bk_admin_need(uid, ARRAY['listings_edit']::text[], 'bk_admin_photo_order', lcc, true, left(coalesce(p_listing::text, ''), 300), lcc);
  perform bk_photo_order_apply(p_listing, p_ids);
  return json_build_object('ok', true);
end $fn$;
revoke all on function public.bk_admin_photo_order(text, bigint, bigint[]) from public;
grant execute on function public.bk_admin_photo_order(text, bigint, bigint[]) to anon, authenticated;
commit;
