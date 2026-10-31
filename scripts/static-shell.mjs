// ════════════════════════════════════════════════════════════════════════
//  BALKOUN · the static pages open in the app (2026-10-31)
//
//  generate-listings.mjs / generate-pages.mjs write ~3,200 crawlable pages
//  (listings, /for-sale/…, /for-rent/…, agencies, guides, about, en/, de/)
//  in their own old cream design. A visitor who arrives from Google landed
//  on that old page. This step turns every one of them into a small copy
//  of the app: the page's own SEO head (title, description, canonical,
//  hreflang, og, JSON-LD) and its text stay exactly as generated, inside
//  #app, where the app's first render replaces it with the live screen.
//
//  The app is 2 MB (490 KB of CSS + 1.4 MB of script inline in index.html);
//  3,200 full copies would be ~6.5 GB, over GitHub Pages' limit. So the CSS
//  and the script are written once to /bundle/app.<hash>.css|js (cached by the
//  browser across pages) and each page is ~25 KB. index.html itself, 404.html
//  and the route copies (/search/ …) are untouched.
//
//  A <meta name="bk-route"> tells the app what the page is (language, and for
//  /for-sale/<gov>/<area>/ the deal, governorate and area by name), so it does
//  not depend on the slugs being loaded. Re-running is safe: a page already
//  converted keeps its stored head and text and only gets the new app files.
//  Runs after csp-hash / generate-routes (the workflow and by hand).
// ════════════════════════════════════════════════════════════════════════
import fs from "fs";
import path from "path";
import crypto from "crypto";

const ROOT = path.resolve(".");
const SUPABASE_URL = "https://coajrqynjrptujmzjjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t"; // public anon key
const LANG_DIRS = ["en", "de", "fr"];
const TREES = ["listing", "agency", "for-sale", "for-rent", "areas", "guides", "about", "contactus", "privacy", "terms"];
const KEEP_VERSIONS = 3;

// ── 1. the app's CSS and script, once, under a content hash ──
const app = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
function largest(re) {
  let best = null, m;
  while ((m = re.exec(app))) if (!best || m[2].length > best.body.length) best = { full: m[0], body: m[2], at: m.index };
  return best;
}
const css = largest(/<style(\s[^>]*)?>([\s\S]*?)<\/style>/g);
const js = largest(/<script((?![^>]*\ssrc=)(?![^>]*application\/ld\+json)[^>]*)>([\s\S]*?)<\/script>/g);
if (!css || !js || css.body.length < 100000 || js.body.length < 500000) throw new Error("app CSS/script not found in index.html");
const hash = crypto.createHash("sha1").update(css.body).update(js.body).digest("hex").slice(0, 10);
const appDir = path.join(ROOT, "bundle");
fs.mkdirSync(appDir, { recursive: true });
const cssFile = `app.${hash}.css`, jsFile = `app.${hash}.js`;
if (!fs.existsSync(path.join(appDir, cssFile))) fs.writeFileSync(path.join(appDir, cssFile), css.body);
if (!fs.existsSync(path.join(appDir, jsFile))) fs.writeFileSync(path.join(appDir, jsFile), js.body);
// keep the last few versions (a page cached in a browser for its 10 minutes may still ask for the previous one)
const verFile = path.join(appDir, "versions.json");
let versions = []; try { versions = JSON.parse(fs.readFileSync(verFile, "utf8")); } catch (e) {}
versions = [hash, ...versions.filter((v) => v !== hash)].slice(0, KEEP_VERSIONS);
fs.writeFileSync(verFile, JSON.stringify(versions) + "\n");
for (const f of fs.readdirSync(appDir)) { const m = f.match(/^app\.([0-9a-f]{10})\.(css|js)$/); if (m && !versions.includes(m[1])) fs.rmSync(path.join(appDir, f)); }

