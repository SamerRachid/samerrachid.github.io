// ════════════════════════════════════════════════════════════════════════
//  BALKOUN · static area & governorate pages (multi-page, three languages)
//
//  Writes real, crawlable HTML in the site's own style, in Arabic (root),
//  English (/en/) and German (/de/):
//    /for-sale/<gov>/            /for-rent/<gov>/            (+ /en/…, /de/…)
//    /for-sale/<gov>/<area>/     /for-rent/<gov>/<area>/     (only where listings exist)
//    /areas/  /about/  /contactus/                           (+ /en/…, /de/…)
//    /en/  /de/                                              (English and German home pages)
//  Every page carries hreflang links to its two sister languages, and the
//  sitemap lists all of them plus the /listing/ pages that generate-listings.mjs
//  produced. Runs in GitHub Actions after that script.
//  Search, map, accounts, posting and admin stay in the app (index.html);
//  every page links into it with the app's own /search?… query format and a
//  ?lang= hint so the app opens in the visitor's language.
// ════════════════════════════════════════════════════════════════════════
import fs from "fs";
import path from "path";
import vm from "vm";
import { GUIDES, GUIDE_WORDS } from "./guides-content.mjs";

const SUPABASE_URL = "https://coajrqynjrptujmzjjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t"; // public anon key
const SITE = "https://balkoun.com";
const ROOT = path.resolve(".");

async function sb(endpoint) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } });
  if (!res.ok) throw new Error(`Supabase ${res.status}: ${endpoint}`);
  return res.json();
}
async function all(table, select, order) {
  const out = [];
  for (let from = 0; ; from += 1000) {
    const rows = await sb(`${table}?select=${select}&order=${order}&offset=${from}&limit=1000`);
    out.push(...rows);
    if (rows.length < 1000) break;
  }
  return out;
}

