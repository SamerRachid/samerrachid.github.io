// ════════════════════════════════════════════════════════════════════════
//  BALKOUN · real pages for the app's own routes
//
//  GitHub Pages answers unknown paths with 404.html (the app), which works
//  for visitors but tells Google "not found". For the routes that deserve
//  indexing we write a copy of the app into <route>/index.html so they
//  answer 200, each with its own title, description and canonical URL.
//  Every other enabled country in the `countries` table gets the same set
//  under /<code>/ (its home /lb/ included), with the country's name in the
//  texts. Runs in GitHub Actions after the app is built; harmless to re-run.
// ════════════════════════════════════════════════════════════════════════
import fs from "fs";
import path from "path";
import vm from "vm";
import { forceEnable } from "./lang.mjs";

const SITE = "https://balkoun.com";
const ROOT = path.resolve(".");
const SUPABASE_URL = "https://coajrqynjrptujmzjjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t"; // public anon key
export const ROUTES = [
  { path: "search",    title: "بحث العقارات في سوريا: شقق وبيوت وأراضٍ للبيع والإيجار",  desc: "ابحث في كل إعلانات بلكون: حسب المحافظة والمنطقة ونوع العقار والسعر وحالة الطابو. Property search in Syria." },
  { path: "mapsearch", title: "البحث على الخريطة: عقارات سوريا حسب الموقع",              desc: "تصفّح العقارات على خريطة سوريا واعثر على الشقق والبيوت والأراضي حسب الموقع. Map search for property in Syria." },
  { path: "wanted",    title: "مطلوب: طلبات المشترين والمستأجرين في سوريا",             desc: "اطّلع على ما يبحث عنه المشترون والمستأجرون: المنطقة، الميزانية والتفاصيل، وتواصل معهم مباشرة إذا كان لديك ما يناسبهم." },
  { path: "agencies",  title: "دليل المكاتب العقارية في سوريا",                          desc: "مكاتب عقارية معتمدة في دمشق وحلب وحمص واللاذقية وباقي المحافظات، مع إعلاناتها ومناطق عملها. Real estate agencies in Syria." },
  { path: "help",      title: "شروحات بلكون: كيف تسجّل وتنشر إعلانك",                       desc: "فيديوهات قصيرة تشرح خطوة بخطوة كيف تسجّل في بلكون وكيف تنشر إعلانك العقاري برسالة نصية." },
  { path: "app",       title: "تطبيق بلكون على هاتفك: ثبّته مجاناً",                         desc: "ثبّت تطبيق بلكون على آيفون أو أندرويد مجاناً وبدون متجر تطبيقات: عقارات للبيع والإيجار من المالك مباشرة. Install the Balkoun app." },
  { path: "services",  title: "خدمات العقار في سوريا: إكساء، سباك، كهربائي، طاقة شمسية، نقل أثاث",  desc: "أصحاب مهن في مدينتك: إكساء وترميم، سباكة وكهرباء، طاقة شمسية وتكييف، ألمنيوم ومطابخ ونجارة، نقل أثاث وتنظيف. تواصل معهم مباشرة على واتساب." },
  { path: "promote",   title: "روّج إعلانك العقاري: تمييز وإعلان ممول على فيسبوك وإنستغرام",    desc: "اجعل إعلانك في أول نتائج البحث على بلكون، أو حوّله إلى ريل ممول على فيسبوك وإنستغرام وحالات واتساب. أسعار واضحة، وتدفع بعد الموافقة." },
  { path: "projects",  title: "مشاريع جديدة وقيد الإنشاء في سوريا بالتقسيط",             desc: "مشاريع سكنية جديدة وقيد الإنشاء من المطوّرين مباشرة، بخطط دفع واضحة: دفعة أولى وأقساط شهرية. New projects in Syria." },
];
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// texts for another country: the Syrian names give way to that country's
const localize = (text, c) => c.is_default ? text : text
  .replace(/عقارات سوريا/g, `عقارات ${c.name_ar}`).replace(/في سوريا/g, `في ${c.name_ar}`).replace(/خريطة سوريا/g, `خريطة ${c.name_ar}`).replace(/سوريا/g, c.name_ar)
  .replace(/في دمشق وحلب وحمص واللاذقية وباقي المحافظات/g, `في كل محافظات ${c.name_ar}`)
  .replace(/Syria/g, c.name_en);

