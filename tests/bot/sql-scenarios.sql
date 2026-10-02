-- Balkoun · intake bot · command / state-machine scenarios (run before every deploy of bk_intake_message or the bot).
-- Runs entirely inside one transaction and ALWAYS rolls back (raise exception at the end): nothing is left behind.
-- Run it through the Supabase SQL editor / MCP; the result arrives in the error text as one line per case:
--   PASS <case>   or   FAIL <case> | got: {...}
-- a tiny checker that lives only in this session: one report line per case, failures counted in a temp table
create temp table bk_f(n int); insert into bk_f values (0);
create function pg_temp.chk(name text, ok boolean, got text) returns text language sql as $f$
  update bk_f set n = n + case when ok then 0 else 1 end;
  select E'\n' || case when ok then 'PASS ' else 'FAIL ' end || name || case when ok then '' else ' | got: ' || coalesce(got,'null') end
$f$;
do $$
declare uid uuid; ag bigint; ch text := '+10000000099'; r json; d1 bigint; d2 bigint; out text := '';
begin
  insert into users (phone, name, pass_hash, phone_verified, lang, country) values (ch, 'اختبار آلي', 'x', true, 'ar', 'SY') returning id into uid;
  insert into agencies (user_id, name, phone, whatsapp, status, country_code, intake_enabled) values (uid, 'مكتب الاختبار الآلي', ch, ch, 'approved', 'SY', true) returning id into ag;

  -- 1. plain «لا» with nothing open → "nothing", not a cancel
  r := bk_intake_message('whatsapp', 'tb-1', ch, 'text', 'لا');
  out := out || pg_temp.chk('no_without_draft', r->>'command' = 'nothing', r::text);

  -- 2. first text opens a draft; not guided yet
  r := bk_intake_message('whatsapp', 'tb-2', ch, 'text', 'شقة للبيع في حماة 100 متر 40 ألف'); d1 := (r->>'draft_id')::bigint;
  out := out || pg_temp.chk('first_text_opens_draft', (r->>'is_new')::boolean and (r->>'guided')::boolean = false, r::text);
  insert into intake_log (draft_id, chat_id, event) values (d1, ch, 'guide_sent');

  -- 3. «لا» while a summary is shown (ready) cancels
  update intake_drafts set status='ready', summary='s', missing='{}', updated_at=now() where id = d1;
  r := bk_intake_message('whatsapp', 'tb-3', ch, 'text', 'لا');
  out := out || pg_temp.chk('soft_no_cancels_ready', r->>'command' = 'cancel' and (select status from intake_drafts where id=d1) = 'cancelled', r::text);

  -- 4. «رجّع» restores it as ready
  r := bk_intake_message('whatsapp', 'tb-4', ch, 'text', 'رجّع');
  out := out || pg_temp.chk('undo_restores_ready', (r->>'restored')::boolean and r->>'status' = 'ready', r::text);

  -- 5. hard cancel, new text, undo → merged into the restored draft
  r := bk_intake_message('whatsapp', 'tb-5', ch, 'text', 'إلغاء');
  r := bk_intake_message('whatsapp', 'tb-6', ch, 'text', 'وفيها غرفتين'); d2 := (r->>'draft_id')::bigint;
  r := bk_intake_message('whatsapp', 'tb-7', ch, 'text', 'رجع');
  out := out || pg_temp.chk('undo_merges_new_text', (r->>'merged')::boolean and (select raw_text like '%غرفتين%' from intake_drafts where id=d1) and (select status from intake_drafts where id=d2) = 'cancelled', r::text);

  -- 6. a draft waiting > 24 h expires when a new message comes, and is reported
  update intake_drafts set status='needs_info', summary='s', updated_at=now()-interval '25 hours', last_message_at=now()-interval '25 hours', fields='{"title":"شقة حماة"}' where id = d1;
  r := bk_intake_message('whatsapp', 'tb-8', ch, 'text', 'محل للإيجار في حمص');
  out := out || pg_temp.chk('stale_draft_expires', (r->>'is_new')::boolean and r->'expired_prev'->>'title' = 'شقة حماة', r::text);

  -- 7. «لا» while nothing is on the table (collecting) is plain text, not a cancel
  r := bk_intake_message('whatsapp', 'tb-9', ch, 'text', 'لا');
  out := out || pg_temp.chk('no_while_collecting_is_text', r->>'command' is null and r->>'status' = 'collecting', r::text);

  -- 8. bare photo within 5 min after a publish joins that listing (rule: only when the published draft is the sender's latest)
  update intake_drafts set status='cancelled', error='test' where chat_id = ch;
  update intake_drafts set status='published', listing_id=37, published_at=now()-interval '2 minutes', created_at=now()+interval '1 second' /* now() is frozen inside the transaction: make d1 the newest draft */ where id = d1;
  r := bk_intake_message('whatsapp', 'tb-10', ch, 'photo', null, '{"mime":"image/jpeg"}'::jsonb);
  out := out || pg_temp.chk('bare_photo_attaches_to_published', (r->>'attach_listing')::int = 37, r::text);

  -- 9. a photo WITH a caption after a publish is a new listing
  r := bk_intake_message('whatsapp', 'tb-11', ch, 'photo', 'شقة للبيع في المزة 150 متر 90 ألف', '{"mime":"image/jpeg"}'::jsonb);
  out := out || pg_temp.chk('captioned_photo_is_new_listing', (r->>'is_new')::boolean and r->>'attach_listing' is null, r::text);
  update intake_drafts set status='cancelled', error='test' where id = (r->>'draft_id')::bigint;

  -- 10. «جديد» then a bare photo → new draft, never glued to the previous listing
  r := bk_intake_message('whatsapp', 'tb-12', ch, 'text', 'جديد');
  r := bk_intake_message('whatsapp', 'tb-13', ch, 'photo', null, '{"mime":"image/jpeg"}'::jsonb);
  out := out || pg_temp.chk('new_then_photo_is_new', (r->>'is_new')::boolean and r->>'attach_listing' is null, r::text);
  d2 := (r->>'draft_id')::bigint;

  -- 11. a bare photo right after a draft went to review joins that draft
  update intake_drafts set status='review', updated_at=now() where id = d2;
  r := bk_intake_message('whatsapp', 'tb-14', ch, 'photo', null, '{"mime":"image/jpeg"}'::jsonb);
  out := out || pg_temp.chk('bare_photo_joins_review_draft', (r->>'attach_review')::boolean and (r->>'draft_id')::bigint = d2, r::text);

  -- 12. the area question: «لا» → ask; the next text → area_set; «لا، X» → area_set X
  update intake_drafts set status='ready', summary='s', missing='{}', fields='{"governorate_id":7,"governorate":"حماة","area_text":"كفر عمرو","area_pending":"1","landmark":"كفر عمرو"}'::jsonb, updated_at=now() where id = d2;
  r := bk_intake_message('whatsapp', 'tb-15', ch, 'text', 'لا');
  out := out || pg_temp.chk('area_no_asks_name', r->>'command' = 'area_ask', r::text);
  r := bk_intake_message('whatsapp', 'tb-16', ch, 'text', 'تلدرة');
  out := out || pg_temp.chk('area_next_text_sets_name', r->>'command' = 'area_set' and r->>'text' = 'تلدرة', r::text);
  update intake_drafts set fields = fields || '{"area_pending":"1"}'::jsonb, status='ready' where id = d2;
  r := bk_intake_message('whatsapp', 'tb-17', ch, 'text', 'لا، كفر زيتا');
  out := out || pg_temp.chk('area_no_comma_name_sets', r->>'command' = 'area_set' and r->>'text' = 'كفر زيتا', r::text);

  -- 13. «نعم» while the bot is still reading → remembered, not refused
  update intake_drafts set fields = fields - 'area_pending' - 'area_wait', status='reading', claimed_at=now() where id = d2;
  r := bk_intake_message('whatsapp', 'tb-18', ch, 'text', 'نعم');
  out := out || pg_temp.chk('yes_mid_read_waits', r->>'command' = 'confirm_wait' and (select fields->>'auto_confirm' from intake_drafts where id=d2) = '1', r::text);

  -- 14. a review draft accepts a text correction for 10 minutes (joins the same draft; the bot then re-reads it via bk_intake_claim)
  update intake_drafts set status='review', updated_at=now() where id = d2;
  r := bk_intake_message('whatsapp', 'tb-19', ch, 'text', 'السعر 45 ألف');
  out := out || pg_temp.chk('review_accepts_correction', (r->>'draft_id')::bigint = d2 and (r->>'is_new')::boolean = false and (select raw_text like '%45 ألف%' from intake_drafts where id=d2), r::text);
  out := out || pg_temp.chk('review_draft_can_be_claimed', (bk_intake_claim(d2)->>'status') = 'reading', null);

  -- 15. a review draft older than 10 minutes is closed: a new text opens a new draft
  update intake_drafts set status='review', updated_at=now()-interval '11 minutes' where id = d2;
  r := bk_intake_message('whatsapp', 'tb-20', ch, 'text', 'بيت عربي للبيع في حمص باب الدريب');
  out := out || pg_temp.chk('old_review_draft_is_closed', (r->>'is_new')::boolean and (r->>'draft_id')::bigint <> d2, r::text);

  raise exception E'BOT_SQL_SCENARIOS fails=% %', (select n from bk_f), out;
end $$;
