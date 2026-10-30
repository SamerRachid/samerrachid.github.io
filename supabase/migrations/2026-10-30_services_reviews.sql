-- 2026-10-30 · «خدمات العقار» phase 2: members rate a provider (1–5 stars + a short text, one review each, never their own
-- card); the directory shows the average and the count, the provider page lists the reviews; the owner can hide a review.

create table if not exists public.service_reviews (
  id bigserial primary key,
  provider_id bigint not null references public.service_providers(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  body text, hidden boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (provider_id, user_id)
);
alter table public.service_reviews enable row level security;

-- the directory, now with each provider's rating
create or replace function public.bk_public_services(p_country text default null)
returns json language sql stable security definer set search_path to 'public' as $$
  select json_build_object(
    'cats', coalesce((select json_agg(json_build_object('slug', c.slug, 'name_ar', c.name_ar, 'name_en', c.name_en, 'grp', c.grp, 'icon', c.icon) order by c.sort, c.slug)
                      from service_cats c where c.enabled), '[]'::json),
    'providers', coalesce((select json_agg(json_build_object('id', s.id, 'name', s.name, 'contact_person', s.contact_person, 'phone', s.phone, 'whatsapp', s.whatsapp,
                      'description', s.description, 'logo_url', s.logo_url, 'photos', s.photos, 'cats', s.cats, 'gov_names', s.gov_names, 'area_names', s.area_names,
                      'verified', s.verified, 'featured', coalesce(s.featured_until > now(), false), 'since', s.created_at, 'user_id', s.user_id,
                      'rating', (select round(avg(r.stars)::numeric, 1) from service_reviews r where r.provider_id = s.id and not r.hidden),
                      'reviews', (select count(*) from service_reviews r where r.provider_id = s.id and not r.hidden))
                      order by coalesce(s.featured_until > now(), false) desc, s.verified desc, s.updated_at desc)
                      from service_providers s where s.status = 'approved' and s.country_code = coalesce(p_country,'SY')), '[]'::json))
$$;
grant execute on function public.bk_public_services(text) to anon, authenticated;

-- one provider's reviews (first names only)
create or replace function public.bk_service_reviews(p_id bigint)
returns json language sql stable security definer set search_path to 'public' as $$
  select coalesce(json_agg(json_build_object('id', r.id, 'stars', r.stars, 'body', r.body, 'at', r.created_at, 'name', split_part(trim(coalesce(u.name,'')),' ',1), 'user_id', r.user_id)
         order by r.created_at desc), '[]'::json)
  from service_reviews r join users u on u.id = r.user_id
  where r.provider_id = p_id and not r.hidden
    and exists (select 1 from service_providers s where s.id = p_id and s.status = 'approved')
$$;
grant execute on function public.bk_service_reviews(bigint) to anon, authenticated;

-- a member rates a provider (again = changes his review); not his own card
create or replace function public.bk_service_review(p_token text, p_id bigint, p_stars integer, p_body text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid; s service_providers;
begin
  uid := bk_member_uid(p_token);
  if uid is null then return json_build_object('error','signin'); end if; perform bk_require_verified(uid);
  select * into s from service_providers where id = p_id and status = 'approved';
  if s.id is null then return json_build_object('error','notfound'); end if;
  if s.user_id = uid then return json_build_object('error','own'); end if;
  if p_stars is null or p_stars not between 1 and 5 then return json_build_object('error','stars'); end if;
  insert into service_reviews (provider_id, user_id, stars, body) values (p_id, uid, p_stars, nullif(left(trim(coalesce(p_body,'')),600),''))
  on conflict (provider_id, user_id) do update set stars = excluded.stars, body = excluded.body, updated_at = now();
  return json_build_object('ok', true);
end $$;
grant execute on function public.bk_service_review(text,bigint,integer,text) to anon, authenticated;

-- the panel hides / shows a review
create or replace function public.bk_admin_service_review_hide(p_token text, p_id bigint, p_hidden boolean)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid; v_cc text;
begin
  select s.country_code into v_cc from service_reviews r join service_providers s on s.id = r.provider_id where r.id = p_id;
  if v_cc is null then return json_build_object('error','notfound'); end if;
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['agencies']::text[], 'bk_admin_service_review_hide', v_cc, true, left(p_id::text,300), v_cc);
  perform bk_admin_guard(uid, v_cc);
  update service_reviews set hidden = coalesce(p_hidden, true) where id = p_id;
  return json_build_object('ok', true);
end $$;
grant execute on function public.bk_admin_service_review_hide(text,bigint,boolean) to anon, authenticated;

-- the panel sees every review with its provider
do $do$
declare d text; o text;
begin
  d := pg_get_functiondef('public.bk_admin_services(text,text)'::regprocedure);
  o := $q$'member', (select json_build_object($q$;
  if position(o in d) = 0 then raise exception 'bk_admin_services: provider object not found'; end if;
  execute replace(d, o, $q$'reviews', (select coalesce(json_agg(json_build_object('id', rv.id, 'stars', rv.stars, 'body', rv.body, 'hidden', rv.hidden, 'at', rv.created_at,
                        'name', (select trim(u2.name||' '||coalesce(u2.family_name,'')) from users u2 where u2.id = rv.user_id)) order by rv.created_at desc), '[]'::json)
                        from service_reviews rv where rv.provider_id = s.id),
    'member', (select json_build_object($q$);
end $do$;
