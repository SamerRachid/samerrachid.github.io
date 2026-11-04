-- Block a member (Google Play / App Store user-generated-content rules, owner 2026-11-03).
-- A member can block another member: the blocked member's listings are hidden from the one who blocked them
-- (the site filters them out), and the list of blocked members is on the account page, where they can be unblocked.
-- Reports about a member go through bk_feedback (kind 'complaint'), so they land in the panel's feedback inbox
-- with the usual admin notification; no change is needed there.

create table if not exists public.user_blocks (
  blocker    uuid not null references public.users(id) on delete cascade,
  blocked    uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
-- reached only through the functions below
alter table public.user_blocks enable row level security;
revoke all on public.user_blocks from anon, authenticated;

-- block (p_block true) or unblock (false); returns the ids the member has blocked now
create or replace function public.bk_block_user(p_token text, p_user uuid, p_block boolean default true)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid;
begin
  uid := bk_member_uid(p_token);
  if uid is null then return json_build_object('error', 'unauthorised'); end if;
  if p_user is null or p_user = uid then return json_build_object('error', 'self'); end if;
  if not exists (select 1 from users where id = p_user) then return json_build_object('error', 'nouser'); end if;
  if p_block then
    if (select count(*) from user_blocks where blocker = uid) >= 500 then return json_build_object('error', 'limit'); end if;
    insert into user_blocks (blocker, blocked) values (uid, p_user) on conflict do nothing;
  else
    delete from user_blocks where blocker = uid and blocked = p_user;
  end if;
  return json_build_object('ok', true,
    'blocked', coalesce((select json_agg(blocked order by created_at desc) from user_blocks where blocker = uid), '[]'::json));
end $$;

-- the members this member has blocked, newest first (for the account page)
create or replace function public.bk_my_blocks(p_token text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid;
begin
  uid := bk_member_uid(p_token);
  if uid is null then return json_build_object('error', 'unauthorised'); end if;
  return json_build_object('ok', true, 'list', coalesce((
    select json_agg(json_build_object('id', u.id, 'name', trim(coalesce(u.name, '') || ' ' || coalesce(u.family_name, '')),
                                      'avatar_url', u.avatar_url, 'at', b.created_at) order by b.created_at desc)
      from user_blocks b join users u on u.id = b.blocked where b.blocker = uid), '[]'::json));
end $$;