// ── the app's own data block (types, deed labels, governorate names, about text) ──
function loadAppData() {
  const src = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const line = src.split("\n").find((l) => /^var D\s*=\s*\{/.test(l));
  if (!line) throw new Error("index.html: data line not found");
  const sandbox = {};
  vm.runInNewContext(line.replace(/^var D\s*=/, "D=").replace(/;\s*$/, ""), sandbox);
  return sandbox.D;
}
const D = loadAppData();
const LI = { ar: 0, en: 1, de: 2 };
const LANGS = {
  ar: { code: "ar", dir: "rtl", prefix: "", og: "ar_SY", font: "Noto Kufi Arabic" },
  en: { code: "en", dir: "ltr", prefix: "/en", og: "en_US", font: "Lato" },
  de: { code: "de", dir: "ltr", prefix: "/de", og: "de_DE", font: "Lato" },
};
const typeName = (k, lang) => (D.TYPES[k] ? D.TYPES[k][LI[lang]] : k);
const tabuName = (k, lang) => (D.TABU[k] ? D.TABU[k][LI[lang]] : k);
const TYPE_PL_AR = { apartment:"شقق", arab:"بيوت عربية", villa:"فلل", floor:"طوابق", building:"أبنية", chalet:"شاليهات", farm:"مزارع",
  shop:"محلات", office:"مكاتب", restaurant:"مطاعم", warehouse:"مستودعات", factory:"معامل", resid:"أراضٍ سكنية", agri:"أراضٍ زراعية", comm:"أراضٍ تجارية", land:"أراضٍ" };
const typePlural = (k, lang) => lang === "ar" ? (TYPE_PL_AR[k] || typeName(k, "ar")) : lang === "en" ? typeName(k, "en") + (/[sxz]$|house$/i.test(typeName(k, "en")) ? "s" : "s") : typeName(k, "de");
const govName = (g, lang) => lang === "ar" ? g.name_ar : lang === "en" ? (g.name_en || (D.GOVN[g.name_ar] || [])[0] || g.name_ar) : ((D.GOVN[g.name_ar] || [])[1] || g.name_en || g.name_ar);
// areas have no English names in the database yet: fall back to the URL slug, title-cased (mezzeh → Mezzeh)
const titleSlug = (s) => String(s || "").split("-").filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ");
const areaName = (a, lang) => lang === "ar" ? a.name_ar : (a.name_en || titleSlug(a.slug) || a.name_ar);
const DEAL = { sale: { slug: "for-sale" }, rent: { slug: "for-rent" } };

// ── words per language ────────────────────────────────────────────────
const S = {
  ar: {
    brand: "بلكون", forSale: "للبيع", forRent: "للإيجار", areas: "المناطق", map: "الخريطة", about: "عن بلكون", login: "دخول", post: "أضف إعلانك", home: "الرئيسية",
    propIn: (d, g) => `عقارات ${d} في ${g}`, propInArea: (d, a, g) => `عقارات ${d} في ${a}، ${g}`,
    nListings: (n) => `${n} إعلاناً`, avgM2: "متوسط سعر المتر", avgM2From: (n) => `من ${n} إعلاناً`, advSearch: "بحث متقدّم", advSearchIn: (a) => `بحث متقدّم في ${a}`,
    govDesc: (n, d, g, avg) => `${n} إعلاناً ${d} في ${g}: شقق، بيوت عربية، فلل، محلات وأراضٍ من المالك مباشرة وبلا عمولة${avg ? `، متوسط سعر المتر ${avg}` : ""}.`,
    areaDesc: (n, d, a, g, types, avg) => `${n} عقاراً ${d} في ${a} (${g}): ${types}${avg ? `. متوسط سعر المتر ${avg}` : ""}. من المالك مباشرة وبلا عمولة.`,
    noneH: (d, g) => `لا إعلانات ${d} في ${g} حالياً`, noneP: "كن أول من يعرض عقاره هنا.", postFree: "أضف إعلانك مجاناً",
    areasOf: (g) => `مناطق ${g}`, areasSub: "المناطق التي فيها إعلانات لها صفحتها الخاصة.", near: (g) => `مناطق قريبة في ${g}`, allOf: (g) => `كل ${g}`,
    faqH: (a) => `أسئلة شائعة عن ${a}`, faqQ1: (d, a) => `كم عدد العقارات ${d} في ${a}؟`, faqA1: (n, d, a) => `يوجد حالياً ${n} إعلاناً ${d} في ${a} على بلكون.`,
    faqQ2: (d, a) => `ما أسعار العقارات ${d} في ${a}؟`, faqA2: (lo, hi, avg) => `تتراوح الأسعار المعروضة بين ${lo} و${hi}${avg ? `، ومتوسط سعر المتر ${avg}` : ""}.`,
    faqQ3: "هل هناك عمولة على المشتري؟", faqA3: "لا. بلكون لا يأخذ عمولة من المشتري أو المستأجر؛ التواصل مباشر مع المالك.",
    govsH: "المحافظات والمناطق", govsT: "كل المحافظات والمناطق", govsDesc: (ng, na) => `تصفّح عقارات سوريا حسب المحافظة والمنطقة: ${ng} محافظة و${na} منطقة على بلكون.`, govsSub: (ng, na) => `${ng} محافظة · ${na} منطقة`, govSmall: (n, a) => `${n} إعلان · ${a} منطقة`, search: "بحث",
    rooms: "غرف", sqm: "م²", floorAbbr: "ط", monthly: "شهري", yearly: "سنوي", noPhoto: "بدون صورة", featured: "مميّز", greenDeed: "طابو أخضر", belowAvg: (p) => `تحت متوسط المنطقة ${p}`, aboveAvg: (p) => `فوق متوسط المنطقة ${p}`,
    aboutT: "عن بلكون", contactT: "تواصل معنا", contactDesc: "تواصل مع فريق بلكون: استفسارات، اقتراحات، أو مساعدة في نشر إعلانك. نرد خلال يوم عمل.",
    phone: "هاتف", wa: "واتساب", mail: "بريد", fb: "فيسبوك", ig: "إنستغرام", yt: "يوتيوب", tt: "تيك توك", sendMsg: "أرسل رسالة", name: "الاسم", contactField: "رقم للتواصل أو بريد", yourMsg: "رسالتك", send: "إرسال", min10: "اكتب 10 أحرف على الأقل.", sending: "جارٍ الإرسال…", sentH: "وصلتنا رسالتك ✓", sentP: "شكراً لك. سنرد في أقرب وقت.", sendErr: "تعذّر الإرسال، حاول مرة أخرى أو استخدم واتساب.",
    footIn: (g) => `عقارات في ${g}`, allAreas: "كل المناطق", aboutPlatform: "عن المنصّة", crumbAria: "مسار الصفحة", inLangs: "اللغات",
    homeT: "بلكون — عقارات سوريا للبيع والإيجار من المالك مباشرة", homeH1: "عقارات سوريا للبيع والإيجار، من المالك مباشرة", homeLede: "شقق وبيوت وأراضٍ في كل المحافظات السورية، مع حالة الطابو في كل إعلان وبدون عمولة.", homeDesc: "عقارات سوريا للبيع والإيجار: شقق، بيوت، فلل وأراضٍ في جميع المحافظات، من المالك مباشرة وبلا عمولة.", browseByGov: "تصفّح حسب المحافظة", latest: "أحدث الإعلانات", openApp: "ابحث في كل الإعلانات", whyH: "لماذا بلكون؟",
    why: [["حالة الطابو في كل إعلان", "طابو أخضر، حكم محكمة، أو حصص سهمية: تعرف الوضع القانوني قبل أن تتصل."], ["من المالك مباشرة", "لا عمولة على المشتري أو المستأجر. التواصل بالهاتف أو واتساب."], ["كل المحافظات", "دمشق وريفها، حلب، حمص، اللاذقية، طرطوس وباقي المحافظات، بالمنطقة والحي."]],
  },
  en: {
    brand: "Balkoun", forSale: "for sale", forRent: "for rent", areas: "Areas", map: "Map", about: "About", login: "Log in", post: "Post a listing", home: "Home",
    propIn: (d, g) => `Property ${d} in ${g}, Syria`, propInArea: (d, a, g) => `Property ${d} in ${a}, ${g}`,
    nListings: (n) => `${n} listing${n === 1 ? "" : "s"}`, avgM2: "average price per m²", avgM2From: (n) => `from ${n} listings`, advSearch: "Advanced search", advSearchIn: (a) => `Advanced search in ${a}`,
    govDesc: (n, d, g, avg) => `${n} listing${n === 1 ? "" : "s"} ${d} in ${g}, Syria: apartments, houses, villas, shops and land, direct from owners with no commission${avg ? `. Average price ${avg} per m²` : ""}.`,
    areaDesc: (n, d, a, g, types, avg) => `${n} propert${n === 1 ? "y" : "ies"} ${d} in ${a} (${g}, Syria): ${types}${avg ? `. Average price ${avg} per m²` : ""}. Direct from owners, no commission.`,
    noneH: (d, g) => `No listings ${d} in ${g} right now`, noneP: "Be the first to list a property here.", postFree: "Post your listing for free",
    areasOf: (g) => `Areas of ${g}`, areasSub: "Areas with listings have their own page.", near: (g) => `Nearby areas in ${g}`, allOf: (g) => `All of ${g}`,
    faqH: (a) => `Frequently asked questions about ${a}`, faqQ1: (d, a) => `How many properties are ${d} in ${a}?`, faqA1: (n, d, a) => `There are currently ${n} listing${n === 1 ? "" : "s"} ${d} in ${a} on Balkoun.`,
    faqQ2: (d, a) => `What do properties ${d} in ${a} cost?`, faqA2: (lo, hi, avg) => `Listed prices range from ${lo} to ${hi}${avg ? `, with an average of ${avg} per m²` : ""}.`,
    faqQ3: "Is there a commission for the buyer?", faqA3: "No. Balkoun charges buyers and tenants no commission; you deal directly with the owner.",
    govsH: "Governorates and areas", govsT: "All governorates and areas of Syria", govsDesc: (ng, na) => `Browse property in Syria by governorate and area: ${ng} governorates and ${na} areas on Balkoun.`, govsSub: (ng, na) => `${ng} governorates · ${na} areas`, govSmall: (n, a) => `${n} listings · ${a} areas`, search: "Search",
    rooms: "rooms", sqm: "m²", floorAbbr: "Fl.", monthly: "month", yearly: "year", noPhoto: "No photo", featured: "Featured", greenDeed: "Green deed", belowAvg: (p) => `${p} below area average`, aboveAvg: (p) => `${p} above area average`,
    aboutT: "About Balkoun", contactT: "Contact us", contactDesc: "Contact the Balkoun team: questions, suggestions, or help publishing your listing. We reply within one working day.",
    phone: "Phone", wa: "WhatsApp", mail: "Email", fb: "Facebook", ig: "Instagram", yt: "YouTube", tt: "TikTok", sendMsg: "Send a message", name: "Name", contactField: "Phone or email", yourMsg: "Your message", send: "Send", min10: "Please write at least 10 characters.", sending: "Sending…", sentH: "Message received ✓", sentP: "Thank you. We will reply as soon as we can.", sendErr: "Could not send. Try again or use WhatsApp.",
    footIn: (g) => `Property in ${g}`, allAreas: "All areas", aboutPlatform: "About", crumbAria: "Breadcrumb", inLangs: "Languages",
    homeT: "Real estate in Syria: property for sale and rent, direct from owners | Balkoun", homeH1: "Real estate in Syria, direct from owners", homeLede: "Apartments, houses, villas and land for sale and rent across Syria, with the title-deed status shown on every listing and no commission.", homeDesc: "Real estate in Syria: apartments, houses, villas and land for sale and rent in Damascus, Aleppo, Homs, Latakia and beyond. Direct from owners, no commission.", browseByGov: "Browse by governorate", latest: "Latest listings", openApp: "Search all listings", whyH: "Why Balkoun?",
    why: [["Title-deed status on every listing", "Green deed, court ruling or shares: you know the legal situation before you call."], ["Direct from the owner", "No commission for buyers or tenants. Contact by phone or WhatsApp."], ["Every governorate", "Damascus and its countryside, Aleppo, Homs, Latakia, Tartus and the rest of Syria, by area and neighbourhood."]],
  },
  de: {
    brand: "Balkoun", forSale: "zum Kauf", forRent: "zur Miete", areas: "Gegenden", map: "Karte", about: "Über uns", login: "Anmelden", post: "Anzeige aufgeben", home: "Start",
    propIn: (d, g) => `Immobilien ${d} in ${g}, Syrien`, propInArea: (d, a, g) => `Immobilien ${d} in ${a}, ${g}`,
    nListings: (n) => `${n} Anzeige${n === 1 ? "" : "n"}`, avgM2: "Durchschnittspreis pro m²", avgM2From: (n) => `aus ${n} Anzeigen`, advSearch: "Erweiterte Suche", advSearchIn: (a) => `Erweiterte Suche in ${a}`,
    govDesc: (n, d, g, avg) => `${n} Anzeige${n === 1 ? "" : "n"} ${d} in ${g}, Syrien: Wohnungen, Häuser, Villen, Läden und Grundstücke direkt vom Eigentümer, ohne Provision${avg ? `. Durchschnittspreis ${avg} pro m²` : ""}.`,
    areaDesc: (n, d, a, g, types, avg) => `${n} Immobilie${n === 1 ? "" : "n"} ${d} in ${a} (${g}, Syrien): ${types}${avg ? `. Durchschnittspreis ${avg} pro m²` : ""}. Direkt vom Eigentümer, ohne Provision.`,
    noneH: (d, g) => `Derzeit keine Anzeigen ${d} in ${g}`, noneP: "Bieten Sie als Erster eine Immobilie hier an.", postFree: "Anzeige kostenlos aufgeben",
    areasOf: (g) => `Gegenden in ${g}`, areasSub: "Gegenden mit Anzeigen haben eine eigene Seite.", near: (g) => `Gegenden in der Nähe in ${g}`, allOf: (g) => `Ganz ${g}`,
    faqH: (a) => `Häufige Fragen zu ${a}`, faqQ1: (d, a) => `Wie viele Immobilien gibt es ${d} in ${a}?`, faqA1: (n, d, a) => `Derzeit gibt es ${n} Anzeige${n === 1 ? "" : "n"} ${d} in ${a} auf Balkoun.`,
    faqQ2: (d, a) => `Was kosten Immobilien ${d} in ${a}?`, faqA2: (lo, hi, avg) => `Die Preise liegen zwischen ${lo} und ${hi}${avg ? `, im Durchschnitt ${avg} pro m²` : ""}.`,
    faqQ3: "Gibt es eine Provision für Käufer?", faqA3: "Nein. Balkoun verlangt von Käufern und Mietern keine Provision; der Kontakt läuft direkt mit dem Eigentümer.",
    govsH: "Gouvernements und Gegenden", govsT: "Alle Gouvernements und Gegenden Syriens", govsDesc: (ng, na) => `Immobilien in Syrien nach Gouvernement und Gegend: ${ng} Gouvernements und ${na} Gegenden auf Balkoun.`, govsSub: (ng, na) => `${ng} Gouvernements · ${na} Gegenden`, govSmall: (n, a) => `${n} Anzeigen · ${a} Gegenden`, search: "Suchen",
    rooms: "Zimmer", sqm: "m²", floorAbbr: "OG", monthly: "Monat", yearly: "Jahr", noPhoto: "Kein Foto", featured: "Empfohlen", greenDeed: "Grünes Grundbuch", belowAvg: (p) => `${p} unter dem Durchschnitt`, aboveAvg: (p) => `${p} über dem Durchschnitt`,
    aboutT: "Über Balkoun", contactT: "Kontakt", contactDesc: "Kontakt zum Balkoun-Team: Fragen, Vorschläge oder Hilfe beim Veröffentlichen Ihrer Anzeige. Wir antworten innerhalb eines Werktags.",
    phone: "Telefon", wa: "WhatsApp", mail: "E-Mail", fb: "Facebook", ig: "Instagram", yt: "YouTube", tt: "TikTok", sendMsg: "Nachricht senden", name: "Name", contactField: "Telefon oder E-Mail", yourMsg: "Ihre Nachricht", send: "Senden", min10: "Bitte mindestens 10 Zeichen schreiben.", sending: "Wird gesendet…", sentH: "Nachricht erhalten ✓", sentP: "Danke. Wir antworten so schnell wie möglich.", sendErr: "Senden fehlgeschlagen. Bitte erneut versuchen oder WhatsApp nutzen.",
    footIn: (g) => `Immobilien in ${g}`, allAreas: "Alle Gegenden", aboutPlatform: "Über die Plattform", crumbAria: "Navigationspfad", inLangs: "Sprachen",
    homeT: "Immobilien in Syrien: Wohnungen und Häuser kaufen und mieten, direkt vom Eigentümer | Balkoun", homeH1: "Immobilien in Syrien, direkt vom Eigentümer", homeLede: "Wohnungen, Häuser, Villen und Grundstücke zum Kauf und zur Miete in ganz Syrien, mit Grundbuchstatus in jeder Anzeige und ohne Provision.", homeDesc: "Immobilien in Syrien: Wohnungen, Häuser, Villen und Grundstücke kaufen und mieten in Damaskus, Aleppo, Homs, Latakia. Direkt vom Eigentümer, ohne Provision.", browseByGov: "Nach Gouvernement", latest: "Neueste Anzeigen", openApp: "Alle Anzeigen durchsuchen", whyH: "Warum Balkoun?",
    why: [["Grundbuchstatus in jeder Anzeige", "Grünes Grundbuch, Gerichtsurteil oder Anteile: Sie kennen die Rechtslage, bevor Sie anrufen."], ["Direkt vom Eigentümer", "Keine Provision für Käufer oder Mieter. Kontakt per Telefon oder WhatsApp."], ["Alle Gouvernements", "Damaskus und Umland, Aleppo, Homs, Latakia, Tartus und das übrige Syrien, nach Gegend und Viertel."]],
  },
};
const dealWord = (deal, lang) => deal === "sale" ? S[lang].forSale : S[lang].forRent;

const esc = (s) => String(s ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
const money = (v) => v == null ? "—" : "$" + Number(v).toLocaleString("en");
const ltr = (s) => `<span class="ltr">${esc(s)}</span>`;
const jsonForScript = (o) => JSON.stringify(o).replace(/</g, "\\u003c");
const q = (o) => Object.entries(o).filter(([, v]) => v != null && v !== "").map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join("&");
const appQ = (lang, o = {}) => lang === "ar" ? o : { ...o, lang };
const searchUrl = (lang, o) => `${SITE}/search?${q(appQ(lang, o))}`;
const appUrl = (lang, p) => `${SITE}/${p}${lang === "ar" ? "" : `?lang=${lang}`}`;
const slugLatin = (s) => String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9\s-]/g, "").trim().replace(/\s+/g, "-").slice(0, 60);
const slugAr = (s) => String(s || "").replace(/[^\p{L}\p{N}\s-]/gu, "").trim().replace(/\s+/g, "-").slice(0, 60);
// listing page URL per language: must match generate-listings.mjs exactly
const TYPE_AR_SLUG = { apartment:"شقة", arab:"بيت عربي", villa:"فيلا", floor:"طابق كامل", building:"بناء كامل", shop:"محل تجاري", office:"مكتب", resid:"أرض سكنية", agri:"أرض زراعية", comm:"أرض تجارية" };
let govById = new Map(), areaById = new Map();
function listingUrl(l, lang) {
  if (lang === "ar") return `${SITE}/listing/${l.id}-${slugAr((TYPE_AR_SLUG[l.property_type] || l.property_type) + " " + (l.area_ar || "") + " " + l.governorate_ar)}/`;
  const g = govById.get(l.governorate_id), a = areaById.get(l.area_id);
  return `${SITE}/${lang}/listing/${l.id}-${slugLatin(typeName(l.property_type, "en") + " " + (a ? areaName(a, "en") : "") + " " + (g ? govName(g, "en") : ""))}/`;
}
const pageUrl = (lang, p) => `${SITE}${LANGS[lang].prefix}/${p}`;

