-- Balkoun · 2026-09-28 · "إضافة عضو" from the users tab: the admin creates a member (optionally with an approved agency
-- page) without the verification code — phone marked verified, a temporary password chosen by the panel and sent to the
-- member on WhatsApp as a direct message (the normal welcome message still goes out through the existing trigger).
-- The mirrored contact row is tagged admin_added so the notebook can tell these accounts apart.

create or replace function public.bk_admin_create_member(p_token text, p_phone text, p_name text, p_family text default null, p_email text default null,
  p_country text default 'SY', p_hash text default null, p_agency_name text default null, p_password_plain text default null, p_send boolean default true) returns json
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare uid uuid; u users; ph text; cc text; ag_id bigint; c_id uuid; msg text; nm text;
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
  if p_send and coalesce(p_password_plain, '') <> '' and c_id is not null then
    msg := 'أهلاً ' || nm || ' 👋 أنشأنا لك حساباً على بلكون.' || E'\n'
        || 'رقم الدخول: ' || E'‎' || ph || E'‎' || E'\n'
        || 'كلمة المرور المؤقتة: ' || E'‎' || p_password_plain || E'‎' || E'\n'
        || 'رقم عضويتك: ' || E'‎' || coalesce(u.member_no, '') || E'‎' || E'\n\n'
        || 'ادخل من https://balkoun.com ثم غيّر كلمة المرور من «حسابي» ← «الأمان».';
    perform bk_admin_message_contact(p_token, c_id, null, 'whatsapp', msg, null);
  end if;
  return json_build_object('ok', true, 'id', u.id, 'member_no', u.member_no, 'phone', ph, 'agency_id', ag_id, 'contact_id', c_id);
end $function$;
grant execute on function public.bk_admin_create_member(text, text, text, text, text, text, text, text, text, boolean) to anon;
