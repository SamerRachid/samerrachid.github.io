-- Welcome messages (owner, 2026-10-16)
--  2. A member who has Telegram gets the welcome on Telegram only (it went out on WhatsApp too).
--  3. An account created from the panel gets ONE WhatsApp message: login details + how to post (it was the
--     login message followed by a separate welcome).
create or replace function public.bk_trg_welcome_member()
 returns trigger language plpgsql security definer set search_path to 'public', 'extensions' as $f$
declare c contacts; x jsonb; phone_now boolean; tg_now boolean; has_tg boolean;
begin
  select coalesce(extras, '{}'::jsonb) into x from site_content where id = 1;
  if coalesce(x->>'intake_welcome_on', 'true') = 'false' then return new; end if;
  select * into c from contacts where user_id = new.id limit 1;
  if c.id is null then return new; end if;

  phone_now := coalesce(new.phone_verified, false) and (tg_op = 'INSERT' or not coalesce(old.phone_verified, false));
  tg_now := new.tg_chat_id is not null and (tg_op = 'INSERT' or old.tg_chat_id is null);
  -- (2026-10-16) a member who has Telegram gets the welcome there only, not on WhatsApp as well
  has_tg := new.tg_chat_id is not null or c.tg_chat_id is not null;

  if phone_now then
    if has_tg then
      if c.tg_consent <> 'unsubscribed' and not exists (select 1 from campaign_sends where contact_id = c.id and channel = 'telegram' and trigger_type = 'welcome') then
        update contacts set tg_chat_id = coalesce(tg_chat_id, new.tg_chat_id), updated_at = now() where id = c.id;
        insert into campaign_sends (trigger_type, contact_id, channel, status) values ('welcome', c.id, 'telegram', 'queued');
      end if;
    elsif coalesce(c.phone, '') <> '' and c.wa_consent <> 'unsubscribed'
       and not exists (select 1 from campaign_sends where contact_id = c.id and channel = 'whatsapp' and trigger_type = 'welcome') then
      insert into campaign_sends (trigger_type, contact_id, channel, status) values ('welcome', c.id, 'whatsapp', 'queued');
    end if;
    if coalesce(c.email, '') <> '' and c.email_consent <> 'unsubscribed'
       and not exists (select 1 from campaign_sends where contact_id = c.id and channel = 'email' and trigger_type = 'welcome') then
      insert into campaign_sends (trigger_type, contact_id, channel, status) values ('welcome', c.id, 'email', 'queued');
    end if;
  end if;

  if tg_now then
    update contacts set tg_chat_id = coalesce(tg_chat_id, new.tg_chat_id), updated_at = now() where id = c.id;
    if c.tg_consent <> 'unsubscribed'
       and not exists (select 1 from campaign_sends where contact_id = c.id and channel = 'telegram' and trigger_type = 'welcome') then
      insert into campaign_sends (trigger_type, contact_id, channel, status) values ('welcome', c.id, 'telegram', 'queued');
    end if;
  end if;
  return new;
exception when others then return new;
end $f$;

CREATE OR REPLACE FUNCTION public.bk_admin_create_member(p_token text, p_phone text, p_name text, p_family text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_country text DEFAULT 'SY'::text, p_hash text DEFAULT NULL::text, p_agency_name text DEFAULT NULL::text, p_password_plain text DEFAULT NULL::text, p_send boolean DEFAULT true)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare uid uuid; u users; ph text; cc text; ag_id bigint; c_id uuid; msg text; nm text; contact_ph text;
begin
  uid := bk_admin_uid(p_token);
  cc := upper(coalesce(nullif(trim(p_country), ''), 'SY'));
  perform bk_admin_guard(uid, cc);
  ph := '+' || regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
  if length(ph) < 9 then return json_build_object('error', 'badphone'); end if;
  if coalesce(trim(p_name), '') = '' then return json_build_object('error', 'noname'); end if;
  if length(coalesce(p_hash, '')) < 32 then return json_build_object('error', 'badhash'); end if;
  if exists (select 1 from users where phone = ph) then return json_build_object('error', 'exists'); end if;
  if p_email is not null and trim(p_email) <> '' and exists (select 1 from users where lower(email) = lower(trim(p_email))) then return json_build_object('error', 'emailexists'); end if;
  insert into users (phone, name, family_name, pass_hash, phone_verified, lang, country, email, email_verified)
    values (ph, left(trim(p_name), 60), left(trim(coalesce(p_family, '')), 60), crypt(p_hash, gen_salt('bf')), true, 'ar', cc, nullif(trim(coalesce(p_email, '')), ''), false)
    returning * into u;
  if coalesce(trim(p_agency_name), '') <> '' then
    insert into agencies (user_id, name, phone, whatsapp, status, country_code) values (u.id, left(trim(p_agency_name), 120), ph, ph, 'approved', cc) returning id into ag_id;
  end if;
  insert into notifications (user_id, type, title, body, link, is_read) values (u.id, 'system', 'welcome', null, '/#/post', false);
  select id into c_id from contacts where user_id = u.id order by created_at limit 1;
  if c_id is not null then
    update contacts set tags = array_append(coalesce(tags, '{}'), 'admin_added'), notes = coalesce(nullif(notes, ''), 'أُضيف من لوحة الإدارة'), updated_at = now() where id = c_id;
  end if;
  nm := coalesce(nullif(trim(u.name || ' ' || coalesce(u.family_name, '')), ''), ph);
  select extras->>'intake_contact_phone' into contact_ph from site_content where id = 1;
  if p_send and coalesce(p_password_plain, '') <> '' and c_id is not null then
    msg := 'أهلاً ' || nm || ' 👋 أنشأنا لك حساباً على بلكون.' || E'\n'
        || 'رقم الدخول: ' || E'‎' || ph || E'‎' || E'\n'
        || 'كلمة المرور المؤقتة: ' || E'‎' || p_password_plain || E'‎' || E'\n'
        || 'رقم عضويتك: ' || E'‎' || coalesce(u.member_no, '') || E'‎' || E'\n\n'
        || 'ادخل من https://balkoun.com ثم غيّر كلمة المرور من «حسابي» ← «الأمان».' || E'\n' || E'\n'
        || '📩 لنشر إعلان عقارك: أرسل تفاصيله وصوره هنا مباشرة وأنشره لك وأرسل لك رابطه، أو انشره بنفسك من https://balkoun.com/post'
        || coalesce(E'\n' || 'للتواصل مع الإدارة: ' || nullif(trim(contact_ph), ''), '');
    perform bk_admin_message_contact(p_token, c_id, null, 'whatsapp', msg, null);
    -- (2026-10-16) this message is the welcome too: the separate WhatsApp welcome queued by trg_welcome_member is dropped
    delete from campaign_sends where contact_id = c_id and trigger_type = 'welcome' and channel = 'whatsapp' and status = 'queued' and claimed_at is null;
  end if;
  return json_build_object('ok', true, 'id', u.id, 'member_no', u.member_no, 'phone', ph, 'agency_id', ag_id, 'contact_id', c_id);
end $function$;