// ── page shell in the site's own style (same tokens as index.html) ───────
const CSS = `
:root{--navy:#14213D;--navy-2:#0D1729;--navy-w:#EEF1F7;--gold:#C4881F;--gold-dk:#8A6522;--gold-w:#FDF5E7;--ink:#22252A;--grey:#6B7280;--light:#9CA3AF;--line:#E6E2D9;--line-2:#D3D4D8;--page:#F4F2ED;--card:#FFF;--ok:#2E7D5B;--ok-w:#EAF5EF;--f:'Noto Kufi Arabic','Lato',system-ui,sans-serif;--fd:'Noto Kufi Arabic','Lato',sans-serif;--r:8px;--sh2:0 12px 30px -12px rgba(9,14,26,.28)}
html[lang=en],html[lang=de]{--f:'Lato','Noto Kufi Arabic',system-ui,sans-serif;--fd:'Lato','Noto Kufi Arabic',sans-serif}
*{box-sizing:border-box;margin:0;padding:0}html{-webkit-text-size-adjust:100%}
body{background:var(--page);color:var(--ink);font:15px/1.8 var(--f);-webkit-font-smoothing:antialiased;overflow-x:hidden}
a{color:inherit;text-decoration:none}img{display:block;max-width:100%}ul{list-style:none}
h1,h2,h3{font-family:var(--fd);font-weight:600;line-height:1.3;color:var(--navy)}
html[lang=en] h1,html[lang=de] h1,html[lang=en] h2,html[lang=de] h2{font-weight:700}
.ltr{direction:ltr;display:inline-block;font-variant-numeric:tabular-nums;unicode-bidi:isolate}
.wrap{max-width:1180px;margin:0 auto;padding:0 18px}
:focus-visible{outline:2px solid var(--gold);outline-offset:2px}
header{background:var(--navy);color:#fff}
.hbar{display:flex;align-items:center;gap:22px;height:62px;direction:ltr}
.logo{display:inline-flex;align-items:center;gap:6px;color:#CFC4AE;margin-left:auto;order:3;flex-direction:row-reverse}
.logo svg{width:38px;height:38px}
.logo .w{display:flex;flex-direction:column;align-items:flex-end;line-height:1}
.logo .w b{font:800 22px/1 'Noto Kufi Arabic',sans-serif}
.logo .w small{font:700 9px 'Lato',sans-serif;letter-spacing:.34em;color:#9DB0CC;margin-top:3px}
.hnav{display:flex;gap:16px;font-size:14px;color:rgba(255,255,255,.86);order:1}
.hnav a:hover{color:var(--gold)}
.htools{display:flex;gap:9px;align-items:center;order:2;margin-left:auto}
.mini{border:1px solid rgba(255,255,255,.3);color:#fff;padding:6px 12px;font-size:12.5px;border-radius:999px}
.gold{background:var(--gold);color:#1A1206;border-radius:999px;padding:6px 13px;font-weight:700;font-size:13px}
.gold:hover{background:#D6952A}
.langs{display:flex;gap:6px;font-size:12px}.langs a{padding:4px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.22);color:rgba(255,255,255,.8)}.langs a.on{background:rgba(255,255,255,.14);color:#fff}
.crumbs{display:flex;gap:8px;font-size:13px;color:var(--light);flex-wrap:wrap;padding-top:18px}
.crumbs a{color:var(--grey)}
.pagehead{padding:10px 0 6px}
.pagehead h1{font-size:clamp(26px,3.2vw,36px)}
.sub{color:var(--grey);font-size:14.5px;margin-top:4px}
.sub b{color:var(--navy)}
.chips{display:flex;gap:8px;flex-wrap:wrap;margin:14px 0 22px}
.chip{display:inline-flex;align-items:center;gap:6px;padding:6px 13px;border-radius:999px;background:#fff;border:1px solid var(--line);font-size:13px;color:var(--navy)}
.chip b{color:var(--gold-dk);font-weight:600}
.chip.act{background:var(--gold);border-color:var(--gold);color:#1A1206;font-weight:700}
.chip:hover{border-color:var(--gold)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:var(--r);overflow:hidden;display:block;transition:box-shadow .22s,transform .22s}
.card:hover{box-shadow:var(--sh2);transform:translateY(-3px)}
.card.feat{border-color:var(--gold);box-shadow:0 0 0 1px var(--gold),0 6px 18px -6px rgba(197,155,64,.45)}
.ph{position:relative;aspect-ratio:4/3;background:var(--navy-w);overflow:hidden}
.ph img{width:100%;height:100%;object-fit:cover}
.ph .nop{width:100%;height:100%;display:grid;place-items:center;color:var(--light);font-size:13px}
.badges{position:absolute;top:8px;inset-inline-start:8px;display:flex;gap:5px}
.badge{padding:2px 8px;border-radius:999px;font-size:11px;font-weight:700;background:rgba(9,14,26,.7);color:#fff}
.badge.feat{background:var(--gold);color:#3a2c05}.badge.ok{background:var(--ok);color:#fff}
.cb{padding:9px 12px 11px}
.cb .p{font:700 19px/1.4 var(--fd);color:var(--navy);white-space:nowrap}
.cb .p small{font:400 12px var(--f);color:var(--grey)}
.cb-loc{font-size:12.5px;font-weight:700;color:#111;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;margin-top:2px}
.cb-details{display:flex;flex-wrap:wrap;gap:4px 9px;font-size:11.5px;color:var(--grey);margin-top:6px}
.cb-type{font-weight:600;color:var(--ink)}
.cb-deed{padding-inline-start:10px;border-inline-start:1px solid var(--line)}
.none{background:#fff;border:1px dashed var(--line-2);border-radius:12px;padding:40px;text-align:center;color:var(--grey);display:grid;gap:10px;justify-items:center}
.sec{padding:44px 0 6px}.sec h2{font-size:24px;margin-bottom:4px}
.areas{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:6px 18px;margin-top:14px;font-size:14px}
.areas li{padding:6px 0;border-bottom:1px solid var(--line);color:var(--grey)}
.areas li a{color:var(--navy);font-weight:600;display:flex;justify-content:space-between}
.areas li a b{color:var(--gold-dk)}
.faq{margin-top:44px;max-width:760px}.faq h2{font-size:22px;margin-bottom:10px}
.faq details{background:#fff;border:1px solid var(--line);border-radius:10px;padding:12px 16px;margin-bottom:8px}
.faq summary{cursor:pointer;font-weight:600;color:var(--navy)}.faq p{color:#3D424D;margin-top:6px;font-size:14px}
.govs{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:14px;margin-top:14px}
.gov{background:#fff;border:1px solid var(--line);border-radius:12px;padding:16px 18px}
.gov h2{font-size:19px;display:flex;justify-content:space-between;align-items:baseline;gap:8px}
.gov h2 small{font:400 12px var(--f);color:var(--light);white-space:nowrap}
.gov .lk{display:flex;gap:12px;font-size:13.5px;margin-top:4px}.gov .lk a{color:var(--gold-dk);font-weight:600}
.gov ul{display:flex;flex-wrap:wrap;gap:6px;margin-top:10px}
.gov ul a{display:inline-block;padding:3px 10px;border:1px solid var(--line);border-radius:999px;font-size:12.5px}
.gov ul a:hover{border-color:var(--gold)}
.prose{max-width:760px;padding:8px 0 20px}.prose h1{font-size:clamp(26px,3.4vw,34px);margin-bottom:6px}.prose .lede{font-size:17px;color:var(--grey);margin-bottom:22px}
.ab{background:#fff;border:1px solid var(--line);border-radius:10px;padding:16px 20px;margin-bottom:12px}.ab h2{font-size:19px;margin-bottom:6px}.ab p{color:#3F444B;margin-bottom:8px;font-size:14.5px}
.cta{display:flex;justify-content:space-between;align-items:center;gap:16px;flex-wrap:wrap;background:var(--navy);color:#fff;border-radius:12px;padding:22px 24px;margin-top:18px}.cta h2{color:var(--gold);font-size:21px}.cta p{color:rgba(255,255,255,.8);font-size:14px}
.chans{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px;margin-bottom:26px}.chan{display:flex;flex-direction:column;gap:2px;background:#fff;border:1px solid var(--line);border-radius:10px;padding:12px 16px;font-weight:600;color:var(--navy)}.chan small{font-weight:400;color:var(--light);font-size:12px}.chan:hover{border-color:var(--gold)}
.cform{background:#fff;border:1px solid var(--line);border-radius:12px;padding:18px 20px;display:grid;gap:12px}.cform h2{font-size:20px}.cform label{display:grid;gap:5px;font-size:13.5px;font-weight:600;color:var(--ink)}.cform input,.cform textarea{font:inherit;font-size:15px;padding:10px 12px;border:1px solid var(--line-2);border-radius:8px;background:#fff}.cform .row{display:grid;grid-template-columns:1fr 1fr;gap:12px}.cform .req{color:#B4232C}.cform button{border:0;cursor:pointer;font:inherit}#cfMsg{font-size:13.5px;color:var(--grey)}
@media(max-width:600px){.cform .row{grid-template-columns:1fr}}
.hero{background:radial-gradient(120% 90% at 20% 10%,#1E3160,#14213D 60%,#0F1B33);color:#fff;border-radius:18px;padding:44px 34px;margin-top:22px}
.hero h1{color:#fff;font-size:clamp(28px,4vw,44px);max-width:20ch}.hero p{color:rgba(255,255,255,.82);font-size:17px;max-width:62ch;margin-top:10px}
.hero .acts{display:flex;gap:10px;flex-wrap:wrap;margin-top:22px}.hero .acts a{padding:11px 18px;border-radius:999px;font-weight:700;font-size:14.5px}
.hero .acts .g{background:var(--gold);color:#1A1206}.hero .acts .o{border:1px solid rgba(255,255,255,.35);color:#fff}
.why{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px;margin-top:14px}.why div{background:#fff;border:1px solid var(--line);border-radius:12px;padding:16px 18px}.why h3{font-size:16px;margin-bottom:4px}.why p{color:var(--grey);font-size:14px}
.gl{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:14px;margin-top:16px}.gl a{background:#fff;border:1px solid var(--line);border-radius:14px;padding:18px 20px;display:flex;flex-direction:column;gap:6px;transition:.2s}.gl a:hover{border-color:var(--gold);box-shadow:var(--sh2)}.gl .k{font-size:11.5px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:var(--gold-dk)}.gl h2{font-size:17px;line-height:1.5}.gl p{color:var(--grey);font-size:14px}
.article{max-width:760px;padding:8px 0 20px}.article .k{font-size:12px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;color:var(--gold-dk)}.article h1{font-size:clamp(26px,3.4vw,36px);margin:6px 0 10px;line-height:1.35}.article .lede{font-size:17.5px;color:#3D424D;line-height:1.8;margin-bottom:8px}.article .meta{font-size:12.5px;color:var(--light);margin-bottom:22px}.article section{margin-top:26px}.article h2{font-size:21px;margin-bottom:8px}.article p{font-size:15.5px;line-height:1.9;color:#2B2F36;margin-bottom:10px}.article .disc{background:var(--gold-w);border:1px solid #EAD9B3;border-radius:12px;padding:12px 16px;font-size:13.5px;color:#6B5320;margin-top:28px}
.morelist{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
footer{background:var(--navy);color:rgba(255,255,255,.7);font-size:13.5px;padding:40px 0 22px;margin-top:64px}
.fl{display:flex;flex-wrap:wrap;gap:8px 18px;margin-bottom:14px}
.fl a:hover{color:#fff}
.fb{display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px;padding-top:16px;border-top:1px solid rgba(255,255,255,.14);font-size:12.5px}
@media(max-width:860px){.hnav{display:none}.hbar{height:58px;gap:8px}.logo{margin-left:0;order:0}.logo svg{width:32px;height:32px}.logo .w b{font-size:18px}.logo .w small{font-size:8px}.htools{margin-left:auto;gap:6px}.mini{display:none}.gold{padding:7px 11px;font-size:12.5px;white-space:nowrap}.langs a{padding:4px 7px;font-size:11.5px}.grid{grid-template-columns:repeat(2,1fr);gap:10px}.cb .p{font-size:17px}.hero{padding:30px 20px}}
`;
const MARK = `<svg viewBox="0 0 100 100" aria-hidden="true"><rect x="19" y="19" width="62" height="62" fill="none" stroke="currentColor" stroke-width="7"/><path d="M50 5 95 50 50 95 5 50Z" fill="none" stroke="#C4881F" stroke-width="9"/><rect x="42.5" y="42.5" width="15" height="15" fill="currentColor"/></svg>`;

