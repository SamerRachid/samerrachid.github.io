-- Security migration B, part 1 (2026-09-03): member sessions.
-- Members now get a random session token at login/register/reset, stored in member_sessions.
-- Every member-facing function verifies that the token belongs to the user id the client claims.
-- Part 2 (2026-09-03_b2_member_functions_token_check.sql, generated from the backup) adds the p_token
-- parameter and the check to the 28 existing member functions.

create table if not exists public.member_sessions (
  token       text primary key,
  user_id     uuid not null references public.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default (now() + interval '30 days')
);
create index if not exists idx_member_sessions_user on public.member_sessions(user_id);
alter table public.member_sessions enable row level security;
revoke all on public.member_sessions from anon, authenticated;

-- resolve a member token to a user id (null when missing, expired, unknown or blocked)
create or replace function public.bk_member_uid(p_token text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  if p_token is null or length(p_token) < 20 then return null; end if;
  delete from member_sessions where expires_at < now();
  select s.user_id into uid from member_sessions s
    join users u on u.id = s.user_id
   where s.token = p_token and s.expires_at > now() and not u.blocked;
  return uid;
end $$;
revoke execute on function public.bk_member_uid(text) from public, anon, authenticated;

-- guard used by every member function: a null user is an anonymous call and is allowed;
-- a non-null user must match the token
create or replace function public.bk_require_member(p_token text, p_user uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_user is null then return; end if;
  if bk_member_uid(p_token) is distinct from p_user then raise exception 'unauthorised'; end if;
end $$;
revoke execute on function public.bk_require_member(text, uuid) from public, anon, authenticated;

create or replace function public.bk_issue_member_token(p_user uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare tok text;
begin
  tok := encode(gen_random_bytes(24), 'hex');
  insert into member_sessions (token, user_id) values (tok, p_user);
  return tok;
end $$;
revoke execute on function public.bk_issue_member_token(uuid) from public, anon, authenticated;

create or replace function public.bk_logout(p_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from member_sessions where token = p_token;
  return json_build_object('ok', true);
end $$;
grant execute on function public.bk_logout(text) to anon, authenticated;

-- bk_me now validates the token, slides the expiry, and returns the full profile + token
drop function if exists public.bk_me(uuid);
create or replace function public.bk_me(p_id uuid, p_token text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare u users; uid uuid;
begin
  uid := bk_member_uid(p_token);
  if uid is null or uid <> p_id then return json_build_object('error','nouser'); end if;
  select * into u from users where id = uid and not blocked;
  if u.id is null then return json_build_object('error','nouser'); end if;
  update member_sessions set expires_at = now() + interval '30 days' where token = p_token;
  update users set last_seen_at = now() where id = u.id;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'token',p_token);
end $$;
grant execute on function public.bk_me(uuid, text) to anon, authenticated;

create or replace function public.bk_login(p_phone text, p_hash text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare u users; tok text;
begin
  select * into u from users where phone = p_phone;
  if u.id is null then return json_build_object('error','nouser'); end if;
  if u.pass_hash is null or u.pass_hash <> crypt(p_hash, u.pass_hash) then
    return json_build_object('error','badpass');
  end if;
  if u.blocked then return json_build_object('error','blocked'); end if;
  update users set last_seen_at = now() where id = u.id;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'token',tok);
end $$;
grant execute on function public.bk_login(text, text) to anon, authenticated;

create or replace function public.bk_register(p_phone text, p_name text, p_family text, p_hash text,
  p_username text default null, p_city text default null, p_country text default null, p_currency text default 'SYP')
returns json language plpgsql security definer set search_path = public, extensions as $$
declare u users; v_currency text; tok text;
begin
  if exists (select 1 from users where phone = p_phone) then
    return json_build_object('error','exists');
  end if;
  if p_username is not null and exists
     (select 1 from users where lower(username) = lower(p_username)) then
    return json_build_object('error','usertaken');
  end if;
  if length(coalesce(p_hash,'')) < 32 then raise exception 'bad hash'; end if;
  v_currency := case when p_currency in ('USD','SYP') then p_currency else 'SYP' end;
  insert into users (phone, username, name, family_name, pass_hash, phone_verified, city, country, preferred_currency)
    values (p_phone, p_username, p_name, p_family, crypt(p_hash, gen_salt('bf')), true, p_city, p_country, v_currency)
    returning * into u;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'city',u.city,'country',u.country,'preferred_currency',u.preferred_currency,'role',u.role,'token',tok);
end $$;
grant execute on function public.bk_register(text,text,text,text,text,text,text,text) to anon, authenticated;

-- NOTE: password reset is still unverified by design (the WhatsApp step is client-side only).
-- It now at least invalidates every other session of the account and returns a fresh token.
create or replace function public.bk_set_password(p_phone text, p_hash text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare u users; tok text;
begin
  select * into u from users where phone = p_phone;
  if u.id is null then return json_build_object('error','nouser'); end if;
  if u.blocked then return json_build_object('error','blocked'); end if;
  if length(coalesce(p_hash,'')) < 32 then raise exception 'bad hash'; end if;
  update users set pass_hash = crypt(p_hash, gen_salt('bf')) where id = u.id;
  delete from member_sessions where user_id = u.id;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'token',tok);
end $$;
grant execute on function public.bk_set_password(text, text) to anon, authenticated;

-- admin "view site as a user": issue a real member session for the admin's own user row
create or replace function public.bk_admin_switch_to_user(p_token text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; u users; tok text;
begin
  uid := bk_admin_uid(p_token);
  select * into u from users where id = uid;
  if u.id is null then return json_build_object('error','nouser'); end if;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'token',tok);
end $$;
grant execute on function public.bk_admin_switch_to_user(text) to anon, authenticated;

-- posting a listing goes through a function: the poster is taken from the token, never from the row,
-- and status/ref/counters can no longer be set by the client. The insert triggers (ref, autopublish,
-- price history) still fire.
create or replace function public.bk_post_listing(p_token text, p_row jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; l listings;
begin
  uid := bk_member_uid(p_token);
  if uid is null then raise exception 'unauthorised'; end if;
  l := jsonb_populate_record(null::listings,
         p_row - 'id' - 'ref' - 'status' - 'user_id' - 'views' - 'saves' - 'is_featured'
               - 'featured_from' - 'featured_until' - 'created_at' - 'updated_at' - 'published_at'
               - 'expires_at' - 'closed_at' - 'closed_reason' - 'orig_price');
  l.id := nextval('listings_id_seq');
  l.user_id := uid;
  l.status := 'pending';
  l.views := 0; l.saves := 0; l.is_featured := false;
  l.created_at := now();
  l.updated_at := now();
  l.expires_at := now() + interval '60 days';
  insert into listings select (l).* returning * into l;
  return row_to_json(l);
end $$;
grant execute on function public.bk_post_listing(text, jsonb) to anon, authenticated;

-- the browser no longer inserts listings directly
revoke insert on public.listings from anon, authenticated;
