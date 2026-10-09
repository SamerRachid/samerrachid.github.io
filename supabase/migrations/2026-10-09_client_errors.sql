-- 2026-10-09 · visitors' browsers report a script failure (the app never rendered, the crawlable block stayed on screen).
-- One anon RPC, capped per hour, so a phone we cannot reproduce on tells us its error message, browser and line.
create table if not exists public.client_errors (
  id bigserial primary key,
  created_at timestamptz not null default now(),
  url text, msg text, src text, line int, col int, ua text, country_code text
);
alter table public.client_errors enable row level security;
revoke all on public.client_errors from anon, authenticated;

create or replace function public.bk_client_error(p_msg text, p_url text default null, p_src text default null, p_line int default null, p_col int default null, p_ua text default null, p_country text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
begin
  if (select count(*) from client_errors where created_at > now() - interval '1 hour') >= 300 then return json_build_object('ok', false); end if;
  insert into client_errors (url, msg, src, line, col, ua, country_code)
  values (left(p_url, 300), left(p_msg, 600), left(p_src, 300), p_line, p_col, left(p_ua, 300), left(p_country, 2));
  return json_build_object('ok', true);
end $$;
revoke all on function public.bk_client_error(text, text, text, int, int, text, text) from public;
grant execute on function public.bk_client_error(text, text, text, int, int, text, text) to anon, authenticated;

select 'client_errors ready' as result;
