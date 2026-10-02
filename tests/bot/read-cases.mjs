// Balkoun · intake bot · reading cases (the model + the code guards) — run before every deploy of the Edge Function.
//   node tests/bot/read-cases.mjs <admin-token>        (a panel admin session token; expires on its own)
// Each case is a real message shape seen in use, with what the bot must get right. Costs ~0.5¢ per case in tokens.
// Note: test_claude runs settle() + areaGuards(); governorate defaulting / units title live in readDraft and are
// covered by the SQL scenarios and by watching the panel, not here.
const SB = "https://coajrqynjrptujmzjjdh.supabase.co", KEY = "sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t";
const token = process.argv[2]; if (!token) { console.error("usage: node tests/bot/read-cases.mjs <admin-token>"); process.exit(2); }

const CASES = [
  { name: "transport line is not the area", text: "للبيع شقة اول طريق المطار بعد دار البيطرة جانب الكازية\nمكرو خط المهاجرين عباب الشقة\nطابق اول. مساحة70متر\nغرفتين وصالون\nالسعر 40 الف وبازار",
    expect: { deal: "sale", property_type: "apartment", area_m2: 70, price: 40000, rooms: 2, negotiable: true }, areaNot: "المهاجرين", areaIs: "البيطرة" },
  { name: "two apartments = one listing, total price", text: "للبيع شقتين في حماة حي الحاضر طابق أول وثاني كل شقة 110 متر 3 غرف وصالون\nالملكية وضع يد\nالسعر للشقتين 60 ألف دولار",
    expect: { deal: "sale", property_type: "apartment", tabu: "possession", price: 60000, area_m2: 110 }, raw: { listings_count: 2 }, areaIs: "الحاضر" },
  { name: "bare أرض stays أرض", text: "ارض للبيع في حماة قرب قمحانة 2 دونم طابو اخضر السعر 30 الف", expect: { property_type: "plot", deal: "sale", area_m2: 2000, tabu: "green", price: 30000 } },
  { name: "أرض زراعية keeps its kind", text: "أرض زراعية للبيع في ريف حماة 10 دونم", expect: { property_type: "agri", deal: "sale", area_m2: 10000 } },
  { name: "hotel apartment is rent only", text: "شقة مفروشة فندقية للإيجار اليومي في المزة بدمشق 60$ باليوم", expect: { property_type: "hotelapt", deal: "rent", rental_period: "daily", price: 60 }, areaIs: "المزة" },
  { name: "2400 سهم طابو أخضر is a full green deed", text: "شقة للبيع في حماة حي الصابونية 140 متر طابو أخضر 2400 سهم 55 ألف", expect: { tabu: "green", price: 55000, area_m2: 140 } },
  { name: "منزل with a floor and lift is an apartment", text: "منزل للبيع مزة فيلات شرقيه دخلة اللوتس طابق تاني مصعد مساحة ١٢٠متر السعر ٢٦٠ الف دولار طابو أخضر", expect: { property_type: "apartment", price: 260000, area_m2: 120, tabu: "green" }, areaIs: "مزة فيلات شرقية" },
  { name: "sale OR rent with a sale price → sale", text: "للبيع_أو_للإيجار صالون حلاقة نسائية بالزاهرة القديمة جانب المركز الثقافي\nالمساحة : 22 متر\nالملكية : طابو أخضر\nالبيع : 100 ألف دولار", expect: { deal: "sale", property_type: "shop", area_m2: 22, tabu: "green", price: 100000 }, areaIs: "الزاهرة القديمة" },
  { name: "hashtags and Arabic digits", text: "للبيع شقة #طابق اول #مساحة70متر غرفتين وصالون في حماة حي البعث السعر ٣١ الف", expect: { deal: "sale", area_m2: 70, price: 31000, rooms: 2 } },
  { name: "unknown place stays a landmark, no look-alike swap", text: "شقة للبيع في دمشق حي العدوي الجديد 90 متر 70 ألف طابو أخضر", expectNot: { area: "العسالي" } },
  { name: "wanted request is not a listing", text: "بدي شقة للإيجار في المزة أو المالكي بحدود 300 دولار شهري", raw: { intent: "wanted" } },
  { name: "greeting is not a listing", text: "مرحبا كيفكم، بدي اسأل عن طريقة النشر عندكم", raw: { intent: "other" } },
  { name: "rent with monthly price", text: "شقة للأجار في حمص الوعر 120 متر مفروشة 250 دولار بالشهر", expect: { deal: "rent", property_type: "apartment", rental_period: "monthly", furnished: true, price: 250 }, areaIs: "الوعر" },
  { name: "shop for rent", text: "محل تجاري للإيجار في حلب الجميلية 40 متر 500 دولار شهري", expect: { deal: "rent", property_type: "shop", area_m2: 40, price: 500 }, areaIs: "الجميلية" },
  { name: "villa in a farm village", text: "فيلا للبيع في ريف دمشق يعفور 500 متر مع حديقة 3 ملايين دولار", expect: { deal: "sale", property_type: "villa", area_m2: 500, price: 3000000 }, areaIs: "يعفور" },
];

const norm = (s) => String(s || "").replace(/[ً-ْـ]/g, "").replace(/^ال/, "").replace(/[أإآ]/g, "ا").replace(/ة/g, "ه").replace(/ى/g, "ي").trim();
let pass = 0, fail = 0;
for (const c of CASES) {
  const r = await fetch(SB + "/functions/v1/bk-intake/admin", { method: "POST", headers: { "Content-Type": "application/json", apikey: KEY, Authorization: "Bearer " + KEY }, body: JSON.stringify({ token, action: "test_claude", country: "SY", text: c.text }) });
  const j = await r.json().catch(() => ({})); const f = j.fields || {}, raw = j.raw || {}; const bad = [];
  if (j.error) bad.push("error: " + j.error);
  for (const [k, v] of Object.entries(c.expect || {})) if (f[k] !== v) bad.push(`${k}=${JSON.stringify(f[k])} (want ${JSON.stringify(v)})`);
  for (const [k, v] of Object.entries(c.expectNot || {})) if (f[k] === v) bad.push(`${k} must not be ${JSON.stringify(v)}`);
  for (const [k, v] of Object.entries(c.raw || {})) if (raw[k] !== v) bad.push(`raw.${k}=${JSON.stringify(raw[k])} (want ${JSON.stringify(v)})`);
  if (c.areaIs && norm(f.area) !== norm(c.areaIs)) bad.push(`area=${JSON.stringify(f.area)} (want ${c.areaIs})`);
  if (c.areaNot && norm(f.area) === norm(c.areaNot)) bad.push(`area must not be ${c.areaNot}`);
  if (bad.length) { fail++; console.log("FAIL", c.name, "\n     ", bad.join(" · ")); } else { pass++; console.log("PASS", c.name); }
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