// alternates: the same page in the other languages; x-default is the Arabic one
function hreflang(alts) {
  return Object.entries(alts).map(([l, href]) => `<link rel="alternate" hreflang="${l}" href="${href}">`).join("\n") + `\n<link rel="alternate" hreflang="x-default" href="${alts.ar}">`;
}
function shell({ lang, title, desc, canonical, alts, robots = "index, follow", jsonld = [], body, image, footLinks }) {
  const L = LANGS[lang], W = S[lang];
  const langBar = `<nav class="langs" aria-label="${W.inLangs}">${["ar", "en", "de"].map((l) => `<a href="${alts[l]}" hreflang="${l}" class="${l === lang ? "on" : ""}">${l === "ar" ? "عربي" : l.toUpperCase()}</a>`).join("")}</nav>`;
  return `<!DOCTYPE html><html lang="${lang}" dir="${L.dir}"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta name="robots" content="${robots}">
<meta name="theme-color" content="#14213D">
<link rel="canonical" href="${canonical}">
${hreflang(alts)}
<meta property="og:type" content="website"><meta property="og:site_name" content="Balkoun"><meta property="og:locale" content="${L.og}">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:url" content="${canonical}">
<meta property="og:image" content="${esc(image || SITE + "/brand/og-image.png")}">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/svg+xml" href="${SITE}/brand/favicon.svg"><link rel="icon" type="image/png" sizes="32x32" href="${SITE}/brand/favicon-32.png"><link rel="apple-touch-icon" href="${SITE}/brand/apple-touch-icon.png">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Noto+Kufi+Arabic:wght@400;500;600;700;800&family=Lato:wght@400;700;900&display=swap" rel="stylesheet">
${jsonld.map((o) => `<script type="application/ld+json">${jsonForScript(o)}</script>`).join("\n")}
<style>${CSS}</style></head><body>
<header><div class="wrap hbar">
<nav class="hnav"><a href="${searchUrl(lang, { deal: "sale" })}">${esc(W.forSale[0].toUpperCase() + W.forSale.slice(1))}</a><a href="${searchUrl(lang, { deal: "rent" })}">${esc(W.forRent[0].toUpperCase() + W.forRent.slice(1))}</a><a href="${pageUrl(lang, "areas/")}">${W.areas}</a><a href="${appUrl(lang, "mapsearch")}">${W.map}</a><a href="${pageUrl(lang, "guides/")}">${GUIDE_WORDS[lang].crumb}</a><a href="${pageUrl(lang, "about/")}">${W.about}</a></nav>
<div class="htools">${langBar}<a class="mini" href="${appUrl(lang, "account")}">${W.login}</a><a class="gold" href="${appUrl(lang, "post")}">${W.post}</a></div>
<a class="logo" href="${lang === "ar" ? SITE + "/" : pageUrl(lang, "")}" aria-label="Balkoun">${MARK}<span class="w"><b>بلكون</b><small>BALKOUN</small></span></a></div></header>
<main class="wrap">${body}</main>
<footer><div class="wrap"><div class="fl">${footLinks}</div><div class="fb"><span>© 2026 ${W.brand} · balkoun.com</span><span><a href="${pageUrl(lang, "guides/")}">${GUIDE_WORDS[lang].crumb}</a> · <a href="${pageUrl(lang, "about/")}">${W.aboutPlatform}</a> · <a href="${pageUrl(lang, "contactus/")}">${W.contactT}</a></span></div></div></footer>
</body></html>`;
}

