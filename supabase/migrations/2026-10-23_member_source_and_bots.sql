-- Owner, 2026-10-23: (1) know where each new member came from (Facebook / Instagram / Google / an ad link …);
-- (2) keep crawlers out of the visitor numbers.

-- 1. the member's source, written once right after sign-up by the member's own session
alter table public.users add column if not exists signup_source text;
alter table public.users add column if not exists signup_source_detail text;

create or replace function public.bk_member_set_source(p_token text, p_source text, p_detail text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $fn$
declare uid uuid; src text := lower(left(regexp_replace(coalesce(p_source,''), '[^a-zA-Z_-]', '', 'g'), 30));
begin
  uid := bk_member_uid(p_token);
  if uid is null then return json_build_object('error','unauthorised'); end if;
  if src = '' then return json_build_object('ok', false); end if;
  -- only a fresh account, and only once: the source is the visit that led to the sign-up, never changed later
  update users set signup_source = src, signup_source_detail = left(p_detail, 160)
   where id = uid and signup_source is null and created_at > now() - interval '1 day';
  return json_build_object('ok', true);
end $fn$;
revoke all on function public.bk_member_set_source(text,text,text) from public;
grant execute on function public.bk_member_set_source(text,text,text) to anon, authenticated;

-- the members list in the panel carries the source
do $$
declare d text;
begin
  d := pg_get_functiondef('public.bk_admin_data_core'::regproc);
  if position('u.signup_source' in d) = 0 then
    d := replace(d, 'u.country, coalesce(u.is_house,false) as is_house', 'u.country, u.signup_source, u.signup_source_detail, coalesce(u.is_house,false) as is_house');
    if position('u.signup_source' in d) = 0 then raise exception 'bk_admin_data_core: users list not found'; end if;
    execute d;
  end if;
end $$;

-- 2. crawler visits kept apart (moved, not deleted): the 22 Oct burst — about 1,800 one-page visits from US / Canada
--    desktops between 11:00 and 15:00 Syria time, nearly all gone within a second, spread over every listing
create table if not exists public.page_views_bots (like public.page_views including defaults);
alter table public.page_views_bots enable row level security;   -- no policies: only the database owner reads it
with spike as (
  select pv.visitor_id from page_views pv
   where pv.created_at between '2026-10-22 08:00+00' and '2026-10-22 12:00+00'
     and (pv.country like 'United S%' or pv.country like 'Canada%') and pv.device = 'desktop'
   group by pv.visitor_id
  having count(*) <= 2
     and coalesce((select extract(epoch from (p.last_seen - p.first_seen)) from visitor_presence p where p.visitor_id = pv.visitor_id), 0) < 5
     and bool_and(pv.user_id is null)
), moved as (
  delete from page_views v using spike s
   where v.visitor_id = s.visitor_id and v.created_at between '2026-10-22 08:00+00' and '2026-10-22 12:00+00'
  returning v.*
)
insert into page_views_bots select * from moved;
