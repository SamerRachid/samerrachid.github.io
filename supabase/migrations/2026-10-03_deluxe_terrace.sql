-- 2026-10-03 · owner's request: two more condition codes and one more property type.
--   conditions: deluxe = ديلوكس, superdeluxe = سوبر ديلوكس (homes/commercial; every country)
--   type:       terrace = تراس (residential, section homes; every country)
-- Touches: listings_condition_check, countries.types, bk_intake_taxonomy (SY fallback + conditions),
-- bk_intake_publish + bk_intake_patch_listing (whitelists). Site/bot/scripts updated in the same commit.

alter table listings drop constraint if exists listings_condition_check;
alter table listings add constraint listings_condition_check
  check (condition = any (array['intact','deluxe','superdeluxe','old','repair','shell','stripped','damaged','empty','built','fenced','planted']));

update countries set types = types || '[{"code":"terrace","ar":"تراس","en":"Terrace apartment","fr":"Appartement avec terrasse"}]'::jsonb
 where jsonb_array_length(coalesce(types,'[]'::jsonb)) > 0 and not (types @> '[{"code":"terrace"}]'::jsonb);

do $$
declare src text; dst text; fn text;
begin
  -- taxonomy: SY fallback type list + both condition lists
  select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'bk_intake_taxonomy';
  dst := replace(src, '{"code":"house","ar":"منزل","en":"House"}', '{"code":"house","ar":"منزل","en":"House"},{"code":"terrace","ar":"تراس","en":"Terrace apartment"}');
  dst := replace(dst, '{"code":"intact","ar":"سليم"},', '{"code":"intact","ar":"سليم"},{"code":"deluxe","ar":"ديلوكس"},{"code":"superdeluxe","ar":"سوبر ديلوكس"},');
  if dst = src then raise exception 'bk_intake_taxonomy: anchors not found'; end if;
  if position('terrace' in dst) = 0 or position('superdeluxe' in dst) = 0 then raise exception 'bk_intake_taxonomy: replace incomplete'; end if;
  execute dst;

  foreach fn in array array['bk_intake_publish','bk_intake_patch_listing'] loop
    select pg_get_functiondef(p.oid) into src from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = fn;
    dst := replace(src, '''workshop'',''house'',''plot'')', '''workshop'',''house'',''plot'',''terrace'')');
    dst := replace(dst, '(''intact'',''old'',''repair'',''shell'',''stripped'',''damaged'')', '(''intact'',''deluxe'',''superdeluxe'',''old'',''repair'',''shell'',''stripped'',''damaged'')');
    if position('terrace' in dst) = 0 or position('superdeluxe' in dst) = 0 then raise exception '%: anchors not found', fn; end if;
    execute dst;
  end loop;
end $$;

-- checks
select (select count(*) from countries where types @> '[{"code":"terrace"}]') as countries_with_terrace,
       (select jsonb_path_exists(bk_intake_taxonomy('SY')::jsonb, '$.types[*] ? (@.code == "terrace")')) as sy_type,
       (select jsonb_path_exists(bk_intake_taxonomy('SY')::jsonb, '$.conditions[*] ? (@.code == "superdeluxe")')) as sy_cond,
       (select jsonb_path_exists(bk_intake_taxonomy('LB')::jsonb, '$.conditions[*] ? (@.code == "deluxe")')) as lb_cond,
       (select pg_get_functiondef(oid) like '%''terrace''%' from pg_proc where proname = 'bk_intake_publish') as publish_type,
       (select pg_get_functiondef(oid) like '%''superdeluxe''%' from pg_proc where proname = 'bk_intake_patch_listing') as patch_cond,
       (select pg_get_constraintdef(oid) like '%deluxe%' from pg_constraint where conname = 'listings_condition_check') as chk;
