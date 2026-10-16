-- The admin sends a request's matches by hand (owner, 2026-10-16), from the panel:
--   p_who = 'seeker' : ONE message to the requester with every listing that fits now (up to 15 links, then the request page)
--   p_who = 'owners' : ONE message to each owner of a fitting listing, naming their listings and linking the request
--   p_who = 'preview': nothing is sent; returns how many listings fit and how many owners / reachable people that means
-- Every listing that fits is recorded in wanted_matches, so the automatic messages never repeat these pairs later.
create or replace function public.bk_admin_wanted_send(p_token text, p_id bigint, p_who text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare uid uuid; w wanted; ids bigint[]; n int; lines text := ''; wtitle text; m record; o record; sent int := 0;
        reach_seeker boolean; reach_owners int; owners int;
begin
  uid := bk_admin_uid(p_token);
  select * into w from wanted where id = p_id;
  if w.id is null then raise exception 'not found'; end if;
  perform bk_admin_guard(uid, w.country_code);
  if w.status <> 'open' then raise exception 'not open'; end if;
  if p_who not in ('seeker','owners','preview') then raise exception 'bad target'; end if;

  select coalesce(array_agg(l.id order by l.created_at desc), '{}') into ids
    from listings l where l.status = 'live' and l.deal = w.deal and bk_wanted_fits(w, l);
  n := coalesce(array_length(ids, 1), 0);
  select count(distinct l.user_id) into owners from listings l where l.id = any(ids);
  select count(distinct l.user_id) into reach_owners from listings l join contacts c on c.user_id = l.user_id
   where l.id = any(ids) and (c.tg_chat_id is not null or coalesce(c.phone,'') <> '');
  reach_seeker := exists (select 1 from contacts c where c.user_id = w.user_id and (c.tg_chat_id is not null or coalesce(c.phone,'') <> ''));
  if p_who = 'preview' or n = 0 then
    return json_build_object('matches', n, 'owners', owners, 'owners_reachable', reach_owners, 'seeker_reachable', reach_seeker, 'sent', 0);
  end if;

  insert into wanted_matches (wanted_id, listing_id) select w.id, x from unnest(ids) x on conflict do nothing;
  wtitle := coalesce(w.title, 'مطلوب '||case w.deal when 'rent' then 'للإيجار' else 'للشراء' end||' في '||coalesce(w.gov_name,''));

  if p_who = 'seeker' then
    for m in select l.id, l.ref from listings l where l.id = any(ids) order by l.created_at desc limit 15 loop
      lines := lines || E'\n' || '• ' || coalesce(m.ref,'') || ' https://balkoun.com/listing/' || m.id;
    end loop;
    insert into notifications (user_id, type, title, body, link)
      values (w.user_id, 'wanted_listing', n||' إعلان يطابق طلبك', coalesce(w.ref,'')||' · '||wtitle, '/wanted/'||w.id);
    perform bk_wanted_msg(w.user_id, 'direct: wanted match (seeker) w'||w.id||'/admin',
      '🏠 '||n||' إعلان يطابق طلبك'||coalesce(' '||w.ref,'')||' («'||wtitle||'»):'||lines||
        (case when n > 15 then E'\n\n'||'وكل الإعلانات المطابقة هنا: https://balkoun.com/wanted/'||w.id else '' end),
      '🏠 '||n||' listings match your request'||coalesce(' '||w.ref,'')||':'||lines||
        (case when n > 15 then E'\n\n'||'All of them: https://balkoun.com/wanted/'||w.id else '' end),
      coalesce(w.country_code,'SY'), null);
    sent := case when reach_seeker then 1 else 0 end;
  else
    for o in select l.user_id, string_agg(coalesce(l.ref,'#'||l.id), '، ' order by l.id) refs, count(*) c, min(l.id) first_id, max(l.country_code) cc
               from listings l where l.id = any(ids) group by l.user_id loop
      insert into notifications (user_id, type, title, body, link)
        values (o.user_id, 'wanted_match', 'طلب يطابق '||(case when o.c > 1 then 'إعلاناتك' else 'إعلانك' end), wtitle||coalesce(' · '||w.ref,''), '/wanted/'||w.id);
      perform bk_wanted_msg(o.user_id, 'direct: wanted match (owner) w'||w.id||'/admin',
        '📋 يوجد طلب شراء/إيجار يطابق '||(case when o.c > 1 then 'إعلاناتك ' else 'إعلانك ' end)||o.refs||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'شاهد الطلب وتواصل مع صاحبه: https://balkoun.com/wanted/'||w.id,
        '📋 A buy/rent request matches your listing(s) '||o.refs||E'\n'||wtitle||coalesce(' · '||w.ref,'')||E'\n\n'||'See it and contact the requester: https://balkoun.com/wanted/'||w.id,
        coalesce(o.cc,'SY'), o.first_id);
    end loop;
    sent := reach_owners;
  end if;
  return json_build_object('matches', n, 'owners', owners, 'owners_reachable', reach_owners, 'seeker_reachable', reach_seeker, 'sent', sent);
end $f$;
revoke all on function public.bk_admin_wanted_send(text, bigint, text) from public;
grant execute on function public.bk_admin_wanted_send(text, bigint, text) to anon, authenticated;
