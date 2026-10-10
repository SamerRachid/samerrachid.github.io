// ════════════════════════════════════════════════════════════════════
//  BALKOUN · branded OG share-image generator
//
//  Builds the 1200×630 image every listing's og:image/twitter:image
//  points to, so a plain link (no attached photo) pasted into
//  Facebook/WhatsApp/Telegram/etc. renders as a branded card — cover
//  photo + logo + price — that is clickable straight through to the
//  listing on balkoun.com. Mirrors the look of the canvas-based promo
//  image the admin "روّج" button builds client-side (admin.js
//  promoPaint), reimplemented here with @napi-rs/canvas since this
//  runs headless in GitHub Actions, not in a browser.
// ════════════════════════════════════════════════════════════════════
import { createCanvas, loadImage, GlobalFonts } from "@napi-rs/canvas";
import fs from "fs";
import path from "path";

const ROOT = path.resolve(".");
let fontsReady = false;
function ensureFonts() {
  if (fontsReady) return;
  GlobalFonts.registerFromPath(path.join(ROOT, "assets/fonts/NotoKufiArabic-Bold.ttf"), "Kufi");
  GlobalFonts.registerFromPath(path.join(ROOT, "assets/fonts/NotoKufiArabic-ExtraBold.ttf"), "KufiXB");
  fontsReady = true;
}

let logoImg = null;
async function getLogo() {
  if (logoImg === undefined) return null;
  if (logoImg) return logoImg;
  try { logoImg = await loadImage(fs.readFileSync(path.join(ROOT, "brand/logo-light.png"))); }
  catch (e) { console.warn("OG logo load failed:", e.message); logoImg = undefined; }
  return logoImg || null;
}

