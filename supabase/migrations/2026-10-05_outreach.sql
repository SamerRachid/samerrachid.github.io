-- 2026-10-05 · agencies outreach tracker (admin › People › «المكاتب المستهدفة»).
-- One row per office the owner is courting; a stage pipeline instead of a WhatsApp scroll-back. When the office signs up,
-- the row is linked to its user (by phone match or by hand) so its live listings show next to the stage.

create table if not exists public.outreach (
  id              bigserial primary key,
  country_code    text not null default 'SY',
  name            text not null,
  phone           text,
  city            text,
  area            text,
  source          text,                                   -- where we found them (group / page / referral)
  stage           text not null default 'new' check (stage in ('new','messaged','replied','agreed','account','first_listing','active','declined')),
  notes           text,
  last_contact_at timestamptz,
  next_at         timestamptz,                            -- follow-up reminder
  user_id         uuid references public.users(id) on delete set null,
  created_by      uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists idx_outreach_stage on public.outreach(stage);
create index if not exists idx_outreach_phone on public.outreach(phone);
alter table public.outreach enable row level security;
revoke all on public.outreach from anon, authenticated;

create or replace function public.bk_admin_outreach_list(p_token text, p_country text default null) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; sc text; al text[];
begin
  uid := bk_admin_uid(p_token); sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(row_to_json(x) order by
      case x.stage when 'active' then 7 when 'first_listing' then 6 when 'account' then 5 when 'agreed' then 4 when 'replied' then 3 when 'messaged' then 2 when 'new' then 1 else 8 end,
      x.next_at nulls last, x.updated_at desc) from (
    select o.*,
           u.name as user_name, u.family_name as user_family, u.member_no,
           (select count(*) from listings l where l.user_id = o.user_id and l.status in ('live','pending')) as listings,
           -- a member whose phone matches, when the row is not linked yet (digits only, last 9 compared)
           (select m.id from users m where o.user_id is null and o.phone is not null
              and right(regexp_replace(m.phone,'\D','','g'), 9) = right(regexp_replace(o.phone,'\D','','g'), 9) limit 1) as match_user,
           (select trim(coalesce(m.name,'')||' '||coalesce(m.family_name,'')) from users m where o.user_id is null and o.phone is not null
              and right(regexp_replace(m.phone,'\D','','g'), 9) = right(regexp_replace(o.phone,'\D','','g'), 9) limit 1) as match_name
      from outreach o left join users u on u.id = o.user_id
     where bk_scope_ok(o.country_code, sc, al)) x), '[]'::json);
end $$;

create or replace function public.bk_admin_outreach_save(p_token text, p_id bigint, p_data jsonb) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; rid bigint; st text;
begin
  uid := bk_admin_uid(p_token);
  st := coalesce(nullif(p_data->>'stage',''), 'new');
  if st not in ('new','messaged','replied','agreed','account','first_listing','active','declined') then st := 'new'; end if;
  if p_id is null then
    if coalesce(trim(p_data->>'name'),'') = '' then return json_build_object('error','name'); end if;
    insert into outreach (country_code, name, phone, city, area, source, stage, notes, last_contact_at, next_at, user_id, created_by)
    values (coalesce(nullif(upper(p_data->>'country_code'),''),'SY'), trim(p_data->>'name'), nullif(trim(p_data->>'phone'),''), nullif(trim(p_data->>'city'),''),
            nullif(trim(p_data->>'area'),''), nullif(trim(p_data->>'source'),''), st, nullif(p_data->>'notes',''),
            nullif(p_data->>'last_contact_at','')::timestamptz, nullif(p_data->>'next_at','')::timestamptz, nullif(p_data->>'user_id','')::uuid, uid)
    returning id into rid;
  else
    update outreach set
      name = coalesce(nullif(trim(p_data->>'name'),''), name),
      phone = case when p_data ? 'phone' then nullif(trim(p_data->>'phone'),'') else phone end,
      city = case when p_data ? 'city' then nullif(trim(p_data->>'city'),'') else city end,
      area = case when p_data ? 'area' then nullif(trim(p_data->>'area'),'') else area end,
      source = case when p_data ? 'source' then nullif(trim(p_data->>'source'),'') else source end,
      stage = case when p_data ? 'stage' then st else stage end,
      notes = case when p_data ? 'notes' then nullif(p_data->>'notes','') else notes end,
      last_contact_at = case when p_data ? 'last_contact_at' then nullif(p_data->>'last_contact_at','')::timestamptz else last_contact_at end,
      next_at = case when p_data ? 'next_at' then nullif(p_data->>'next_at','')::timestamptz else next_at end,
      user_id = case when p_data ? 'user_id' then nullif(p_data->>'user_id','')::uuid else user_id end,
      updated_at = now()
    where id = p_id returning id into rid;
  end if;
  return json_build_object('id', rid);
end $$;

create or replace function public.bk_admin_outreach_delete(p_token text, p_id bigint) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  delete from outreach where id = p_id;
  return json_build_object('ok', true);
end $$;

revoke all on function public.bk_admin_outreach_list(text, text) from public;
revoke all on function public.bk_admin_outreach_save(text, bigint, jsonb) from public;
revoke all on function public.bk_admin_outreach_delete(text, bigint) from public;
grant execute on function public.bk_admin_outreach_list(text, text) to anon, authenticated;
grant execute on function public.bk_admin_outreach_save(text, bigint, jsonb) to anon, authenticated;
grant execute on function public.bk_admin_outreach_delete(text, bigint) to anon, authenticated;

select count(*) as outreach_rows from outreach;
