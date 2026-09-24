-- Balkoun · 2026-09-24 · Email verification channel, part 2: the functions that could NOT be safely
-- rewritten from the on-disk copies in 2026-09-24_verify_email_channel.sql, because their live bodies
-- (pulled just now via pg_get_functiondef, Supabase MCP having been reconnected) carry a `member_no` field
-- that was never captured in any migration file. Every function below is reproduced from its ACTUAL live
-- body, with only the additions noted per-function — nothing else changed.

-- bk_register: trust the ticket's candidate email ONLY when this exact ticket both used the 'email'
-- channel and was actually verified (v_ok, computed from t.status='verified' a few lines up) — a candidate
-- typed on the sign-up form but never confirmed (e.g. the person verified via Telegram/wa_code instead)
-- must never become a verified email. Re-checks the claimed-email race right before the insert: if lost,
-- the email is dropped rather than failing the whole signup (the users_email_uq index is the final backstop).
create or replace function public.bk_register(p_ticket uuid, p_secret text, p_name text, p_family text, p_hash text, p_currency text default 'USD'::text, p_lang text default null::text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare t verify_tickets; u users; v_currency text; tok text; v_lang text; v_ok boolean; v_email text;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.purpose <> 'signup' then raise exception 'badticket'; end if;
  if t.status = 'verified' then v_ok := true;
  elsif t.status = 'pending' and t.channel = 'whatsapp' and t.wa_sent_at is not null and t.expires_at > now() then v_ok := false;
  else return json_build_object('error','notverified'); end if;
  if exists (select 1 from users where phone = t.phone) then return json_build_object('error','exists'); end if;
  if length(coalesce(p_hash,'')) < 32 then raise exception 'bad hash'; end if;
  if coalesce(trim(p_name),'') = '' then raise exception 'name required'; end if;
  v_currency := case when upper(coalesce(p_currency,'')) ~ '^[A-Z]{3}$' then upper(p_currency) else 'USD' end;
  v_lang := case when p_lang in ('ar','en','de','fr') then p_lang else null end;
  v_email := case when v_ok and t.channel = 'email' and t.email is not null and not exists (select 1 from users where lower(email) = t.email)
             then t.email end;
  insert into users (phone, name, family_name, pass_hash, phone_verified, preferred_currency, lang, country, email, email_verified)
    values (t.phone, left(trim(p_name),60), left(trim(coalesce(p_family,'')),60), crypt(p_hash, gen_salt('bf')), v_ok, v_currency, v_lang, t.country_code, v_email, v_email is not null)
    returning * into u;
  update verify_tickets set user_id = u.id, status = case when v_ok then 'used' else 'pending' end, used_at = case when v_ok then now() end where id = t.id;
  insert into notifications (user_id, type, title, body, link, is_read) values (u.id, 'system', 'welcome', null, '/#/post', false);
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'city',u.city,'country',u.country,'preferred_currency',u.preferred_currency,'role',u.role,'phone_verified',u.phone_verified,'member_no',u.member_no,
    'email',u.email,'email_verified',u.email_verified,'token',tok);
end $function$;

create or replace function public.bk_set_password(p_ticket uuid, p_secret text, p_hash text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare t verify_tickets; u users; tok text;
begin
  t := bk_verify_ticket(p_ticket, p_secret);
  if t.purpose <> 'reset' or t.status <> 'verified' then return json_build_object('error','notverified'); end if;
  if t.verified_at < now() - interval '2 hours' then update verify_tickets set status = 'expired' where id = t.id; return json_build_object('error','expired'); end if;
  select * into u from users where phone = t.phone;
  if u.id is null then return json_build_object('error','nouser'); end if;
  if u.blocked then return json_build_object('error','blocked'); end if;
  if length(coalesce(p_hash,'')) < 32 then raise exception 'bad hash'; end if;
  update users set pass_hash = crypt(p_hash, gen_salt('bf')), phone_verified = true where id = u.id;
  update verify_tickets set status = 'used', used_at = now(), user_id = u.id where id = t.id;
  delete from member_sessions where user_id = u.id;
  delete from login_attempts where phone = u.phone;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'phone_verified',true,'member_no',u.member_no,
    'email',u.email,'email_verified',u.email_verified,'token',tok);
end $function$;

