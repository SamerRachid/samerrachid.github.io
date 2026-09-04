// ════════════════════════════════════════════════════════════════════════
//  BALKOUN · static area & governorate pages (multi-page structure)
//
//  Writes real, crawlable HTML in the site's own style for:
//    /for-sale/<gov>/            /for-rent/<gov>/
//    /for-sale/<gov>/<area>/     /for-rent/<gov>/<area>/   (only where listings exist)
//    /areas/                     (every governorate and area)
//  and rewrites sitemap.xml with these pages plus the /listing/ pages that
//  generate-listings.mjs produced. Runs in GitHub Actions after that script.
//  Search, map, accounts, posting and admin stay in the app (index.html);
//  every page links into it with the app's own /search?… query format.
// ════════════════════════════════════════════════════════════════════════
import fs from "fs";
import path from "path";
import vm from "vm";

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

const TYPE = { apartment:"شقة", arab:"بيت عربي", villa:"فيلا", floor:"طابق كامل", building:"بناء كامل", chalet:"شاليه", farm:"مزرعة",
  shop:"محل تجاري", office:"مكتب", restaurant:"مطعم", warehouse:"مستودع", factory:"معمل", resid:"أرض سكنية", agri:"أرض زراعية", comm:"أرض تجارية", land:"أرض" };
const TYPE_PL = { apartment:"شقق", arab:"بيوت عربية", villa:"فلل", floor:"طوابق", building:"أبنية", chalet:"شاليهات", farm:"مزارع",
  shop:"محلات", office:"مكاتب", restaurant:"مطاعم", warehouse:"مستودعات", factory:"معامل", resid:"أراضٍ سكنية", agri:"أراضٍ زراعية", comm:"أراضٍ تجارية", land:"أراضٍ" };
const TABU = { green:"طابو أخضر", shares:"حصص سهمية", court:"حكم محكمة", court_desc:"حكم محكمة موصوف", poa:"وكالة كاتب عدل", none:"بدون طابو" };
const DEAL = { sale: { ar:"للبيع", slug:"for-sale" }, rent: { ar:"للإيجار", slug:"for-rent" } };