function crumbs(lang, items) {
  const W = S[lang], home = lang === "ar" ? SITE + "/" : pageUrl(lang, "");
  const ld = { "@context":"https://schema.org", "@type":"BreadcrumbList", itemListElement: [{ name: W.home, href: home }, ...items].map((it, i) => ({ "@type":"ListItem", position: i + 1, name: it.name, ...(it.href ? { item: it.href } : {}) })) };
  const html = `<nav class="crumbs" aria-label="${W.crumbAria}"><a href="${home}">${W.home}</a>${items.map((it) => `<span>›</span>${it.href ? `<a href="${it.href}">${esc(it.name)}</a>` : `<span>${esc(it.name)}</span>`}`).join("")}</nav>`;
  return { html, ld };
}

function card(l, avg, lang) {
  const W = S[lang], isRent = l.deal === "rent", deedOk = l.tabu === "green";
  const g = govById.get(l.governorate_id), a = areaById.get(l.area_id);
  const gname = g ? govName(g, lang) : l.governorate_ar, aname = a ? areaName(a, lang) : (lang === "ar" ? l.area_ar : "");
  const ppm = l.area_m2 > 0 && l.price_usd ? l.price_usd / l.area_m2 : null;
  const diff = avg && ppm && !isRent ? Math.round((ppm - avg) / avg * 100) : null;
  const sep = lang === "ar" ? "، " : ", ";
  return `<a class="card${l.is_featured ? " feat" : ""}" href="${listingUrl(l, lang)}">
<div class="ph">${l.cover_url ? `<img src="${esc(l.cover_url)}" alt="${esc(typeName(l.property_type, lang))} ${lang === "ar" ? "في" : "in"} ${esc(aname || gname)}" loading="lazy" width="800" height="600">` : `<div class="nop">${W.noPhoto}</div>`}
<div class="badges">${l.is_featured ? `<span class="badge feat">${W.featured}</span>` : ""}${deedOk ? `<span class="badge ok">${W.greenDeed}</span>` : ""}</div></div>
<div class="cb"><div class="p">${ltr(money(l.price_usd))}${isRent ? ` <small>/ ${l.rental_period === "yearly" ? W.yearly : W.monthly}</small>` : ""}</div>
<div class="cb-loc">${esc([aname, gname].filter(Boolean).join(sep))}${l.landmark && lang === "ar" ? ` · ${esc(l.landmark)}` : ""}</div>
<div class="cb-details"><span class="cb-type">${esc(typeName(l.property_type, lang))}</span>${l.rooms != null ? `<span>${ltr(l.rooms)} ${W.rooms}</span>` : ""}${l.area_m2 ? `<span>${ltr(l.area_m2)} ${W.sqm}</span>` : ""}${l.floor != null ? `<span>${W.floorAbbr} ${ltr(l.floor)}</span>` : ""}${l.tabu ? `<span class="cb-deed">${esc(tabuName(l.tabu, lang))}</span>` : ""}${diff != null && Math.abs(diff) >= 5 ? `<span style="color:${diff < 0 ? "var(--ok)" : "var(--gold-dk)"};font-weight:600;margin-inline-start:auto">${diff < 0 ? W.belowAvg(Math.abs(diff) + "%") : W.aboveAvg(Math.abs(diff) + "%")}</span>` : ""}</div>
</div></a>`;
}

let avgByArea = new Map();
const altsFor = (p) => ({ ar: SITE + "/" + p, en: pageUrl("en", p), de: pageUrl("de", p) });

