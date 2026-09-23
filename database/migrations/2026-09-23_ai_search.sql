-- Balkoun · 2026-09-23 · AI search bar (applied as migration "ai_search")
-- Logs each AI-parsed homepage search (cost, tokens, filters) and folds that cost into the same
-- cost_month/cost_total the admin panel's Message intake page already shows for the listing-reader feature.

create table if not exists public.ai_search_log (
  id bigserial primary key,
  vid text not null,
  country_code text not null default 'SY',
  query_text text,
  fields jsonb,
  tokens_in integer not null default 0,
  tokens_out integer not null default 0,
  cost_usd numeric(10,6) not null default 0,
  created_at timestamptz not null default now()
);
alter table public.ai_search_log enable row level security;
create index if not exists ai_search_log_created_idx on public.ai_search_log (created_at desc);
create index if not exists ai_search_log_vid_idx on public.ai_search_log (vid, created_at desc);

create or replace function public.bk_admin_intake(p_token text, p_country text default null, p_status text default null, p_limit integer default 200)
returns json language plpgsql security definer set search_path to 'public','extensions' as $$
declare uid uuid; sc text; al text[]; cfg jsonb;
begin
  uid := bk_admin_uid(p_token);
  sc := bk_admin_scope(uid, p_country); al := bk_admin_allowed(uid);
  cfg := bk_intake_cfg();
  return json_build_object(
    'cfg', cfg,
    'counts', (select json_build_object(
        'collecting', count(*) filter (where status in ('collecting','reading')),
        'ready', count(*) filter (where status in ('ready','needs_info')),
        'review', count(*) filter (where status = 'review'),
        'published', count(*) filter (where status = 'published'),
        'failed', count(*) filter (where status = 'failed'),
        'today', count(*) filter (where created_at > now() - interval '24 hours'),
        'cost_month', coalesce(sum(cost_usd) filter (where created_at > date_trunc('month', now())), 0)
          + (select coalesce(sum(cost_usd) filter (where created_at > date_trunc('month', now())), 0) from ai_search_log where bk_scope_ok(country_code, sc, al)),
        'cost_total', coalesce(sum(cost_usd), 0)
          + (select coalesce(sum(cost_usd), 0) from ai_search_log where bk_scope_ok(country_code, sc, al)),
        'search_today', (select count(*) from ai_search_log where bk_scope_ok(country_code, sc, al) and created_at > now() - interval '24 hours'),
        'search_total', (select count(*) from ai_search_log where bk_scope_ok(country_code, sc, al)))
      from intake_drafts where bk_scope_ok(country_code, sc, al)),
    'drafts', coalesce((select json_agg(row_to_json(x)) from (
        select d.id, d.source, d.chat_id, d.sender_name, d.agency_id, d.user_id, d.by_admin, d.country_code, d.status,
               d.raw_text, d.fields, d.missing, d.summary, d.photos, d.listing_id, d.error, d.model, d.tokens_in, d.tokens_out, d.cost_usd,
               d.reads, d.created_at, d.updated_at, d.last_message_at, d.processed_at, d.published_at,
               a.name as agency_name, a.intake_trusted, l.ref as listing_ref, l.status as listing_status,
               (select count(*) from intake_messages m where m.draft_id = d.id) as messages
          from intake_drafts d left join agencies a on a.id = d.agency_id left join listings l on l.id = d.listing_id
         where bk_scope_ok(d.country_code, sc, al) and (p_status is null or d.status = p_status)
         order by d.created_at desc limit greatest(1, least(coalesce(p_limit,200), 500))) x), '[]'::json),
    'agencies', coalesce((select json_agg(row_to_json(x)) from (
        select a.id, a.name, a.status, a.country_code, a.intake_enabled, a.intake_trusted, a.intake_phone, a.intake_telegram, a.intake_telegram_name, a.intake_code, a.intake_paired_at, a.whatsapp, a.phone, a.user_id
          from agencies a where a.status = 'approved' and bk_scope_ok(coalesce(a.country_code,'SY'), sc, al) order by a.name) x), '[]'::json),
    'log', coalesce((select json_agg(row_to_json(x)) from (
        select id, draft_id, chat_id, level, event, detail, created_at from intake_log order by created_at desc limit 80) x), '[]'::json));
end $$;