const esc = (s) => String(s ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
const money = (v) => v == null ? "—" : "$" + Number(v).toLocaleString("en");
const ltr = (s) => `<span class="ltr">${esc(s)}</span>`;
const jsonForScript = (o) => JSON.stringify(o).replace(/</g, "\\u003c");
const q = (o) => Object.entries(o).filter(([, v]) => v != null && v !== "").map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join("&");
const searchUrl = (o) => `${SITE}/search?${q(o)}`;
const listingSlug = (l) => { const t = TYPE[l.property_type] || l.property_type; return (t + " " + (l.area_ar || "") + " " + l.governorate_ar).replace(/[^\p{L}\p{N}\s-]/gu, "").trim().replace(/\s+/g, "-").slice(0, 60); };
const listingUrl = (l) => `${SITE}/listing/${l.id}-${listingSlug(l)}/`;

// ── page shell in the site's own style (same tokens as index.html) ───────
const CSS = `
:root{--navy:#14213D;--navy-2:#0D1729;--navy-w:#EEF1F7;--gold:#C4881F;--gold-dk:#8A6522;--gold-w:#FDF5E7;--ink:#22252A;--grey:#6B7280;--light:#9CA3AF;--line:#E6E2D9;--line-2:#D3D4D8;--page:#F4F2ED;--card:#FFF;--ok:#2E7D5B;--ok-w:#EAF5EF;--f:'IBM Plex Sans Arabic','Cairo',system-ui,sans-serif;--fd:'El Messiri','IBM Plex Sans Arabic',sans-serif;--r:8px;--sh2:0 12px 30px -12px rgba(9,14,26,.28)}
*{box-sizing:border-box;margin:0;padding:0}html{-webkit-text-size-adjust:100%}
body{background:var(--page);color:var(--ink);font:15px/1.8 var(--f);-webkit-font-smoothing:antialiased;overflow-x:hidden}
a{color:inherit;text-decoration:none}img{display:block;max-width:100%}ul{list-style:none}
h1,h2,h3{font-family:var(--fd);font-weight:600;line-height:1.3;color:var(--navy)}
.ltr{direction:ltr;display:inline-block;font-variant-numeric:tabular-nums;unicode-bidi:isolate}
.wrap{max-width:1180px;margin:0 auto;padding:0 18px}
:focus-visible{outline:2px solid var(--gold);outline-offset:2px}
header{background:var(--navy);color:#fff}
.hbar{display:flex;align-items:center;gap:22px;height:62px}
.logo{font:700 24px/1 var(--fd);color:var(--gold);letter-spacing:.01em}
.hnav{display:flex;gap:20px;font-size:14.5px;color:rgba(255,255,255,.86)}
.hnav a:hover{color:var(--gold)}
.htools{margin-inline-start:auto;display:flex;gap:9px;align-items:center}
.mini{border:1px solid rgba(255,255,255,.3);color:#fff;padding:6px 12px;font-size:12.5px;border-radius:5px}
.gold{background:var(--gold);color:#1A1206;border-radius:6px;padding:9px 16px;font-weight:700;font-size:14px}
.gold:hover{background:#D6952A}
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
.cb .d{font-size:11.5px;color:var(--light);margin-top:6px}
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
footer{background:var(--navy);color:rgba(255,255,255,.7);font-size:13.5px;padding:40px 0 22px;margin-top:64px}
.fl{display:flex;flex-wrap:wrap;gap:8px 18px;margin-bottom:14px}
.fl a:hover{color:#fff}
.fb{display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px;padding-top:16px;border-top:1px solid rgba(255,255,255,.14);font-size:12.5px}
@media(max-width:860px){.hnav{display:none}.hbar{height:58px;gap:10px}.gold{padding:8px 12px;font-size:13px}.grid{grid-template-columns:repeat(2,1fr);gap:10px}.cb .p{font-size:17px}}
`;

function shell({ title, desc, canonical, robots = "index, follow", jsonld = [], body, image }) {
  return `<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta name="robots" content="${robots}">
<meta name="theme-color" content="#14213D">
<link rel="canonical" href="${canonical}">
<meta property="og:type" content="website"><meta property="og:site_name" content="Balkoun"><meta property="og:locale" content="ar_SY">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}"><meta property="og:url" content="${canonical}">
${image ? `<meta property="og:image" content="${esc(image)}">` : ""}
<meta name="twitter:card" content="${image ? "summary_large_image" : "summary"}">
<link rel="icon" href="${SITE}/favicon.ico">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&family=El+Messiri:wght@500;600;700&display=swap" rel="stylesheet">
${jsonld.map((o) => `<script type="application/ld+json">${jsonForScript(o)}</script>`).join("\n")}
<style>${CSS}</style></head><body>
<header><div class="wrap hbar"><a class="logo" href="${SITE}/">بلكون</a>
<nav class="hnav"><a href="${searchUrl({ deal: "sale" })}">للبيع</a><a href="${searchUrl({ deal: "rent" })}">للإيجار</a><a href="${SITE}/areas/">المناطق</a><a href="${SITE}/mapsearch">الخريطة</a><a href="${SITE}/about">عن بلكون</a></nav>
<div class="htools"><a class="mini" href="${SITE}/account">دخول</a><a class="gold" href="${SITE}/post">أضف إعلانك</a></div></div></header>
<main class="wrap">${body}</main>
<footer><div class="wrap"><div class="fl">%FOOTLINKS%</div><div class="fb"><span>© 2026 بلكون · balkoun.com</span><span><a href="${SITE}/about">عن المنصّة</a> · <a href="${SITE}/contactus">تواصل معنا</a></span></div></div></footer>
</body></html>`;
}

function crumbs(items) {
  const ld = { "@context":"https://schema.org", "@type":"BreadcrumbList", itemListElement: [{ name:"الرئيسية", href: SITE + "/" }, ...items].map((it, i) => ({ "@type":"ListItem", position: i + 1, name: it.name, ...(it.href ? { item: it.href } : {}) })) };
  const html = `<nav class="crumbs" aria-label="مسار الصفحة"><a href="${SITE}/">الرئيسية</a>${items.map((it) => `<span>›</span>${it.href ? `<a href="${it.href}">${esc(it.name)}</a>` : `<span>${esc(it.name)}</span>`}`).join("")}</nav>`;
  return { html, ld };
}

function card(l, avg) {
  const isRent = l.deal === "rent";
  const deedOk = l.tabu === "green";
  const ppm = l.area_m2 > 0 && l.price_usd ? l.price_usd / l.area_m2 : null;
  const diff = avg && ppm && !isRent ? Math.round((ppm - avg) / avg * 100) : null;
  return `<a class="card${l.is_featured ? " feat" : ""}" href="${listingUrl(l)}">
<div class="ph">${l.cover_url ? `<img src="${esc(l.cover_url)}" alt="${esc(TYPE[l.property_type] || "")} في ${esc(l.area_ar || l.governorate_ar)}" loading="lazy" width="800" height="600">` : `<div class="nop">بدون صورة</div>`}
<div class="badges">${l.is_featured ? `<span class="badge feat">مميّز</span>` : ""}${deedOk ? `<span class="badge ok">طابو أخضر</span>` : ""}</div></div>
<div class="cb"><div class="p">${ltr(money(l.price_usd))}${isRent ? ` <small>/ ${l.rental_period === "yearly" ? "سنوي" : "شهري"}</small>` : ""}</div>
<div class="cb-loc">${esc([l.area_ar, l.governorate_ar].filter(Boolean).join("، "))}${l.landmark ? ` · ${esc(l.landmark)}` : ""}</div>
<div class="cb-details"><span class="cb-type">${esc(TYPE[l.property_type] || l.property_type)}</span>${l.rooms != null ? `<span>${ltr(l.rooms)} غرف</span>` : ""}${l.area_m2 ? `<span>${ltr(l.area_m2)} م²</span>` : ""}${l.floor != null ? `<span>ط ${ltr(l.floor)}</span>` : ""}${l.tabu ? `<span class="cb-deed">${esc(TABU[l.tabu] || l.tabu)}</span>` : ""}${diff != null && Math.abs(diff) >= 5 ? `<span style="color:${diff < 0 ? "var(--ok)" : "var(--gold-dk)"};font-weight:600;margin-inline-start:auto">${diff < 0 ? "تحت" : "فوق"} متوسط المنطقة ${ltr(Math.abs(diff) + "%")}</span>` : ""}</div>
</div></a>`;
}

function govPage({ deal, g, areas, listings, avg, footLinks }) {
  const d = DEAL[deal], other = deal === "sale" ? "rent" : "sale";
  const url = `${SITE}/${d.slug}/${g.slug}/`;
  const title = `عقارات ${d.ar} في ${g.name_ar}`;
  const desc = `${listings.length} إعلاناً ${d.ar} في ${g.name_ar}: شقق، بيوت عربية، فلل، محلات وأراضٍ من المالك مباشرة وبلا عمولة${avg ? `، متوسط سعر المتر ${money(avg)}` : ""}.`;
  const withL = areas.filter((a) => a.count[deal] > 0).sort((x, y) => y.count[deal] - x.count[deal]);
  const c = crumbs([{ name: d.ar, href: searchUrl({ deal }) }, { name: g.name_ar }]);
  const body = `${c.html}
<div class="pagehead"><h1>${esc(title)}</h1><p class="sub">${ltr(listings.length)} إعلاناً${avg ? ` · متوسط سعر المتر للبيع <b>${ltr(money(avg))}</b>` : ""} · <a href="${SITE}/${DEAL[other].slug}/${g.slug}/" style="color:var(--gold-dk)">${DEAL[other].ar} في ${esc(g.name_ar)}</a> · <a href="${searchUrl({ deal, govs: g.name_ar })}" style="color:var(--gold-dk)">بحث متقدّم</a></p></div>
${withL.length ? `<div class="chips">${withL.map((a) => `<a class="chip" href="${SITE}/${d.slug}/${g.slug}/${a.slug}/">${esc(a.name_ar)} <b>${ltr(a.count[deal])}</b></a>`).join("")}</div>` : ""}
${listings.length ? `<div class="grid">${listings.map((l) => card(l, l.area_id ? avgByArea.get(l.area_id) : null)).join("")}</div>` : `<div class="none"><h2>لا إعلانات ${d.ar} في ${esc(g.name_ar)} حالياً</h2><p>كن أول من يعرض عقاره هنا.</p><a class="gold" href="${SITE}/post">أضف إعلانك مجاناً</a></div>`}
<section class="sec"><h2>مناطق ${esc(g.name_ar)}</h2><p class="sub">المناطق التي فيها إعلانات لها صفحتها الخاصة.</p>
<ul class="areas">${areas.map((a) => a.count[deal] > 0 ? `<li><a href="${SITE}/${d.slug}/${g.slug}/${a.slug}/">${esc(a.name_ar)} <b>${ltr(a.count[deal])}</b></a></li>` : `<li>${esc(a.name_ar)}</li>`).join("")}</ul></section>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"CollectionPage", name: title, description: desc, url, numberOfItems: listings.length }];
  return { url, html: shell({ title: title + " | بلكون", desc, canonical: url, robots: listings.length ? "index, follow" : "noindex, follow", jsonld: ld, body, image: listings[0]?.cover_url }).replace("%FOOTLINKS%", footLinks) };
}

let avgByArea = new Map();

function areaPage({ deal, g, a, listings, siblings, market, footLinks }) {
  const d = DEAL[deal];
  const url = `${SITE}/${d.slug}/${g.slug}/${a.slug}/`;
  const title = `عقارات ${d.ar} في ${a.name_ar}، ${g.name_ar}`;
  const types = [...new Set(listings.map((l) => TYPE_PL[l.property_type] || l.property_type))];
  const avg = market && market.listings >= 3 ? Math.round(Number(market.avg_price_per_m2)) : null;
  const desc = `${listings.length} عقاراً ${d.ar} في ${a.name_ar} (${g.name_ar}): ${types.slice(0, 3).join("، ")}${avg && deal === "sale" ? `. متوسط سعر المتر ${money(avg)}` : ""}. من المالك مباشرة وبلا عمولة.`;
  const prices = listings.map((l) => l.price_usd).filter((x) => x != null).sort((x, y) => x - y);
  const faq = [
    { q: `كم عدد العقارات ${d.ar} في ${a.name_ar}؟`, a: `يوجد حالياً ${listings.length} إعلاناً ${d.ar} في ${a.name_ar} على بلكون.` },
    prices.length ? { q: `ما أسعار العقارات ${d.ar} في ${a.name_ar}؟`, a: `تتراوح الأسعار المعروضة بين ${money(prices[0])} و${money(prices[prices.length - 1])}${avg && deal === "sale" ? `، ومتوسط سعر المتر ${money(avg)}` : ""}.` } : null,
    { q: "هل هناك عمولة على المشتري؟", a: "لا. بلكون لا يأخذ عمولة من المشتري أو المستأجر؛ التواصل مباشر مع المالك." },
  ].filter(Boolean);
  const c = crumbs([{ name: d.ar, href: searchUrl({ deal }) }, { name: g.name_ar, href: `${SITE}/${d.slug}/${g.slug}/` }, { name: a.name_ar }]);
  const body = `${c.html}
<div class="pagehead"><h1>${esc(title)}</h1><p class="sub">${ltr(listings.length)} إعلاناً${avg && deal === "sale" ? ` · متوسط سعر المتر <b>${ltr(money(avg))}</b> من ${ltr(market.listings)} إعلاناً` : ""} · <a href="${searchUrl({ deal, govs: g.name_ar, areas: a.name_ar })}" style="color:var(--gold-dk)">بحث متقدّم في ${esc(a.name_ar)}</a></p></div>
<div class="grid">${listings.map((l) => card(l, avg)).join("")}</div>
${siblings.length ? `<section class="sec"><h2>مناطق قريبة في ${esc(g.name_ar)}</h2><div class="chips">${siblings.map((s) => `<a class="chip" href="${SITE}/${d.slug}/${g.slug}/${s.slug}/">${esc(s.name_ar)} <b>${ltr(s.count[deal])}</b></a>`).join("")}<a class="chip" href="${SITE}/${d.slug}/${g.slug}/" style="color:var(--grey)">كل ${esc(g.name_ar)}</a></div></section>` : ""}
<section class="faq"><h2>أسئلة شائعة عن ${esc(a.name_ar)}</h2>${faq.map((f) => `<details><summary>${esc(f.q)}</summary><p>${esc(f.a)}</p></details>`).join("")}</section>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"CollectionPage", name: title, description: desc, url, numberOfItems: listings.length },
    { "@context":"https://schema.org", "@type":"FAQPage", mainEntity: faq.map((f) => ({ "@type":"Question", name: f.q, acceptedAnswer: { "@type":"Answer", text: f.a } })) }];
  return { url, html: shell({ title: title + " | بلكون", desc, canonical: url, jsonld: ld, body, image: listings[0]?.cover_url }).replace("%FOOTLINKS%", footLinks) };
}

