# Balkoun text-to-listing bot — the fixed rules

Decided by the owner; a future change needs the owner's word, not a hunch from one message. When a real message
fools the bot, add it to `tests/bot/` and fix it in the weekly batch (see "How changes happen" below).

## The sender's experience
1. **Summary first, then the question** (owner's rule, 2026-10-03; replaces the earlier "one message publishes").
   A message with the property facts (and photos, optional) is read; the sender gets the summary and chooses:
   **نعم** → publish · **لا** → cancel · **تصحيح** → then writes the correction («السعر 75 ألف») · **إضافة** → then sends
   photos, a video or more details and writes «تم». Nothing publishes before «نعم» (a «نعم» sent while the bot was
   still reading counts). Admin forwards still go to the panel for review.
2. **One question at most, and «تخطي» ends it.** The bot asks once for: sale or rent, the property type, the
   governorate, the size, and the neighbourhood only when the message names no place at all. Everything is asked in
   one message. The sender can answer **«تخطي» / skip** and the summary comes back without the optional parts (size
   shown as «غير مذكورة», no neighbourhood, no price, no deed, no photos). Only three things can never be skipped,
   because the listing cannot be filed without them: governorate, property type, sale-or-rent.
3. **Unknown places never block.** A neighbourhood/village that is not in our list publishes as written (shown as the
   landmark, kept as `area_text`); the admin gets a Telegram alert and adds it from المناطق ← مناطق مقترحة, which links
   the listing. The sender is **not** asked "is this the area's name?".
4. **After publishing there is no edit window.** The publish message says: for a new listing write «جديد» then send it
   (optional: any text after a publish simply opens a new listing); to edit, delete or add photos later **send the
   listing's number** (SY10281, «10281», «رقم الإعلان 10281»). The bot opens it for 30 minutes and offers:
   **1** edit the details (then every text is a correction, «تم» ends) · **2** add photos / video (then every photo or
   video is attached) · **3** delete («رجّع» within 10 minutes brings it back) · **لا** exit. A member opens only their
   own listings; admin chats open any. A new listing text closes the session. «جديد» at any time starts fresh; it
   cancels a draft the sender is still building or confirming, but never a listing that already waits in the panel
   (review): that one stays for the admin; the chat only lets go of it.
4b. **One listing at a time; «جديد» starts each one** (owner, 2026-10-03, reaffirmed after a 10-message batch from
   a real agency glued into one failed draft: no batch mode, no per-message splitting, no numbered answers — "no more
   confusion"; the failure reply and the client guide say to send one listing, answer its summary, then «جديد»). While a listing is open (being built,
   waiting for «نعم», or waiting in the panel for the last 10 minutes), every text and photo belongs to it, whatever
   words it holds: the words للبيع/للإيجار never start a new listing by themselves, because nobody knows where a
   sender writes them. Write «جديد», then send the next listing with its photos. After a publish or a cancel nothing is
   open, so the next message simply opens a new listing without «جديد». Two listings pasted in ONE message are still
   split into two drafts, but the photos sent with that message all stay on the first. A generic word heading a
   landmark («مدرسة المناضل», «جانب الجامع») is never the area.
5. **The sender's words are the description.** Verbatim, including the phone number; only command words and the
   membership number are dropped. The model's rewrite is used only when the panel switches `intake_keep_text` off.
   Exception (2026-10-03): a member who turned on «إخفاء رقمي» in their account gets phone numbers stripped from the
   published text, and their listings show no phone at all — visitors use the visit/message request instead.
6. **The how-to is sent once** per chat (not to admins) and again on «مساعدة».

## Reading rules (what the fields mean)
- Property type = the sender's word: فيلا → villa, بيت عربي → arab, منزل/بيت → house, except a منزل on a numbered
  floor or with a lift → apartment. «أرض» alone → plot; زراعية/سكنية/تجارية/صناعية/سياحية only when written.
  شقة فندقية → hotelapt, always rent.
- Several units in one message = **one** listing titled «شقة عدد N», total price, full text in the description.
- Deed words include «وضع يد» → possession. «طابو أخضر 2400 سهم» is a full green deed.
- Transport lines (مكرو/خط/سرفيس/باص/كراج + name) and «قرب/جانب/بعد/مقابل + place» are landmarks, never the area.
- A name is an area only if it is written in the message (no look-alike swaps: العدوي ≠ العسالي), and a governorate
  written nowhere is never guessed: «الصناعة» exists in four governorates, so the sender is asked which one.
- «ريف X» with no rural governorate of its own → X. Multi-governorate agencies are asked for the governorate when the
  text does not settle it (a Hama agency writing a Damascus street → ask).
- Video: stored as sent (no AI), up to 3 minutes / panel size limit; Telegram caps files at 20 MB.
- "Video from Samer"-style captions and media-only messages are not read as text.

## How changes happen
- The owner wants problems fixed as soon as they show up (2026-10-02). Every fix still ships with its test case:
  run `tests/bot/sql-scenarios.sql` (must say `fails=0`) and `node tests/bot/read-cases.mjs <token>` before deploying.
- Every change to a rule above is written here first, dated, with the owner's decision.
