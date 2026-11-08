-- 2026-11-07 (owner: "make sure I have full control of the permissions I give the other admins")
-- Five admin reads let ANY admin in (bk_admin_need with no permission). Each now needs the permission of the page that shows it:
--   bk_admin_analytics     → «التحليلات» (stats) or «المربعات» (ads: the ad-performance table)
--   bk_admin_visitors_now  → stats
--   bk_admin_get_settings  → «الإعدادات» (settings)
--   bk_admin_storage_usage → «التخزين» (storage) or stats
--   bk_admin_media_used    → listings_view / listings_edit (the media library page)
-- The super admin passes every check (bk_admin_need). admin.js only calls them for admins who hold the permission.
do $$
declare r record; d text; o text; n text;
begin
  for r in select * from (values
    ('bk_admin_analytics',     'bk_admin_need(uid, null::text[], ''bk_admin_analytics''',     'bk_admin_need(uid, ARRAY[''stats'',''ads'']::text[], ''bk_admin_analytics'''),
    ('bk_admin_visitors_now',  'bk_admin_need(uid, null::text[], ''bk_admin_visitors_now''',  'bk_admin_need(uid, ARRAY[''stats'']::text[], ''bk_admin_visitors_now'''),
    ('bk_admin_get_settings',  'bk_admin_need(uid, null::text[], ''bk_admin_get_settings''',  'bk_admin_need(uid, ARRAY[''settings'']::text[], ''bk_admin_get_settings'''),
    ('bk_admin_storage_usage', 'bk_admin_need(uid, null::text[], ''bk_admin_storage_usage''', 'bk_admin_need(uid, ARRAY[''storage'',''stats'']::text[], ''bk_admin_storage_usage'''),
    ('bk_admin_media_used',    'bk_admin_need(uid, null::text[], ''bk_admin_media_used''',    'bk_admin_need(uid, ARRAY[''listings_view'',''listings_edit'']::text[], ''bk_admin_media_used''')
  ) v(fn, old, new) loop
    select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = r.fn;
    if d is null or (length(d) - length(replace(d, r.old, ''))) / length(r.old) <> 1 then raise exception '%: permission line not found exactly once', r.fn; end if;
    execute replace(d, r.old, r.new);
  end loop;
end $$;