function areasIndex({ govs, areasByGov, counts, footLinks }) {
  const url = `${SITE}/areas/`;
  const title = "كل المحافظات والمناطق";
  const totalAreas = [...areasByGov.values()].reduce((s, l) => s + l.length, 0);
  const desc = `تصفّح عقارات سوريا حسب المحافظة والمنطقة: ${govs.length} محافظة و${totalAreas} منطقة على بلكون.`;
  const c = crumbs([{ name: "المناطق" }]);
  const body = `${c.html}<div class="pagehead"><h1>المحافظات والمناطق</h1><p class="sub">${ltr(govs.length)} محافظة · ${ltr(totalAreas)} منطقة</p></div>
<div class="govs">${govs.map((g) => { const list = areasByGov.get(g.id) || []; const live = list.filter((a) => a.count.sale || a.count.rent); const n = counts.gov.get(g.id) || 0;
  return `<section class="gov" id="${esc(g.slug)}"><h2><a href="${SITE}/for-sale/${g.slug}/">${esc(g.name_ar)}</a><small>${ltr(n)} إعلان · ${ltr(list.length)} منطقة</small></h2><div class="lk"><a href="${SITE}/for-sale/${g.slug}/">للبيع</a><a href="${SITE}/for-rent/${g.slug}/">للإيجار</a><a href="${searchUrl({ govs: g.name_ar })}">بحث</a></div>${live.length ? `<ul>${live.map((a) => `<li><a href="${SITE}/${a.count.sale ? "for-sale" : "for-rent"}/${g.slug}/${a.slug}/">${esc(a.name_ar)}</a></li>`).join("")}</ul>` : ""}</section>`; }).join("")}</div>`;
  return { url, html: shell({ title: title + " | بلكون", desc, canonical: url, jsonld: [c.ld], body }).replace("%FOOTLINKS%", footLinks) };
}

