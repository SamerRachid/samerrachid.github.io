// Stamps the theme stylesheet link with the time of the last change (theme-hu.css?v=YYYYMMDDHHMM), so a browser that
// cached an older copy (the owner's desktop Chrome did, through a preview server that once allowed caching) fetches the
// new one on an ordinary reload. Run before csp-hash.mjs after any change to theme-hu.css.
import fs from "fs";
const f = "app.html", s = fs.readFileSync(f, "utf8");
const d = new Date(), p = (n) => String(n).padStart(2, "0");
const v = "" + d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + p(d.getHours()) + p(d.getMinutes());
const out = s.replace(/href="\/theme-hu\.css(\?v=\d+)?"/g, 'href="/theme-hu.css?v=' + v + '"');
if (out === s) { console.log("hu-stamp: link not found or unchanged"); process.exit(1) }
fs.writeFileSync(f, out); console.log("hu-stamp: theme-hu.css?v=" + v);