function govPage({ lang, deal, g, areas, listings, avg, footLinks }) {
  const W = S[lang], d = DEAL[deal], dw = dealWord(deal, lang), other = deal === "sale" ? "rent" : "sale";
  const rel = `${d.slug}/${g.slug}/`, url = pageUrl(lang, rel), gname = govName(g, lang);
  const title = W.propIn(dw, gname);
  const desc = W.govDesc(listings.length, dw, gname, avg ? money(avg) : null);
  const withL = areas.filter((a) => a.count[deal] > 0).sort((x, y) => y.count[deal] - x.count[deal]);
  const c = crumbs(lang, [{ name: dw, href: searchUrl(lang, { deal }) }, { name: gname }]);
  const body = `${c.html}
<div class="pagehead"><h1>${esc(title)}</h1><p class="sub">${ltr(listings.length)} ${lang === "ar" ? "إعلاناً" : W.nListings(listings.length).replace(/^\d+\s/, "")}${avg ? ` · ${W.avgM2} <b>${ltr(money(avg))}</b>` : ""} · <a href="${pageUrl(lang, `${DEAL[other].slug}/${g.slug}/`)}" style="color:var(--gold-dk)">${esc(W.propIn(dealWord(other, lang), gname))}</a> · <a href="${searchUrl(lang, { deal, govs: g.name_ar })}" style="color:var(--gold-dk)">${W.advSearch}</a></p></div>
${withL.length ? `<div class="chips">${withL.map((a) => `<a class="chip" href="${pageUrl(lang, `${d.slug}/${g.slug}/${a.slug}/`)}">${esc(areaName(a, lang))} <b>${ltr(a.count[deal])}</b></a>`).join("")}</div>` : ""}
${listings.length ? `<div class="grid">${listings.map((l) => card(l, l.area_id ? avgByArea.get(l.area_id) : null, lang)).join("")}</div>` : `<div class="none"><h2>${esc(W.noneH(dw, gname))}</h2><p>${W.noneP}</p><a class="gold" href="${appUrl(lang, "post")}">${W.postFree}</a></div>`}
<section class="sec"><h2>${esc(W.areasOf(gname))}</h2><p class="sub">${W.areasSub}</p>
<ul class="areas">${areas.map((a) => a.count[deal] > 0 ? `<li><a href="${pageUrl(lang, `${d.slug}/${g.slug}/${a.slug}/`)}">${esc(areaName(a, lang))} <b>${ltr(a.count[deal])}</b></a></li>` : `<li>${esc(areaName(a, lang))}</li>`).join("")}</ul></section>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"CollectionPage", name: title, description: desc, url, numberOfItems: listings.length, inLanguage: lang }];
  return { url, html: shell({ lang, title: title + " | Balkoun", desc, canonical: url, alts: altsFor(rel), robots: listings.length ? "index, follow" : "noindex, follow", jsonld: ld, body, image: listings[0]?.cover_url, footLinks }) };
}

function areaPage({ lang, deal, g, a, listings, siblings, market, footLinks }) {
  const W = S[lang], d = DEAL[deal], dw = dealWord(deal, lang);
  const rel = `${d.slug}/${g.slug}/${a.slug}/`, url = pageUrl(lang, rel), gname = govName(g, lang), aname = areaName(a, lang);
  const title = W.propInArea(dw, aname, gname);
  const types = [...new Set(listings.map((l) => typePlural(l.property_type, lang)))];
  const avg = market && market.listings >= 3 ? Math.round(Number(market.avg_price_per_m2)) : null;
  const desc = W.areaDesc(listings.length, dw, aname, gname, types.slice(0, 3).join(lang === "ar" ? "، " : ", "), avg && deal === "sale" ? money(avg) : null);
  const prices = listings.map((l) => l.price_usd).filter((x) => x != null).sort((x, y) => x - y);
  const faq = [
    { q: W.faqQ1(dw, aname), a: W.faqA1(listings.length, dw, aname) },
    prices.length ? { q: W.faqQ2(dw, aname), a: W.faqA2(money(prices[0]), money(prices[prices.length - 1]), avg && deal === "sale" ? money(avg) : null) } : null,
    { q: W.faqQ3, a: W.faqA3 },
  ].filter(Boolean);
  const c = crumbs(lang, [{ name: dw, href: searchUrl(lang, { deal }) }, { name: gname, href: pageUrl(lang, `${d.slug}/${g.slug}/`) }, { name: aname }]);
  const body = `${c.html}
<div class="pagehead"><h1>${esc(title)}</h1><p class="sub">${ltr(listings.length)} ${lang === "ar" ? "إعلاناً" : W.nListings(listings.length).replace(/^\d+\s/, "")}${avg && deal === "sale" ? ` · ${W.avgM2} <b>${ltr(money(avg))}</b> ${W.avgM2From(ltr(market.listings))}` : ""} · <a href="${searchUrl(lang, { deal, govs: g.name_ar, areas: a.name_ar })}" style="color:var(--gold-dk)">${esc(W.advSearchIn(aname))}</a></p></div>
<div class="grid">${listings.map((l) => card(l, avg, lang)).join("")}</div>
${siblings.length ? `<section class="sec"><h2>${esc(W.near(gname))}</h2><div class="chips">${siblings.map((s) => `<a class="chip" href="${pageUrl(lang, `${d.slug}/${g.slug}/${s.slug}/`)}">${esc(areaName(s, lang))} <b>${ltr(s.count[deal])}</b></a>`).join("")}<a class="chip" href="${pageUrl(lang, `${d.slug}/${g.slug}/`)}" style="color:var(--grey)">${esc(W.allOf(gname))}</a></div></section>` : ""}
<section class="faq"><h2>${esc(W.faqH(aname))}</h2>${faq.map((f) => `<details><summary>${esc(f.q)}</summary><p>${esc(f.a)}</p></details>`).join("")}</section>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"CollectionPage", name: title, description: desc, url, numberOfItems: listings.length, inLanguage: lang },
    { "@context":"https://schema.org", "@type":"FAQPage", mainEntity: faq.map((f) => ({ "@type":"Question", name: f.q, acceptedAnswer: { "@type":"Answer", text: f.a } })) }];
  return { url, html: shell({ lang, title: title + " | Balkoun", desc, canonical: url, alts: altsFor(rel), jsonld: ld, body, image: listings[0]?.cover_url, footLinks }) };
}

function areasIndex({ lang, govs, areasByGov, counts, footLinks }) {
  const W = S[lang], rel = "areas/", url = pageUrl(lang, rel);
  const totalAreas = [...areasByGov.values()].reduce((s, l) => s + l.length, 0);
  const desc = W.govsDesc(govs.length, totalAreas);
  const c = crumbs(lang, [{ name: W.areas }]);
  const body = `${c.html}<div class="pagehead"><h1>${W.govsH}</h1><p class="sub">${W.govsSub(ltr(govs.length), ltr(totalAreas))}</p></div>
<div class="govs">${govs.map((g) => { const list = areasByGov.get(g.id) || []; const live = list.filter((a) => a.count.sale || a.count.rent); const n = counts.gov.get(g.id) || 0;
  return `<section class="gov" id="${esc(g.slug)}"><h2><a href="${pageUrl(lang, `for-sale/${g.slug}/`)}">${esc(govName(g, lang))}</a><small>${W.govSmall(ltr(n), ltr(list.length))}</small></h2><div class="lk"><a href="${pageUrl(lang, `for-sale/${g.slug}/`)}">${esc(S[lang].forSale)}</a><a href="${pageUrl(lang, `for-rent/${g.slug}/`)}">${esc(S[lang].forRent)}</a><a href="${searchUrl(lang, { govs: g.name_ar })}">${W.search}</a></div>${live.length ? `<ul>${live.map((a) => `<li><a href="${pageUrl(lang, `${a.count.sale ? "for-sale" : "for-rent"}/${g.slug}/${a.slug}/`)}">${esc(areaName(a, lang))}</a></li>`).join("")}</ul>` : ""}</section>`; }).join("")}</div>`;
  return { url, html: shell({ lang, title: W.govsT + " | Balkoun", desc, canonical: url, alts: altsFor(rel), jsonld: [c.ld], body, footLinks }) };
}

