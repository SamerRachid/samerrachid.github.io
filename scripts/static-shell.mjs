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
import { split as langSplit } from "./lang-split.mjs";

const ROOT = path.resolve(".");
const SUPABASE_URL = "https://coajrqynjrptujmzjjdh.supabase.co";
const SUPABASE_KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t"; // public anon key
const LANG_DIRS = ["en", "de", "fr"];
const TREES = ["listing", "agency", "for-sale", "for-rent", "areas", "guides", "about", "contactus", "privacy", "terms"];
const KEEP_VERSIONS = 3;

// ── 1. the app's CSS and script, once, under a content hash ──
const app = fs.readFileSync(path.join(ROOT, "app.html"), "utf8");   // the app's source
function largest(re) {
  let best = null, m;
  while ((m = re.exec(app))) if (!best || m[2].length > best.body.length) best = { full: m[0], body: m[2], at: m.index };
  return best;
}
const css = largest(/<style(\s[^>]*)?>([\s\S]*?)<\/style>/g);
const js = largest(/<script((?![^>]*\ssrc=)(?![^>]*application\/ld\+json)[^>]*)>([\s\S]*?)<\/script>/g);
if (!css || !js || css.body.length < 100000 || js.body.length < 500000) throw new Error("app CSS/script not found in app.html");
const hash = crypto.createHash("sha1").update(css.body).update(js.body).digest("hex").slice(0, 10);
const appDir = path.join(ROOT, "bundle");
fs.mkdirSync(appDir, { recursive: true });
const cssFile = `app.${hash}.css`, jsFile = `app.${hash}.js`;
// German in its own file (lang-split.mjs): the app script without it, and /bundle/lang-de.<hash>.js for the German pages
const LS = langSplit(js.body);
if (!LS) throw new Error("lang-split: nothing moved — the tables changed shape?");
const langFile = `lang-${LS.lang}.${hash}.js`;
// the script loader (see the template below). A new behaviour gets a new number: the service worker serves .js files from its
// cache first, so a changed file under the same name would reach some phones one visit late
const LOADER = "loader-2.js";
const LOADER_SRC = `/* Balkoun: adds the page's scripts (data-src: "url#integrity url …", run in that order). On a phone's home page they wait
   until the hero photo the page already carries is painted (at most 2.5 s); elsewhere they are added at once. A page that opens
   in a language kept in its own file (data-lang-<code>) gets that file first — the language is found as the app finds it */
(function(){ var me=document.currentScript, list=((me&&me.getAttribute("data-src"))||"").split(" "), done=false, lang=null;
  try{ var mr=document.querySelector('meta[name="bk-route"]'); if(mr) lang=(JSON.parse(mr.getAttribute("content")||"{}")||{}).lang||null }catch(x){}
  if(!lang){ var q=location.search.match(/[?&]lang=(ar|en|de|fr)(?![a-z])/); if(q) lang=q[1] }
  if(!lang){ try{ lang=localStorage.getItem("balkoun_lang") }catch(x){} }
  var pack=lang&&me&&me.getAttribute("data-lang-"+lang); if(pack) list.unshift(pack);
  var go=function(){
  if(done) return; done=true;
  for(var i=0;i<list.length;i++){ if(!list[i]) continue; var p=list[i].split("#"), s=document.createElement("script"); s.src=p[0]; if(p[1]) s.integrity=p[1]; s.async=false; document.body.appendChild(s) } };
  var img=document.querySelector("#huHero img");
  if(!img || !window.requestAnimationFrame){ go(); return }
  // a photo filling the whole screen (desktop) is taken for a background and never reported as the largest paint: nothing to wait for
  var r=img.getBoundingClientRect(); if(r.width>=innerWidth && r.height>=innerHeight){ go(); return }
  setTimeout(go,2500);
  // Chrome / Edge / Firefox report the paint itself (largest-contentful-paint names the photo); other browsers: decoded, then a frame
  var types=(window.PerformanceObserver&&PerformanceObserver.supportedEntryTypes)||[];
  if(types.indexOf("largest-contentful-paint")>-1){ try{ new PerformanceObserver(function(l){ var e=l.getEntries(); for(var i=0;i<e.length;i++) if(e[i].element===img){ setTimeout(go,0); return } }).observe({type:"largest-contentful-paint",buffered:true}); img.addEventListener("error",go); return }catch(x){} }
  var after=function(){ requestAnimationFrame(function(){ setTimeout(go,0) }) }, ready=function(){ if(img.decode) img.decode().then(after,after); else after() };
  if(img.complete) ready(); else { img.addEventListener("load",ready); img.addEventListener("error",go) } })();
`;
if (!fs.existsSync(path.join(appDir, cssFile))) fs.writeFileSync(path.join(appDir, cssFile), css.body);
for (const [f, body] of [[jsFile, LS.code], [langFile, LS.pack]]) { const p = path.join(appDir, f); if (!fs.existsSync(p) || fs.readFileSync(p, "utf8") !== body) fs.writeFileSync(p, body); }
{ const lp = path.join(appDir, LOADER); if (!fs.existsSync(lp) || fs.readFileSync(lp, "utf8") !== LOADER_SRC) fs.writeFileSync(lp, LOADER_SRC); }
// keep the last few versions (a page cached in a browser for its 10 minutes may still ask for the previous one)
const verFile = path.join(appDir, "versions.json");
let versions = []; try { versions = JSON.parse(fs.readFileSync(verFile, "utf8")); } catch (e) {}
versions = [hash, ...versions.filter((v) => v !== hash)].slice(0, KEEP_VERSIONS);
fs.writeFileSync(verFile, JSON.stringify(versions) + "\n");
for (const f of fs.readdirSync(appDir)) { const m = f.match(/^(?:app|lang-[a-z]{2})\.([0-9a-f]{10})\.(css|js)$/); if (m && !versions.includes(m[1])) fs.rmSync(path.join(appDir, f)); }

