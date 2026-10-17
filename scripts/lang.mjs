// ════════════════════════════════════════════════════════════════════════
//  BALKOUN · languages of the static pages, per country
//
//  Shared by generate-listings.mjs and generate-pages.mjs. A country's static
//  pages are built in the languages of its `countries.languages` column:
//  Arabic always (at the root of the country), plus whichever of en/de/fr the
//  column lists, in the column's order. Syria lists ar/en/de, Lebanon ar/fr/en.
//  An empty or unreadable column falls back to ar/en/de (the original set).
//  French labels for property types, deeds, condition and directions come from
//  the app itself (index.html `var FR_LABELS = {…}`), the way the app adds them.
// ════════════════════════════════════════════════════════════════════════
import vm from "vm";

export const STATIC_LANGS = ["ar", "en", "de", "fr"];
export const DEFAULT_LANGS = ["ar", "en", "de"];
export function countryLangs(c) {
  const ls = c && Array.isArray(c.languages) ? c.languages.map((x) => String(x || "").trim().toLowerCase()).filter(Boolean) : [];
  if (!ls.length) return DEFAULT_LANGS.slice();
  return ["ar", ...ls.filter((l, i) => l !== "ar" && STATIC_LANGS.includes(l) && ls.indexOf(l) === i)];
}

// testing only: BK_FORCE_ENABLE=LB (comma-separated codes) treats those countries as enabled for this run.
// Unset in the GitHub workflow, so it changes nothing there. The database is never touched.
export function forceEnable(countries) {
  const codes = new Set(String(process.env.BK_FORCE_ENABLE || "").toUpperCase().split(/[\s,]+/).filter(Boolean));
  if (codes.size) for (const c of countries) if (codes.has(c.code)) { c.enabled = true; console.warn(`BK_FORCE_ENABLE: ${c.code} treated as enabled (test run)`); }
  return countries;
}

// French needs the country's article: "au Liban", "du Liban", "en Syrie", "de Syrie"
const FR_IN = { SY: "en Syrie", LB: "au Liban", JO: "en Jordanie", IQ: "en Irak", EG: "en Égypte", DZ: "en Algérie", MA: "au Maroc", TN: "en Tunisie", LY: "en Libye", SA: "en Arabie saoudite", QA: "au Qatar", BH: "à Bahreïn", OM: "à Oman", AE: "aux Émirats arabes unis", KW: "au Koweït", PS: "en Palestine", YE: "au Yémen", SD: "au Soudan", MR: "en Mauritanie", SO: "en Somalie", DJ: "à Djibouti", KM: "aux Comores" };
const FR_OF = { SY: "de Syrie", LB: "du Liban", JO: "de Jordanie", IQ: "d'Irak", EG: "d'Égypte", DZ: "d'Algérie", MA: "du Maroc", TN: "de Tunisie", LY: "de Libye", SA: "d'Arabie saoudite", QA: "du Qatar", BH: "de Bahreïn", OM: "d'Oman", AE: "des Émirats arabes unis", KW: "du Koweït", PS: "de Palestine", YE: "du Yémen", SD: "du Soudan", MR: "de Mauritanie", SO: "de Somalie", DJ: "de Djibouti", KM: "des Comores" };
export const frIn = (code, name) => FR_IN[code] || `en ${name}`;
export const frOf = (code, name) => FR_OF[code] || (/^[AEIOUYÉÈÂÎaeiouyéèâî]/.test(String(name || "")) ? `d'${name}` : `de ${name}`);

// the app's French labels (index.html: var FR_LABELS={…};) and the 4th (French) entry it pushes onto D's label tables
export function loadFrLabels(src) {
  try {
    const i = src.indexOf("var FR_LABELS="); if (i < 0) return {};
    const j = src.indexOf("\n};", i); if (j < 0) return {};
    const box = {}; vm.runInNewContext(src.slice(i + 4, j + 2), box);
    return box.FR_LABELS || {};
  } catch (e) { console.warn("FR_LABELS unreadable, French labels fall back to English:", e.message); return {}; }
}
export function addFrLabels(D, FR) {
  for (const tb of ["TYPES", "TABU", "COND", "LANDC", "DIR"]) {
    const o = D[tb]; if (!o) continue;
    for (const k of Object.keys(o)) if (Array.isArray(o[k]) && o[k].length === 3) o[k].push(((FR || {})[tb] || {})[k] || o[k][1]);
  }
  return D;
}
