// ════════════════════════════════════════════════════════════════════
//  BALKOUN · static listing page generator
//
//  Runs in GitHub Actions on a schedule. Reads every live listing from
//  Supabase and writes a real, crawlable HTML page for each one at
//  /listing/<id>-<slug>/index.html, plus a fresh sitemap.xml.
//
//  Nothing here needs a server — it's a build step. GitHub Pages just
//  serves whatever files exist in the repo, and this script is what
//  keeps those files in sync with your database.
// ════════════════════════════════════════════════════════════════════
import fs from "fs";
import path from "path";

const SUPABASE_URL = "https://coajrqynjrptujmzjjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t"; // public anon key — safe, RLS restricts it to live listings
const SITE = "https://balkoun.com";
const OUT_DIR = path.resolve("listing");
const SITEMAP_PATH = path.resolve("sitemap.xml");

// Talking to Supabase over plain HTTP instead of the @supabase/supabase-js
// SDK. The SDK also sets up a realtime/WebSocket connection on startup —
// a browser feature that plain Node.js doesn't have — which is what was
// crashing this script before any listing was even fetched. This script
// only ever reads data, so a bare REST call is simpler and has zero
// dependency on Node's WebSocket support either way.
async function sb(endpoint) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`
    }
  });
  if (!res.ok) {
    throw new Error(`Supabase request failed (${res.status}): ${endpoint}`);
  }
  return res.json();
}

// TYPE_AR feeds the folder slug (see main()). Do NOT rename existing keys
// or values here — that would move every already-indexed URL. Add new
// property types to TYPE_DISPLAY below instead; it is only used for text
// inside the page.
const TYPE_AR = { apartment:"شقة", arab:"بيت عربي", villa:"فيلا", floor:"طابق كامل",
  building:"بناء كامل", shop:"محل تجاري", office:"مكتب", resid:"أرض سكنية",
  agri:"أرض زراعية", comm:"أرض تجارية" };
const TYPE_DISPLAY = { ...TYPE_AR, chalet:"شاليه", farm:"مزرعة", land:"أرض",
  restaurant:"مطعم", warehouse:"مستودع", factory:"معمل" };
const TYPE_ICON = { apartment:"🏢", arab:"🏛️", villa:"🏡", floor:"🏢", building:"🏬",
  chalet:"🏖️", farm:"🌾", shop:"🏪", office:"🏢", land:"🗺️", restaurant:"🍽️",
  warehouse:"🏭", factory:"🏭", resid:"🗺️", agri:"🌱", comm:"🗺️" };
const TABU_AR = { green:"طابو أخضر", shares:"حصص سهمية", court:"حكم محكمة",
  court_desc:"حكم محكمة موصوف", poa:"وكالة كاتب عدل", none:"بدون طابو" };
const COND_AR = { intact:"سليم", repair:"يحتاج ترميم", shell:"على العظم", stripped:"معفش",
  damaged:"متضرر", empty:"أرض فارغة", built:"عليها بناء", fenced:"مسوّرة", planted:"مزروعة" };
const DIR_AR = { s:"قبلي (جنوبي)", n:"شمالي", e:"شرقي", w:"غربي", se:"قبلي شرقي",
  sw:"قبلي غربي", ne:"شمالي شرقي", nw:"شمالي غربي" };
const PERIOD_AR = { yearly:"سنوي", monthly:"شهري", weekly:"أسبوعي", daily:"يومي" };

function slugify(text) {
  return (text || "")
    .toString()
    .replace(/[^\p{L}\p{N}\s-]/gu, "")
    .trim()
    .replace(/\s+/g, "-")
    .slice(0, 60);
}

function esc(s) {
  return String(s ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}

function money(v) { return "$" + Number(v).toLocaleString("en"); }

// ── small template helpers ─────────────────────────────────────────────
function has(v) { return v !== null && v !== undefined && v !== ""; }

// Left-to-right run for numbers inside RTL text (keeps "$1,200" and "120 م²" tidy).
function ltr(s) { return `<span class="ltr">${esc(s)}</span>`; }

// Escaped text with line breaks preserved (\n → <br>).
function nl2br(s) { return esc(s).replace(/\r\n|\r|\n/g, "<br>"); }

function pill(text, cls) { return `<span class="pill ${cls || ""}">${text}</span>`; }

// One key-fact card. Skips itself when the value is missing.
function fact(label, value) {
  if (!has(value)) return "";
  return `<div class="fact"><span class="fl">${esc(label)}</span><span class="fv">${value}</span></div>`;
}

// Inline JSON-LD must never be able to close its own <script> tag.
function jsonForScript(obj) { return JSON.stringify(obj).replace(/</g, "\\u003c"); }

function renderPage(l, photos) {
  const typeLabel = TYPE_DISPLAY[l.property_type] || TYPE_AR[l.property_type] || l.property_type;
  const typeIcon = TYPE_ICON[l.property_type] || "🏠";
  const tabuLabel = TABU_AR[l.tabu] || l.tabu;
  const condLabel = COND_AR[l.condition] || l.condition;
  const isRent = l.deal === "rent";
  const dealLabel = isRent ? "للإيجار" : "للبيع";
  const periodLabel = isRent && l.rental_period ? (PERIOD_AR[l.rental_period] || l.rental_period) : "";
  const areaName = l.area_ar || "";
  const gov = l.governorate_ar || "";
  const place = [areaName, gov].filter(Boolean).join("، ");

  const title = `${typeLabel} ${dealLabel} ${l.area_m2} م² — ${areaName} ${gov} | بلكون`;
  // Meta description: a factual lead (type, place, size, rooms, deed) then the
  // owner's own words, trimmed so the whole thing stays around 155 chars.
  const leadBits = [`${typeLabel} ${dealLabel} في ${place}`, has(l.area_m2) ? `${l.area_m2} م²` : "",
    has(l.rooms) ? `${l.rooms} غرف` : "", tabuLabel ? String(tabuLabel) : "", money(l.price_usd)].filter(Boolean);
  const lead = leadBits.join("، ") + ".";
  const ownText = (l.description || "").replace(/\s+/g, " ").trim();
  const desc = (lead + (ownText ? " " + ownText : "")).slice(0, 155);

  // Must mirror main() exactly (TYPE_AR, not TYPE_DISPLAY) so the canonical
  // URL always points at the folder this page is actually written into.
  const slugLabel = TYPE_AR[l.property_type] || l.property_type;
  const slug = slugify(slugLabel + " " + (l.area_ar||"") + " " + l.governorate_ar);
  const url = `${SITE}/listing/${l.id}-${slug}/`;
  const appUrl = `${SITE}/listing/${l.id}`;

  // Photos: what listing_photos gave us, falling back to the view's cover_url.
  const allPhotos = photos.length ? photos : (l.cover_url ? [l.cover_url] : []);
  const cover = allPhotos[0] || "";
  const thumbs = allPhotos.slice(1, 7);

  const phoneDigits = (l.contact_phone || "").replace(/\D/g, "");
  const tel = phoneDigits ? `tel:+${phoneDigits}` : null;
  const wa = phoneDigits && l.accepts_whatsapp !== false
    ? `https://wa.me/${phoneDigits}?text=${encodeURIComponent("مرحبا، مهتم بهذا العقار: " + title + "\n" + url)}`
    : null;
  const contactName = l.contact_name || l.owner_name || "";
  const refCode = `BK-${l.id}`;

  const osm = has(l.lat) && has(l.lng)
    ? `https://www.openstreetmap.org/?mlat=${encodeURIComponent(l.lat)}&mlon=${encodeURIComponent(l.lng)}#map=16/${encodeURIComponent(l.lat)}/${encodeURIComponent(l.lng)}`
    : null;

  // ── hero ────────────────────────────────────────────────────────────
  const hero = cover
    ? `<a class="hero" href="${esc(cover)}" target="_blank" rel="noopener"><img src="${esc(cover)}" alt="${esc(title)}" width="1080" height="608" fetchpriority="high"></a>`
    : `<div class="hero ph" role="img" aria-label="${esc(typeLabel)}"><span>${typeIcon}</span><small>${esc(typeLabel)}</small></div>`;
  const thumbStrip = thumbs.length
    ? `<div class="thumbs">${thumbs.map((p, i) =>
        `<a href="${esc(p)}" target="_blank" rel="noopener"><img src="${esc(p)}" alt="${esc(typeLabel)} — صورة ${i + 2}" loading="lazy"></a>`
      ).join("")}</div>`
    : "";

  // ── pills ───────────────────────────────────────────────────────────
  const pills = [
    tabuLabel ? pill(esc(tabuLabel), l.tabu === "green" ? "ok" : "grey") : "",
    l.by_owner ? pill("من المالك", "gold") : "",
    pill(ltr(refCode), "muted")
  ].filter(Boolean).join("");

  // ── key facts ───────────────────────────────────────────────────────
  const floorText = has(l.floor)
    ? (Number(l.floor) === 0 ? "أرضي" : ltr(l.floor)) + (has(l.floors_total) ? ` من ${ltr(l.floors_total)}` : "")
    : null;
  const furnishedText = typeof l.furnished === "boolean" ? (l.furnished ? "مفروش" : "غير مفروش")
    : (has(l.furnished) ? esc(l.furnished) : null);
  const facts = [
    fact("مساحة", has(l.area_m2) ? `${ltr(l.area_m2)} م²` : null),
    fact("غرف", has(l.rooms) ? ltr(l.rooms) : null),
    fact("حمّامات", has(l.baths) ? ltr(l.baths) : null),
    fact("صالونات", has(l.living_rooms) ? ltr(l.living_rooms) : null),
    fact("الطابق", floorText),
    fact("سنة البناء", has(l.year_built) ? ltr(l.year_built) : null),
    fact("ساعات الكهرباء", has(l.power_hours) ? `${ltr(l.power_hours)} ساعة/يوم` : null),
    fact("الحالة", condLabel ? esc(condLabel) : null),
    fact("الاتجاه", has(l.direction) ? esc(DIR_AR[l.direction] || l.direction) : null),
    fact("مفروش", furnishedText),
    fact("مدة العقد", isRent && has(l.lease_months) ? `${ltr(l.lease_months)} شهر` : null),
    fact("فترة الإيجار", periodLabel ? esc(periodLabel) : null)
  ].join("");

  const amenities = Array.isArray(l.amenities) ? l.amenities.filter(Boolean) : [];

  // ── JSON-LD ─────────────────────────────────────────────────────────
  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "RealEstateListing",
    "name": title,
    "description": l.description || desc,
    "url": url,
    "datePosted": l.created_at,
    "identifier": refCode,
    ...(allPhotos.length ? { "image": allPhotos } : {}),
    "offers": {
      "@type": "Offer",
      "price": l.price_usd,
      "priceCurrency": "USD",
      "availability": "https://schema.org/InStock",
      "url": url
    },
    "address": {
      "@type": "PostalAddress",
      "addressLocality": l.area_ar || l.governorate_ar,
      "addressRegion": l.governorate_ar,
      "addressCountry": "SY"
    },
    ...(has(l.lat) && has(l.lng) ? { "geo": { "@type": "GeoCoordinates", "latitude": l.lat, "longitude": l.lng } } : {}),
    ...(has(l.area_m2) ? { "floorSize": { "@type": "QuantitativeValue", "value": l.area_m2, "unitCode": "MTK" } } : {}),
    ...(has(l.rooms) ? { "numberOfRooms": l.rooms } : {})
  };

  return `<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta name="robots" content="index, follow">
<meta name="theme-color" content="#14213D">
<link rel="canonical" href="${url}">
<meta property="og:type" content="product">
<meta property="og:site_name" content="Balkoun">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${url}">
${cover ? `<meta property="og:image" content="${esc(cover)}">` : ""}
<meta property="og:locale" content="ar_SY">
<meta name="twitter:card" content="${cover ? "summary_large_image" : "summary"}">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}">
${cover ? `<meta name="twitter:image" content="${esc(cover)}">` : ""}
<script type="application/ld+json">${jsonForScript(jsonLd)}</script>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Cairo:wght@300;400;500;600;700;800&display=swap" rel="stylesheet">
<style>
:root{--navy:#14213D;--navy-2:#0D1729;--navy-w:#EEF1F7;--gold:#C4881F;--gold-w:#FDF5E7;
--ink:#22252A;--grey:#6B7280;--light:#9CA3AF;--line:#E4E4E7;--page:#F6F6F7;--card:#FFF;
--ok:#2E7D5B;--ok-w:#EAF5EF;--f:'Cairo',system-ui,sans-serif;
--sh:0 1px 2px rgba(20,33,61,.06);--sh2:0 2px 8px rgba(20,33,61,.10)}
*{box-sizing:border-box;margin:0;padding:0}
html{-webkit-text-size-adjust:100%}
body{background:var(--page);color:var(--ink);font-family:var(--f);font-size:15px;line-height:1.8;
  -webkit-font-smoothing:antialiased;overflow-x:hidden;padding-bottom:132px}
a{color:inherit;text-decoration:none}
img{display:block;max-width:100%}
:focus-visible{outline:2px solid var(--navy);outline-offset:2px}
.ltr{direction:ltr;display:inline-block;font-variant-numeric:tabular-nums;unicode-bidi:isolate}
.wrap{max-width:1080px;margin:0 auto;padding-inline:16px}

/* top bar */
.top{background:var(--navy);color:#fff}
.top .wrap{display:flex;align-items:center;justify-content:space-between;height:56px}
.logo{padding:4px 12px;border:1px dashed rgba(255,255,255,.35);border-radius:4px;font-weight:700;font-size:19px;color:var(--gold)}
.top nav a{font-size:14.5px;color:rgba(255,255,255,.86);font-weight:600}
.top nav a:hover{color:var(--gold)}

/* page grid */
.main{padding-top:16px;display:grid;gap:16px;grid-template-columns:1fr}
.col{display:grid;gap:16px;align-content:start}

/* hero */
.hero{display:block;width:100%;aspect-ratio:16/9;border-radius:12px;overflow:hidden;background:var(--navy-2);box-shadow:var(--sh)}
.hero img{width:100%;height:100%;object-fit:cover}
.hero.ph{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;color:rgba(255,255,255,.85)}
.hero.ph span{font-size:64px;line-height:1}
.hero.ph small{font-size:15px;font-weight:600}
.thumbs{display:grid;grid-template-columns:repeat(6,1fr);gap:8px;margin-top:8px}
.thumbs a{display:block;aspect-ratio:4/3;border-radius:8px;overflow:hidden;background:var(--navy-w)}
.thumbs img{width:100%;height:100%;object-fit:cover}

/* cards */
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;box-shadow:var(--sh);padding:18px}
.card h2{font-size:17px;font-weight:700;color:var(--navy);margin-bottom:12px;padding-bottom:10px;border-bottom:1px solid var(--line);
  display:flex;align-items:center;gap:8px}
.card h2::before{content:"";width:4px;height:18px;border-radius:4px;background:var(--gold)}

/* title block */
h1{font-size:22px;line-height:1.45;font-weight:800;color:var(--navy)}
.place{color:var(--grey);font-size:14.5px;margin-top:2px}
.pricerow{display:flex;align-items:baseline;flex-wrap:wrap;gap:6px 12px;margin-top:10px}
.price{font-size:32px;font-weight:800;color:var(--gold);line-height:1.2;letter-spacing:-.5px}
.price small{font-size:15px;font-weight:600;color:var(--grey);letter-spacing:0}
.deal{font-size:15px;font-weight:700;color:var(--navy);background:var(--navy-w);padding:3px 12px;border-radius:4px}
.neg{font-size:13.5px;color:var(--grey)}
.pills{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.pill{display:inline-flex;align-items:center;font-size:13.5px;font-weight:600;padding:4px 12px;border-radius:4px;
  background:var(--navy-w);color:var(--navy);line-height:1.6}
.pill.ok{background:var(--ok-w);color:var(--ok)}
.pill.grey{background:#F0F0F2;color:var(--grey)}
.pill.gold{background:var(--gold-w);color:#8A6522}
.pill.muted{background:transparent;color:var(--light);border:1px solid var(--line);font-weight:500}

/* key facts */
.facts{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}
.fact{background:var(--page);border:1px solid var(--line);border-radius:8px;padding:10px 12px;min-width:0}
.fact .fl{display:block;font-size:13px;color:var(--grey);line-height:1.5}
.fact .fv{display:block;font-size:16px;font-weight:700;color:var(--ink);line-height:1.5;overflow-wrap:anywhere}

/* description / amenities / location */
.desc{font-size:15.5px;line-height:1.9;overflow-wrap:anywhere}
.amen{display:flex;flex-wrap:wrap;gap:8px}
.amen span{background:var(--navy-w);color:var(--navy);font-size:14px;font-weight:600;padding:5px 12px;border-radius:4px}
.loc p{margin-bottom:6px}
.loc .lm{color:var(--grey);font-size:14.5px}
.maplink{display:inline-flex;align-items:center;gap:6px;margin-top:8px;font-size:14.5px;font-weight:700;color:var(--navy);
  background:var(--navy-w);padding:8px 14px;border-radius:8px}
.maplink:hover{background:#E2E7F1}

/* contact */
.contact .who{font-size:14.5px;color:var(--grey);margin-bottom:12px}
.contact .who b{color:var(--ink);font-weight:700}
.btns{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.btn{display:flex;align-items:center;justify-content:center;gap:8px;padding:13px 14px;border-radius:8px;
  font-weight:700;font-size:15.5px;color:#fff;background:var(--navy);text-align:center;line-height:1.4}
.btn.wa{background:var(--ok)}
.btn:hover{filter:brightness(1.08)}
.btns.one{grid-template-columns:1fr}
.open{display:block;text-align:center;margin-top:12px;font-size:14.5px;font-weight:600;color:var(--navy);text-decoration:underline;text-underline-offset:3px}
.open:hover{color:var(--gold)}

/* footer */
footer{background:var(--navy-2);color:rgba(255,255,255,.8);margin-top:28px;padding:26px 0;font-size:14px}
footer .wrap{display:flex;flex-wrap:wrap;gap:8px 20px;align-items:center;justify-content:space-between}
footer .brand{font-weight:700;color:var(--gold);font-size:16px}
footer nav{display:flex;gap:18px}
footer nav a:hover{color:var(--gold)}
footer .note{width:100%;color:rgba(255,255,255,.5);font-size:13px}

/* phones: contact card sticks to the bottom */
@media(max-width:899px){
  .contact{position:fixed;bottom:0;left:0;right:0;z-index:10;border-radius:12px 12px 0 0;
    padding:12px 16px calc(12px + env(safe-area-inset-bottom));box-shadow:0 -4px 16px rgba(20,33,61,.12)}
  .contact h2,.contact .who{display:none}
  .btn{padding:12px 10px}
  .open{margin-top:8px;font-size:14px}
  .thumbs{grid-template-columns:repeat(3,1fr)}
}
/* tablets and up */
@media(min-width:720px){
  .facts{grid-template-columns:repeat(4,1fr)}
  h1{font-size:26px}
  .price{font-size:36px}
}
/* desktop: two columns, contact card sticky in the side column */
@media(min-width:900px){
  body{padding-bottom:0}
  .main{grid-template-columns:minmax(0,1fr) 340px;align-items:start;padding-top:22px;gap:22px}
  .side{position:sticky;top:22px}
  .thumbs{grid-template-columns:repeat(6,1fr)}
}
</style></head><body>
<header class="top"><div class="wrap">
  <a class="logo" href="${SITE}/">بلكون</a>
  <nav><a href="${SITE}/search">كل الإعلانات</a></nav>
</div></header>

<main class="wrap main">
<div class="col">
  <section>
    ${hero}
    ${thumbStrip}
  </section>

  <section class="card">
    <h1>${esc(typeLabel)} ${esc(dealLabel)} — ${ltr(l.area_m2)} م²${place ? ` في ${esc(place)}` : ""}</h1>
    ${place ? `<div class="place">${esc(place)}</div>` : ""}
    <div class="pricerow">
      <span class="price">${ltr(money(l.price_usd))}${periodLabel ? `<small> / ${esc(periodLabel)}</small>` : ""}</span>
      <span class="deal">${esc(dealLabel)}</span>
      ${l.price_negotiable ? `<span class="neg">قابل للتفاوض</span>` : ""}
    </div>
    <div class="pills">${pills}</div>
  </section>

  ${facts ? `<section class="card"><h2>التفاصيل</h2><div class="facts">${facts}</div></section>` : ""}

  ${l.description ? `<section class="card"><h2>الوصف</h2><div class="desc">${nl2br(l.description)}</div></section>` : ""}

  ${amenities.length ? `<section class="card"><h2>المرافق</h2><div class="amen">${amenities.map(a => `<span>${esc(a)}</span>`).join("")}</div></section>` : ""}

  <section class="card loc">
    <h2>الموقع</h2>
    <p><b>${esc(gov)}</b>${areaName ? ` — ${esc(areaName)}` : ""}</p>
    ${l.landmark ? `<p class="lm">${esc(l.landmark)}</p>` : ""}
    ${osm ? `<a class="maplink" href="${osm}" target="_blank" rel="noopener">📍 عرض على الخريطة (OpenStreetMap)</a>` : ""}
  </section>
</div>

<aside class="col side">
  <section class="card contact">
    <h2>تواصل مع المالك</h2>
    ${contactName ? `<p class="who">الإعلان من: <b>${esc(contactName)}</b>${l.by_owner ? " · المالك مباشرة" : ""}</p>` : ""}
    <div class="btns${wa && tel ? "" : " one"}">
      ${wa ? `<a class="btn wa" href="${esc(wa)}" target="_blank" rel="noopener">واتساب</a>` : ""}
      ${tel ? `<a class="btn" href="${esc(tel)}">اتصل</a>` : ""}
    </div>
    <a class="open" href="${appUrl}">افتح الإعلان الكامل في الموقع</a>
  </section>
</aside>
</main>

<footer><div class="wrap">
  <span class="brand">بلكون — عقارات سوريا من المالك مباشرة</span>
  <nav><a href="${SITE}/about">من نحن</a><a href="${SITE}/contactus">اتصل بنا</a></nav>
  <span class="note">صفحات الإعلانات تُحدَّث تلقائياً من قاعدة بيانات بلكون. الرقم المرجعي ${ltr(refCode)}.</span>
</div></footer>
</body></html>`;
}

