-- «المشاهدات» on a listing were never views (owner, 2026-10-26): bk_contact added one per WhatsApp / call / show-number
-- click, and opening the page added nothing. Now:
--   listings.views    = the different visitors who opened the listing page (a visitor counts once per listing)
--   listings.contacts = the contact clicks (WhatsApp, call, show number, visit request), as before kept in contact_events

alter table listings add column if not exists contacts int not null default 0;

-- a counter moving is not an edit: «آخر تحديث» stays when only views / saves / contacts change
create or replace function bk_touch_listing() returns trigger language plpgsql as $$
begin
  if (to_jsonb(new) - 'views' - 'saves' - 'contacts' - 'updated_at') = (to_jsonb(old) - 'views' - 'saves' - 'contacts' - 'updated_at')
    then new.updated_at := old.updated_at;
    else new.updated_at := now(); end if;
  return new;
end $$;
drop trigger if exists t_touch on listings;
create trigger t_touch before update on listings for each row execute function bk_touch_listing();

create index if not exists page_views_listing_visitor_idx on page_views (listing_id, visitor_id) where listing_id is not null;

-- a contact click counts as a contact, no longer as a view
create or replace function public.bk_contact(p_listing bigint, p_user uuid, p_kind text, p_token text default null)
 returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
begin
  perform bk_require_member(p_token, p_user);
  insert into contact_events (listing_id, user_id, kind) values (p_listing, p_user, p_kind);
  update listings set contacts = contacts + 1 where id = p_listing;
  return json_build_object('ok', true);
end $function$;

-- opening a listing page: one view per visitor per listing
create or replace function public.bk_log_view2(p_path text, p_view text, p_user uuid, p_country text, p_token text DEFAULT NULL::text, p_visitor text DEFAULT NULL::text, p_device text DEFAULT NULL::text, p_referrer text DEFAULT NULL::text, p_site_country text DEFAULT NULL::text)
 returns void language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare lid bigint; seen boolean := false;
begin
  perform bk_require_member(p_token, p_user);
  lid := nullif(substring(coalesce(p_path,'') from '/listing/(\d+)'), '')::bigint;
  if lid is not null then
    seen := (p_visitor is not null and exists (select 1 from page_views where listing_id = lid and visitor_id = left(p_visitor,40)))
         or (p_user is not null and exists (select 1 from page_views where listing_id = lid and user_id = p_user));
  end if;
  insert into page_views (path, view, user_id, country, visitor_id, device, referrer, listing_id, site_country)
  values (left(p_path,300), left(p_view,40), p_user, left(p_country,8), left(p_visitor,40), left(p_device,10), left(p_referrer,200), lid, coalesce(nullif(upper(left(p_site_country,2)),''),'SY'));
  if lid is not null and not seen then update listings set views = views + 1 where id = lid; end if;
end $function$;

-- the counts so far, from what was recorded since 2026-09-06 (crawler visits were moved out to page_views_bots)
update listings l set
  views = coalesce((select count(distinct coalesce(v.visitor_id, v.user_id::text, v.id::text)) from page_views v where v.listing_id = l.id), 0),
  contacts = coalesce((select count(*) from contact_events c where c.listing_id = l.id), 0);
