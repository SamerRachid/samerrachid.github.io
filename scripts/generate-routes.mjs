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

const SITE = "https://balkoun.com";
const ROOT = path.resolve(".");
const SUPABASE_URL = "https://coajrqynjrptujmzjjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t"; // public anon key
export const ROUTES = [
  { path: "search",    title: "بحث العقارات في سوريا: شقق وبيوت وأراضٍ للبيع والإيجار",  desc: "ابحث في كل إعلانات بلكون: حسب المحافظة والمنطقة ونوع العقار والسعر وحالة الطابو. Property search in Syria." },
  { path: "mapsearch", title: "البحث على الخريطة: عقارات سوريا حسب الموقع",              desc: "تصفّح العقارات على خريطة سوريا واعثر على الشقق والبيوت والأراضي حسب الموقع. Map search for property in Syria." },
  { path: "wanted",    title: "مطلوب: طلبات المشترين والمستأجرين في سوريا",             desc: "اطّلع على ما يبحث عنه المشترون والمستأجرون: المنطقة، الميزانية والتفاصيل، وتواصل معهم مباشرة إذا كان لديك ما يناسبهم." },
  { path: "agencies",  title: "دليل المكاتب العقارية في سوريا",                          desc: "مكاتب عقارية معتمدة في دمشق وحلب وحمص واللاذقية وباقي المحافظات، مع إعلاناتها ومناطق عملها. Real estate agencies in Syria." },
  { path: "projects",  title: "مشاريع جديدة وقيد الإنشاء في سوريا بالتقسيط",             desc: "مشاريع سكنية جديدة وقيد الإنشاء من المطوّرين مباشرة، بخطط دفع واضحة: دفعة أولى وأقساط شهرية. New projects in Syria." },
];
const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// texts for another country: the Syrian names give way to that country's
const localize = (text, c) => c.is_default ? text : text
  .replace(/عقارات سوريا/g, `عقارات ${c.name_ar}`).replace(/في سوريا/g, `في ${c.name_ar}`).replace(/خريطة سوريا/g, `خريطة ${c.name_ar}`).replace(/سوريا/g, c.name_ar)
  .replace(/في دمشق وحلب وحمص واللاذقية وباقي المحافظات/g, `في كل محافظات ${c.name_ar}`)
  .replace(/Syria/g, c.name_en);

function writeCopy(app, dir, url, title, desc, extra) {
  let html = app
    .replace(/<title>[^<]*<\/title>/, `<title>${esc(title)} | بلكون</title>`)
    .replace(/<meta name="description" content="[^"]*">/, `<meta name="description" content="${esc(desc)}">`)
    .replace(/<link rel="canonical" href="[^"]*">/, `<link rel="canonical" href="${url}">`)
    .replace(/<meta property="og:url" content="[^"]*">/, `<meta property="og:url" content="${url}">`)
    .replace(/<meta property="og:title" content="[^"]*">/, `<meta property="og:title" content="${esc(title)}">`)
    .replace(/<meta property="og:description" content="[^"]*">/, `<meta property="og:description" content="${esc(desc)}">`)
    // the language alternates describe the Syrian home page only
    .replace(/<link rel="alternate" hreflang="[^"]*" href="[^"]*">\n?/g, "");
  if (extra) html = extra(html);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "index.html"), html);
}

export async function buildRoutes() {
  const app = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  let countries = [{ code: "SY", name_ar: "سوريا", name_en: "Syria", enabled: true, is_default: true }];
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/countries?select=code,name_ar,name_en,enabled,is_default&order=sort_order.asc`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } });
    if (res.ok) { const rows = await res.json(); if (rows.length) countries = rows; }
  } catch (e) { console.warn("countries unreadable, Syria only:", e.message); }
  if (!countries.some((c) => c.is_default)) countries.forEach((c) => { if (c.code === "SY") c.is_default = true; });
  const urls = [];
  for (const c of countries.filter((c) => c.enabled)) {
    const prefix = c.is_default ? "" : "/" + c.code.toLowerCase();
    const base = path.join(ROOT, prefix.replace(/^\//, ""));
    if (!c.is_default) {
      // the country's home: the app itself, answering 200 at /lb/
      const url = `${SITE}${prefix}/`;
      writeCopy(app, base, url, `بلكون | عقارات ${c.name_ar}`, localize("عقارات سوريا للبيع والإيجار من المالك مباشرة، مع حالة سند الملكية في كل إعلان. Real estate in Syria, direct from owners.", c));
      urls.push(url);
    }
    for (const r of ROUTES) {
      const url = `${SITE}${prefix}/${r.path}/`;
      writeCopy(app, path.join(base, r.path), url, localize(r.title, c), localize(r.desc, c));
      urls.push(url);
    }
  }
  return urls;
}

if (process.argv[1] && process.argv[1].endsWith("generate-routes.mjs")) {
  const urls = await buildRoutes();
  console.log(`Wrote ${urls.length} route pages: ${urls.join(", ")}`);
}