async function main() {
  console.log("Fetching live listings from Supabase…");
  let listings;
  try {
    listings = await sb("v_listings?select=*&status=eq.live&order=created_at.desc");
  } catch (e) {
    console.error("Fetch failed:", e.message);
    process.exit(1);
  }
  console.log(`Found ${listings.length} live listing(s).`);

  fs.rmSync(OUT_DIR, { recursive: true, force: true });
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const urls = [`${SITE}/`];

  for (const l of listings) {
    let photoRows = [];
    try {
      photoRows = await sb(`listing_photos?select=url&listing_id=eq.${l.id}&order=sort_order`);
    } catch (e) {
      console.warn(`Photos fetch failed for listing ${l.id}:`, e.message);
    }
    const photos = photoRows.map(p => p.url);

    const typeLabel = TYPE_AR[l.property_type] || l.property_type;
    const slug = `${l.id}-${slugify(typeLabel + " " + (l.area_ar||"") + " " + l.governorate_ar)}`;
    const dir = path.join(OUT_DIR, slug);
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, "index.html"), renderPage(l, photos));
    urls.push(`${SITE}/listing/${slug}/`);
  }

  const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map(u => `  <url><loc>${u}</loc><changefreq>daily</changefreq></url>`).join("\n")}
</urlset>`;
  fs.writeFileSync(SITEMAP_PATH, sitemap);

  console.log(`Wrote ${listings.length} listing page(s) and sitemap.xml with ${urls.length} URL(s).`);
}

main();
