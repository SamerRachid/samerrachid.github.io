// ════════════════════════════════════════════════════════════════════
//  BALKOUN · static listing page generator (three languages)
//
//  Runs in GitHub Actions on a schedule. Reads every live listing from
//  Supabase and writes a real, crawlable HTML page for each one at
//    /listing/<id>-<arabic-slug>/index.html          (Arabic)
//    /en/listing/<id>-<latin-slug>/index.html        (English)
//    /de/listing/<id>-<latin-slug>/index.html        (German)
//  each linking to the other two with hreflang. A listing in another enabled
//  country (see the `countries` table) gets the same three pages under /<code>/,
//  e.g. /lb/listing/…, /lb/en/listing/…. generate-pages.mjs runs
//  afterwards and writes the sitemap that lists all of them.
//
//  Nothing here needs a server — it's a build step. GitHub Pages just
//  serves whatever files exist in the repo, and this script is what
//  keeps those files in sync with your database.
// ════════════════════════════════════════════════════════════════════
import fs from "fs";
import path from "path";
import vm from "vm";

const SUPABASE_URL = "https://coajrqynjrptujmzjjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t"; // public anon key — safe, RLS restricts it to live listings
const SITE = "https://balkoun.com";
const ROOT = path.resolve(".");
let CUR_PRE = "", CUR_CN = { code: "SY", ar: "سوريا", en: "Syria", de: "Syrien" };   // the current listing's country: URL prefix and names

async function sb(endpoint) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } });
  if (!res.ok) throw new Error(`Supabase request failed (${res.status}): ${endpoint}`);
  return res.json();
}

