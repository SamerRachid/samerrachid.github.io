-- Balkoun · 2026-10-02 · price and deed are optional (owner's rule).
--   listings.price_usd  → nullable; check becomes (price_usd is null or price_usd > 0). Null shows as "السعر عند التواصل"
--                         ("Price on request" / "Preis auf Anfrage") on cards, pages, map and static pages; such listings
--                         sort last by price and drop out only when a visitor sets a price range.
--   listings.tabu       → nullable; a listing without a deed word shows no deed pill at all (no more "بدون طابو" by default).
--   bk_intake_publish() → no 'noprice' error (usd := null); unknown / missing deed → tabu := null (was 'none').
--   Edge Function       → settle() no longer asks for price or tabu; summary says "السعر: عند التواصل" / "الطابو: غير مذكور".
--   Site post form      → price and deed fields optional (labels lost "req"; empty price → null; no deed → null).
alter table public.listings alter column price_usd drop not null;
alter table public.listings drop constraint if exists listings_price_usd_check;
alter table public.listings add constraint listings_price_usd_check check (price_usd is null or price_usd > 0);
alter table public.listings alter column tabu drop not null;
