-- Engagement ledger: one record with a client-facing code every time a listing is featured,
-- an ad square goes live, or a banner item is put up. Codes look like BK-F-2609-0007
-- (F featured / A ad square / B banner, then year-month, then a running number).
create table if not exists public.engagements (
  id bigserial primary key,
  code text not null unique,
  kind text not null check (kind in ('featured','ad','banner')),
  ref_id bigint,
  ref_text text,
  title text,
  client_name text,
  phone text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active','ended','cancelled')),
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);
create index if not exists engagements_kind_created on public.engagements(kind, created_at desc);
create index if not exists engagements_ref on public.engagements(kind, ref_id);
create sequence if not exists public.engagement_code_seq;
alter table public.engagements enable row level security;

create or replace function public.bk_engagement_code(p_kind text) returns text
language plpgsql as $$
declare n bigint;
begin
  n := nextval('public.engagement_code_seq');
  return 'BK-'||case p_kind when 'featured' then 'F' when 'ad' then 'A' else 'B' end||'-'||to_char(now(),'YYMM')||'-'||lpad(n::text,4,'0');
end $$;

create or replace function public.bk_engage(p_kind text, p_ref_id bigint, p_ref_text text, p_title text, p_client text, p_phone text,
  p_starts timestamptz, p_ends timestamptz, p_notes text, p_by uuid)
returns public.engagements language plpgsql security definer set search_path = public, extensions as $$
declare r public.engagements;
begin
  -- a new engagement of the same object closes the previous active one
  update public.engagements set status='ended', ended_at=now()
   where kind=p_kind and ref_id=p_ref_id and status='active' and (p_kind<>'banner' or ref_text=p_ref_text);
  insert into public.engagements(code,kind,ref_id,ref_text,title,client_name,phone,starts_at,ends_at,notes,created_by)
    values (public.bk_engagement_code(p_kind),p_kind,p_ref_id,p_ref_text,p_title,p_client,p_phone,coalesce(p_starts,now()),p_ends,p_notes,p_by)
    returning * into r;
  return r;
end $$;

create or replace function public.bk_engage_end(p_kind text, p_ref_id bigint, p_ref_text text, p_status text) returns void
language sql security definer set search_path = public, extensions as $$
  update public.engagements set status=coalesce(p_status,'ended'), ended_at=now()
   where kind=p_kind and ref_id=p_ref_id and status='active' and (p_kind<>'banner' or p_ref_text is null or ref_text=p_ref_text);
$$;
revoke execute on function public.bk_engagement_code(text) from public, anon, authenticated;
revoke execute on function public.bk_engage(text,bigint,text,text,text,text,timestamptz,timestamptz,text,uuid) from public, anon, authenticated;
revoke execute on function public.bk_engage_end(text,bigint,text,text) from public, anon, authenticated;