create or replace function public.bk_login(p_phone text, p_hash text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare u users; tok text;
begin
  if not bk_login_guard(p_phone) then return json_build_object('error','locked'); end if;
  select * into u from users where phone = p_phone;
  if u.id is null then perform bk_login_fail(p_phone); return json_build_object('error','nouser'); end if;
  if u.pass_hash is null or u.pass_hash <> crypt(p_hash, u.pass_hash) then perform bk_login_fail(p_phone); return json_build_object('error','badpass'); end if;
  if u.blocked then return json_build_object('error','blocked'); end if;
  delete from login_attempts where phone = p_phone;
  update users set last_seen_at = now() where id = u.id;
  tok := bk_issue_member_token(u.id);
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'phone_verified',u.phone_verified,'member_no',u.member_no,
    'email',u.email,'email_verified',u.email_verified,'token',tok);
end $function$;

create or replace function public.bk_me(p_id uuid, p_token text default null::text)
returns json language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare u users; uid uuid;
begin
  uid := bk_member_uid(p_token);
  if uid is null or uid <> p_id then return json_build_object('error','nouser'); end if;
  select * into u from users where id = uid and not blocked;
  if u.id is null then return json_build_object('error','nouser'); end if;
  update member_sessions set expires_at = now() + interval '30 days' where token = p_token;
  update users set last_seen_at = now() where id = u.id;
  return json_build_object('id',u.id,'phone',u.phone,'name',u.name,'family_name',u.family_name,
    'username',u.username,'city',u.city,'country',u.country,'avatar_url',u.avatar_url,'bio',u.bio,
    'role',u.role,'preferred_currency',u.preferred_currency,'phone_verified',u.phone_verified,'member_no',u.member_no,
    'email',u.email,'email_verified',u.email_verified,'token',p_token);
end $function$;

-- bk_admin_countries: adds a `verify` subset per country (only the on/off toggle keys, not readiness —
-- those stay global) so the new per-country checkboxes on the "الدول" page can render real state instead
-- of always defaulting to "on". Every other field/expression below is reproduced byte-for-byte from the
-- live function.
create or replace function public.bk_admin_countries(p_token text)
returns json language plpgsql security definer set search_path to 'public' as $function$
declare uid uuid; al text[];
begin
  uid := bk_admin_uid(p_token); al := bk_admin_allowed(uid);
  return coalesce((select json_agg(json_build_object(
    'code',c.code,'name_ar',c.name_ar,'name_en',c.name_en,'name_de',c.name_de,'name_fr',c.name_fr,'name_tr',c.name_tr,
    'enabled',c.enabled,'is_default',c.is_default,'currencies',c.currencies,'rates',c.rates,'phone_code',c.phone_code,
    'tz',c.tz,'lat',c.lat,'lng',c.lng,'zoom',c.zoom,'sort_order',c.sort_order,'languages',c.languages,'notes',c.notes,'types',c.types,
    'govs',(select count(*) from governorates g where g.country_code=c.code),
    'areas',(select count(*) from areas a join governorates g on g.id=a.governorate_id where g.country_code=c.code),
    'listings',(select count(*) from listings l where l.country_code=c.code and l.status='live'),
    'wanted',(select count(*) from wanted w where w.country_code=c.code and w.status='open'),
    'agencies',(select count(*) from agencies a where a.country_code=c.code),
    'ads',(select count(*) from ad_slots a where a.country_code=c.code and a.enabled),
    'featured',(select count(*) from listings l where l.country_code=c.code and l.status='live' and l.is_featured),
    'bg',(select s.hero_bg_type from site_content s where s.country_code=c.code limit 1),
    'bg_photo',(select s.hero_bg_photo_url from site_content s where s.country_code=c.code limit 1),
    'banners',(select case when s.banner_items is null or s.banner_items='' then 0 else coalesce(jsonb_array_length(s.banner_items::jsonb),0) end from site_content s where s.country_code=c.code limit 1),
    'banner_on',(select s.banner_enabled from site_content s where s.country_code=c.code limit 1),
    'deeds',(select coalesce(json_agg(json_build_object('code',d.code,'ar',d.name_ar,'en',d.name_en,'de',d.name_de,'fr',d.name_fr,'strong',d.is_strong,'enabled',d.enabled) order by d.sort_order),'[]'::json) from deed_types d where d.country_code=c.code),
    'verify',coalesce((select (select jsonb_object_agg(key,value) from jsonb_each(coalesce(extras,'{}'::jsonb)) where key in ('verify_telegram_on','verify_wa_code_on','verify_email_on')) from site_content s where s.country_code=c.code), '{}'::jsonb)
  ) order by c.sort_order) from countries c where al is null or c.code = any(al)), '[]'::json);
end $function$;