// another country: the Syrian-only head bits go (keywords), the locale and the JSON-LD name that country
const countryHead = (c) => (html) => c.is_default ? html : html
  .replace(/<meta name="keywords" content="[^"]*">\n?/, "")
  .replace(/<meta property="og:locale" content="ar_SY">/, `<meta property="og:locale" content="ar_${c.code}">`)
  .replace(/"inLanguage":\[[^\]]*\]/, `"inLanguage":${JSON.stringify(c.languages && c.languages.length ? c.languages : ["ar", "en"])}`)
  .replace(/"description":"Syrian property listings[^"]*"/, `"description":"Property listings in ${c.name_en} with the ownership status on every ad, direct from owners."`)
  .replace(/"url":"https:\/\/balkoun\.com\/"/, `"url":"https://balkoun.com/${c.code.toLowerCase()}/"`);
function writeCopy(app, dir, url, title, desc, extra) {
  let html = app
    .replace(/<title>[^<]*<\/title>/, `<title>${esc(title)} | بلكون</title>`)
    .replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${esc(desc)}">`)
    .replace(/<link rel="canonical" href="[^"]*">/, `<link rel="canonical" href="${url}">`)
    .replace(/<meta property="og:url" content="[^"]*">/, `<meta property="og:url" content="${url}">`)
    .replace(/<meta property="og:title" content="[^"]*">/, `<meta property="og:title" content="${esc(title)}">`)
    .replace(/<meta property="og:description" content="[^"]*">/, `<meta property="og:description" content="${esc(desc)}">`)
    // the language alternates describe the Syrian home page only
    .replace(/<link rel="alternate" hreflang="[^"]*" href="[^"]*">\n?/g, "")
    // the crawlable home block belongs to / only (duplicate text on /search etc. would compete with the home)
    .replace(/<!--seo-home-->[\s\S]*?<!--\/seo-home-->/, "");
  if (extra) html = extra(html);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "index.html"), html);
}