function aboutPage({ lang, footLinks }) {
  const W = S[lang], A = D.ABOUT[lang] || D.ABOUT.ar, rel = "about/", url = pageUrl(lang, rel);
  const desc = String(A.lede || "").replace(/<[^>]+>/g, "").slice(0, 160);
  const c = crumbs(lang, [{ name: W.aboutT }]);
  const body = `${c.html}<article class="prose"><h1>${A.h1}</h1><p class="lede">${A.lede}</p>
${(A.blocks || []).map((b) => `<section class="ab"><h2>${b[0]}</h2>${b[1].map((p) => `<p>${p}</p>`).join("")}</section>`).join("")}
<div class="cta"><div><h2>${A.ctaH}</h2><p>${A.ctaP}</p></div><a class="gold" href="${appUrl(lang, "post")}">${W.post}</a></div></article>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"AboutPage", name: W.aboutT, url, description: desc, inLanguage: lang },
    { "@context":"https://schema.org", "@type":"Organization", name: "Balkoun", alternateName: "بلكون", url: SITE, logo: SITE + "/brand/og-image.png", areaServed: "SY" }];
  return { url, html: shell({ lang, title: W.aboutT + " | Balkoun", desc, canonical: url, alts: altsFor(rel), jsonld: ld, body, footLinks }) };
}

function contactPage({ lang, site, footLinks }) {
  const W = S[lang], rel = "contactus/", url = pageUrl(lang, rel), s = site || {};
  const chan = [];
  if (s.phone_number) chan.push({ label: W.phone, href: "tel:" + s.phone_number, text: s.phone_number });
  if (s.wa_number) chan.push({ label: W.wa, href: "https://wa.me/" + String(s.wa_number).replace(/\D/g, ""), text: s.wa_number });
  if (s.email_address) chan.push({ label: W.mail, href: "mailto:" + s.email_address, text: s.email_address });
  if (s.fb_url && s.fb_name) chan.push({ label: W.fb, href: s.fb_url, text: s.fb_name });
  if (s.ig_url && s.ig_name) chan.push({ label: W.ig, href: s.ig_url, text: s.ig_name });
  if (s.yt_url && s.yt_name) chan.push({ label: W.yt, href: s.yt_url, text: s.yt_name });
  if (s.tiktok_url && s.tiktok_name) chan.push({ label: W.tt, href: s.tiktok_url, text: s.tiktok_name });
  const desc = W.contactDesc;
  const c = crumbs(lang, [{ name: W.contactT }]);
  const body = `${c.html}<article class="prose"><h1>${W.contactT}</h1><p class="lede">${desc}</p>
${chan.length ? `<div class="chans">${chan.map((x) => `<a class="chan" href="${esc(x.href)}" target="_blank" rel="noopener"><small>${x.label}</small><span class="ltr">${esc(x.text)}</span></a>`).join("")}</div>` : ""}
<form class="cform" id="cf" novalidate><h2>${W.sendMsg}</h2>
<div class="row"><label>${W.name}<input name="name" autocomplete="name"></label><label>${W.contactField}<input name="contact" autocomplete="tel"></label></div>
<label>${W.yourMsg} <span class="req">*</span><textarea name="body" required minlength="10" maxlength="1500" rows="5"></textarea></label>
<div class="row" style="align-items:center"><button class="gold" type="submit">${W.send}</button><span id="cfMsg"></span></div></form></article>
<script>(function(){var f=document.getElementById("cf"),m=document.getElementById("cfMsg");f.addEventListener("submit",async function(e){e.preventDefault();var b=f.body.value.trim();if(b.length<10){m.textContent=${JSON.stringify(W.min10)};return}var btn=f.querySelector("button");btn.disabled=true;m.textContent=${JSON.stringify(W.sending)};try{var r=await fetch("${SUPABASE_URL}/rest/v1/rpc/bk_feedback",{method:"POST",headers:{"Content-Type":"application/json",apikey:"${SUPABASE_KEY}",Authorization:"Bearer ${SUPABASE_KEY}"},body:JSON.stringify({p_kind:"inquiry",p_name:f.name.value||null,p_contact:f.contact.value||null,p_body:b,p_user:null})});if(!r.ok)throw new Error(await r.text());f.innerHTML=${JSON.stringify(`<h2>${W.sentH}</h2><p>${W.sentP}</p>`)}}catch(err){m.textContent=${JSON.stringify(W.sendErr)};btn.disabled=false}})})();</script>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"ContactPage", name: W.contactT, url, description: desc, inLanguage: lang }];
  return { url, html: shell({ lang, title: W.contactT + " | Balkoun", desc, canonical: url, alts: altsFor(rel), jsonld: ld, body, footLinks }) };
}

// English and German home pages (the Arabic home is the app itself at /)
function homePage({ lang, govs, counts, latest, footLinks }) {
  const W = S[lang], url = pageUrl(lang, "");
  const topGovs = govs.filter((g) => (counts.gov.get(g.id) || 0) > 0).sort((a, b) => (counts.gov.get(b.id) || 0) - (counts.gov.get(a.id) || 0));
  const body = `<section class="hero"><h1>${esc(W.homeH1)}</h1><p>${esc(W.homeLede)}</p>
<div class="acts"><a class="g" href="${searchUrl(lang, { deal: "sale" })}">${esc(W.forSale[0].toUpperCase() + W.forSale.slice(1))}</a><a class="o" href="${searchUrl(lang, { deal: "rent" })}">${esc(W.forRent[0].toUpperCase() + W.forRent.slice(1))}</a><a class="o" href="${appUrl(lang, "mapsearch")}">${W.map}</a></div></section>
<section class="sec"><h2>${W.browseByGov}</h2><div class="chips">${(topGovs.length ? topGovs : govs).map((g) => `<a class="chip" href="${pageUrl(lang, `for-sale/${g.slug}/`)}">${esc(govName(g, lang))}${counts.gov.get(g.id) ? ` <b>${ltr(counts.gov.get(g.id))}</b>` : ""}</a>`).join("")}<a class="chip" href="${pageUrl(lang, "areas/")}" style="color:var(--grey)">${W.allAreas}</a></div></section>
${latest.length ? `<section class="sec"><h2>${W.latest}</h2><div class="grid" style="margin-top:14px">${latest.map((l) => card(l, l.area_id ? avgByArea.get(l.area_id) : null, lang)).join("")}</div><p style="margin-top:14px"><a class="gold" href="${searchUrl(lang, {})}">${W.openApp}</a></p></section>` : ""}
<section class="sec"><h2>${W.whyH}</h2><div class="why">${W.why.map((w) => `<div><h3>${esc(w[0])}</h3><p>${esc(w[1])}</p></div>`).join("")}</div></section>`;
  const ld = [{ "@context":"https://schema.org", "@type":"WebSite", name: "Balkoun", url: SITE, inLanguage: lang, description: W.homeDesc },
    { "@context":"https://schema.org", "@type":"Organization", name: "Balkoun", alternateName: "بلكون", url: SITE, logo: SITE + "/brand/og-image.png", areaServed: "SY" }];
  return { url, html: shell({ lang, title: W.homeT, desc: W.homeDesc, canonical: url, alts: { ar: SITE + "/", en: pageUrl("en", ""), de: pageUrl("de", "") }, jsonld: ld, body, image: latest[0]?.cover_url, footLinks }) };
}

function guidesIndex({ lang, footLinks }) {
  const GW = GUIDE_WORDS[lang], rel = "guides/", url = pageUrl(lang, rel);
  const c = crumbs(lang, [{ name: GW.crumb }]);
  const body = `${c.html}<div class="pagehead"><h1>${esc(GW.index)}</h1><p class="sub">${esc(GW.indexDesc)}</p></div>
<div class="gl">${GUIDES.map((g) => `<a href="${pageUrl(lang, `guides/${g.slug}/`)}"><span class="k">${esc(g.tag[lang])}</span><h2>${esc(g.title[lang])}</h2><p>${esc(g.lede[lang])}</p></a>`).join("")}</div>
<p class="disc" style="max-width:760px;margin-top:28px;background:var(--gold-w);border:1px solid #EAD9B3;border-radius:12px;padding:12px 16px;font-size:13.5px;color:#6B5320">${esc(GW.disclaimer)}</p>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"CollectionPage", name: GW.index, description: GW.indexDesc, url, inLanguage: lang }];
  return { url, html: shell({ lang, title: GW.index + " | Balkoun", desc: GW.indexDesc, canonical: url, alts: altsFor(rel), jsonld: ld, body, footLinks }) };
}
function guidePage({ lang, g, footLinks }) {
  const GW = GUIDE_WORDS[lang], rel = `guides/${g.slug}/`, url = pageUrl(lang, rel);
  const words = [g.lede[lang], ...g.sections.flatMap((s) => s.p.map((p) => p[lang]))].join(" ").split(/s+/).length;
  const c = crumbs(lang, [{ name: GW.crumb, href: pageUrl(lang, "guides/") }, { name: g.title[lang] }]);
  const others = GUIDES.filter((x) => x.slug !== g.slug);
  const faq = g.faq.map((f) => ({ q: f[lang][0], a: f[lang][1] }));
  const body = `${c.html}<article class="article"><div class="k">${esc(g.tag[lang])}</div><h1>${esc(g.title[lang])}</h1><p class="lede">${esc(g.lede[lang])}</p><div class="meta">${GW.readMin(Math.max(2, Math.round(words / 180)))} · ${GW.updated}: <span class="ltr">${new Date().toISOString().slice(0, 10)}</span></div>
${g.sections.map((s) => `<section><h2>${esc(s.h[lang])}</h2>${s.p.map((p) => `<p>${esc(p[lang])}</p>`).join("")}</section>`).join("")}
<section class="faq" style="margin-top:34px"><h2>${GW.faqH}</h2>${faq.map((f) => `<details><summary>${esc(f.q)}</summary><p>${esc(f.a)}</p></details>`).join("")}</section>
<p class="disc">${esc(GW.disclaimer)}</p>
<div class="cta" style="margin-top:26px"><div><h2 style="color:var(--gold);font-size:20px">${esc(S[lang].homeH1)}</h2></div><a class="gold" href="${searchUrl(lang, {})}">${GW.cta}</a></div>
<section style="margin-top:30px"><h2 style="font-size:18px">${GW.more}</h2><div class="morelist">${others.map((o) => `<a class="chip" href="${pageUrl(lang, `guides/${o.slug}/`)}">${esc(o.title[lang])}</a>`).join("")}</div></section></article>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"Article", headline: g.title[lang], description: g.lede[lang], url, inLanguage: lang, dateModified: new Date().toISOString().slice(0, 10), author: { "@type":"Organization", name: "Balkoun" }, publisher: { "@type":"Organization", name: "Balkoun", logo: { "@type":"ImageObject", url: SITE + "/brand/og-image.png" } }, mainEntityOfPage: url },
    { "@context":"https://schema.org", "@type":"FAQPage", mainEntity: faq.map((f) => ({ "@type":"Question", name: f.q, acceptedAnswer: { "@type":"Answer", text: f.a } })) }];
  return { url, html: shell({ lang, title: g.title[lang] + " | Balkoun", desc: g.lede[lang].slice(0, 158), canonical: url, alts: altsFor(rel), jsonld: ld, body, footLinks }) };
}