function round(ctx, x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function coverDraw(ctx, im, x, y, w, h) {
  const s = Math.max(w / im.width, h / im.height); const sw = im.width * s, sh = im.height * s;
  ctx.save(); ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip(); ctx.drawImage(im, x + (w - sw) / 2, y + (h - sh) / 2, sw, sh); ctx.restore();
}
function ellipsize(ctx, text, maxW) {
  if (ctx.measureText(text).width <= maxW) return text;
  let s = text;
  while (s.length > 1 && ctx.measureText(s + "…").width > maxW) s = s.slice(0, -1);
  return s + "…";
}

const CARD_W = 1200, CARD_H = 630, SCALE = 2;
export const OG_WIDTH = CARD_W * SCALE, OG_HEIGHT = CARD_H * SCALE; // actual pixel size of the rendered file — callers use this for og:image:width/height

// l: the v_listings row (same shape generate-listings.mjs works with). coverUrl: first photo URL or null.
// title/place/price/deed/periodLabel/dealLabel: plain Arabic strings already formatted by the caller (kept
// here so this module doesn't duplicate generate-listings.mjs's label tables).
export async function renderOgCard({ coverUrl, title, place, price, dealLabel, isRent, periodLabel, deed, areaTxt, roomsTxt }) {
  ensureFonts();
  const W = CARD_W, H = CARD_H, navy = "#14213D", gold = "#E6B655", sand = "#CFC4AE";
  const ph = Math.round(H * 0.62); // photo on top, solid panel below — same split as the admin promo image,
  const c = createCanvas(W * SCALE, H * SCALE); const ctx = c.getContext("2d"); // so text never has to fight a busy/captioned photo for legibility
  ctx.scale(SCALE, SCALE); // render at 2x and downsample on encode — sharp on retina feeds, crisper text/photo than 1x
  ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = "high";
  ctx.fillStyle = navy; ctx.fillRect(0, 0, W, H);
  let photo = null;
  if (coverUrl) { try { const r = await fetch(coverUrl); if (r.ok) photo = await loadImage(Buffer.from(await r.arrayBuffer())); } catch (e) { console.warn("OG cover fetch failed:", coverUrl, e.message); } }
  if (photo) coverDraw(ctx, photo, 0, 0, W, ph); else { ctx.fillStyle = "#0D1729"; ctx.fillRect(0, 0, W, ph); }

  // fade the bottom of the photo into the solid panel, and scrim the top for the logo/badge
  let g = ctx.createLinearGradient(0, 0, 0, 150); g.addColorStop(0, "rgba(20,33,61,.6)"); g.addColorStop(1, "rgba(20,33,61,0)"); ctx.fillStyle = g; ctx.fillRect(0, 0, W, 150);
  g = ctx.createLinearGradient(0, ph - 110, 0, ph); g.addColorStop(0, "rgba(20,33,61,0)"); g.addColorStop(1, navy); ctx.fillStyle = g; ctx.fillRect(0, ph - 110, W, 110);
  ctx.fillStyle = navy; ctx.fillRect(0, ph, W, H - ph);

  ctx.direction = "rtl"; ctx.textAlign = "right"; ctx.textBaseline = "middle";
  // deal badge, top-right
  ctx.font = "800 30px KufiXB"; const bw = ctx.measureText(dealLabel).width + 50;
  round(ctx, W - 40 - bw, 36, bw, 56, 28); ctx.fillStyle = gold; ctx.fill(); ctx.fillStyle = navy; ctx.fillText(dealLabel, W - 40 - 25, 36 + 28);
  // logo, top-left
  const logo = await getLogo();
  if (logo) { const lw = 220, lh = Math.round(lw * logo.height / logo.width); ctx.globalAlpha = .95; ctx.drawImage(logo, 40, 32, lw, lh); ctx.globalAlpha = 1; }

  // text block, in the solid panel below the photo, right-aligned
  const pad = 46, maxW = W - 2 * pad;
  let y = ph + 44;
  ctx.fillStyle = "#fff"; ctx.font = "800 36px KufiXB";
  ctx.fillText(ellipsize(ctx, title, maxW), W - pad, y); y += 40;
  if (place) { ctx.fillStyle = sand; ctx.font = "500 21px Kufi"; ctx.fillText(place, W - pad, y); y += 36; }
  ctx.fillStyle = gold; ctx.font = "800 44px KufiXB"; ctx.direction = "ltr"; ctx.textAlign = "right";
  ctx.fillText(price, W - pad, y);
  if (isRent && periodLabel) { ctx.fillStyle = sand; ctx.font = "500 19px Kufi"; ctx.textAlign = "left"; ctx.fillText(periodLabel, pad, y); ctx.textAlign = "right"; }
  ctx.direction = "rtl"; y += 38;

  // fact chips
  const chips = [areaTxt, roomsTxt, deed].filter(Boolean).slice(0, 3);
  if (chips.length) {
    ctx.font = "700 18px KufiXB"; let cx = W - pad; const ch = 32;
    chips.forEach((ctext) => {
      const w = ctx.measureText(ctext).width + 28; if (cx - w < pad) return;
      round(ctx, cx - w, y, w, ch, ch / 2); ctx.fillStyle = (ctext === deed && /أخضر/.test(deed)) ? "#1f8f5f" : "rgba(255,255,255,.14)"; ctx.fill();
      ctx.fillStyle = "#fff"; ctx.fillText(ctext, cx - 13, y + ch / 2); cx -= w + 9;
    });
  }

  // footer
  const fy = H - 20; ctx.fillStyle = "rgba(255,255,255,.16)"; ctx.fillRect(pad, fy - 18, W - 2 * pad, 1);
  ctx.fillStyle = gold; ctx.font = "800 19px Kufi"; ctx.fillText("ببلاش · بلا عمولة", W - pad, fy);
  ctx.fillStyle = "#fff"; ctx.font = "700 19px Kufi"; ctx.direction = "ltr"; ctx.textAlign = "left"; ctx.fillText("balkoun.com", pad, fy); ctx.direction = "rtl"; ctx.textAlign = "right";

  // PNG, not JPEG: @napi-rs/canvas 1.0.10's bundled JPEG encoder silently corrupts this exact image — large
  // patches of the photo (never the solid-color panel/text) decode back as flat grayscale (R=G=B) after
  // toBuffer("image/jpeg", ...), independent of the quality value (0.5 through 1 all produced the identical
  // byte count, another sign the encoder itself is broken, not the input). Confirmed live: Facebook's share
  // preview showed a grayscale cover photo with a normally-colored navy/gold text panel next to it — exactly
  // what a photo-only corruption looks like. getImageData() right before encoding is correct every time; only
  // the JPEG round-trip loses color, and PNG (lossless, no chroma subsampling to misencode) doesn't exhibit it
  // at any canvas size or image dimension tried. Costs ~1MB instead of ~25KB per card, fetched once by a link-
  // preview crawler rather than by every visitor, so the trade is worth it over a corrupted share image.
  return { buffer: c.toBuffer("image/png"), width: OG_WIDTH, height: OG_HEIGHT };
}
