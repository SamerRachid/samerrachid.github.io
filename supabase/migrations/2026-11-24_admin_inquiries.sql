-- 2026-11-24 panel «طلبات المعاينة»: every visit request / message a visitor sent about a listing, the replies that
-- followed in «رسائلي», and how each one reached the other side (Telegram / WhatsApp, sent / skipped / failed).
-- Read only. A relay row in campaign_sends is written in the same transaction as the inquiry / reply, so its
-- created_at equals the message's — that is how a delivery is matched to its message.
create or replace function public.bk_admin_inquiries(p_token text, p_country text default null, p_limit integer default 300)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, array['notify','reports','feedback']::text[], 'bk_admin_inquiries', null, false, null, nullif(upper(p_country),''));
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return (with q as (
      select i.*, l.ref as listing_ref, l.status as listing_status, l.property_type, l.deal, g.name_ar as gov, a.name_ar as area,
             coalesce(l.country_code, tu.country, 'SY') as cc,
             nullif(trim(coalesce(fu.name,'')||' '||coalesce(fu.family_name,'')),'') as from_member_name, fu.phone as from_member_phone, fu.member_no as from_member_no,
             nullif(trim(coalesce(tu.name,'')||' '||coalesce(tu.family_name,'')),'') as to_name, tu.phone as to_phone, tu.member_no as to_member_no,
             (select ag.name from agencies ag where ag.user_id = i.to_user and ag.status = 'approved' limit 1) as to_agency
        from inquiries i
        left join listings l on l.id = i.property_id
        left join governorates g on g.id = l.governorate_id
        left join areas a on a.id = l.area_id
        left join users fu on fu.id = i.from_user
        left join users tu on tu.id = i.to_user
       where bk_scope_ok(coalesce(l.country_code, tu.country, 'SY'), sc, al)
    )
    select json_build_object(
      'total', (select count(*) from q),
      'rows', coalesce((select json_agg(json_build_object(
          'id', q.id, 'kind', q.kind, 'status', q.status, 'created_at', q.created_at, 'country_code', q.cc,
          'listing_id', q.property_id, 'listing_ref', q.listing_ref, 'listing_status', q.listing_status,
          'property_type', q.property_type, 'deal', q.deal, 'gov', q.gov, 'area', q.area,
          'from_user', q.from_user, 'from_name', coalesce(nullif(q.name,''), q.from_member_name), 'from_phone', coalesce(q.phone, q.from_member_phone), 'from_member_no', q.from_member_no,
          'to_user', q.to_user, 'to_name', q.to_name, 'to_phone', q.to_phone, 'to_member_no', q.to_member_no, 'to_agency', q.to_agency,
          'message', q.message,
          'sent', coalesce((select json_agg(json_build_object('channel', cs.channel, 'status', cs.status, 'error', cs.error) order by cs.id)
                              from campaign_sends cs join contacts c on c.id = cs.contact_id
                             where cs.created_at = q.created_at and c.user_id = q.to_user), '[]'::json),
          'thread', coalesce((select json_agg(json_build_object('sender', m.sender, 'body', m.body, 'created_at', m.created_at,
               'sent', coalesce((select json_agg(json_build_object('channel', cs.channel, 'status', cs.status, 'error', cs.error) order by cs.id)
                                   from campaign_sends cs join contacts c on c.id = cs.contact_id
                                  where cs.created_at = m.created_at and c.user_id = case when m.sender = 'owner' then q.from_user else q.to_user end), '[]'::json))
               order by m.created_at, m.id) from message_followups m where m.kind = 'inquiry' and m.ref_id = q.id), '[]'::json),
          'last_at', greatest(q.created_at, (select max(m.created_at) from message_followups m where m.kind = 'inquiry' and m.ref_id = q.id))
        ) order by greatest(q.created_at, (select max(m.created_at) from message_followups m where m.kind = 'inquiry' and m.ref_id = q.id)) desc)
        from (select * from q order by created_at desc limit greatest(1, least(coalesce(p_limit,300), 1000))) q), '[]'::json)));
end $function$;
revoke all on function public.bk_admin_inquiries(text,text,integer) from public;
grant execute on function public.bk_admin_inquiries(text,text,integer) to anon, authenticated, service_role;
