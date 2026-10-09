-- 2026-10-08 · the bot's place memory: landmarks and phrases that resolve to a governorate/area, learned from published
-- listings and from corrections; shown to the model with the taxonomy and applied before the word scan. Also switches
-- the reader to Claude Sonnet 5 (prices per million tokens for the cost log).
create table if not exists public.intake_places (
  id bigserial primary key,
  country_code text not null default 'SY',
  phrase text not null,
  phrase_norm text not null,
  governorate_id int references public.governorates(id) on delete cascade,
  area_id int references public.areas(id) on delete cascade,
  hits int not null default 1,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (country_code, phrase_norm)
);
alter table public.intake_places enable row level security;
revoke all on public.intake_places from anon, authenticated;

-- seed: what this week's corrections taught us (phrase_norm = the Edge Function's norm(): no diacritics, no leading ال, ة→ه, ى→ي)
insert into public.intake_places (country_code, phrase, phrase_norm, governorate_id, area_id, source) values
  ('SY', 'ساحة المرجة',      'ساحه مرجه',       1, (select id from areas where name_ar = 'المرجة'   and governorate_id = 1 limit 1), 'seed'),
  ('SY', 'شام فيو',          'شام فيو',         2, (select id from areas where name_ar = 'الصبورة'  and governorate_id = 2 limit 1), 'seed'),
  ('SY', 'مشروع شام فيو',    'مشروع شام فيو',   2, (select id from areas where name_ar = 'الصبورة'  and governorate_id = 2 limit 1), 'seed'),
  ('SY', 'مشفى الأسدي',      'مشفي اسدي',       1, (select id from areas where name_ar = 'المزة'    and governorate_id = 1 limit 1), 'seed'),
  ('SY', 'دوار جامع البراء', 'دوار جامع براء',  2, (select id from areas where name_ar = 'ببيلا'    and governorate_id = 2 limit 1), 'seed'),
  ('SY', 'منتزه السلام',     'منتزه سلام',      2, (select id from areas where name_ar = 'ببيلا'    and governorate_id = 2 limit 1), 'seed'),
  ('SY', 'جامع المصطفى',     'جامع مصطفي',      1, (select id from areas where name_ar = 'الصناعة'  and governorate_id = 1 limit 1), 'seed'),
  ('SY', 'جامع العمري',      'جامع عمري',       2, (select id from areas where name_ar = 'المليحة'  and governorate_id = 2 limit 1), 'seed')
on conflict (country_code, phrase_norm) do nothing;
delete from public.intake_places where area_id is null;

update public.site_content set extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('intake_model', 'claude-sonnet-5', 'intake_price_in', 3, 'intake_price_out', 15) where id = 1;

select (select count(*) from public.intake_places) as places, (select bk_intake_cfg()->>'intake_model') as model;
