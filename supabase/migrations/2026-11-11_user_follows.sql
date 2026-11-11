-- 2026-11-11 · follow an agency or a broker (owner, after dalelook.sy's «متابعة المعلن»)
-- A member follows another member; when the followed one gets a listing live, each follower finds a bell
-- notification in their account (type follow_listing, the site prints it in the viewer's language).
-- Nothing is sent outside the site: no WhatsApp, Telegram or e-mail.
-- Undo: 2026-11-11_user_follows_undo.sql

create table if not exists public.user_follows (
  follower   uuid not null references public.users(id) on delete cascade,
  followed   uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower, followed),
  check (follower <> followed)
);
create index if not exists user_follows_followed on public.user_follows (followed);
alter table public.user_follows enable row level security;   -- no policy: reached only through the functions below
revoke all on public.user_follows from anon, authenticated;

-- follow / unfollow; answers with everyone the member follows (newest first)
create or replace function public.bk_follow_user(p_token text, p_user uuid, p_on boolean default true)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare uid uuid;
begin
  uid := bk_member_uid(p_token);
  if uid is null then return json_build_object('error', 'unauthorised'); end if;
  if p_user is null or p_user = uid then return json_build_object('error', 'self'); end if;
  if p_on then
    if not exists (select 1 from users where id = p_user and not blocked) then return json_build_object('error', 'nouser'); end if;
    if (select count(*) from user_follows where follower = uid) >= 300 then return json_build_object('error', 'limit'); end if;
    insert into user_follows (follower, followed) values (uid, p_user) on conflict do nothing;
  else
    delete from user_follows where follower = uid and followed = p_user;
  end if;
  return json_build_object('ok', true,
    'following', coalesce((select json_agg(followed order by created_at desc) from user_follows where follower = uid), '[]'::json));
end $function$;

-- the account page's list: the agency's name and page when the followed member runs an approved agency
create or replace function public.bk_my_follows(p_token text)
 returns json language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare uid uuid;
begin
  uid := bk_member_uid(p_token);
  if uid is null then return json_build_object('error', 'unauthorised'); end if;
  return json_build_object('ok', true, 'list', coalesce((
    select json_agg(json_build_object('id', u.id,
             'name', coalesce(nullif(trim(a.name), ''), trim(coalesce(u.name, '') || ' ' || coalesce(u.family_name, ''))),
             'avatar_url', u.avatar_url, 'agency_id', a.id, 'at', f.created_at) order by f.created_at desc)
      from user_follows f join users u on u.id = f.followed
      left join lateral (select ag.id, ag.name from agencies ag where ag.user_id = u.id and ag.status = 'approved' order by ag.id limit 1) a on true
     where f.follower = uid), '[]'::json));
end $function$;

-- a listing goes live: one bell per follower. Only a recent listing counts (a year-old one switched back on is not news),
-- once per listing, not for a follower who has since blocked the advertiser. Any failure here is swallowed:
-- a bell must never stop a listing from going live.
create or replace function public.bk_trg_listing_live_follows()
 returns trigger language plpgsql security definer set search_path to 'public'
as $function$
declare nm text;
begin
  if new.status = 'live' and new.user_id is not null and (tg_op = 'INSERT' or old.status is distinct from 'live')
     and new.created_at > now() - interval '14 days' then
    begin
      if exists (select 1 from user_follows where followed = new.user_id) then
        select coalesce((select nullif(trim(ag.name), '') from agencies ag where ag.user_id = u.id and ag.status = 'approved' order by ag.id limit 1),
                        nullif(trim(coalesce(u.name, '') || ' ' || coalesce(u.family_name, '')), ''))
          into nm from users u where u.id = new.user_id;
        insert into notifications (user_id, type, title, body, link)
        select f.follower, 'follow_listing', 'follow_listing', coalesce(nm, '') || ' · ' || coalesce(new.ref, '#' || new.id), '/listing/' || new.id
          from user_follows f join users fu on fu.id = f.follower and not fu.blocked
         where f.followed = new.user_id
           and not exists (select 1 from user_blocks b where b.blocker = f.follower and b.blocked = new.user_id)
           and not exists (select 1 from notifications n where n.user_id = f.follower and n.type = 'follow_listing' and n.link = '/listing/' || new.id);
      end if;
    exception when others then null;
    end;
  end if;
  return new;
end $function$;
revoke all on function public.bk_trg_listing_live_follows() from public, anon, authenticated;

drop trigger if exists trg_listing_live_follows on public.listings;
create trigger trg_listing_live_follows after insert or update of status on public.listings
  for each row execute function public.bk_trg_listing_live_follows();
