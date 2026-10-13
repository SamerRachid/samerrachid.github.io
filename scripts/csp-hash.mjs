// ════════════════════════════════════════════════════════════════════════
//  BALKOUN · CSP script hashes
//
//  index.html carries a Content-Security-Policy <meta> whose script-src
//  allows inline scripts only by SHA-256 hash, so a script injected into
//  the page (XSS) is refused by the browser. The app itself is inline, and
//  its text changes with every release, so the hashes are recomputed here:
//  locally before a commit, and in the Actions build right before the
//  route copies and 404.html are written (they inherit the same scripts).
//
//  usage: node scripts/csp-hash.mjs [file ...]     (default: index.html)
// ════════════════════════════════════════════════════════════════════════
import fs from "fs";
import crypto from "crypto";

const files = process.argv.slice(2).length ? process.argv.slice(2) : ["index.html"];
let failed = false;
for (const f of files) {
  const html = fs.readFileSync(f, "utf8");
  // every inline <script> that the browser executes: no src, and not a JSON-LD data block
  const scripts = [...html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)]
    .filter((m) => !/\ssrc=/.test(m[1]) && !/application\/ld\+json/.test(m[1]))
    .map((m) => m[2]);
  const hashes = scripts.map((s) => "'sha256-" + crypto.createHash("sha256").update(s, "utf8").digest("base64") + "'");
  const re = /(<meta http-equiv="Content-Security-Policy" content="[^"]*?script-src[^;"]*?)((?:'sha256-[A-Za-z0-9+/=]+'\s*)+)/;
  if (!re.test(html)) { console.error(`${f}: no CSP meta with sha256 tokens in script-src`); failed = true; continue; }
  const out = html.replace(re, (_, pre) => pre + hashes.join(" ") + " ");
  if (out !== html) { fs.writeFileSync(f, out); console.log(`${f}: CSP hashes updated (${hashes.length} inline scripts)`); }
  else console.log(`${f}: CSP hashes unchanged (${hashes.length} inline scripts)`);
}
if (failed) process.exit(1);
