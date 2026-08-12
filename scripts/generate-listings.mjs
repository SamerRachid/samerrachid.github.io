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
import { createClient } from "@supabase/supabase-js";
import fs from "fs";
import path from "path";

const SUPABASE_URL = "https://coajrqynjrptujmzjjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t"; // public anon key — safe, RLS restricts it to live listings
const SITE = "https://www.balkoun.com";
const OUT_DIR = path.resolve("listing");
const SITEMAP_PATH = path.resolve("sitemap.xml");

const db = createClient(SUPABASE_URL, SUPABASE_KEY);

const TYPE_AR = { apartment:"شقة", arab:"بيت عربي", villa:"فيلا", floor:"طابق كامل",
  building:"بناء كامل", shop:"محل تجاري", office:"مكتب", resid:"أرض سكنية",
  agri:"أرض زراعية", comm:"أرض تجارية" };
const TABU_AR = { green:"طابو أخضر", shares:"أسهم", court:"حكم محكمة", poa:"وكالة", none:"خارج التنظيم" };
const COND_AR = { intact:"سليم", repair:"يحتاج ترميم", shell:"على العظم", damaged:"متضرر",
  empty:"أرض فارغة", built:"عليها بناء", fenced:"مسوّرة", planted:"مزروعة" };

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

function renderPage(l, photos) {
  const typeLabel = TYPE_AR[l.property_type] || l.property_type;
  const tabuLabel = TABU_AR[l.tabu] || l.tabu;
  const condLabel = COND_AR[l.condition] || l.condition;
  const dealLabel = l.deal === "rent" ? "للإيجار" : "للبيع";
  const title = `${typeLabel} ${dealLabel} ${l.area_m2} م² — ${l.area_ar || ""} ${l.governorate_ar} | بلكون`;
  const desc = (l.description || "").slice(0, 155);
  const url = `${SITE}/listing/${l.id}-${slugify(typeLabel + " " + (l.area_ar||"") + " " + l.governorate_ar)}/`;
  const cover = photos[0] || "";
  const wa = l.contact_phone ? `https://wa.me/${l.contact_phone.replace(/\D/g,"")}` : null;

  const photoTags = photos.length
    ? photos.map(p => `<img src="${esc(p)}" alt="${esc(title)}" loading="lazy" style="width:100%;max-width:640px;border-radius:8px;margin-bottom:10px;display:block">`).join("\n  ")
    : "";

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "RealEstateListing",
    "name": title,
    "description": l.description || "",
    "url": url,
    "datePosted": l.created_at,
    ...(cover ? { "image": photos } : {}),
    "offers": {
      "@type": "Offer",
      "price": l.price_usd,
      "priceCurrency": "USD",
      "availability": "https://schema.org/InStock"
    },
    "address": {
      "@type": "PostalAddress",
      "addressLocality": l.area_ar || l.governorate_ar,
      "addressRegion": l.governorate_ar,
      "addressCountry": "SY"
    },
    "floorSize": { "@type": "QuantitativeValue", "value": l.area_m2, "unitCode": "MTK" }
  };

  return `<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<link rel="canonical" href="${url}">
<meta property="og:type" content="product">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${url}">
${cover ? `<meta property="og:image" content="${esc(cover)}">` : ""}
<meta property="og:locale" content="ar_SY">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">${JSON.stringify(jsonLd)}</script>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;600;700&display=swap" rel="stylesheet">
<style>
 body{font-family:'IBM Plex Sans Arabic',sans-serif;max-width:680px;margin:0 auto;padding:20px 18px 60px;
   color:#1A2233;line-height:1.8;background:#F6F6F7}
 a{color:#14213D}
 .price{font-size:28px;font-weight:700;color:#14213D}
 .tag{display:inline-block;background:#EAF5EF;color:#2E8B57;font-size:13px;font-weight:600;
   padding:4px 12px;border-radius:5px;margin:4px 6px 4px 0}
 .cta{display:block;background:#25976C;color:#fff;text-align:center;padding:14px;border-radius:8px;
   font-weight:700;text-decoration:none;margin-top:16px}
 .backlink{display:inline-block;margin-bottom:14px;font-size:14px}
 h1{font-size:20px;line-height:1.5}
 .meta{color:#666;font-size:14px;margin-bottom:14px}
</style></head><body>
<a class="backlink" href="${SITE}/#/search">\u2039 كل الإعلانات</a>
<h1>${esc(typeLabel)} ${esc(dealLabel)} \u2014 ${esc(l.area_m2)} \u0645\u00b2</h1>
<div class="meta">${esc(l.area_ar || "")}${l.area_ar ? "\u060c " : ""}${esc(l.governorate_ar)}${l.landmark ? " \u00b7 " + esc(l.landmark) : ""}</div>
<div class="price">${money(l.price_usd)}</div>
${photoTags}
<div style="margin-top:10px">
 <span class="tag">${esc(tabuLabel)}</span>
 <span class="tag">${esc(condLabel)}</span>
 ${l.rooms ? `<span class="tag">${l.rooms} غرف</span>` : ""}
 ${l.power_hours ? `<span class="tag">${l.power_hours} ساعة كهرباء</span>` : ""}
</div>
<p>${esc(l.description || "")}</p>
${wa ? `<a class="cta" href="${wa}?text=${encodeURIComponent("مرحبا، مهتم بهذا العقار: " + title)}" target="_blank" rel="noopener">مراسلة عبر واتساب</a>` : ""}
<a class="cta" style="background:#14213D" href="${SITE}/#/listing/${l.id}">افتح الإعلان الكامل بالموقع</a>
</body></html>`;
}

async function main() {
  console.log("Fetching live listings from Supabase\u2026");
  const { data: listings, error } = await db
    .from("v_listings")
    .select("*")
    .eq("status", "live")
    .order("created_at", { ascending: false });

  if (error) { console.error("Fetch failed:", error.message); process.exit(1); }
  console.log(`Found ${listings.length} live listing(s).`);

  fs.rmSync(OUT_DIR, { recursive: true, force: true });
  fs.mkdirSync(OUT_DIR, { recursive: true });

  const urls = [`${SITE}/`];

  for (const l of listings) {
    const { data: photoRows } = await db
      .from("listing_photos")
      .select("url")
      .eq("listing_id", l.id)
      .order("sort_order");
    const photos = (photoRows || []).map(p => p.url);

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
