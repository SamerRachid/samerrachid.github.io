# Balkoun text-to-listing bot — the fixed rules

Decided by the owner; a future change needs the owner's word, not a hunch from one message. When a real message
fools the bot, add it to `tests/bot/` and fix it in the weekly batch (see "How changes happen" below).

## The sender's experience
1. **One message publishes.** A message with the property facts (and photos, optional) is read and published right
   away; the sender gets the summary and the link. No «نعم» step for chats. Panel drafts (web) and admin forwards still
   confirm / go to review.
2. **One question at most, and «تخطي» ends it.** The bot asks once for: sale or rent, the property type, the
   governorate, the size, and the neighbourhood only when the message names no place at all. Everything is asked in
   one message. The sender can answer **«تخطي» / skip** and the listing publishes without the optional parts (size
   shown as «غير مذكورة», no neighbourhood, no price, no deed, no photos). Only three things can never be skipped,
   because the listing cannot be filed without them: governorate, property type, sale-or-rent.
3. **Unknown places never block.** A neighbourhood/village that is not in our list publishes as written (shown as the
   landmark, kept as `area_text`); the admin gets a Telegram alert and adds it from المناطق ← مناطق مقترحة, which links
   the listing. The sender is **not** asked "is this the area's name?".
4. **The hour after publishing** (nothing new started since):
   - a short text («السعر 75 ألف», «الطابق الثالث», «طابو أخضر») **corrects** the listing — only the changed facts are
     written; a listing-shaped text (للبيع/للإيجار + details) is a **new** listing;
   - «إلغاء» takes the listing off the site; «رجّع» within 10 minutes brings it back;
   - bare photos/videos within 5 minutes are added to it; «جديد» ends all of that and starts fresh.
5. **The sender's words are the description.** Verbatim, including the phone number; only command words and the
   membership number are dropped. The model's rewrite is used only when the panel switches `intake_keep_text` off.
6. **The how-to is sent once** per chat (not to admins) and again on «مساعدة».

## Reading rules (what the fields mean)
- Property type = the sender's word: فيلا → villa, بيت عربي → arab, منزل/بيت → house, except a منزل on a numbered
  floor or with a lift → apartment. «أرض» alone → plot; زراعية/سكنية/تجارية/صناعية/سياحية only when written.
  شقة فندقية → hotelapt, always rent.
- Several units in one message = **one** listing titled «شقة عدد N», total price, full text in the description.
- Deed words include «وضع يد» → possession. «طابو أخضر 2400 سهم» is a full green deed.
- Transport lines (مكرو/خط/سرفيس/باص/كراج + name) and «قرب/جانب/بعد/مقابل + place» are landmarks, never the area.
- A name is an area only if it is written in the message (no look-alike swaps: العدوي ≠ العسالي).
- «ريف X» with no rural governorate of its own → X. Multi-governorate agencies are asked for the governorate when the
  text does not settle it (a Hama agency writing a Damascus street → ask).
- Video: stored as sent (no AI), up to 3 minutes / panel size limit; Telegram caps files at 20 MB.
- "Video from Samer"-style captions and media-only messages are not read as text.

## How changes happen
- The owner wants problems fixed as soon as they show up (2026-10-02). Every fix still ships with its test case:
  run `tests/bot/sql-scenarios.sql` (must say `fails=0`) and `node tests/bot/read-cases.mjs <token>` before deploying.
- Every change to a rule above is written here first, dated, with the owner's decision.
