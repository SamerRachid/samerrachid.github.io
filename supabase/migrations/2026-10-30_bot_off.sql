-- 2026-10-30 · owner's request: members replying to a message from Balkoun on WhatsApp got answers from the listing bot.
-- 1) a per-member switch «البوت لا يرد» (users.bot_off) for people who do not post listings by message — the bot stays
--    silent for them and the owner answers by hand on Balkoun's WhatsApp;
-- 2) after the team sends someone a direct message from the panel, the bot stays silent for that number for a while
--    (extras.intake_quiet_after_dm_hours, default 48; 0 turns it off), so a reply is never read as a listing.

alter table public.users add column if not exists bot_off boolean not null default false;

create or replace function public.bk_admin_set_bot_off(p_token text, p_user uuid, p_off boolean)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid;
begin
  uid := bk_admin_uid(p_token);
  perform public.bk_admin_need(uid, ARRAY['users_edit']::text[], 'bk_admin_set_bot_off', (select coalesce(country,'SY') from users where id=p_user), true, left(coalesce(p_user::text,''),300), (select coalesce(country,'SY') from users where id=p_user));
  perform bk_admin_guard(uid, (select country from users where id = p_user));
  update users set bot_off = coalesce(p_off, false) where id = p_user;
  return json_build_object('ok', true);
end $$;
grant execute on function public.bk_admin_set_bot_off(text,uuid,boolean) to anon, authenticated;

-- asked by the bot (service key) for every WhatsApp message: stay silent for this number?
create or replace function public.bk_intake_quiet(p_chat_id text)
returns json language plpgsql stable security definer set search_path to 'public', 'extensions' as $$
declare digits text; hrs int; u users;
begin
  digits := bk_intake_norm_phone(p_chat_id);
  if digits is null then return json_build_object('quiet', false); end if;
  select * into u from users where bk_intake_norm_phone(phone) = digits and coalesce(bot_off,false) order by created_at desc limit 1;
  if u.id is not null then return json_build_object('quiet', true, 'reason', 'member', 'user_id', u.id); end if;
  select coalesce(nullif(extras->>'intake_quiet_after_dm_hours','')::int, 48) into hrs from site_content where id = 1;
  if coalesce(hrs, 48) > 0 and exists (
       select 1 from campaign_sends s join campaigns cp on cp.id = s.campaign_id join contacts c on c.id = s.contact_id
        where s.trigger_type = 'manual' and cp.kind = 'manual' and s.channel = 'whatsapp' and s.status = 'sent'
          and s.sent_at > now() - make_interval(hours => coalesce(hrs, 48))
          and bk_intake_norm_phone(c.phone) = digits) then
    return json_build_object('quiet', true, 'reason', 'direct_message');
  end if;
  return json_build_object('quiet', false);
end $$;
revoke all on function public.bk_intake_quiet(text) from public, anon, authenticated;

-- the panel's member list carries the switch
do $do$
declare d text; o text;
begin
  d := pg_get_functiondef('public.bk_admin_data_core(text,text)'::regprocedure);
  o := $q$u.skip_review, u.avatar_url$q$;
  if position(o in d) = 0 then raise exception 'bk_admin_data_core: users column list not found'; end if;
  execute replace(d, o, $q$u.skip_review, coalesce(u.bot_off,false) as bot_off, u.avatar_url$q$);
end $do$;