// ── About and Contact: same text the app shows (D.ABOUT inside index.html, contact details from site_content) ──
function loadAboutText() {
  const src = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const line = src.split("\n").find((l) => /^var D\s*=\s*\{/.test(l));
  if (!line) throw new Error("index.html: data line not found");
  const sandbox = {};
  vm.runInNewContext(line.replace(/^var D\s*=/, "D=").replace(/;\s*$/, ""), sandbox);
  return sandbox.D.ABOUT.ar;
}
function aboutPage({ footLinks }) {
  const A = loadAboutText();
  const url = `${SITE}/about/`;
  const desc = String(A.lede || "").replace(/<[^>]+>/g, "").slice(0, 160);
  const c = crumbs([{ name: "عن بلكون" }]);
  const body = `${c.html}<article class="prose"><h1>${A.h1}</h1><p class="lede">${A.lede}</p>
${(A.blocks || []).map((b) => `<section class="ab"><h2>${b[0]}</h2>${b[1].map((p) => `<p>${p}</p>`).join("")}</section>`).join("")}
<div class="cta"><div><h2>${A.ctaH}</h2><p>${A.ctaP}</p></div><a class="gold" href="${SITE}/post">أضف إعلانك</a></div></article>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"AboutPage", name: "عن بلكون", url, description: desc },
    { "@context":"https://schema.org", "@type":"Organization", name: "بلكون", alternateName: "Balkoun", url: SITE, areaServed: "SY" }];
  return { url, html: shell({ title: "عن بلكون | Balkoun", desc, canonical: url, jsonld: ld, body }).replace("%FOOTLINKS%", footLinks) };
}
function contactPage({ site, footLinks }) {
  const url = `${SITE}/contactus/`;
  const s = site || {};
  const chan = [];
  if (s.phone_number) chan.push({ label: "هاتف", href: "tel:" + s.phone_number, text: s.phone_number });
  if (s.wa_number) chan.push({ label: "واتساب", href: "https://wa.me/" + String(s.wa_number).replace(/\D/g, ""), text: s.wa_number });
  if (s.email_address) chan.push({ label: "بريد", href: "mailto:" + s.email_address, text: s.email_address });
  if (s.fb_url && s.fb_name) chan.push({ label: "فيسبوك", href: s.fb_url, text: s.fb_name });
  if (s.ig_url && s.ig_name) chan.push({ label: "إنستغرام", href: s.ig_url, text: s.ig_name });
  if (s.yt_url && s.yt_name) chan.push({ label: "يوتيوب", href: s.yt_url, text: s.yt_name });
  if (s.tiktok_url && s.tiktok_name) chan.push({ label: "تيك توك", href: s.tiktok_url, text: s.tiktok_name });
  const desc = "تواصل مع فريق بلكون: استفسارات، اقتراحات، أو مساعدة في نشر إعلانك. نرد خلال يوم عمل.";
  const c = crumbs([{ name: "تواصل معنا" }]);
  const body = `${c.html}<article class="prose"><h1>تواصل معنا</h1><p class="lede">${desc}</p>
${chan.length ? `<div class="chans">${chan.map((x) => `<a class="chan" href="${esc(x.href)}" target="_blank" rel="noopener"><small>${x.label}</small><span class="ltr">${esc(x.text)}</span></a>`).join("")}</div>` : ""}
<form class="cform" id="cf" novalidate><h2>أرسل رسالة</h2>
<div class="row"><label>الاسم<input name="name" autocomplete="name"></label><label>رقم للتواصل أو بريد<input name="contact" autocomplete="tel"></label></div>
<label>رسالتك <span class="req">*</span><textarea name="body" required minlength="10" maxlength="1500" rows="5"></textarea></label>
<div class="row" style="align-items:center"><button class="gold" type="submit">إرسال</button><span id="cfMsg"></span></div></form></article>
<script>(function(){var f=document.getElementById("cf"),m=document.getElementById("cfMsg");f.addEventListener("submit",async function(e){e.preventDefault();var b=f.body.value.trim();if(b.length<10){m.textContent="اكتب 10 أحرف على الأقل.";return}var btn=f.querySelector("button");btn.disabled=true;m.textContent="جارٍ الإرسال…";try{var r=await fetch("${SUPABASE_URL}/rest/v1/rpc/bk_feedback",{method:"POST",headers:{"Content-Type":"application/json",apikey:"${SUPABASE_KEY}",Authorization:"Bearer ${SUPABASE_KEY}"},body:JSON.stringify({p_kind:"inquiry",p_name:f.name.value||null,p_contact:f.contact.value||null,p_body:b,p_user:null})});if(!r.ok)throw new Error(await r.text());f.innerHTML='<h2>وصلتنا رسالتك ✓</h2><p>شكراً لك. سنرد في أقرب وقت.</p>'}catch(err){m.textContent="تعذّر الإرسال، حاول مرة أخرى أو استخدم واتساب.";btn.disabled=false}})})();</script>`;
  const ld = [c.ld, { "@context":"https://schema.org", "@type":"ContactPage", name: "تواصل معنا", url, description: desc }];
  return { url, html: shell({ title: "تواصل معنا | Balkoun", desc, canonical: url, jsonld: ld, body }).replace("%FOOTLINKS%", footLinks) };
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
  const footLinks = usableGovs.slice(0, 12).map((g) => `<a href="${SITE}/for-sale/${g.slug}/">عقارات في ${esc(g.name_ar)}</a>`).join("") + `<a href="${SITE}/areas/">كل المناطق</a>`;

  // remove previously generated trees so deleted areas/govs don't leave stale pages
  for (const dir of ["for-sale", "for-rent", "areas", "about", "contactus"]) fs.rmSync(path.join(ROOT, dir), { recursive: true, force: true });

  const urls = [];
  for (const deal of ["sale", "rent"]) {
    for (const g of usableGovs) {
      const gAreas = areasByGov.get(g.id) || [];
      const gl = live.filter((l) => l.deal === deal && l.governorate_id === g.id);
      const m2 = gAreas.map((a) => avgByArea.get(a.id)).filter(Boolean);
      const avg = m2.length ? Math.round(m2.reduce((s, v) => s + v, 0) / m2.length) : null;
      const page = govPage({ deal, g, areas: gAreas, listings: gl, avg, footLinks });
      write(page.url, page.html); if (gl.length) urls.push({ loc: page.url, priority: "0.7" });
      for (const a of gAreas) {
        const al = gl.filter((l) => l.area_id === a.id);
        if (!al.length) continue;
        const siblings = gAreas.filter((x) => x.id !== a.id && x.count[deal] > 0).slice(0, 12);
        const ap = areaPage({ deal, g, a, listings: al, siblings, market: marketByArea.get(a.id), footLinks });
        write(ap.url, ap.html); urls.push({ loc: ap.url, priority: "0.8" });
      }
    }
  }
  const idx = areasIndex({ govs: usableGovs, areasByGov, counts, footLinks });
  write(idx.url, idx.html); urls.push({ loc: idx.url, priority: "0.6" });
  const ab = aboutPage({ footLinks }); write(ab.url, ab.html); urls.push({ loc: ab.url, priority: "0.5" });
  let site = null;
  try { site = (await sb("site_content?select=phone_number,wa_number,email_address,fb_url,fb_name,ig_url,ig_name,yt_url,yt_name,tiktok_url,tiktok_name&limit=1"))[0]; } catch (e) { console.warn("site_content unreadable:", e.message); }
  const ct = contactPage({ site, footLinks }); write(ct.url, ct.html); urls.push({ loc: ct.url, priority: "0.5" });

  // sitemap: home + these pages + every /listing/ page on disk
  const listingDirs = fs.existsSync(path.join(ROOT, "listing")) ? fs.readdirSync(path.join(ROOT, "listing")).filter((d) => fs.existsSync(path.join(ROOT, "listing", d, "index.html"))) : [];
  const today = new Date().toISOString().slice(0, 10);
  const entries = [{ loc: SITE + "/", priority: "1.0" }, ...urls, ...listingDirs.map((d) => ({ loc: `${SITE}/listing/${d}/`, priority: "0.9" }))];
  fs.writeFileSync(path.join(ROOT, "sitemap.xml"), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${entries.map((e) => `  <url><loc>${e.loc}</loc><lastmod>${today}</lastmod><priority>${e.priority}</priority></url>`).join("\n")}\n</urlset>\n`);
  console.log(`Wrote ${urls.length} governorate/area pages (+ areas index) and sitemap.xml with ${entries.length} URLs.`);
}
main().catch((e) => { console.error(e); process.exit(1); });
