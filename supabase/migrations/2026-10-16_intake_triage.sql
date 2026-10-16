-- Bot message triage (owner, 2026-10-16): every text is sorted before it can join a listing.
-- intake_pending holds one text per chat while the bot asks "is this a new listing?" (15 minutes);
-- bk_intake_chat_state tells the bot what the sender has on the table, so a question like «شو لسى» gets a real answer.
create table if not exists intake_pending (
  source text not null, chat_id text not null, text text not null, created_at timestamptz not null default now(),
  primary key (source, chat_id)
);
alter table intake_pending enable row level security;   -- no policies: service role only

create or replace function public.bk_intake_pending(p_source text, p_chat_id text, p_set text default null, p_take boolean default false)
returns text language plpgsql security definer set search_path to 'public' as $f$
declare t text;
begin
  if p_set is not null then
    insert into intake_pending (source, chat_id, text) values (p_source, p_chat_id, left(p_set, 4000))
      on conflict (source, chat_id) do update set text = excluded.text, created_at = now();
    return p_set;
  end if;
  select text into t from intake_pending where source = p_source and chat_id = p_chat_id and created_at > now() - interval '15 minutes';
  if p_take then delete from intake_pending where source = p_source and chat_id = p_chat_id; end if;
  return t;
end $f$;

create or replace function public.bk_intake_chat_state(p_source text, p_chat_id text)
returns json language plpgsql stable security definer set search_path to 'public' as $f$
declare d intake_drafts; last_d intake_drafts; sess boolean; lref text; lst text;
begin
  select * into d from intake_drafts
   where source = p_source and chat_id = p_chat_id
     and ((status in ('collecting','reading') and last_message_at > now() - interval '12 hours')
       or (status in ('ready','needs_info') and updated_at > now() - interval '24 hours')
       or (status = 'review' and updated_at > now() - interval '10 minutes'))
   order by created_at desc limit 1;
  select * into last_d from intake_drafts where source = p_source and chat_id = p_chat_id and status in ('published','review','failed')
   order by updated_at desc limit 1;
  if last_d.listing_id is not null then select ref, status into lref, lst from listings where id = last_d.listing_id; end if;
  sess := exists (select 1 from intake_log l where l.chat_id = p_chat_id and l.event = 'listing_opened' and l.created_at > now() - interval '30 minutes'
                   and not exists (select 1 from intake_log c where c.chat_id = p_chat_id and c.event = 'listing_closed' and c.id > l.id));
  return json_build_object(
    'session', sess,
    'open', case when d.id is null then null else json_build_object('id', d.id, 'status', d.status, 'missing', d.missing,
              'type', d.fields->>'property_type', 'deal', d.fields->>'deal', 'area', coalesce(d.fields->>'area', d.fields->>'governorate'),
              'area_wait', d.fields->>'area_wait', 'photos', jsonb_array_length(coalesce(d.photos,'[]'::jsonb))) end,
    'last', case when last_d.id is null then null else json_build_object('status', last_d.status, 'ref', lref, 'listing_status', lst,
              'listing_id', last_d.listing_id, 'at', last_d.updated_at) end);
end $f$;

revoke all on function public.bk_intake_pending(text, text, text, boolean) from public, anon, authenticated;
revoke all on function public.bk_intake_chat_state(text, text) from public, anon, authenticated;
