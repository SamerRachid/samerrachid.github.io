// ════════════════════════════════════════════════════════════════════════
//  BALKOUN · German moves out of the app script (2026-11-02)
//
//  Every visitor downloaded the German text of the site (~50 KB compressed)
//  though only the German pages use it. static-shell.mjs passes the app
//  script through split(): in the four tables that hold the site's words —
//  D (I18N, GUIDES, ABOUT …), GX_T, HX_T and LEGAL — each { ar, en, de … }
//  entry loses its `de`, which goes to /bundle/lang-de.<hash>.js instead.
//
//  At run time bkLangFill(name) puts them back: the script calls it right
//  after each table is defined (so a German page sees exactly the original
//  tables), and bkLangLoad("de") calls it for all four when a visitor
//  switches to German later. Only plain literals move (strings, numbers,
//  objects and arrays of them); anything computed stays in the script.
//  D.I18N.de keeps its dir and name (the language menu and the page
//  direction read them before any German is needed).
//  French stays in the script: it is built at start-up from FR_T / FR_GX
//  and is small.
// ════════════════════════════════════════════════════════════════════════
import * as acorn from "acorn";

const TABLES = ["D", "GX_T", "HX_T", "LEGAL"];
const LANG = "de";
const LANG_KEYS = ["ar", "en", "de", "fr"];

const keyOf = (p) => (p.type === "Property" && !p.computed && !p.method && p.kind === "init")
  ? (p.key.type === "Identifier" ? p.key.name : (p.key.type === "Literal" ? String(p.key.value) : null)) : null;

// a value that can be written into the language file as it is: no names, no calls, no code
function pure(n) {
  if (!n) return false;
  switch (n.type) {
    case "Literal": return !n.regex;
    case "TemplateLiteral": return n.expressions.length === 0;
    case "UnaryExpression": return (n.operator === "-" || n.operator === "+") && n.argument.type === "Literal" && typeof n.argument.value === "number";
    case "ArrayExpression": return n.elements.every((e) => e && pure(e));
    case "ObjectExpression": return n.properties.every((p) => keyOf(p) !== null && pure(p.value));
    default: return false;
  }
}

export function split(code) {
  const ast = acorn.parse(code, { ecmaVersion: 2022, sourceType: "script" });
  const cuts = [];        // [start, end, replacement] in the script
  const fills = {};       // table → [[path, key, valueSource, merge?]]
  const after = [];       // [position after the table's statement, table]
  for (const st of ast.body) {
    if (st.type !== "VariableDeclaration") continue;
    for (const d of st.declarations) {
      const name = d.id && d.id.name;
      if (!TABLES.includes(name) || !d.init || d.init.type !== "ObjectExpression") continue;
      const list = (fills[name] = fills[name] || []);
      const visit = (node, path) => {
        if (node.type === "ArrayExpression") { node.elements.forEach((e, i) => { if (e) visit(e, path.concat(i)); }); return; }
        if (node.type !== "ObjectExpression") return;
        const keys = node.properties.map(keyOf);
        if (keys.some((k) => k === null)) return;   // a spread or a computed key: leave this object alone
        const isLangSet = keys.length > 1 && keys.every((k) => LANG_KEYS.includes(k)) && keys.includes("ar") && keys.includes(LANG);
        // a key written twice in one object (GX_T has a few): only the last one counts, as in JavaScript
        const last = {}; keys.forEach((k, i) => { last[k] = i; });
        node.properties.forEach((p, i) => {
          const k = keys[i];
          if (last[k] !== i) return;
          if (isLangSet && k === LANG) {
            const v = p.value;
            if (v.type === "ObjectExpression" && keyOf(v.properties.find((q) => keyOf(q) === "dir") || {}) === "dir") {
              // D.I18N.de: keep dir and name in place, move the rest
              const keep = v.properties.filter((q) => ["dir", "name"].includes(keyOf(q)));
              const move = v.properties.filter((q) => !["dir", "name"].includes(keyOf(q)));
              if (!move.every((q) => keyOf(q) !== null && pure(q.value))) return;
              list.push([path, k, "{" + move.map((q) => code.slice(q.start, q.end)).join(",") + "}", 1]);
              cuts.push([v.start, v.end, "{" + keep.map((q) => code.slice(q.start, q.end)).join(",") + "}"]);
              return;
            }
            if (!pure(v)) return;
            list.push([path, k, code.slice(v.start, v.end), 0]);
            // drop the property with the comma that joins it to its neighbour
            const prev = node.properties[i - 1], next = node.properties[i + 1];
            if (next) cuts.push([p.start, next.start, ""]);
            else if (prev) cuts.push([prev.end, p.end, ""]);
            else cuts.push([p.start, p.end, ""]);
            return;
          }
          visit(p.value, path.concat(k));
        });
      };
      visit(d.init, []);
      if (list.length) after.push([st.end, name]);
    }
  }
  const moved = Object.values(fills).reduce((n, l) => n + l.length, 0);
  if (!moved) return null;
  // apply the cuts from the end, then the fill calls after each table's statement
  const edits = cuts.map((c) => ({ at: c[0], end: c[1], text: c[2] }))
    .concat(after.map((a) => ({ at: a[0], end: a[0], text: `\n;bkLangFill("${a[1]}");` })))
    .sort((a, b) => b.at - a.at || b.end - a.end);
  for (let i = 1; i < edits.length; i++) if (edits[i].end > edits[i - 1].at) throw new Error("lang-split: overlapping edits");
  let out = code;
  for (const e of edits) out = out.slice(0, e.at) + e.text + out.slice(e.end);
  const head = `/* German lives in /bundle/lang-${LANG}.*.js (scripts/lang-split.mjs): bkLangFill puts it back into the four tables */
var BK_LANG_SPLIT=["${LANG}"];
function bkLangFill(name){ var P=window.__BK_LANG, list=P&&P.t&&P.t[name], root=window[name]; if(!list||!root) return;
  for(var i=0;i<list.length;i++){ var it=list[i], o=root; for(var j=0;j<it[0].length&&o;j++) o=o[it[0][j]]; if(!o||typeof o!=="object") continue;
    // fill what is missing: a value the script set in the meantime (a later Object.assign, a fallback) wins, as it did before the split
    if(it[3]){ var t=o[it[1]]; if(!t||typeof t!=="object") continue; for(var k in it[2]) if(!(k in t)) t[k]=it[2][k] }
    else if(o[it[1]]===undefined) o[it[1]]=it[2] } }
`;
  const pack = `/* Balkoun: the German words of the site, put back by bkLangFill (scripts/lang-split.mjs) */
window.__BK_LANG={lang:"${LANG}",t:{` + Object.entries(fills).filter(([, l]) => l.length).map(([n, l]) => JSON.stringify(n) + ":[" + l.map((it) => "[" + JSON.stringify(it[0]) + "," + JSON.stringify(it[1]) + "," + it[2] + "," + it[3] + "]").join(",\n") + "]").join(",\n") + `}};\n`;
  return { code: head + out, pack, lang: LANG, moved };
}