-- admin RPCs
create or replace function public.bk_admin_engage(p_token text, p_kind text, p_ref_id bigint, p_ref_text text, p_title text,
  p_client text default null, p_phone text default null, p_starts timestamptz default null, p_ends timestamptz default null, p_notes text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; r public.engagements;
begin
  uid := bk_admin_uid(p_token);
  r := public.bk_engage(p_kind,p_ref_id,p_ref_text,p_title,p_client,p_phone,p_starts,p_ends,p_notes,uid);
  return row_to_json(r);
end $$;

create or replace function public.bk_admin_engage_end(p_token text, p_kind text, p_ref_id bigint, p_ref_text text default null, p_status text default 'ended')
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_engage_end(p_kind,p_ref_id,p_ref_text,p_status);
  return json_build_object('ok',true);
end $$;

create or replace function public.bk_admin_engagement_update(p_token text, p_id bigint, p_client text default null, p_phone text default null,
  p_notes text default null, p_status text default null, p_ends timestamptz default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update public.engagements set client_name=coalesce(p_client,client_name), phone=coalesce(p_phone,phone), notes=coalesce(p_notes,notes),
    ends_at=coalesce(p_ends,ends_at), status=coalesce(p_status,status),
    ended_at=case when p_status in ('ended','cancelled') then now() else ended_at end
   where id=p_id;
  return json_build_object('ok',true);
end $$;

create or replace function public.bk_admin_engagements(p_token text, p_days integer default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; since timestamptz;
begin
  uid := bk_admin_uid(p_token);
  since := case when p_days is null then null else now() - (p_days||' days')::interval end;
  return coalesce((select json_agg(row_to_json(x) order by x.created_at desc) from (
    select e.*,
      (e.status='active' and (e.starts_at is null or e.starts_at<=now()) and (e.ends_at is null or e.ends_at>=now())) as live,
      (e.status='active' and e.starts_at>now()) as scheduled,
      case e.kind
        when 'featured' then (select json_build_object('ref',l.ref,'status',l.status,'is_featured',l.is_featured,'views',l.views,'saves',l.saves,'price',l.price_usd,
              'poster',trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),'phone',u.phone,'gov',g.name_ar,'area',ar.name_ar,'exists',true)
              from listings l left join users u on u.id=l.user_id left join governorates g on g.id=l.governorate_id left join areas ar on ar.id=l.area_id where l.id=e.ref_id)
        when 'ad' then (select json_build_object('label',a.label,'sponsor',a.sponsor_name,'enabled',a.enabled,'image',a.image_url,'link',a.link_url,'linked',a.linked_listing_id,'position',a.position,
              'views',(select count(*) from ad_events v where v.slot_id=a.id and v.kind='view' and v.created_at>=coalesce(e.starts_at,e.created_at) and v.created_at<=coalesce(e.ended_at,e.ends_at,now())),
              'clicks',(select count(*) from ad_events v where v.slot_id=a.id and v.kind='click' and v.created_at>=coalesce(e.starts_at,e.created_at) and v.created_at<=coalesce(e.ended_at,e.ends_at,now())),
              'exists',true) from ad_slots a where a.id=e.ref_id)
        else null end as obj
    from public.engagements e
    where since is null or e.created_at>=since or e.status='active'
  ) x), '[]'::json);
end $$;

-- featuring writes the ledger
create or replace function public.bk_admin_feature_listing(p_token text, p_listing bigint, p_from timestamptz, p_days integer)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; r public.engagements; v_ref text; v_client text; v_phone text;
begin
  uid := bk_admin_uid(p_token);
  if p_days is null or p_days < 1 then raise exception 'invalid duration'; end if;
  update listings set featured_from = p_from, featured_until = p_from + (p_days || ' days')::interval where id = p_listing;
  perform bk_recompute_featured(p_listing);
  select l.ref, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')), coalesce(l.contact_phone,u.phone)
    into v_ref, v_client, v_phone from listings l left join users u on u.id=l.user_id where l.id=p_listing;
  r := public.bk_engage('featured', p_listing, v_ref, v_ref, v_client, v_phone, p_from, p_from + (p_days||' days')::interval, null, uid);
  return json_build_object('ok', true, 'code', r.code);
end $$;

create or replace function public.bk_admin_unfeature_listing(p_token text, p_listing bigint)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  update listings set featured_from = null, featured_until = null, is_featured = false where id = p_listing;
  perform public.bk_engage_end('featured', p_listing, null, 'cancelled');
  return json_build_object('ok', true);
end $$;

-- ad squares write the ledger
create or replace function public.bk_admin_save_ad(p_token text, p_id bigint, p_position integer, p_image_url text, p_link_url text, p_label text, p_enabled boolean,
  p_media_type text, p_linked_listing_id bigint, p_image_urls jsonb, p_video_embed_url text, p_sponsor_name text default null,
  p_starts_at timestamptz default null, p_expires_at timestamptz default null, p_overlay_top text default null, p_overlay_bottom text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; v_id bigint; v_pos int; v_code text; v_active public.engagements; v_title text; v_lref text;
begin
  uid := bk_admin_uid(p_token);
  if p_id is null then
    select coalesce(max(position),0)+1 into v_pos from ad_slots;
    insert into ad_slots (position, image_url, link_url, label, enabled, media_type, linked_listing_id, image_urls, video_embed_url, sponsor_name, starts_at, expires_at, overlay_top, overlay_bottom)
      values (v_pos, p_image_url, p_link_url, p_label, coalesce(p_enabled,true), coalesce(p_media_type,'image'), p_linked_listing_id,
        coalesce(p_image_urls,'[]'::jsonb), p_video_embed_url, p_sponsor_name, p_starts_at, p_expires_at, p_overlay_top, p_overlay_bottom)
      returning id into v_id;
  else
    update ad_slots set image_url=p_image_url, link_url=p_link_url, label=p_label, enabled=coalesce(p_enabled,true), media_type=coalesce(p_media_type,'image'),
      linked_listing_id=p_linked_listing_id, image_urls=coalesce(p_image_urls,'[]'::jsonb), video_embed_url=p_video_embed_url, sponsor_name=p_sponsor_name,
      starts_at=p_starts_at, expires_at=p_expires_at, overlay_top=p_overlay_top, overlay_bottom=p_overlay_bottom where id=p_id;
    v_id := p_id;
  end if;
  select ref into v_lref from listings where id=p_linked_listing_id;
  v_title := coalesce(nullif(p_label,''), nullif(p_sponsor_name,''), v_lref, 'مربع #'||v_id);
  select * into v_active from public.engagements where kind='ad' and ref_id=v_id and status='active' order by created_at desc limit 1;
  if coalesce(p_enabled,true) then
    if v_active.id is null then
      v_active := public.bk_engage('ad', v_id, v_lref, v_title, p_sponsor_name, null, p_starts_at, p_expires_at, null, uid);
    else
      update public.engagements set title=v_title, client_name=coalesce(nullif(p_sponsor_name,''),client_name), starts_at=coalesce(p_starts_at,starts_at), ends_at=p_expires_at, ref_text=coalesce(v_lref,ref_text)
       where id=v_active.id;
    end if;
    v_code := v_active.code;
  else
    perform public.bk_engage_end('ad', v_id, null, 'ended');
  end if;
  return json_build_object('ok', true, 'id', v_id, 'code', v_code);
end $$;

create or replace function public.bk_admin_delete_ad(p_token text, p_id bigint)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_engage_end('ad', p_id, null, 'ended');
  delete from ad_slots where id = p_id;
  return json_build_object('ok', true);
end $$;

-- the ledger starts with what is live today
insert into public.engagements(code,kind,ref_id,ref_text,title,client_name,phone,starts_at,ends_at)
select public.bk_engagement_code('featured'),'featured',l.id,l.ref,l.ref,trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')),coalesce(l.contact_phone,u.phone),l.featured_from,l.featured_until
  from listings l left join users u on u.id=l.user_id
 where l.featured_until is not null and l.featured_until>now()
   and not exists (select 1 from public.engagements e where e.kind='featured' and e.ref_id=l.id and e.status='active');
insert into public.engagements(code,kind,ref_id,ref_text,title,client_name,starts_at,ends_at)
select public.bk_engagement_code('ad'),'ad',a.id,(select ref from listings where id=a.linked_listing_id),
       coalesce(nullif(a.label,''),nullif(a.sponsor_name,''),(select ref from listings where id=a.linked_listing_id),'مربع #'||a.id),a.sponsor_name,coalesce(a.starts_at,a.created_at),a.expires_at
  from ad_slots a
 where a.enabled and (a.expires_at is null or a.expires_at>now())
   and not exists (select 1 from public.engagements e where e.kind='ad' and e.ref_id=a.id and e.status='active');
