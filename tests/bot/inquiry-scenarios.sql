-- Balkoun · visit/message requests between members — runs in one transaction and ALWAYS rolls back (raise at the end).
--   npx.cmd --yes supabase db query --linked --project-ref coajrqynjrptujmzjjdh -f tests/bot/inquiry-scenarios.sql
create temp table bk_f(n int); insert into bk_f values (0);
create function pg_temp.chk(name text, ok boolean, got text) returns text language sql as $f$
  update bk_f set n = n + case when ok then 0 else 1 end;
  select E'\n' || case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else ' | got: ' || coalesce(got,'null') end
$f$;
do $$
declare a uuid; b uuid; ta text; tb text; lid bigint; r json; m json; iq bigint; out text := '';
begin
  -- two throwaway members (no phone, like the house accounts) and one listing owned by B
  insert into users (phone, name, family_name, pass_hash, role, country, city, lang, hide_phone) values (null, 'اختبار', 'طالب', 'x', 'owner', 'SY', 'دمشق', 'ar', true) returning id into a;
  insert into users (phone, name, family_name, pass_hash, role, country, city, lang, hide_phone) values (null, 'اختبار', 'مالك', 'x', 'owner', 'SY', 'دمشق', 'ar', true) returning id into b;
  ta := bk_issue_member_token(a); tb := bk_issue_member_token(b);
  insert into listings (user_id, status, section, deal, property_type, governorate_id, price_usd, area_m2, description, contact_phone, country_code, condition)
    values (b, 'live', 'homes', 'sale', 'apartment', 1, 50000, 100, 'شقة اختبار آلي للطلبات — تُحذف مع نهاية الاختبار', null, 'SY', 'intact') returning id into lid;

  -- 1. a guest without a number is refused; a member without a number is accepted
  r := bk_inquiry_send(lid, null, 'زائر', '', 'مرحبا', 'visit', null, null);
  out := out || pg_temp.chk('guest_needs_phone', r->>'error' = 'phone', r::text);
  r := bk_inquiry_send(lid, null, '', '', 'أرغب بالمعاينة غداً', 'visit', a, ta);
  out := out || pg_temp.chk('member_without_phone_ok', (r->>'ok')::boolean, r::text); iq := (r->>'id')::bigint;
  out := out || pg_temp.chk('name_taken_from_account', (select name = 'اختبار طالب' and phone is null and to_user = b and from_user = a from inquiries where id = iq), null);
  out := out || pg_temp.chk('owner_rang_on_site', exists (select 1 from notifications where user_id = b and link = '/#/msgs?inquiry=' || iq), null);
  out := out || pg_temp.chk('no_outbound_queued_without_contacts', not exists (select 1 from campaign_sends s join contacts c on c.id = s.contact_id where c.user_id in (a, b)), null);

  -- 2. the owner sees it in رسائلي as owner; the requester sees it as requester
  m := bk_my_messages(b, tb);
  out := out || pg_temp.chk('owner_sees_thread', (m->'inquiries'->0->>'role') = 'owner' and (m->'inquiries'->0->>'other_name') = 'اختبار طالب' and (m->'inquiries'->0->>'listing_id')::bigint = lid, m::text);
  m := bk_my_messages(a, ta);
  out := out || pg_temp.chk('requester_sees_thread', (m->'inquiries'->0->>'role') = 'requester' and (m->'inquiries'->0->>'other_name') = 'اختبار مالك', m::text);

  -- 3. the owner replies → the requester is rung and sees the bubble; the requester replies back
  r := bk_member_reply(b, 'inquiry', iq, 'أهلاً، غداً الخامسة مساءً يناسب', tb);
  out := out || pg_temp.chk('owner_reply_ok', (r->>'ok')::boolean and (select status from inquiries where id = iq) = 'replied', r::text);
  out := out || pg_temp.chk('requester_rang', exists (select 1 from notifications where user_id = a and link = '/#/msgs?inquiry=' || iq), null);
  m := bk_my_messages(a, ta);
  out := out || pg_temp.chk('requester_sees_owner_bubble', (m->'inquiries'->0->'thread'->0->>'sender') = 'owner', m::text);
  r := bk_member_reply(a, 'inquiry', iq, 'تمام، أراك غداً', ta);
  out := out || pg_temp.chk('requester_reply_ok', (r->>'ok')::boolean and (select count(*) from message_followups where kind = 'inquiry' and ref_id = iq) = 2, r::text);

  -- 4. a stranger can neither reply nor delete; the owner cannot request on their own listing; the cap holds
  begin r := bk_member_reply(b, 'inquiry', iq + 999999, 'x', tb); out := out || pg_temp.chk('unknown_thread_refused', false, r::text); exception when others then out := out || pg_temp.chk('unknown_thread_refused', true, null); end;
  r := bk_inquiry_send(lid, null, '', '', 'x', 'visit', b, tb);
  out := out || pg_temp.chk('owner_cannot_request_own_listing', r->>'error' = 'self', r::text);
  r := bk_inquiry_send(lid, null, '', '', '2', 'visit', a, ta); r := bk_inquiry_send(lid, null, '', '', '3', 'visit', a, ta); r := bk_inquiry_send(lid, null, '', '', '4', 'visit', a, ta);
  out := out || pg_temp.chk('three_per_day_cap', r->>'error' = 'limit', r::text);

  -- 5. either side can close the conversation
  r := bk_member_delete_message(a, 'inquiry', iq, ta);
  out := out || pg_temp.chk('requester_can_close', (r->>'ok')::boolean and not exists (select 1 from inquiries where id = iq), r::text);

  raise exception E'INQUIRY_SCENARIOS fails=% %', (select n from bk_f), out;
end $$;
