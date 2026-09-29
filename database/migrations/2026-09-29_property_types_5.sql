-- Balkoun · 2026-09-29 · five property types added after comparing with doushesh (owner's request):
--   hotelapt  شقة مفروشة فندقية  (residential, RENT ONLY — never for sale)
--   clinic    عيادة              (commercial)
--   hotel     فندق ومنشأة سياحية (commercial)
--   indust    أرض صناعية         (land)
--   tourist   أرض سياحية         (land)
-- Applied live through targeted replace() on the function bodies (see the DO blocks in the session); this file records
-- the effective changes so a rebuild from migrations lands in the same place.
--
-- 1. countries.types: every country row with its own list got the five entries appended (ar / en / fr).
update countries set types = types || '[{"code":"hotelapt","ar":"شقة مفروشة فندقية","en":"Serviced apartment","fr":"Appartement hôtelier meublé"},{"code":"clinic","ar":"عيادة","en":"Clinic","fr":"Cabinet médical"},{"code":"hotel","ar":"فندق ومنشأة سياحية","en":"Hotel & tourism facility","fr":"Hôtel et établissement touristique"},{"code":"indust","ar":"أرض صناعية","en":"Industrial land","fr":"Terrain industriel"},{"code":"tourist","ar":"أرض سياحية","en":"Tourism land","fr":"Terrain touristique"}]'::jsonb
 where jsonb_array_length(coalesce(types,'[]'::jsonb)) > 0 and not (types @> '[{"code":"hotelapt"}]'::jsonb);
-- 2. bk_intake_taxonomy(): the Syrian fallback list carries the five types; land_types = resid, agri, comm, indust, tourist;
--    commercial_types = shop, office, factory, warehouse, clinic, hotel.
-- 3. bk_intake_publish(): the type whitelist accepts the five codes; section = land for indust/tourist, commercial for
--    clinic/hotel; a hotelapt listing is forced to deal = rent.
-- Site (index.html): D_TYPES_SY + FR labels, LANDT/COMMT, RENT_ONLY_TYPES (post form locks the deal to rent), home type
-- groups, tiles; scripts/generate-pages.mjs plurals; scripts/generate-listings.mjs icons; Edge Function SYSTEM rules +
-- settle() forcing rent for hotelapt.

-- 2026-09-29 (later) · four more commercial types, same wiring: hall صالة أفراح ومناسبات · showroom صالة عرض ·
-- station محطة وقود · workshop ورشة. Appended to every country's types (ar/en/fr), to the SY fallback and
-- commercial_types in bk_intake_taxonomy(), and to bk_intake_publish()'s whitelist + commercial section.
-- NOTE: the publish whitelist had silently kept the original 15 codes (the first replace() never matched its
-- exact text); it was re-applied with a whitespace-tolerant regexp_replace and now lists all 24 codes.
update countries set types = types || '[{"code":"hall","ar":"صالة أفراح ومناسبات","en":"Event hall","fr":"Salle des fêtes"},{"code":"showroom","ar":"صالة عرض","en":"Showroom","fr":"Salle d''exposition"},{"code":"station","ar":"محطة وقود","en":"Fuel station","fr":"Station-service"},{"code":"workshop","ar":"ورشة","en":"Workshop","fr":"Atelier"}]'::jsonb
 where jsonb_array_length(coalesce(types,'[]'::jsonb)) > 0 and not (types @> '[{"code":"hall"}]'::jsonb);

-- later: 'house' منزل (residential) added the same way — 25 types. Bot: "منزل"/"بيت" = house unless the text clearly
-- describes a flat (floor + elevator, "شقة") or an Arab courtyard house (حوش، أرض ديار).
