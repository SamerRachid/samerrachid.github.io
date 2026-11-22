-- 2026-11-22 bot fixes after «أبو نافع» (drafts 938/939):
-- 1) bk_intake_add_photo refuses a photo whose fingerprint (p_photo.dh, 64-bit difference hash from bk-intake) is within
--    10 bits of a photo already in the draft — the same picture sent twice, also once in HD and once in normal quality.
--    When the new copy is clearly sharper (20 % more pixels) it takes the old one's place (same position, same send order)
--    and the answer names the old files so bk-intake removes them.
-- 2) bk_intake_publish and bk_intake_patch_listing keep descriptions up to 6000 characters (was 1200: a villa's text was cut in half).

create or replace function public.bk_intake_add_photo(p_draft bigint, p_photo jsonb)
 returns json
 language plpgsql
 security definer
 set search_path to 'public', 'extensions'
as $function$
declare n int; mx int; isv boolean; cfg jsonb; nd text; dup jsonb; dupi int;
begin
  cfg := bk_intake_cfg(); isv := coalesce(p_photo->>'kind','photo') = 'video';
  mx := case when isv then coalesce(bk_intake_int(cfg->>'intake_max_videos'), 1) else coalesce(bk_intake_int(cfg->>'intake_max_photos'), 12) end;
  select (select count(*) from jsonb_array_elements(photos) x where (coalesce(x->>'kind','photo') = 'video') = isv) into n from intake_drafts where id = p_draft for update;
  if n is null then return json_build_object('error','nodraft'); end if;
  nd := lower(coalesce(p_photo->>'dh',''));
  if not isv and nd ~ '^[0-9a-f]{16}$' then
    select e.x, (e.o - 1)::int into dup, dupi
      from intake_drafts d, jsonb_array_elements(d.photos) with ordinality as e(x, o)
     where d.id = p_draft and coalesce(e.x->>'kind','photo') = 'photo' and lower(coalesce(e.x->>'dh','')) ~ '^[0-9a-f]{16}$'
       and bit_count(('x' || lower(e.x->>'dh'))::bit(64) # ('x' || nd)::bit(64)) <= 10
     order by bit_count(('x' || lower(e.x->>'dh'))::bit(64) # ('x' || nd)::bit(64)) limit 1;
    if dup is not null then
      if coalesce(bk_intake_int(p_photo->>'w'),0)::numeric * coalesce(bk_intake_int(p_photo->>'h'),0)
         > coalesce(bk_intake_int(dup->>'w'),0)::numeric * coalesce(bk_intake_int(dup->>'h'),0) * 1.2 then
        update intake_drafts set photos = jsonb_set(photos, array[dupi::text], p_photo || jsonb_build_object('ts', dup->'ts', 'seq', dup->'seq')),
               last_message_at = now(), updated_at = now() where id = p_draft;
        return json_build_object('ok', true, 'n', n, 'max', mx, 'video', false,
               'replaced', json_build_object('path', dup->>'path', 'thumb_path', dup->>'thumb_path'));
      end if;
      return json_build_object('ok', false, 'reason', 'dup', 'n', n, 'max', mx, 'video', false, 'kept', dup->>'path');
    end if;
  end if;
  if n >= mx then return json_build_object('ok', false, 'reason', 'max', 'n', n, 'max', mx, 'video', isv); end if;
  update intake_drafts set photos = bk_intake_sort_photos(photos || jsonb_build_array(p_photo)), last_message_at = now(), updated_at = now() where id = p_draft;
  return json_build_object('ok', true, 'n', n + 1, 'max', mx, 'video', isv);
end $function$;

do $$
declare s text;
begin
  s := pg_get_functiondef('public.bk_intake_publish'::regproc);
  if position('descr := left(descr, 1200);' in s) = 0 then raise exception 'bk_intake_publish: description cap not found'; end if;
  execute replace(s, 'descr := left(descr, 1200);', 'descr := left(descr, 6000);');
  s := pg_get_functiondef('public.bk_intake_patch_listing'::regproc);
  if position('left(v_descr, 1200)' in s) = 0 then raise exception 'bk_intake_patch_listing: description cap not found'; end if;
  execute replace(s, 'left(v_descr, 1200)', 'left(v_descr, 6000)');
end $$;