function write(url, html) {
  const rel = url.replace(SITE, "").replace(/^\//, "");
  const dir = path.join(ROOT, rel);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "index.html"), html);
}

async function main() {
  const [govs, areas, listings, prices] = await Promise.all([
    all("governorates", "id,name_ar,name_en,slug,sort_order", "sort_order.asc,id.asc"),
    all("areas", "id,governorate_id,name_ar,name_en,slug", "id.asc"),
    all("v_listings", "id,deal,property_type,governorate_id,governorate_ar,area_id,area_ar,landmark,price_usd,area_m2,rooms,floor,tabu,rental_period,is_featured,cover_url,created_at,status", "created_at.desc"),
    all("v_area_prices", "area_id,listings,avg_price_per_m2", "area_id.asc"),
  ]);
  govById = new Map(govs.map((g) => [g.id, g])); areaById = new Map(areas.map((a) => [a.id, a]));
  const live = listings.filter((l) => l.status === "live" && DEAL[l.deal]);
  const usableGovs = govs.filter((g) => g.slug);
  avgByArea = new Map(prices.filter((p) => p.listings >= 3).map((p) => [p.area_id, Number(p.avg_price_per_m2)]));
  const marketByArea = new Map(prices.map((p) => [p.area_id, p]));

  const counts = { gov: new Map(), area: new Map() };
  for (const l of live) {
    counts.gov.set(l.governorate_id, (counts.gov.get(l.governorate_id) || 0) + 1);
    if (l.area_id) { const k = counts.area.get(l.area_id) || { sale: 0, rent: 0 }; k[l.deal]++; counts.area.set(l.area_id, k); }
  }
  const areasByGov = new Map();
  for (const a of areas.filter((x) => x.slug)) {
    const row = { ...a, count: counts.area.get(a.id) || { sale: 0, rent: 0 } };
    (areasByGov.get(a.governorate_id) || areasByGov.set(a.governorate_id, []).get(a.governorate_id)).push(row);
  }
  const footLinksFor = (lang) => usableGovs.slice(0, 12).map((g) => `<a href="${pageUrl(lang, `for-sale/${g.slug}/`)}">${esc(S[lang].footIn(govName(g, lang)))}</a>`).join("") + `<a href="${pageUrl(lang, "areas/")}">${S[lang].allAreas}</a>`;

  // remove previously generated trees so deleted areas/govs don't leave stale pages
  for (const dir of ["for-sale", "for-rent", "areas", "about", "contactus", "en/for-sale", "en/for-rent", "en/areas", "en/about", "en/contactus", "de/for-sale", "de/for-rent", "de/areas", "de/about", "de/contactus", "guides", "en/guides", "de/guides"]) fs.rmSync(path.join(ROOT, dir), { recursive: true, force: true });
  for (const l of ["en", "de"]) { const f = path.join(ROOT, l, "index.html"); if (fs.existsSync(f)) fs.rmSync(f); }

  let site = null;
  try { site = (await sb("site_content?select=phone_number,wa_number,email_address,fb_url,fb_name,ig_url,ig_name,yt_url,yt_name,tiktok_url,tiktok_name&limit=1"))[0]; } catch (e) { console.warn("site_content unreadable:", e.message); }

  const urls = [];
  for (const lang of ["ar", "en", "de"]) {
    const footLinks = footLinksFor(lang);
    for (const deal of ["sale", "rent"]) {
      for (const g of usableGovs) {
        const gAreas = areasByGov.get(g.id) || [];
        const gl = live.filter((l) => l.deal === deal && l.governorate_id === g.id);
        const m2 = gAreas.map((a) => avgByArea.get(a.id)).filter(Boolean);
        const avg = m2.length ? Math.round(m2.reduce((s, v) => s + v, 0) / m2.length) : null;
        const page = govPage({ lang, deal, g, areas: gAreas, listings: gl, avg, footLinks });
        write(page.url, page.html); if (gl.length) urls.push({ loc: page.url, priority: "0.7" });
        for (const a of gAreas) {
          const al = gl.filter((l) => l.area_id === a.id);
          if (!al.length) continue;
          const siblings = gAreas.filter((x) => x.id !== a.id && x.count[deal] > 0).slice(0, 12);
          const ap = areaPage({ lang, deal, g, a, listings: al, siblings, market: marketByArea.get(a.id), footLinks });
          write(ap.url, ap.html); urls.push({ loc: ap.url, priority: "0.8" });
        }
      }
    }
    const idx = areasIndex({ lang, govs: usableGovs, areasByGov, counts, footLinks }); write(idx.url, idx.html); urls.push({ loc: idx.url, priority: "0.6" });
    const ab = aboutPage({ lang, footLinks }); write(ab.url, ab.html); urls.push({ loc: ab.url, priority: "0.5" });
    const ct = contactPage({ lang, site, footLinks }); write(ct.url, ct.html); urls.push({ loc: ct.url, priority: "0.5" });
    const gi = guidesIndex({ lang, footLinks }); write(gi.url, gi.html); urls.push({ loc: gi.url, priority: "0.7" });
    for (const g of GUIDES) { const gp = guidePage({ lang, g, footLinks }); write(gp.url, gp.html); urls.push({ loc: gp.url, priority: "0.7" }); }
    if (lang !== "ar") { const hp = homePage({ lang, govs: usableGovs, counts, latest: live.slice(0, 12), footLinks }); write(hp.url, hp.html); urls.push({ loc: hp.url, priority: "0.9" }); }
  }

  // sitemap: home + these pages + every /listing/ page on disk, in every language
  const listingDirsOf = (base) => fs.existsSync(base) ? fs.readdirSync(base).filter((d) => fs.existsSync(path.join(base, d, "index.html"))) : [];
  const today = new Date().toISOString().slice(0, 10);
  // the app routes that have their own 200 page (see generate-routes.mjs)
  const routeUrls = ["search", "mapsearch", "wanted", "agencies", "projects"].filter((r) => fs.existsSync(path.join(ROOT, r, "index.html"))).map((r) => ({ loc: `${SITE}/${r}/`, priority: "0.6" }));
  const entries = [{ loc: SITE + "/", priority: "1.0" }, ...routeUrls, ...urls,
    ...listingDirsOf(path.join(ROOT, "listing")).map((d) => ({ loc: `${SITE}/listing/${d}/`, priority: "0.9" })),
    ...listingDirsOf(path.join(ROOT, "en", "listing")).map((d) => ({ loc: `${SITE}/en/listing/${d}/`, priority: "0.8" })),
    ...listingDirsOf(path.join(ROOT, "de", "listing")).map((d) => ({ loc: `${SITE}/de/listing/${d}/`, priority: "0.8" }))];
  fs.writeFileSync(path.join(ROOT, "sitemap.xml"), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${entries.map((e) => `  <url><loc>${e.loc}</loc><lastmod>${today}</lastmod><priority>${e.priority}</priority></url>`).join("\n")}\n</urlset>\n`);
  console.log(`Wrote ${urls.length} pages in ar/en/de and sitemap.xml with ${entries.length} URLs.`);
}
main().catch((e) => { console.error(e); process.exit(1); });