// ── 2. the page template: the app with the two big blocks as files, and empty SEO slots ──
const SEO_TAG = /<title>[\s\S]*?<\/title>\n?|<meta name="(?:description|keywords|robots)"[^>]*>\n?|<link rel="(?:canonical|alternate)"[^>]*>\n?|<meta property="og:[^"]*"[^>]*>\n?|<meta name="twitter:[^"]*"[^>]*>\n?|<script type="application\/ld\+json">[\s\S]*?<\/script>\n?/g;
let tpl = app.slice(0, css.at) + `<link rel="stylesheet" href="/bundle/${cssFile}">` + app.slice(css.at + css.full.length);
const jsAt = tpl.indexOf(js.full);
tpl = tpl.slice(0, jsAt) + `<script src="/bundle/${jsFile}"></script>` + tpl.slice(jsAt + js.full.length);
// the vendor scripts and the app file (2026-11-02): one small loader runs once the page is parsed and adds them in the same
// order — on the home page once the hero photo is painted, so it is on screen before the 1.5 MB app script runs (with plain
// defer the photo had arrived but waited behind the script; Lighthouse phone: ~8 s); on every other page at once, as before
{
  const tags = [...tpl.matchAll(/<script src="(\/(?:vendor|bundle)\/[^"]+)"(?: integrity="([^"]+)")?><\/script>\n?/g)];
  if (tags.length !== 3 || !tags[2][1].startsWith("/bundle/app.")) throw new Error("expected supabase, morphdom and the app script, found " + tags.map((t) => t[1]).join(", "));
  const list = tags.map((t) => t[1] + (t[2] ? "#" + t[2] : "")).join(" ");
  const at = tags[0].index;
  for (const t of tags.slice().reverse()) tpl = tpl.slice(0, t.index) + tpl.slice(t.index + t[0].length);
  tpl = tpl.slice(0, at) + `<script defer src="/bundle/${LOADER}" data-src="${list}" data-lang-${LS.lang}="/bundle/${langFile}"></script>\n` + tpl.slice(at);
}
const headEnd = tpl.indexOf("</head>") > -1 ? tpl.indexOf("</head>") : tpl.indexOf("<body");
tpl = tpl.slice(0, headEnd).replace(SEO_TAG, "") + "@@SEOHEAD@@\n" + tpl.slice(headEnd);
tpl = tpl.replace(/<html[^>]*>/, "<html@@HTMLATTR@@>");
tpl = tpl.replace(/<div id="app" role="main"><!--seo-home-->[\s\S]*?<!--\/seo-home--><\/div>|<div id="app" role="main"><\/div>/, () => '<div id="app" role="main"><!--seo-page-->@@BODY@@<!--/seo-page--></div>');
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
  } else if (APP_COPY.test(src)) {
    // a full copy of the app written by generate-routes.mjs (/search/, /wanted/<id>/ …): its own head, no text of its own
    htmlAttr = (src.match(/<html([^>]*)>/) || [, ' lang="ar" dir="rtl"'])[1];
    seoHead = (src.slice(0, src.indexOf("<body")).match(SEO_TAG) || []).map((t) => t.trim()).join("\n");
    body = "";
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
  // a file held for a moment by another program (antivirus / indexer on Windows) is tried again rather than stopping the run
  for (let k = 0; ; k++) { try { fs.writeFileSync(file, out); break; } catch (e) { if (k >= 5) throw e; const t = Date.now(); while (Date.now() - t < 300 * (k + 1)) {} } }
  return "written";
}
// the app's own route pages (generate-routes.mjs): full 2 MB copies until here — the same small shell now (2026-10-31: on a phone
// /search/ painted after 6.4 s in Lighthouse, the shell pages after 1.6 s)
const APP_COPY = /<script>[\s\S]{500000,}?<\/script>/;
const ROUTE_DIRS = ["search", "mapsearch", "wanted", "agencies", "help", "app", "services", "promote", "projects", "delete-account"];
const count = { written: 0, same: 0, skip: 0 };
function walk(dir, rel) {
  if (!fs.existsSync(dir)) return;
  for (const d of fs.readdirSync(dir, { withFileTypes: true })) {
    if (d.isDirectory()) walk(path.join(dir, d.name), rel ? rel + "/" + d.name : d.name);
    else if (d.name === "index.html") count[convert(path.join(dir, d.name), rel)]++;
  }
}
for (const t of TREES) walk(path.join(ROOT, t), t);
for (const t of ROUTE_DIRS) walk(path.join(ROOT, t), t);
for (const l of LANG_DIRS) {
  if (!fs.existsSync(path.join(ROOT, l))) continue;
  const home = path.join(ROOT, l, "index.html"); if (fs.existsSync(home)) count[convert(home, l)]++;
  for (const t of TREES) walk(path.join(ROOT, l, t), l + "/" + t);
}
// ── 5. the home (index.html) and the deep-link fallback (404.html, which GitHub Pages answers for /listing/123, /post …) are
//       light pages too (2026-10-31): the app's own head, the crawlable home block in #app (the home only), no bk-route meta —
//       the app reads the address itself, exactly as it did when both were full 2 MB copies of the app
{
  const head = app.slice(0, app.indexOf("<body")), htmlAttr = (app.match(/<html([^>]*)>/) || [, ' lang="ar" dir="rtl"'])[1];
  const seo = (head.match(SEO_TAG) || []).map((t) => t.trim()).join("\n");
  const homeBlock = (app.match(/<div id="app" role="main">(<!--seo-home-->[\s\S]*?<!--\/seo-home-->)<\/div>/) || [, ""])[1];
  const page = (body) => tpl.replace("@@HTMLATTR@@", () => htmlAttr).replace("@@SEOHEAD@@", () => seo)
    .replace("<!--seo-page-->@@BODY@@<!--/seo-page-->", () => body);
  // the home only: (1) the intro switches as they are now (a first visit has no saved settings, so the phone intro the owner
  // switched off played anyway); (2) the first hero photo is requested from the start instead of after the app has drawn the
  // hero (Lighthouse: the photo is the largest paint, and it waited ~4.6 s for the script on a phone)
  // (3) 2026-11-02: the hero's first photo is in the page, in the same markup the app draws and under the same id, so the app's
  // first draw takes it over (morphdom) instead of the page staying empty until the 500 KB script has run (Lighthouse phone: the
  // photo painted at ~8 s). Not the headline: its place depends on the search bar under it, which only the app draws
  let boot = {}, heroPreload = "", preHero = "", siteCopy = "";
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/site_content?select=*&id=eq.1&limit=1`, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` } });
    const row = r.ok ? (await r.json())[0] : null, ex = (row && row.extras) || {};
    // (4) 2026-11-04: the whole Syrian settings row, for a first visit (nothing saved in the browser yet). Without it the app drew
    //     its built-in headline (four lines on a desktop) and swapped in the owner's one-line headline when the row arrived, so the
    //     search bar jumped up ~180 px (Lighthouse desktop CLS 0.165). A JSON script block never runs, so the CSP needs no hash
    if (row) siteCopy = `<script type="application/json" id="bkSite">${JSON.stringify(row).replace(/</g, String.fromCharCode(92) + "u003c")}</script>`;
    for (const [k, v] of [["opening", "opening_enabled"], ["opening_m", "opening_enabled_m"], ["opening_app", "opening_app"]]) if (ex[v] !== undefined && ex[v] !== null) boot[k] = ex[v];
    if (row && row.hero_bg_type !== "photo" && row.hero_bg_type !== "video") {   // the built-in slides (a studio photo/video has its own address)
      const P = "/next/images/hero/umayyad", V = "?v=2";
      heroPreload = `<link rel="preload" as="image" type="image/avif" href="${P}-phone.avif${V}" media="(max-width:860px)" fetchpriority="high">` +
        `<link rel="preload" as="image" type="image/avif" imagesrcset="${P}-1080.avif${V} 1080w, ${P}-1920.avif${V} 1920w" imagesizes="100vw" media="(min-width:861px)" fetchpriority="high">`;
      // the first slide exactly as heroSlidesHtml() writes it, so the app's patch keeps the same image element
      const slide = `<div class="hslide on"><picture><source media="(max-width:860px)" type="image/avif" srcset="${P}-phone.avif${V}"><source media="(max-width:860px)" type="image/webp" srcset="${P}-phone.webp${V}"><source type="image/avif" srcset="${P}-1080.avif${V} 1080w, ${P}-1920.avif${V} 1920w" sizes="100vw"><img src="${P}-1920.webp${V}" srcset="${P}-1080.webp${V} 1080w, ${P}-1920.webp${V} 1920w" sizes="100vw" alt="" fetchpriority="high"></picture></div>`;
      preHero = `<div class="hero-outer hu pre" id="huHero"><div class="hv on" id="hv"><div class="hslides">${slide}</div></div><div class="hscrim"></div></div>`;   // no empty <section class="hero">: filled later it would grow upwards and count as a layout shift
    }
  } catch (e) { console.warn("site settings unreadable, home without boot settings:", e.message); }
  let homeHtml = page(preHero + homeBlock).replace("</title>", () => `</title>\n<meta name="bk-boot" content="${escAttr(JSON.stringify(boot))}">${heroPreload}${siteCopy}`);
  if (preHero) {   // the hero's styles are scoped to body.home-hero in places; render() sets the same class
    homeHtml = homeHtml.replace("<body>", '<body class="home-hero">');
    if (!homeHtml.includes('<body class="home-hero">')) throw new Error("home: <body> not found for the hero copy");
    // the navy loading cover would sit over the photo until the app draws; the photo is the loading screen now
    const splash = '<div id="bootSplash" aria-hidden="true"></div>';
    if (!homeHtml.includes(splash)) throw new Error("home: bootSplash not found");
    homeHtml = homeHtml.replace(splash, "");
  }
  for (const [f, html] of [["index.html", homeHtml], ["404.html", page("")]]) {
    const p = path.join(ROOT, f); const old = fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "";
    if (old !== html) { for (let k = 0; ; k++) { try { fs.writeFileSync(p, html); break; } catch (e) { if (k >= 5) throw e; const t = Date.now(); while (Date.now() - t < 300 * (k + 1)) {} } } }
  }
  if (!homeBlock) console.warn("warning: no <!--seo-home--> block in app.html — the home page has no crawlable text");
}
console.log(`static pages → app shell (app.${hash}): ${count.written} written, ${count.same} unchanged, ${count.skip} left as they are`);
