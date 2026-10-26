-- the panel's own type list (what the site and the bot use): «تراس» → «تراس / سطح» (owner, 2026-10-25)
update site_content set extras = jsonb_set(extras, '{property_types}', (
  select jsonb_agg(case when r->>'code' = 'terrace' then r || '{"ar":"تراس / سطح","en":"Terrace / rooftop apartment"}'::jsonb else r end order by i)
    from jsonb_array_elements(extras->'property_types') with ordinality t(r, i)))
 where id = 1 and jsonb_typeof(extras->'property_types') = 'array';