// ── 2. the page template: the app with the two big blocks as files, and empty SEO slots ──
const SEO_TAG = /<title>[\s\S]*?<\/title>\n?|<meta name="(?:description|keywords|robots)"[^>]*>\n?|<link rel="(?:canonical|alternate)"[^>]*>\n?|<meta property="og:[^"]*"[^>]*>\n?|<meta name="twitter:[^"]*"[^>]*>\n?|<script type="application\/ld\+json">[\s\S]*?<\/script>\n?/g;
let tpl = app.slice(0, css.at) + `<link rel="stylesheet" href="/bundle/${cssFile}">` + app.slice(css.at + css.full.length);
const jsAt = tpl.indexOf(js.full);
tpl = tpl.slice(0, jsAt) + `<script src="/bundle/${jsFile}"></script>` + tpl.slice(jsAt + js.full.length);
const headEnd = tpl.indexOf("</head>") > -1 ? tpl.indexOf("</head>") : tpl.indexOf("<body");
tpl = tpl.slice(0, headEnd).replace(SEO_TAG, "") + "@@SEOHEAD@@\n" + tpl.slice(headEnd);
tpl = tpl.replace(/<html[^>]*>/, "<html@@HTMLATTR@@>");
tpl = tpl.replace(/<div id="app" role="main">[\s\S]*?<\/div>\s*(?=<style|<link rel="stylesheet" href="\/bundle\/)/, () => '<div id="app" role="main"><!--seo-page-->@@BODY@@<!--/seo-page--></div>\n');
if (!tpl.includes("@@BODY@@") || !tpl.includes("@@SEOHEAD@@") || !tpl.includes("@@HTMLATTR@@")) throw new Error("template slots not found");

// ── 3. names for /for-sale/<gov>/<area>/ ──
async function all(table, select) {
  const out = [];
  for (let from = 0; ; from += 1000) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=${select}&order=id.asc&offset=${from}&limit=1000`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } });
    if (!res.ok) throw new Error(`${table}: HTTP ${res.status}`);
    const rows = await res.json(); out.push(...rows); if (rows.length < 1000) return out;
  }
}
const govs = await all("governorates", "id,name_ar,slug,country_code");
const areas = await all("areas", "id,governorate_id,name_ar,slug");
const govBySlug = new Map(govs.filter((g) => (g.country_code || "SY") === "SY").map((g) => [g.slug, g]));
const areaBySlug = new Map(areas.map((a) => [a.governorate_id + "/" + a.slug, a]));

function routeOf(rel) {   // rel: "en/for-sale/damascus/msakn-brza" (decoded, no slashes at the ends)
  const parts = rel.split("/").filter(Boolean), r = { path: "/" + rel + (rel ? "/" : "") };
  if (LANG_DIRS.includes(parts[0])) r.lang = parts.shift();
  const p0 = parts[0] || "";
  if (!p0) r.view = "home";
  else if (p0 === "for-sale" || p0 === "for-rent") {
    r.view = "search"; r.deal = p0 === "for-rent" ? "rent" : "sale";
    const g = parts[1] && govBySlug.get(parts[1]); if (g) { r.gov = g.name_ar; const a = parts[2] && areaBySlug.get(g.id + "/" + parts[2]); if (a) r.area = a.name_ar; }
  }
  else if (p0 === "areas") r.view = "areas";
  else if (p0 === "guides") r.view = "static";
  else if (["about", "contactus", "privacy", "terms"].includes(p0)) r.view = p0;
  return r;   // listing / agency: the app reads the path itself
}

// ── 4. every generated page → the template ──
const escAttr = (s) => String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
function convert(file, rel) {
  const src = fs.readFileSync(file, "utf8");
  let htmlAttr, seoHead, body;
  if (src.includes("<!--bk-shell-->")) {
    htmlAttr = (src.match(/<html([^>]*)>/) || [, ""])[1];
    seoHead = (src.match(/<!--seo-head-->([\s\S]*?)<!--\/seo-head-->/) || [, ""])[1].trim();
    body = (src.match(/<!--seo-page-->([\s\S]*?)<!--\/seo-page-->/) || [, ""])[1];
  } else {
    if (!/<main[\s>]/.test(src) || /http-equiv="refresh"/.test(src)) return "skip";   // id stubs and old-slug redirects stay as they are
    htmlAttr = (src.match(/<html([^>]*)>/) || [, ' lang="ar" dir="rtl"'])[1];
    const head = src.slice(0, src.indexOf("</head>"));
    seoHead = (head.match(SEO_TAG) || []).map((t) => t.trim()).join("\n");
    body = src.slice(src.indexOf(">", src.indexOf("<body")) + 1, src.lastIndexOf("</body>"))
      .replace(/<header[\s\S]*?<\/header>/, "").replace(/<footer[\s\S]*?<\/footer>/g, "")
      .replace(/<script(?![^>]*application\/ld\+json)[\s\S]*?<\/script>/g, "").replace(/<style[\s\S]*?<\/style>/g, "").trim();
  }
  const route = routeOf(rel);
  const out = tpl
    .replace("@@HTMLATTR@@", () => htmlAttr)
    .replace("@@SEOHEAD@@", () => `<!--seo-head-->\n${seoHead}\n<!--/seo-head-->\n<meta name="bk-route" content="${escAttr(JSON.stringify(route))}"><!--bk-shell-->`)
    .replace("@@BODY@@", () => body);
  if (out === src) return "same";
  fs.writeFileSync(file, out); return "written";
}
const count = { written: 0, same: 0, skip: 0 };
function walk(dir, rel) {
  if (!fs.existsSync(dir)) return;
  for (const d of fs.readdirSync(dir, { withFileTypes: true })) {
    if (d.isDirectory()) walk(path.join(dir, d.name), rel ? rel + "/" + d.name : d.name);
    else if (d.name === "index.html") count[convert(path.join(dir, d.name), rel)]++;
  }
}
for (const t of TREES) walk(path.join(ROOT, t), t);
for (const l of LANG_DIRS) {
  if (!fs.existsSync(path.join(ROOT, l))) continue;
  const home = path.join(ROOT, l, "index.html"); if (fs.existsSync(home)) count[convert(home, l)]++;
  for (const t of TREES) walk(path.join(ROOT, l, t), l + "/" + t);
}
console.log(`static pages → app shell (app.${hash}): ${count.written} written, ${count.same} unchanged, ${count.skip} left as they are`);
