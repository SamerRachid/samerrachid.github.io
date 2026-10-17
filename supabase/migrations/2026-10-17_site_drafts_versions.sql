-- Site editor, phase 3 (owner, 2026-10-17): an editor draft kept on the server, «نشر» publishes it, and every
-- publish leaves a snapshot that can be loaded back as a draft («استرجاع»). Nothing in site_content changes shape;
-- publishing still goes through bk_admin_set_content, so its rules (and its permission check) stay the only writer.

create table if not exists public.site_drafts(
  country_code text primary key,
  draft        jsonb not null default '{}'::jsonb,      -- {"site":{column:value…},"extras":{key:value…}} — only the changed fields
  updated_at   timestamptz not null default now(),
  updated_by   uuid
);
create table if not exists public.site_versions(
  id           bigserial primary key,
  country_code text not null,
  created_at   timestamptz not null default now(),
  created_by   uuid,
  kind         text not null default 'publish' check (kind in ('original','publish')),
  label        text,
  snapshot     jsonb not null                             -- the whole site_content row as it was live after this publish
);
create index if not exists site_versions_cc_time on public.site_versions(country_code, created_at desc);
alter table public.site_drafts enable row level security;
alter table public.site_versions enable row level security;
revoke all on public.site_drafts, public.site_versions from anon, authenticated;
revoke all on sequence public.site_versions_id_seq from anon, authenticated;

-- the draft of one country (empty object when there is none)
create or replace function public.bk_admin_draft_get(p_token text, p_country text default 'SY')
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; r record; begin
  uid := bk_admin_uid(p_token); perform bk_admin_guard(uid, coalesce(p_country,'SY'));
  select d.draft, d.updated_at, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as who
    into r from site_drafts d left join users u on u.id=d.updated_by where d.country_code=coalesce(p_country,'SY');
  if not found then return json_build_object('draft','{}'::jsonb); end if;
  return json_build_object('draft',r.draft,'updated_at',r.updated_at,'who',r.who);
end $$;

-- keep (or, when empty, drop) the draft; called a moment after each edit
create or replace function public.bk_admin_draft_put(p_token text, p_country text, p_draft jsonb)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; cc text := coalesce(p_country,'SY'); d jsonb := coalesce(p_draft,'{}'::jsonb); begin
  uid := bk_admin_uid(p_token); perform bk_admin_guard(uid, cc);
  if jsonb_typeof(d)<>'object' then raise exception 'bad draft'; end if;
  if pg_column_size(d) > 400000 then raise exception 'draft too large'; end if;
  d := jsonb_build_object('site',coalesce(d->'site','{}'::jsonb),'extras',coalesce(d->'extras','{}'::jsonb));
  if d->'site' = '{}'::jsonb and d->'extras' = '{}'::jsonb then delete from site_drafts where country_code=cc; return json_build_object('ok',true,'empty',true); end if;
  insert into site_drafts(country_code,draft,updated_at,updated_by) values (cc,d,now(),uid)
    on conflict (country_code) do update set draft=excluded.draft, updated_at=excluded.updated_at, updated_by=excluded.updated_by;
  return json_build_object('ok',true);
end $$;

-- publish: the very first publish also keeps the state from before it; then the patch is written by the usual
-- content function, the live row is snapshotted, the draft is cleared, and only the latest 60 versions are kept
create or replace function public.bk_admin_publish(p_token text, p_country text, p_patch jsonb, p_label text default null)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; cc text := coalesce(p_country,'SY'); vid bigint; snap jsonb; begin
  uid := bk_admin_uid(p_token); perform bk_admin_guard(uid, cc);
  if not exists(select 1 from site_versions where country_code=cc) then
    select to_jsonb(s) into snap from site_content s where s.country_code=cc;
    if snap is not null then insert into site_versions(country_code,created_by,kind,label,snapshot) values (cc,uid,'original',null,snap); end if;
  end if;
  if p_patch is not null and p_patch <> '{}'::jsonb then perform bk_admin_set_content(p_token, p_patch, cc); end if;
  select to_jsonb(s) into snap from site_content s where s.country_code=cc;
  if snap is null then raise exception 'no settings row for country %', cc; end if;
  insert into site_versions(country_code,created_by,kind,label,snapshot) values (cc,uid,'publish',left(nullif(trim(p_label),''),160),snap) returning id into vid;
  delete from site_drafts where country_code=cc;
  delete from site_versions where country_code=cc and kind='publish' and id not in (select id from site_versions where country_code=cc and kind='publish' order by created_at desc, id desc limit 60);
  return json_build_object('ok',true,'version',vid);
end $$;

-- the list (no snapshots), newest first
create or replace function public.bk_admin_versions(p_token text, p_country text default 'SY')
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; cc text := coalesce(p_country,'SY'); begin
  uid := bk_admin_uid(p_token); perform bk_admin_guard(uid, cc);
  return coalesce((select json_agg(x order by x.created_at desc, x.id desc) from (
    select v.id, v.created_at, v.kind, v.label, trim(coalesce(u.name,'')||' '||coalesce(u.family_name,'')) as who
      from site_versions v left join users u on u.id=v.created_by where v.country_code=cc order by v.created_at desc, v.id desc limit 61) x), '[]'::json);
end $$;

-- one version's snapshot, to load back into the editor as a draft
create or replace function public.bk_admin_version_get(p_token text, p_id bigint)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; r record; begin
  uid := bk_admin_uid(p_token);
  select * into r from site_versions where id=p_id; if not found then raise exception 'not found'; end if;
  perform bk_admin_guard(uid, r.country_code);
  return json_build_object('id',r.id,'created_at',r.created_at,'kind',r.kind,'label',r.label,'snapshot',r.snapshot);
end $$;

revoke all on function public.bk_admin_draft_get(text,text), public.bk_admin_draft_put(text,text,jsonb), public.bk_admin_publish(text,text,jsonb,text),
  public.bk_admin_versions(text,text), public.bk_admin_version_get(text,bigint) from public;
grant execute on function public.bk_admin_draft_get(text,text), public.bk_admin_draft_put(text,text,jsonb), public.bk_admin_publish(text,text,jsonb,text),
  public.bk_admin_versions(text,text), public.bk_admin_version_get(text,bigint) to anon, authenticated;