// the app's own label tables (property types, deed status, condition) so every language matches the site
function loadAppData() {
  const src = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const line = src.split("\n").find((l) => /^var D\s*=\s*\{/.test(l));
  const sandbox = {}; vm.runInNewContext(line.replace(/^var D\s*=/, "D=").replace(/;\s*$/, ""), sandbox); return sandbox.D;
}
const D = loadAppData();
const LI = { ar: 0, en: 1, de: 2 };
const LANGS = { ar: { dir: "rtl", prefix: "", og: "ar_SY" }, en: { dir: "ltr", prefix: "/en", og: "en_US" }, de: { dir: "ltr", prefix: "/de", og: "de_DE" } };

// TYPE_AR feeds the Arabic folder slug. Do NOT rename existing keys or values
// here — that would move every already-indexed URL.
const TYPE_AR = { apartment:"شقة", arab:"بيت عربي", villa:"فيلا", floor:"طابق كامل", building:"بناء كامل", shop:"محل تجاري", office:"مكتب", resid:"أرض سكنية", agri:"أرض زراعية", comm:"أرض تجارية" };
const TYPE_ICON = { apartment:"🏢", arab:"🏛️", villa:"🏡", floor:"🏢", building:"🏬", chalet:"🏖️", farm:"🌾", shop:"🏪", office:"🏢", land:"🗺️", restaurant:"🍽️", warehouse:"🏭", factory:"🏭", resid:"🗺️", agri:"🌱", comm:"🗺️" };
const typeName = (k, lang) => (D.TYPES[k] ? D.TYPES[k][LI[lang]] : (TYPE_AR[k] || k));
const tabuName = (k, lang) => (D.TABU[k] ? D.TABU[k][LI[lang]] : (k === "none" ? { ar: "بدون طابو", en: "No deed", de: "Kein Grundbuch" }[lang] : k));
const condName = (k, lang) => (D.COND[k] ? D.COND[k][LI[lang]] : (D.LANDC && D.LANDC[k] ? D.LANDC[k][LI[lang]] : k));
const DIR = { s:["قبلي (جنوبي)","South","Süd"], n:["شمالي","North","Nord"], e:["شرقي","East","Ost"], w:["غربي","West","West"], se:["قبلي شرقي","South-east","Südost"], sw:["قبلي غربي","South-west","Südwest"], ne:["شمالي شرقي","North-east","Nordost"], nw:["شمالي غربي","North-west","Nordwest"] };
const PERIOD = { yearly:["سنوي","year","Jahr"], monthly:["شهري","month","Monat"], weekly:["أسبوعي","week","Woche"], daily:["يومي","day","Tag"] };
const S = {
  ar: { home:"الرئيسية", forSale:"للبيع", forRent:"للإيجار", inPlace:(p)=>`في ${p}`, allListings:"كل الإعلانات", details:"التفاصيل", desc:"الوصف", amen:"المرافق", location:"الموقع", onMap:"عرض على الخريطة (OpenStreetMap)", contact:"تواصل مع المالك", from:"الإعلان من", byOwner:"المالك مباشرة", wa:"واتساب", call:"اتصل", openApp:"افتح الإعلان الكامل في الموقع", negotiable:"قابل للتفاوض", ownerPill:"من المالك",
    area:"مساحة", rooms:"غرف", baths:"حمّامات", living:"صالونات", floor:"الطابق", ground:"أرضي", of:"من", year:"سنة البناء", power:"ساعات الكهرباء", hday:"ساعة/يوم", cond:"الحالة", dir:"الاتجاه", furnished:"مفروش", unfurnished:"غير مفروش", lease:"مدة العقد", months:"شهر", period:"فترة الإيجار", photoN:(n)=>`صورة ${n}`,
    about:"من نحن", contactUs:"اتصل بنا", brandLine:"بلكون — عقارات سوريا من المالك مباشرة", note:(r)=>`صفحات الإعلانات تُحدَّث تلقائياً من قاعدة بيانات بلكون. الرقم المرجعي ${r}.`, waText:(t,u)=>`مرحبا، مهتم بهذا العقار: ${t}\n${u}`, roomsShort:"غرف", sqm:"م²", sep:"، ", langs:"اللغات", descNote:"" },
  en: { home:"Home", forSale:"for sale", forRent:"for rent", inPlace:(p)=>`in ${p}`, allListings:"All listings", details:"Details", desc:"Description", amen:"Amenities", location:"Location", onMap:"Show on the map (OpenStreetMap)", contact:"Contact the owner", from:"Listed by", byOwner:"owner, no agent", wa:"WhatsApp", call:"Call", openApp:"Open the full listing in the app", negotiable:"negotiable", ownerPill:"Direct from owner",
    area:"Size", rooms:"Rooms", baths:"Bathrooms", living:"Living rooms", floor:"Floor", ground:"Ground", of:"of", year:"Year built", power:"Electricity", hday:"h/day", cond:"Condition", dir:"Facing", furnished:"Furnished", unfurnished:"Unfurnished", lease:"Lease", months:"months", period:"Rental period", photoN:(n)=>`photo ${n}`,
    about:"About", contactUs:"Contact", brandLine:"Balkoun — real estate in Syria, direct from owners", note:(r)=>`Listing pages are generated automatically from the Balkoun database. Reference ${r}.`, waText:(t,u)=>`Hello, I am interested in this property: ${t}\n${u}`, roomsShort:"rooms", sqm:"m²", sep:", ", langs:"Languages", descNote:"Description in the owner's words (Arabic):" },
  de: { home:"Start", forSale:"zum Kauf", forRent:"zur Miete", inPlace:(p)=>`in ${p}`, allListings:"Alle Anzeigen", details:"Details", desc:"Beschreibung", amen:"Ausstattung", location:"Lage", onMap:"Auf der Karte zeigen (OpenStreetMap)", contact:"Eigentümer kontaktieren", from:"Anbieter", byOwner:"direkt vom Eigentümer", wa:"WhatsApp", call:"Anrufen", openApp:"Vollständige Anzeige in der App öffnen", negotiable:"verhandelbar", ownerPill:"Direkt vom Eigentümer",
    area:"Fläche", rooms:"Zimmer", baths:"Bäder", living:"Wohnzimmer", floor:"Etage", ground:"EG", of:"von", year:"Baujahr", power:"Strom", hday:"Std./Tag", cond:"Zustand", dir:"Ausrichtung", furnished:"Möbliert", unfurnished:"Unmöbliert", lease:"Mietdauer", months:"Monate", period:"Mietzeitraum", photoN:(n)=>`Foto ${n}`,
    about:"Über uns", contactUs:"Kontakt", brandLine:"Balkoun — Immobilien in Syrien, direkt vom Eigentümer", note:(r)=>`Anzeigenseiten werden automatisch aus der Balkoun-Datenbank erzeugt. Referenz ${r}.`, waText:(t,u)=>`Hallo, ich interessiere mich für diese Immobilie: ${t}\n${u}`, roomsShort:"Zimmer", sqm:"m²", sep:", ", langs:"Sprachen", descNote:"Beschreibung des Eigentümers (Arabisch):" },
};

const slugAr = (s) => String(s || "").replace(/[^\p{L}\p{N}\s-]/gu, "").trim().replace(/\s+/g, "-").slice(0, 60);
const slugLatin = (s) => String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9\s-]/g, "").trim().replace(/\s+/g, "-").slice(0, 60);
const esc = (s) => String(s ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
const money = (v) => "$" + Number(v).toLocaleString("en");
const has = (v) => v !== null && v !== undefined && v !== "";
const ltr = (s) => `<span class="ltr">${esc(s)}</span>`;
const nl2br = (s) => esc(s).replace(/\r\n|\r|\n/g, "<br>");
const pill = (text, cls) => `<span class="pill ${cls || ""}">${text}</span>`;
const fact = (label, value) => has(value) ? `<div class="fact"><span class="fl">${esc(label)}</span><span class="fv">${value}</span></div>` : "";
const jsonForScript = (obj) => JSON.stringify(obj).replace(/</g, "\\u003c");

let govById = new Map(), areaById = new Map();
const govName = (l, lang) => { const g = govById.get(l.governorate_id); if (lang === "ar" || !g) return l.governorate_ar; return lang === "en" ? (g.name_en || (D.GOVN[g.name_ar] || [])[0] || g.name_ar) : ((D.GOVN[g.name_ar] || [])[1] || g.name_en || g.name_ar); };
const titleSlug = (s) => String(s || "").split("-").filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");
const areaNm = (l, lang) => { if (lang === "ar") return l.area_ar || ""; const a = areaById.get(l.area_id); return a ? (a.name_en || titleSlug(a.slug) || a.name_ar) : ""; };
// folder per language — generate-pages.mjs builds the same URLs, keep them in step
function slugFor(l, lang) {
  if (lang === "ar") return `${l.id}-${slugAr((TYPE_AR[l.property_type] || l.property_type) + " " + (l.area_ar || "") + " " + l.governorate_ar)}`;
  return `${l.id}-${slugLatin(typeName(l.property_type, "en") + " " + areaNm(l, "en") + " " + govName(l, "en"))}`;
}
const urlFor = (l, lang) => `${SITE}${CUR_PRE}${LANGS[lang].prefix}/listing/${slugFor(l, lang)}/`;
const appLink = (lang, p) => `${SITE}${CUR_PRE}/${p}${lang === "ar" ? "" : `?lang=${lang}`}`;
const MARK = `<svg viewBox="0 0 100 100" aria-hidden="true"><rect x="19" y="19" width="62" height="62" fill="none" stroke="currentColor" stroke-width="7"/><path d="M50 5 95 50 50 95 5 50Z" fill="none" stroke="#C4881F" stroke-width="9"/><rect x="42.5" y="42.5" width="15" height="15" fill="currentColor"/></svg>`;

function renderPage(l, photos, lang) {
  const W = S[lang], L = LANGS[lang];
  const typeLabel = typeName(l.property_type, lang);
  const typeIcon = TYPE_ICON[l.property_type] || "🏠";
  const tabuLabel = l.tabu ? tabuName(l.tabu, lang) : "";
  const condLabel = l.condition ? condName(l.condition, lang) : "";
  const isRent = l.deal === "rent";
  const dealLabel = isRent ? W.forRent : W.forSale;
  const periodLabel = isRent && l.rental_period ? (PERIOD[l.rental_period] ? PERIOD[l.rental_period][LI[lang]] : l.rental_period) : "";
  const areaName = areaNm(l, lang), gov = govName(l, lang);
  const place = [areaName, gov].filter(Boolean).join(W.sep);

  const sizeTxt = has(l.area_m2) ? `${l.area_m2} ${W.sqm}` : "";
  const title = lang === "ar" ? `${typeLabel} ${dealLabel} ${sizeTxt} — ${areaName} ${gov} | بلكون`
    : `${typeLabel} ${dealLabel}${sizeTxt ? `, ${sizeTxt}` : ""} ${W.inPlace(place)}, ${CUR_CN[lang] || CUR_CN.en} | Balkoun`;
  const leadBits = [`${typeLabel} ${dealLabel} ${W.inPlace(place)}`, sizeTxt, has(l.rooms) ? `${l.rooms} ${W.roomsShort}` : "", tabuLabel, money(l.price_usd)].filter(Boolean);
  const lead = leadBits.join(W.sep) + ".";
  const ownText = (l.description || "").replace(/\s+/g, " ").trim();
  const desc = (lead + (lang === "ar" && ownText ? " " + ownText : "")).slice(0, 155);

  const url = urlFor(l, lang);
  const alts = { ar: urlFor(l, "ar"), en: urlFor(l, "en"), de: urlFor(l, "de") };
  const appUrl = appLink(lang, `listing/${l.id}`);

  const allPhotos = photos.length ? photos : (l.cover_url ? [l.cover_url] : []);
  const cover = allPhotos[0] || "";
  const thumbs = allPhotos.slice(1, 7);

  const phoneDigits = (l.contact_phone || "").replace(/\D/g, "");
  const tel = phoneDigits ? `tel:+${phoneDigits}` : null;
  const wa = phoneDigits && l.accepts_whatsapp !== false ? `https://wa.me/${phoneDigits}?text=${encodeURIComponent(W.waText(title, url))}` : null;
  const contactName = l.contact_name || l.owner_name || "";
  const refCode = `BK-${l.id}`;
  const osm = has(l.lat) && has(l.lng) ? `https://www.openstreetmap.org/?mlat=${encodeURIComponent(l.lat)}&mlon=${encodeURIComponent(l.lng)}#map=16/${encodeURIComponent(l.lat)}/${encodeURIComponent(l.lng)}` : null;

  const hero = cover
    ? `<a class="hero" href="${esc(cover)}" target="_blank" rel="noopener"><img src="${esc(cover)}" alt="${esc(title)}" width="1080" height="608" fetchpriority="high"></a>`
    : `<div class="hero ph" role="img" aria-label="${esc(typeLabel)}"><span>${typeIcon}</span><small>${esc(typeLabel)}</small></div>`;
  const thumbStrip = thumbs.length ? `<div class="thumbs">${thumbs.map((p, i) => `<a href="${esc(p)}" target="_blank" rel="noopener"><img src="${esc(p)}" alt="${esc(typeLabel)} — ${W.photoN(i + 2)}" loading="lazy"></a>`).join("")}</div>` : "";

  const pills = [tabuLabel ? pill(esc(tabuLabel), l.tabu === "green" ? "ok" : "grey") : "", l.by_owner ? pill(W.ownerPill, "gold") : "", pill(ltr(refCode), "muted")].filter(Boolean).join("");

  const floorText = has(l.floor) ? (Number(l.floor) === 0 ? W.ground : ltr(l.floor)) + (has(l.floors_total) ? ` ${W.of} ${ltr(l.floors_total)}` : "") : null;
  const furnishedText = typeof l.furnished === "boolean" ? (l.furnished ? W.furnished : W.unfurnished) : (has(l.furnished) ? esc(l.furnished) : null);
  const facts = [
    fact(W.area, has(l.area_m2) ? `${ltr(l.area_m2)} ${W.sqm}` : null),
    fact(W.rooms, has(l.rooms) ? ltr(l.rooms) : null),
    fact(W.baths, has(l.baths) ? ltr(l.baths) : null),
    fact(W.living, has(l.living_rooms) ? ltr(l.living_rooms) : null),
    fact(W.floor, floorText),
    fact(W.year, has(l.year_built) ? ltr(l.year_built) : null),
    fact(W.power, has(l.power_hours) ? `${ltr(l.power_hours)} ${W.hday}` : null),
    fact(W.cond, condLabel ? esc(condLabel) : null),
    fact(W.dir, has(l.direction) ? esc(DIR[l.direction] ? DIR[l.direction][LI[lang]] : l.direction) : null),
    fact(W.furnished, furnishedText),
    fact(W.lease, isRent && has(l.lease_months) ? `${ltr(l.lease_months)} ${W.months}` : null),
    fact(W.period, periodLabel ? esc(periodLabel) : null),
  ].join("");
  const amenities = Array.isArray(l.amenities) ? l.amenities.filter(Boolean) : [];

  const jsonLd = {
    "@context": "https://schema.org", "@type": "RealEstateListing", "name": title, "description": l.description || desc, "url": url, "inLanguage": lang,
    "datePosted": l.created_at, "identifier": refCode, ...(allPhotos.length ? { "image": allPhotos } : {}),
    "offers": { "@type": "Offer", "price": l.price_usd, "priceCurrency": "USD", "availability": "https://schema.org/InStock", "url": url },
    "address": { "@type": "PostalAddress", "addressLocality": areaName || gov, "addressRegion": gov, "addressCountry": CUR_CN.code },
    ...(has(l.lat) && has(l.lng) ? { "geo": { "@type": "GeoCoordinates", "latitude": l.lat, "longitude": l.lng } } : {}),
    ...(has(l.area_m2) ? { "floorSize": { "@type": "QuantitativeValue", "value": l.area_m2, "unitCode": "MTK" } } : {}),
    ...(has(l.rooms) ? { "numberOfRooms": l.rooms } : {}),
    ...((l.videos || []).length ? { "video": (l.videos || []).map((v) => ({ "@type": "VideoObject", "name": title, "description": lead, "contentUrl": v.url, ...(v.thumb_url ? { "thumbnailUrl": v.thumb_url } : {}), "uploadDate": l.created_at })) } : {}),
  };
  const langBar = `<nav class="langs" aria-label="${W.langs}">${["ar", "en", "de"].map((k) => `<a href="${alts[k]}" hreflang="${k}" class="${k === lang ? "on" : ""}">${k === "ar" ? "عربي" : k.toUpperCase()}</a>`).join("")}</nav>`;

  return `<!DOCTYPE html><html lang="${lang}" dir="${L.dir}"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta name="robots" content="index, follow">
<meta name="theme-color" content="#14213D">
<link rel="canonical" href="${url}">
${["ar", "en", "de"].map((k) => `<link rel="alternate" hreflang="${k}" href="${alts[k]}">`).join("\n")}
<link rel="alternate" hreflang="x-default" href="${alts.ar}">
<meta property="og:type" content="product">
<meta property="og:site_name" content="Balkoun">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${url}">
<meta property="og:image" content="${esc(cover || SITE + "/brand/og-image.png")}">
<meta property="og:locale" content="${L.og}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}">
<meta name="twitter:image" content="${esc(cover || SITE + "/brand/og-image.png")}">
<link rel="icon" type="image/svg+xml" href="${SITE}/brand/favicon.svg"><link rel="apple-touch-icon" href="${SITE}/brand/apple-touch-icon.png">
<script type="application/ld+json">${jsonForScript(jsonLd)}</script>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Noto+Kufi+Arabic:wght@400;500;600;700;800&family=Lato:wght@400;700;900&display=swap" rel="stylesheet">
<style>
:root{--navy:#14213D;--navy-2:#0D1729;--navy-w:#EEF1F7;--gold:#C4881F;--gold-w:#FDF5E7;
--ink:#22252A;--grey:#6B7280;--light:#9CA3AF;--line:#E4E4E7;--page:#F6F6F7;--card:#FFF;
--ok:#2E7D5B;--ok-w:#EAF5EF;--f:'Noto Kufi Arabic','Lato',system-ui,sans-serif;
--sh:0 1px 2px rgba(20,33,61,.06);--sh2:0 2px 8px rgba(20,33,61,.10)}
html[lang=en],html[lang=de]{--f:'Lato','Noto Kufi Arabic',system-ui,sans-serif}
*{box-sizing:border-box;margin:0;padding:0}
html{-webkit-text-size-adjust:100%}
body{background:var(--page);color:var(--ink);font-family:var(--f);font-size:15px;line-height:1.8;-webkit-font-smoothing:antialiased;overflow-x:hidden;padding-bottom:132px}
a{color:inherit;text-decoration:none}
img{display:block;max-width:100%}
:focus-visible{outline:2px solid var(--navy);outline-offset:2px}
.ltr{direction:ltr;display:inline-block;font-variant-numeric:tabular-nums;unicode-bidi:isolate}
.wrap{max-width:1080px;margin:0 auto;padding-inline:16px}
.top{background:var(--navy);color:#fff}
.top .wrap{display:flex;align-items:center;justify-content:space-between;height:56px;direction:ltr;gap:12px}
.logo{display:inline-flex;align-items:center;gap:6px;color:#CFC4AE;flex-direction:row-reverse;margin-left:auto}
.logo svg{width:34px;height:34px}.logo .w{display:flex;flex-direction:column;align-items:flex-end;line-height:1}.logo .w b{font:800 20px/1 'Noto Kufi Arabic',sans-serif}.logo .w small{font:700 8.5px 'Lato',sans-serif;letter-spacing:.34em;color:#9DB0CC;margin-top:3px}
.top nav{display:flex;gap:14px}.top nav a{font-size:14.5px;color:rgba(255,255,255,.86);font-weight:600}
.top nav a:hover{color:var(--gold)}
.langs{display:flex;gap:6px;font-size:12px}.langs a{padding:3px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.22);color:rgba(255,255,255,.8);font-weight:600}.langs a.on{background:rgba(255,255,255,.14);color:#fff}
.main{padding-top:16px;display:grid;gap:16px;grid-template-columns:1fr}
.col{display:grid;gap:16px;align-content:start}
.hero{display:block;width:100%;aspect-ratio:16/9;border-radius:12px;overflow:hidden;background:var(--navy-2);box-shadow:var(--sh)}
.hero img{width:100%;height:100%;object-fit:cover}
.hero.ph{display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;color:rgba(255,255,255,.85)}
.hero.ph span{font-size:64px;line-height:1}.hero.ph small{font-size:15px;font-weight:600}
.thumbs{display:grid;grid-template-columns:repeat(6,1fr);gap:8px;margin-top:8px}
.thumbs a{display:block;aspect-ratio:4/3;border-radius:8px;overflow:hidden;background:var(--navy-w)}
.thumbs img{width:100%;height:100%;object-fit:cover}
.lvid{display:block;width:100%;max-height:440px;margin-top:10px;border-radius:12px;background:#000}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;box-shadow:var(--sh);padding:18px}
.card h2{font-size:17px;font-weight:700;color:var(--navy);margin-bottom:12px;padding-bottom:10px;border-bottom:1px solid var(--line);display:flex;align-items:center;gap:8px}
.card h2::before{content:"";width:4px;height:18px;border-radius:4px;background:var(--gold)}
h1{font-size:22px;line-height:1.45;font-weight:800;color:var(--navy)}
.place{color:var(--grey);font-size:14.5px;margin-top:2px}
.pricerow{display:flex;align-items:baseline;flex-wrap:wrap;gap:6px 12px;margin-top:10px}
.price{font-size:32px;font-weight:800;color:var(--gold);line-height:1.2;letter-spacing:-.5px}
.price small{font-size:15px;font-weight:600;color:var(--grey);letter-spacing:0}
.deal{font-size:15px;font-weight:700;color:var(--navy);background:var(--navy-w);padding:3px 12px;border-radius:4px}
.neg{font-size:13.5px;color:var(--grey)}
.pills{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
.pill{display:inline-flex;align-items:center;font-size:13.5px;font-weight:600;padding:4px 12px;border-radius:4px;background:var(--navy-w);color:var(--navy);line-height:1.6}
.pill.ok{background:var(--ok-w);color:var(--ok)}.pill.grey{background:#F0F0F2;color:var(--grey)}.pill.gold{background:var(--gold-w);color:#8A6522}.pill.muted{background:transparent;color:var(--light);border:1px solid var(--line);font-weight:500}
.facts{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}
.fact{background:var(--page);border:1px solid var(--line);border-radius:8px;padding:10px 12px;min-width:0}
.fact .fl{display:block;font-size:13px;color:var(--grey);line-height:1.5}
.fact .fv{display:block;font-size:16px;font-weight:700;color:var(--ink);line-height:1.5;overflow-wrap:anywhere}
.desc{font-size:15.5px;line-height:1.9;overflow-wrap:anywhere}.desc.ar{direction:rtl;text-align:right;font-family:'Noto Kufi Arabic',sans-serif}.descnote{font-size:12.5px;color:var(--light);margin-bottom:6px}
.amen{display:flex;flex-wrap:wrap;gap:8px}
.amen span{background:var(--navy-w);color:var(--navy);font-size:14px;font-weight:600;padding:5px 12px;border-radius:4px}
.loc p{margin-bottom:6px}.loc .lm{color:var(--grey);font-size:14.5px}
.maplink{display:inline-flex;align-items:center;gap:6px;margin-top:8px;font-size:14.5px;font-weight:700;color:var(--navy);background:var(--navy-w);padding:8px 14px;border-radius:8px}
.maplink:hover{background:#E2E7F1}
.contact .who{font-size:14.5px;color:var(--grey);margin-bottom:12px}.contact .who b{color:var(--ink);font-weight:700}
.btns{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.btn{display:flex;align-items:center;justify-content:center;gap:8px;padding:13px 14px;border-radius:8px;font-weight:700;font-size:15.5px;color:#fff;background:var(--navy);text-align:center;line-height:1.4}
.btn.wa{background:var(--ok)}.btn:hover{filter:brightness(1.08)}.btns.one{grid-template-columns:1fr}
.open{display:block;text-align:center;margin-top:12px;font-size:14.5px;font-weight:600;color:var(--navy);text-decoration:underline;text-underline-offset:3px}
.open:hover{color:var(--gold)}
footer{background:var(--navy-2);color:rgba(255,255,255,.8);margin-top:28px;padding:26px 0;font-size:14px}
footer .wrap{display:flex;flex-wrap:wrap;gap:8px 20px;align-items:center;justify-content:space-between}
footer .brand{font-weight:700;color:var(--gold);font-size:16px}
footer nav{display:flex;gap:18px}footer nav a:hover{color:var(--gold)}
footer .note{width:100%;color:rgba(255,255,255,.5);font-size:13px}
@media(max-width:899px){
  .contact{position:fixed;bottom:0;left:0;right:0;z-index:10;border-radius:12px 12px 0 0;padding:12px 16px calc(12px + env(safe-area-inset-bottom));box-shadow:0 -4px 16px rgba(20,33,61,.12)}
  .contact h2,.contact .who{display:none}.btn{padding:12px 10px}.open{margin-top:8px;font-size:14px}.thumbs{grid-template-columns:repeat(3,1fr)}
}
@media(min-width:720px){.facts{grid-template-columns:repeat(4,1fr)}h1{font-size:26px}.price{font-size:36px}}
@media(min-width:900px){body{padding-bottom:0}.main{grid-template-columns:minmax(0,1fr) 340px;align-items:start;padding-top:22px;gap:22px}.side{position:sticky;top:22px}.thumbs{grid-template-columns:repeat(6,1fr)}}
</style></head><body>
<header class="top"><div class="wrap">
  <nav><a href="${lang === "ar" ? SITE + CUR_PRE + "/" : `${SITE}${CUR_PRE}/?lang=${lang}`}">${W.home}</a><a href="${appLink(lang, "search")}">${W.allListings}</a></nav>
  ${langBar}
  <a class="logo" href="${lang === "ar" ? SITE + CUR_PRE + "/" : `${SITE}${CUR_PRE}/?lang=${lang}`}" aria-label="Balkoun">${MARK}<span class="w"><b>بلكون</b><small>BALKOUN</small></span></a>
</div></header>

<main class="wrap main">
<div class="col">
  <section>${hero}${thumbStrip}${(l.videos || []).map((v) => `<video class="lvid" controls preload="none" playsinline${v.thumb_url ? ` poster="${esc(v.thumb_url)}"` : ""} src="${esc(v.url)}"></video>`).join("")}</section>
  <section class="card">
    <h1>${esc(typeLabel)} ${esc(dealLabel)}${sizeTxt ? ` — ${ltr(l.area_m2)} ${W.sqm}` : ""}${place ? ` ${esc(W.inPlace(place))}` : ""}</h1>
    ${place ? `<div class="place">${esc(place)}</div>` : ""}
    <div class="pricerow"><span class="price">${ltr(money(l.price_usd))}${periodLabel ? `<small> / ${esc(periodLabel)}</small>` : ""}</span><span class="deal">${esc(dealLabel)}</span>${l.price_negotiable ? `<span class="neg">${W.negotiable}</span>` : ""}</div>
    <div class="pills">${pills}</div>
  </section>
  ${facts ? `<section class="card"><h2>${W.details}</h2><div class="facts">${facts}</div></section>` : ""}
  ${l.description ? `<section class="card"><h2>${W.desc}</h2>${lang !== "ar" ? `<p class="descnote">${W.descNote}</p>` : ""}<div class="desc${lang !== "ar" ? " ar" : ""}" ${lang !== "ar" ? 'lang="ar"' : ""}>${nl2br(l.description)}</div></section>` : ""}
  ${amenities.length ? `<section class="card"><h2>${W.amen}</h2><div class="amen">${amenities.map((a) => `<span>${esc(a)}</span>`).join("")}</div></section>` : ""}
  <section class="card loc"><h2>${W.location}</h2><p><b>${esc(gov)}</b>${areaName ? ` — ${esc(areaName)}` : ""}</p>${l.landmark ? `<p class="lm">${esc(l.landmark)}</p>` : ""}${osm ? `<a class="maplink" href="${osm}" target="_blank" rel="noopener">📍 ${W.onMap}</a>` : ""}</section>
</div>
<aside class="col side">
  <section class="card contact"><h2>${W.contact}</h2>
    ${contactName ? `<p class="who">${W.from}: <b>${esc(contactName)}</b>${l.by_owner ? ` · ${W.byOwner}` : ""}</p>` : ""}
    <div class="btns${wa && tel ? "" : " one"}">${wa ? `<a class="btn wa" href="${esc(wa)}" target="_blank" rel="noopener">${W.wa}</a>` : ""}${tel ? `<a class="btn" href="${esc(tel)}">${W.call}</a>` : ""}</div>
    <a class="open" href="${appUrl}">${W.openApp}</a>
  </section>
</aside>
</main>
<footer><div class="wrap">
  <span class="brand">${W.brandLine.replace(/سوريا|Syria|Syrien/, CUR_CN[lang] || CUR_CN.en)}</span>
  <nav><a href="${SITE}${CUR_PRE}${LANGS[lang].prefix}/about/">${W.about}</a><a href="${SITE}${CUR_PRE}${LANGS[lang].prefix}/contactus/">${W.contactUs}</a></nav>
  <span class="note">${W.note(ltr(refCode))}</span>
</div></footer>
</body></html>`;
}

async function main() {
  console.log("Fetching live listings from Supabase…");
  let listings, govs, areas;
  try {
    [listings, govs, areas] = await Promise.all([
      sb("v_listings?select=*&status=eq.live&order=created_at.desc"),
      sb("governorates?select=id,name_ar,name_en,slug"),
      sb("areas?select=id,governorate_id,name_ar,name_en,slug&limit=5000"),
    ]);
  } catch (e) { console.error("Fetch failed:", e.message); process.exit(1); }
  govById = new Map(govs.map((g) => [g.id, g])); areaById = new Map(areas.map((a) => [a.id, a]));
  console.log(`Found ${listings.length} live listing(s).`);
  let countries = [];
  try { countries = await sb("countries?select=code,name_ar,name_en,name_de,enabled,is_default&order=sort_order.asc"); if (!Array.isArray(countries) || !countries.length) throw new Error("empty list"); }
  catch (e) { console.warn("countries unreadable, Syria only:", e.message); countries = [{ code: "SY", name_ar: "سوريا", name_en: "Syria", name_de: "Syrien", enabled: true, is_default: true }]; }
  if (!countries.some((c) => c.is_default)) countries.forEach((c) => { if (c.code === "SY") c.is_default = true; });
  const CTRY = new Map(countries.filter((c) => c.enabled).map((c) => [c.code, { prefix: c.is_default ? "" : "/" + c.code.toLowerCase(), cn: { code: c.code, ar: c.name_ar, en: c.name_en, de: c.name_de || c.name_en } }]));

  for (const ctx of CTRY.values()) for (const lang of ["ar", "en", "de"]) { const dir = path.join(ROOT, ctx.prefix.replace(/^\//, ""), LANGS[lang].prefix.replace(/^\//, ""), "listing"); fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true }); }

  let n = 0;
  for (const l of listings) {
    const ctx = CTRY.get(l.country_code || "SY"); if (!ctx) continue;   // a listing in a country that is switched off gets no page
    CUR_PRE = ctx.prefix; CUR_CN = ctx.cn;
    let photoRows = [];
    try { photoRows = await sb(`listing_photos?select=url,thumb_url,kind&listing_id=eq.${l.id}&order=sort_order`); } catch (e) { console.warn(`Photos fetch failed for listing ${l.id}:`, e.message); }
    const photos = photoRows.filter((p) => p.kind !== "video").map((p) => p.url);
    l.videos = photoRows.filter((p) => p.kind === "video");
    for (const lang of ["ar", "en", "de"]) {
      const dir = path.join(ROOT, CUR_PRE.replace(/^\//, ""), LANGS[lang].prefix.replace(/^\//, ""), "listing", slugFor(l, lang));
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, "index.html"), renderPage(l, photos, lang)); n++;
    }
  }
  console.log(`Wrote ${n} listing page(s) in ar/en/de. (sitemap.xml is written by generate-pages.mjs)`);
}
main();