export async function buildRoutes() {
  const app = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  let countries = [{ code: "SY", name_ar: "سوريا", name_en: "Syria", enabled: true, is_default: true }];
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/countries?select=code,name_ar,name_en,enabled,is_default,languages&order=sort_order.asc`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } });
    if (res.ok) { const rows = await res.json(); if (rows.length) countries = rows; }
  } catch (e) { console.warn("countries unreadable, Syria only:", e.message); }
  if (!countries.some((c) => c.is_default)) countries.forEach((c) => { if (c.code === "SY") c.is_default = true; });
  forceEnable(countries);   // test runs only (BK_FORCE_ENABLE, unset in the workflow)
  const urls = [];
  // request pages have one address for every country (/wanted/<id>/, 2026-10-17): the old /lb/wanted/<id>/ ones go
  for (const c of countries.filter((c) => !c.is_default)) cleanWantedPages(path.join(ROOT, c.code.toLowerCase()), new Set());
  const wantedRows = [];   // every enabled country's open requests, written once below
  for (const c of countries.filter((c) => c.enabled)) {
    const prefix = c.is_default ? "" : "/" + c.code.toLowerCase();
    const base = path.join(ROOT, prefix.replace(/^\//, ""));
    if (!c.is_default) {
      // the country's home: the app itself, answering 200 at /lb/
      const url = `${SITE}${prefix}/`;
      writeCopy(app, base, url, `بلكون | عقارات ${c.name_ar}`, localize("عقارات سوريا للبيع والإيجار من المالك مباشرة، مع حالة سند الملكية في كل إعلان. Real estate in Syria, direct from owners.", c), countryHead(c));
      urls.push(url);
    }
    for (const r of ROUTES) {
      const url = `${SITE}${prefix}/${r.path}/`;
      writeCopy(app, path.join(base, r.path), url, localize(r.title, c), localize(r.desc, c), countryHead(c));
      urls.push(url);
    }
    const rows = await readWanted(c); if (rows === null) { wantedRows.failed = true; continue } rows.forEach((w) => wantedRows.push({ w, c }));
  }
  urls.push(...buildWantedPages(app, wantedRows));
  return urls;
}

// ── one real page per open request (/wanted/<id>/, 2026-10-16) ─────────────────────────────────────────────────
// Before this, /wanted/37 had no file: GitHub answered 404.html (the app), so the request still opened for a visitor,
// but WhatsApp/Facebook previews showed the home page's title and Google never indexed it. Each open, unexpired
// request now gets a copy of the app with its own title and description; nothing about the request itself changes
// (same id, same address, same data). A request that closes, expires or is deleted loses its page on the next run and
// its link keeps working through 404.html exactly as before. Phone numbers never go into the page text.
// the app's own type names (the `var D = {…}` data line of index.html), so a type added in the panel is named too
const W_AR = (() => {
  try {
    const line = fs.readFileSync(path.join(ROOT, "index.html"), "utf8").split("\n").find((l) => /^var D\s*=\s*\{/.test(l));
    const box = {}; vm.runInNewContext(line.replace(/^var D\s*=/, "D=").replace(/;\s*$/, ""), box);
    return Object.fromEntries(Object.entries(box.D.TYPES || {}).map(([k, v]) => [k, v[0]]));
  } catch (e) { console.warn("type names unreadable:", e.message); return {}; }
})();
const noPhones = (s) => String(s || "").replace(/\+?\d[\d\s-]{6,}\d/g, "").replace(/\s+/g, " ").trim();
function wantedTexts(w, c) {
  const types = (w.property_types && w.property_types.length ? w.property_types : (w.property_type ? [w.property_type] : [])).map((k) => W_AR[k] || "").filter(Boolean);
  const deal = w.deal === "rent" ? "للإيجار" : "للشراء";
  const where = w.gov_name || c.name_ar;
  const title = "مطلوب: " + (noPhones(w.title) || `${types.join(" أو ") || "عقار"} ${deal} في ${where}`);
  const cur = w.currency || "USD", num = (n) => Number(n).toLocaleString("en");
  const budget = w.budget_min && w.budget_max ? `الميزانية ${num(w.budget_min)}–${num(w.budget_max)} ${cur}` : w.budget_max ? `الميزانية حتى ${num(w.budget_max)} ${cur}` : w.budget_min ? `الميزانية من ${num(w.budget_min)} ${cur}` : "";
  const areas = (w.area_names || []).slice(0, 3).join("، ");
  const lead = [`${types.join(" أو ") || "عقار"} ${deal}`, where + (areas ? " – " + areas : ""), budget].filter(Boolean).join(" · ");
  const more = noPhones(w.description).slice(0, 150);
  return { title, desc: (lead + (more ? ". " + more : "") + ". لديك ما يناسب؟ تواصل مع صاحب الطلب على بلكون.").slice(0, 300) };
}
function cleanWantedPages(base, keep) {
  const dir = path.join(base, "wanted");
  if (!fs.existsSync(dir)) return;
  for (const d of fs.readdirSync(dir, { withFileTypes: true })) {
    if (d.isDirectory() && /^\d+$/.test(d.name) && !keep.has(d.name)) fs.rmSync(path.join(dir, d.name), { recursive: true, force: true });
  }
}
async function readWanted(c) {
  let rows;
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/bk_public_wanted`, { method: "POST", headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify({ p_country: c.code }) });
    if (!res.ok) throw new Error("HTTP " + res.status);
    rows = await res.json();
  } catch (e) { console.warn(`requests for ${c.code} unreadable, pages left as they are:`, e.message); return null; }
  return (Array.isArray(rows) ? rows : []).filter((w) => w && w.id && w.status === "open" && (!w.expires_at || new Date(w.expires_at) > new Date()));
}
function buildWantedPages(app, all) {
  if (!all.failed) cleanWantedPages(ROOT, new Set(all.map((x) => String(x.w.id))));   // only after every read succeeded: a failed read never deletes pages
  const urls = [];
  for (const { w, c } of all) {
    const url = `${SITE}/wanted/${w.id}/`;
    const t = wantedTexts(w, c);
    writeCopy(app, path.join(ROOT, "wanted", String(w.id)), url, t.title, t.desc, countryHead(c));
    urls.push(url);
  }
  return urls;
}

if (process.argv[1] && process.argv[1].endsWith("generate-routes.mjs")) {
  const urls = await buildRoutes();
  console.log(`Wrote ${urls.length} route pages: ${urls.join(", ")}`);
}
