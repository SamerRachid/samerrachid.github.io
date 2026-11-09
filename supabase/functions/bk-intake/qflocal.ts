// @ts-nocheck
// The free listing reader — the same rules as the site's «املأ الحقول» box, trained 2026-11-08 on 469 messages the bot received
// (source of truth: balkoun-ds/.ds-sync/_qftrain.js; copied here unchanged). No model, no cost: rules plus Balkoun's own place list.
// makeQfReader(D) gives qfLocalRead(raw, geo, learned, home) → {fields, missing}, fields shaped like the model's listing_fields.
export function makeQfReader(D: any) {
/* QF-LOCAL-START */
var QF_PLACES=null;   // [[phrase, governorate, area]] the bot learned — loaded once, on the first «املأ الحقول»
/* ── free reader for the «املأ الحقول» box (owner 2026-11-01): reads a pasted listing message in the browser with rules
   and Balkoun's own place list — no server, no model, no cost. Answers in the same shape as the bk-intake /web read
   ({fields, missing}), so applyQuickFill() places both the same way. When a fact is unclear it is left empty, never guessed. ── */
function qfLocalRead(raw, geo, learned, home){
  home=(home||[]).filter(function(g){ return (geo||D.GEO)[g] });   // the poster's governorates, first = main
  geo=geo||D.GEO; learned=learned||QF_PLACES||[];
  var lat=String(raw||"").replace(/[٠-٩]/g,function(d){ return String(d.charCodeAt(0)-0x660) }).replace(/[۰-۹]/g,function(d){ return String(d.charCodeAt(0)-0x6f0) })
    .replace(/(\d)[٬,،](?=\d{3}\b)/g,"$1").replace(/٫/g,".").replace(/(\d)،(\d{1,2})(?!\d)/g,"$1.$2")
    .replace(/(\d+(?:\.\d+)?) ?(?:متر|م)\s*\+\s*(?:(?:جنينه|جنينة|حديقه|حديقة|وجيبه|وجيبة|سقيفه|سقيفة) )?(\d+(?:\.\d+)?) ?(?:متر|م)(?![a-z؀-ۿ])/g,function(m,a,b){ return (+a + +b)+" متر" });   // 2026-11-08
  var N=function(s){ return String(s||"").replace(/(?:ا|أ|إ)?(?:وتستراد|وتوستراد|توستراد|ستراد)/g,"اوتوستراد").toLowerCase().replace(/ڤ/g,"ف").replace(/[ً-ْـ]/g,"").replace(/[أإآ]/g,"ا").replace(/ة/g,"ه").replace(/ى/g,"ي") };
  var t=" "+N(lat).replace(/[،؛؟٪«»؜​-‏]/g," ").replace(/(\D)\.|\.(\D)/g,"$1 $2").replace(/[^؀-ۿa-z0-9$.\/²%]+/g," ").replace(/\s+/g," ")+" ";   // one line, words and numbers only (Arabic commas and dots split words)
  t=t.replace(/(كسوه|اكساء)(?=سوبر|ديلوكس|جيد|ممتاز|ملكي|قديم)/g,"$1 ").replace(/سوبرديلوكس/g,"سوبر ديلوكس").replace(/سوبر(?=لوكس)/g,"سوبر ");   // hashtags glue words: «#كسوةسوبرديلوكس»
  t=t.replace(/ (شقه|شقتين|شقتان)(?=[^ ]{3,} )/g," $1 ");
  // «نص دلم» = half a دونم; «سعرالمتر» glued; «الغوطة الشرقية زبدين»: the region is the governorate, the village is the area (2026-11-08)
  t=t.replace(/ (دلم|دنوم) /g," دونم ").replace(/سعرال(متر|دونم)/g,"سعر ال$1").replace(/ (بال|في ال|ال)?غوطه (ال)?(شرقيه|غربيه) /g," ريف دمشق ");
  t=t.replace(/(الملكيه)?طابوا? ?(?=اخضر|زراعي|اسكان|نظامي)/g," طابو ").replace(/(\d)(سهم|اسهم)/g,"$1 $2").replace(/ طابو(\d)/g," طابو $1").replace(/\s+/g," ");   // 2026-11-08 (one space between words: an empty "word" would join names)   // «شقةالصناعة», «#شقةغربي الميدان» (2026-11-08)
  var f={}, has=function(re){ return re.test(t) }, NEAR=/(مقابل|قرب|قريب من|جانب|بجانب|خلف|بعد|امتداد|فوق|تحت|جنب|عند|ورا|شارع|مدخل|تجاه|ضمن|دخله|نزله|طلعه) ?$/, first=function(list,skipNear){ var best=null;
    list.forEach(function(p){ var re=new RegExp(p[1].source,"g"), m; while((m=re.exec(t))){ if(skipNear&&NEAR.test(t.slice(Math.max(0,m.index-14),m.index+1))){ re.lastIndex=m.index+1; continue } if(!best||m.index<best.i) best={i:m.index,v:p[0]}; break } }); return best?best.v:null };
  var W="(?=[\\s.,:؛،)!؟]|$)";   // end of word
  // deal
  var rentRe=/ (لل|ل)?(ايجار|اجار|اجاره|تاجير|استئجار)|(^| )(شهري|بالشهر|سنوي|بالسنه|يومي|اسبوعي|ايجار شهري) /, saleRe=/ (لل|ل)?(بيع|مبيع|بسع) /, shareRe=/ (لل)?مشاركه /;
  var dm=[["rent",rentRe],["sale",saleRe],["share",shareRe]].map(function(p){ var m=p[1].exec(t); return m?{v:p[0],i:m.index}:null }).filter(Boolean).sort(function(a,b){ return a.i-b.i });
  if(dm.length) f.deal=dm[0].v;
  // property type: the earliest type word wins (the message names the property before its features)
  var T=[["hotelapt",/ (شقه|شقق) (مفروشه )?فندقيه| مفروش(ه)? (لل?ايجار |للاجار )?(ال)?يومي /],["duplex",/ (شقه )?دوبل(ي)?كس/],["terrace",/ (شقه|طابق) (تراس|سطح)| روف |^ تراس /],
    ["studio",/ (ا)?ستو?ديو /],["suite",/ سويت /],["floor",/ طابق كامل /],["building",/ (بناء كامل|بنايه|عماره|بناء مؤلف|بناء من) /],
    ["villa",/ (فيلا|فيله|فيلل|فلل|فله) /],["arab",/ (بيت|منزل|دار) (عربي|شامي)| حوش | ارض ديار /],["chalet",/ شاليه /],["clinic",/ عياده /],
    ["restaurant",/ مطعم /],["hall",/ (صاله|قاعه) (افراح|مناسبات|احتفالات) /],["showroom",/ (صاله عرض|معرض) /],["station",/ (كازيه|محطه وقود|بنزينه) /],
    ["hotel",/ (فندق|منشاه سياحيه) /],["workshop",/ (ورشه|معمل صغير) /],["factory",/ (معمل|مصنع) /],["warehouse",/ (مستودع|هنكار) /],
    ["basement",/ قبو (تجاري|صناعي) /],["shop",/ (محل|محلات|دكان|محلين|صالون حلاقه|حلاقه نسائيه|كوافير|كافيه|كافيتريا|كافتيريا|مقهي) /],["farm",/ مزرعه /],
    ["agri",/ (ارض|قطعه ارض) زراعيه /],["resid",/ (ارض|قطعه ارض) سكنيه /],["comm",/ (ارض|قطعه ارض) تجاريه /],["indust",/ (ارض|قطعه ارض) صناعيه /],["tourist",/ (ارض|قطعه ارض) سياحيه /],
    ["mahdar",/ محضر /],["plot",/ (ارض|قطعه ارض|مقسم) /],["office",/ (مكتب|مكاتب|مكتبين)(?! (عقاري|العقار|عقاريه|الصلح|المحامي|عقار))/],
    ["apartment",/ (شقه|شقق|شقتين) /],["house",/ (منزل|بيت) /]];
  T=T.filter(function(p){ return !D.TYPES||D.TYPES[p[0]] });
  var pt=first(T,true); if(pt) f.property_type=pt;
  if(!f.property_type && / (للبيع|لبيع|للايجار|للاجار|للإيجار) قبو /.test(t)) f.property_type="apartment";   // «للبيع قبو بالمليحة»: a basement flat (2026-11-08)
  // a plot whose deed or licence says what kind of land it is (2026-11-08)
  if(f.property_type==="plot"){ var lk=first([["agri",/ (طابو زراعي|اراضي زراعيه|زراعي بريء) /.test(t)&&!/ (سكني|تنظيم|التنظيم|بالتنظيم) /.test(t)?/ /:/^$/],["tourist",/ (ترخيص سياحي|رخصه سياحيه|مرخصه سياحيا) /],["comm",/ (دونم|دنم|متر) تجاري /]].filter(function(p){ return !D.TYPES||D.TYPES[p[0]] })); if(lk) f.property_type=lk }
  // names in Balkoun's own lists that no rule here knows (a type, deed, finish or amenity the admin adds later): used only when
  // the rules found nothing, only as the exact whole name, 4+ letters, never a general word; two equal matches → nothing
  var GENW=/^(ارض|طابق|بيت|منزل|شقه|محل|مكتب|بناء|سكني|تجاري|زراعي|عقار|غرفه)$/;
  var lbl=function(v){ return N(Array.isArray(v)?v[0]:(v&&typeof v==="object"?(v.ar||""):v)).replace(/[^؀-ۿ ]/g," ").replace(/s+/g," ").trim() };
  var at=function(L){ var m=new RegExp(" (?:و|ب|بال|وب|وال)?"+L.replace(/^ال/,"(?:ال)?")+" ").exec(t); return m?m.index:-1 };   // the whole name, «و/بـ» stuck to it allowed
  var byName=function(dict,known){ var hits=[]; Object.keys(dict||{}).forEach(function(k){ if(known[k]) return; var L=lbl(dict[k]); if(L.length<4||GENW.test(L)) return;
      var i=at(L); if(i>-1) hits.push({k:k,i:i,len:L.length}) });
    if(!hits.length) return null; hits.sort(function(a,b){ return a.i-b.i||b.len-a.len });
    return (hits[1]&&hits[1].i===hits[0].i&&hits[1].len===hits[0].len) ? null : hits[0].k };
  if(!f.property_type){ var knownT={}; T.forEach(function(p){ knownT[p[0]]=1 }); var nt=byName(D.TYPES,knownT); if(nt) f.property_type=nt }
  if(f.property_type==="hotelapt") f.deal="rent";
  // size
  var unitRe="(?:م2|م²|م ?مربع|متر ?مربع|مترمربع|متر|متار|امتار|م|دونم|دونمات|دنم|دنمات|هكتار)", szAll=[], m;
  var szRe=new RegExp("(\\d+(?:\\.\\d+)?) ?(الف )?(و ?نص |و ?نصف )?"+unitRe+W,"g");
  var szT=t.replace(/ (\d+(?:\.\d+)?) (دونم|دنم) و ?نص(ف)? /g,function(m,n){ return " "+(+n+0.5)+" دونم " }).replace(/ نصف? (دونم|دنم) /g," 0.5 دونم ").replace(/ (دونم|دنم) و ?نص(ف)? /g," 1.5 دونم ")
    .replace(/ (ارض|مساحه|المساحه|مساحتها)( ارض)? (دونم|دنم) /g," $1$2 1 دونم ").replace(/ (دونم|دنم) كامل /g," 1 دونم ")
    .replace(/ (\d+) (?:الي |بين )?(\d+) (?=(?:م2|م²|متر|م|متر مربع) )/g,function(m,a,b){ a=+a; b=+b; return (a>=20&&b>a&&b<=a*1.5)?" "+Math.round((a+b)/2)+" ":m });   // 2026-11-08
  while((m=szRe.exec(szT))){ var u=m[0].replace(m[1],"").trim(), v=parseFloat(m[1]); if(m[2]) v*=1000; if(m[3]) v+=0.5; if(/(دونم|دنم)/.test(u)) v*=1000; else if(/هكتار/.test(u)) v*=10000;
    var before=szT.slice(Math.max(0,m.index-16),m.index); szAll.push({v:Math.floor(v+1e-9),i:m.index,key:/(مساح|مسطح)/.test(before),side:/(واجه|بعد|تراس|حديق|برند|شرف|عرض|طول|عمق|ارتفاع|شارع|سطح|قبو|مستودع|محل|مدخل|الطابق)/.test(before)}) }
  var szK=szT.match(/(?:مساحه?|مسطح)(?:ها|ه|تها|تو)? ?(?:[:؛(]| حوالي| تقريبا| بحدود| الاجماليه| الطابق)? ?(\d+(?:\.\d+)?)/);
  var sz=szAll.filter(function(x){ return x.key })[0]||(szK?{v:Math.round(parseFloat(szK[1]))}:null)||szAll.filter(function(x){ return !x.side })[0];
  if(sz&&sz.v>=8&&sz.v<=2000000) f.area_m2=sz.v;
  var perF=/ (?:مساحه )?(?:كل طابق|الطابق الواحد) ?(?:مساحته )?(\d+)/.exec(szT), nFl=/ (\d+) طوابق | عدد الطوابق (\d+) | (طابقين) /.exec(szT);
  if(perF&&nFl&&f.area_m2==+perF[1]&&f.property_type&&f.property_type!=="apartment"&&!/ (بيع|يباع|تباع) كل طابق /.test(szT)){ var fl=nFl[3]?2:+(nFl[1]||nFl[2]); if(fl>=2&&fl<=30) f.area_m2*=fl }   // 2026-11-08
  // rooms / baths / living rooms
  var NUMW={"واحد":1,"وحده":1,"اثنين":2,"ثلاث":3,"ثلاثه":3,"تلات":3,"تلاته":3,"اربع":4,"اربعه":4,"خمس":5,"خمسه":5,"ست":6,"سته":6,"سبع":7,"سبعه":7,"ثمان":8,"ثماني":8,"تمن":8};
  var wn="(\\d{1,2}|"+Object.keys(NUMW).join("|")+")", num=function(s){ return /^\d+$/.test(s)?+s:NUMW[s] };
  var rm=t.replace(/ (ط|طابق|الطابق) (\d{1,2}) (?=(غرفه|غرف|اوضه) )/g," $1 $2 و ").match(new RegExp(" و?"+wn+" (غرف|غرفه|اوض|غرف نوم|نوم)"+W));
  if(rm) f.rooms=num(rm[1]); else if(/ و?(غرفتين|غرفتان|اوضتين) /.test(t)) f.rooms=2; else if(/ (غرفه|اوضه) و ?صالون /.test(t)) f.rooms=1;
  var bm=t.match(new RegExp(" و?"+wn+" (حمام|حمامات)"+W));
  var bm2=t.match(/ (?:حمام|حمامات) (?:عدد|عدد:|×|x) ?(\d)/);
  if(bm) f.baths=num(bm[1]); else if(bm2) f.baths=+bm2[1]; else if(/ و?حمامين /.test(t)) f.baths=2; else if(/ (و|،)? ?حمام (و|،|مطبخ|موزع|ماستر|رئيسي)/.test(t)) f.baths=1;
  var lv=t.match(new RegExp(" و?"+wn+" (صالون|صالونات)"+W));
  if(lv) f.living_rooms=num(lv[1]); else if(/ و?صالونين /.test(t)) f.living_rooms=2; else if(/ و ?(صالون|صوفا|صوفه|قعده) /.test(t)) f.living_rooms=1;
  var flS=t.split(/ (?=(?:ال)?طابق (?:الارضي|الاول|الثاني|التاني|العلوي|السفلي|الاخير) )/);
  if(flS.length>=3){ var rSum=0, rN=0; flS.slice(1).forEach(function(p){ p=" "+p.split(/ (?:الاتجاه|اتجاه|الملكيه|السعر|المساحه|الكسوه|اكساء) /)[0]+" ";
      var r1=p.match(new RegExp(" و?"+wn+" (غرف|غرفه|اوض)"+W)); var r=r1?num(r1[1]):(/ (غرفتين|غرفتان) /.test(p)?2:(/ (غرفه|اوضه) /.test(p)?1:0)); if(r){ rSum+=r; rN++ } });
    if(rN>=2 && rSum>(f.rooms||0)) f.rooms=rSum }
  var rpf=t.match(new RegExp(" كل طابق "+wn+" (غرف|غرفه)"+W)), nfl=t.match(/ (\d{1,2}) طوابق /);
  if(rpf&&nfl&&f.rooms===num(rpf[1])) f.rooms=num(rpf[1])*(+nfl[1]);   // 2026-11-08
  if(f.rooms>40) delete f.rooms; if(f.baths>10) delete f.baths;
  // floor ("ط" = طابق)
  var ORD={"ارضي":0,"الارضي":0,"اول":1,"الاول":1,"ثاني":2,"الثاني":2,"تاني":2,"ثالث":3,"الثالث":3,"تالت":3,"رابع":4,"الرابع":4,"خامس":5,"الخامس":5,"سادس":6,"السادس":6,"سابع":7,"السابع":7,"ثامن":8,"الثامن":8,"تاسع":9,"التاسع":9,"عاشر":10,"العاشر":10,"تسويه":-1,"قبو":-1};
  var fm=t.match(new RegExp(" (?:ب?الطابق|طابق|ط\\.?) ?(\\d{1,2}|"+Object.keys(ORD).join("|")+")"+W));
  if(fm) f.floor=/^\d+$/.test(fm[1])?+fm[1]:ORD[fm[1]]; else if(/ (شقه|بيت|منزل) (ارضي|ارضيه) /.test(t)) f.floor=0;
  if(f.floor>30) delete f.floor;
  // «غرفة وصالون قبو»: the unit is the basement («والقبو», «بالقبو», «حصة بالقبو» are a share of it, not the floor)
  if(f.floor==null && / قبو /.test(t) && !/ (حصه|حصه في) قبو | قبو (تجاري|صناعي) /.test(t)) f.floor=-1;
  if(f.property_type==="house" && (f.floor>=1 || / مصعد /.test(t))) f.property_type="apartment";   // a «منزل» on an upper floor or with a lift is a flat (owner's rule)
  // no type word but a floor, or rooms with a «صالون/منتفعات»: a flat (2026-11-08: «الطابق السادس … 3 غرف وصالون»)
  if(!f.property_type && (f.floor>=1 || (f.floor==null && f.rooms!=null && / (صالون|منتفعات|منافع) /.test(t))) && !/ (ارض|اراضي|دونم|دنم|مزرعه|صاله|مصلحه|تجاري|تجاريه) /.test(t)) f.property_type="apartment";
  // deed
  var tb=null;
  if(has(/حكم محكمه (اسهم )?موصوف/)) tb="court_desc"; else if(has(/حكم محكمه/)) tb="court";
  else if(has(/(طابو|سند) زراعي|سند 25|مشاع زراعي/)) tb="agri"; else if(has(/طابو اسكان|مؤسسه الاسكان/)) tb="housing";
  else if(has(/ اسهم من طابو| حصص سهميه/)) tb="shares";
  else if(has(/سجل مؤقت/)) tb="coop";
  else if(has(/طابو اخضر| طابو نظامي| 2400 سهم| طابو 2400| الفين واربعمائه سهم| الفين و ?اربعمئه سهم/)) tb="green";
  else if(has(/تنازل جمعيه|جمعيه سكنيه|سجل مؤقت/)) tb="coop"; else if(has(/ (كاتب عدل|وكاله)/)) tb="poa";
  else if(has(/ (وضع يد|واضع يد)/)) tb="possession"; else if(has(/ (اسهم|\d+ سهم) /)) tb="shares"; else if(has(/ (بدون طابو|عقد عرفي)/)) tb="none";
  if(!tb) tb=byName(D.TABU,{green:1,shares:1,court:1,court_desc:1,possession:1,poa:1,agri:1,coop:1,housing:1,none:1});
  if(!tb && / طابو /.test(t) && !/ نوع (ال)?طابو /.test(t)) tb="green";   // 2026-11-08
  if(tb) f.tabu=tb;
  // condition (repair wins over old; land has its own list)
  var land=/^(plot|agri|resid|comm|indust|tourist|farm|mahdar)$/.test(f.property_type||"");
  var cd=land ? first([["fenced",/ مسور/],["planted",/ مزروع/],["built",/ عليها (بناء|بيت|غرفه)/],["empty",/ ارض (فارغه|بيضاء)/]])
    : (has(/ (بحاجه|يحتاج|بدها|بدو) ترميم/)?"repair" : first([["superdeluxe",/ (سوبر ديلوكس|سوبر سوبر|كسوه سوبر|اكساء سوبر|سوبر لوكس|(?:ب?كسوه|كسوتها|ب?اكساء|ب?الكسوه|ب?الاكساء|كسوتو) ممتازه? جدا|(?:ب?كسوه|كسوتها|ب?اكساء|ب?الكسوه|ب?الاكساء|كسوتو) ممتازه? كثير)/],["deluxe",/ (ديلوكس|كسوه ديلوكس|لوكس|(?:ب?كسوه|كسوتها|ب?اكساء|ب?الكسوه|ب?الاكساء|كسوتو) ممتازه?) /],
       ["shell",/ (علي العظم|عالعظم|ع العظم|علي العضم|عالعضم|عاالعضم|عضم|ع العضم) /],["finishing",/ (قيد الاكساء|تحت الاكساء|عم ينكسي|بمرحله الاكساء|قيد التشطيب)/],["stripped",/ (معفش|معفشه) /],
       ["damaged",/ (متضرر|متضرره) /],["old",/ (اكساء قديم|كسوه قديمه|اكساء عادي)/],["intact",/ (سليم|سليمه|جاهز للسكن|جاهزه للسكن|(ب?كسوه|كسوتها|ب?اكساء|ب?الكسوه|ب?الاكساء) (و ?فرش |والفرش )?(جيده|جيد|جيده جدا|نظيفه|حلوه|جديده|جديد)) /]]));
  if(!cd) cd=byName(land?D.LANDC:D.COND,land?{fenced:1,planted:1,built:1,empty:1}:{repair:1,superdeluxe:1,deluxe:1,shell:1,finishing:1,stripped:1,damaged:1,old:1,intact:1});
  if(cd&&(land?D.LANDC:D.COND)&&(land?D.LANDC:D.COND)[cd]) f.condition=cd;
  // «فاضي» = unfurnished
  if(has(/ (غير مفروش|غير مفروشه|بدون فرش|بلا فرش|فاضي|فاضيه|فارغ|فارغه) /)) f.furnished=false; else if(has(/ (مفروش|مفروشه|بفرشه|بفرشها|مع الفرش) /)) f.furnished=true;
  // facing: «قبلي» is always a direction; the other words only after «اتجاه / واجهة»
  // the words after it, in any order and with "و"/"•" between them: north/south + east/west make a corner ("شرقي قبلي" = se)
  var DW="(قبلي|جنوبي|شمالي|شرقي|غربي)ه?", dctx=new RegExp(" (?:ب?الاتجاه|اتجاه|اتجاهها|الاتجاهات|اتجاهات|واجهه|الواجهه|واجهتها) ?(?:[:•] ?)?"+DW+"((?: ?[•و]? ?"+DW+"){0,3})").exec(t)||/ (قبلي)((?: (?:و ?)?(?:شرقي|غربي|شمالي)){0,2}) /.exec(t);
  if(dctx){ var dws=(dctx[1]+" "+dctx[2]).match(/قبلي|جنوبي|شمالي|شرقي|غربي/g)||[], hasW=function(w){ return dws.indexOf(w)>-1 };
    var nsw=dws.filter(function(w){ return /قبلي|جنوبي|شمالي/.test(w) })[0], eww=dws.filter(function(w){ return /شرقي|غربي/.test(w) })[0];
    var ns=nsw?(nsw==="شمالي"?"n":"s"):"", ew=eww?(eww==="شرقي"?"e":"w"):"";
    if(ns||ew) f.direction=ns+ew;   // first north/south word + first east/west word
  }
  // amenities (the Arabic labels; applyQuickFill maps them to the page language)
  var AM=land?[["سور",/ (سور|مسوره) /],["بئر ماء",/ (بئر|بير) /],["كهرباء واصلة",/ كهرباء واصله/],["ماء واصل",/ (ماء|مي|مياه) واصل/],["طريق معبّد",/ (طريق معبد|مزفت|زفت)/],["أرض مستوية",/ مستويه /],["داخل التنظيم",/ (داخل|ضمن) التنظيم/],["مفرزة",/ مفرز/],["إطلالة",/ (اطلاله|مطله|مطل) /],["قريبة من الطريق العام",/ (علي|عل|قريبه من|قرب) (الطريق|الشارع) العام/]]
     :[["مصعد",/ (مصعد|اسانسير) /],["موقف سيارات",/ (موقف سيارات|كراج سياره|باركينغ|موقف خاص|(مكان|محل) (لصف|صف|ركن) (سياره|سيارات)|صف سياره|كراج خاص)/],["تدفئة مركزية",/ تدفئه مركزيه/],["خزّان مياه",/ (خزان|خزانات) /],["اشتراك مولّدة",/ (اشتراك موّلده|اشتراك مولده|امبيرات|امبير) /],["حارس",/ (حارس|ناطور) /],["إنترنت",/ (انترنت|نت) /],["باب أمان",/ (باب امان|باب حمايه|ابواب حمايه|باب مصفح)/],["شرفة",/ و?(شرفه|برندا|برنده|فرندا|فرنده|ورندا|بلكونه|بلكونات|شرفات|برندات|برندتين) /],["تكييف",/ (تكييف|مكيف|مكيفات|مكيفه) /],["طاقة بديلة",/ (طاقه شمسيه|طاقه بديله|الواح شمسيه|ليثيوم|طاقه) /]];
  var tA=t.replace(/ و(?=[؀-ۿ]{3,})/g," ");
  var am=AM.filter(function(p){ return p[1].test(t)||p[1].test(tA) }).map(function(p){ return p[0] });
  var amList=((land?D.LANDAMEN:D.AMEN)||{}).ar||[], amKnown={}; AM.forEach(function(p){ amKnown[p[0]]=1 });
  amList.forEach(function(a){ if(amKnown[a]||am.indexOf(a)>-1) return; var L=lbl(a); if(L.length>=4&&!GENW.test(L)&&at(L)>-1) am.push(a) });   // an amenity added later, by its exact name
  if(am.length) f.amenities=am;
  // rental period
  if(f.deal==="rent"){ var rp=first([["daily",/ (يومي|باليوم|الليله) /],["weekly",/ (اسبوعي|بالاسبوع) /],["monthly",/ (شهري|بالشهر|شهريا|الشهري|بالشهري) /],["quarterly",/ (كل|لكل|ب) ?(3|ثلاث|تلات|ثلاثه|تلاته) (اشهر|شهور) /],["semiannual",/ (كل|لكل|ب) ?(6|ست|سته) (اشهر|شهور) | (نص سنوي|كل نص سنه|لكل نص سنه|نصف سنوي) /],["yearly",/ (سنوي|بالسنه|سنويا|السنوي|لكل سنه|كل سنه) /]]); if(rp) f.rental_period=rp }   // the price is for that period (owner 2026-11-01)
  // price: the number near «السعر/المطلوب» or with a currency; "85 ألف" multiplies, "66000 ألف" does not; phone numbers are skipped
  var pr=[], pRe=/(\d+(?:\.\d+)?) ?(\$)? ?(الف|الاف|مليون|ملايين|مليار)? ?(و ?نص|و ?نصف|و ?ربع)?( ?و ?(\d+)( ?(الف|مليون))?)? ?(دولار|دولر|دلار|\$|usd|ليره سوريه|ليره|ل\.?س|ل س|sy|syp)?/g, mul={"الف":1e3,"الاف":1e3,"مليون":1e6,"ملايين":1e6,"مليار":1e9};
  // hundreds written in words after «ألف و…» («22 ألف وخمسمية» = 22,500)
  var HUN0={"مية":100,"ميه":100,"مئه":100,"مايه":100,"ميتين":200,"مئتين":200,"ميتان":200,"تلتمية":300,"تلاتمية":300,"ثلاثمية":300,"ثلاثمئه":300,"ثلثمئه":300,"اربعمية":400,"اربعمئه":400,"خمسمية":500,"خمسمئه":500,"خمسماىه":500,"ستمية":600,"ستمئه":600,"سبعمية":700,"سبعمئه":700,"تمنمية":800,"ثمانمئه":800,"ثمنمية":800,"تسعمية":900,"تسعمئه":900};
  var HUN={}; Object.keys(HUN0).forEach(function(k){ HUN[N(k)]=HUN0[k] });
  var wordsP=t.replace(new RegExp("(^| )و?("+Object.keys(HUN).join("|")+")(?= )","g"),function(x,s,w){ return s+"و"+HUN[w] })
    .replace(/ مليونين /g," 2 مليون ").replace(/ مليون /g,function(x,i,s){ return /\d ?$/.test(s.slice(0,i))?x:" 1 مليون " }).replace(/ الفين /g," 2 الف ").replace(/ مليارين /g," 2 مليار ")
    .replace(/ (تالاف|تلاف|الآف) /g," الف ").replace(/(\d+(?:\.\d+)?) (مليون|مليار) (دولار|دولر|\$) و ?(نص|نصف)( (مليون|مليار))?/g,"$1 $2 و$4 $3")
    .replace(/(\d+(?:\.\d+)?) مليون (دولار|دولر|\$) و ?(\d+) ?(الف)/g,"$1 مليون و$3 $4 $2");   // 2026-11-08
  while((m=pRe.exec(wordsP))){ if(!m[0].trim()) { pRe.lastIndex++; continue }
    var digits=m[1].replace(".",""); if(digits.length>=9 || /^0\d{8,}/.test(m[1])) continue;
    var after=wordsP.slice(m.index+m[0].length, m.index+m[0].length+10), bef=wordsP.slice(Math.max(0,m.index-22),m.index);
    if(/^ ?(م|متر|م2|م²|دونم|دنم|غرف|غرفه|حمام|سهم|طابق|امبير|ساعه|شهر|اشهر|سنه|سنوات|دقيقه|كم|%)/.test(after) && !m[3] && !m[2] && !m[9]) continue;
    if(!m[9]&&!m[2]&&/^ ?(م|متر|م2|دونم|دنم|هكتار)( |$)/.test(after)) continue;   // "240 ألف متر" is a size
    var unitPrice=/(للمتر|بالمتر|المتر|للدونم|الدونم|بالدونم|الدنم|للدنم|بالدنم|للمتر المربع)/.test(after+" "+bef.slice(-10));   // "75 دولار للمتر", "سعر الدونم 2200": not the asking price
    var base=parseFloat(m[1]), mu=m[3]?mul[m[3]]:1, v=(m[3]&&base<1000)?base*mu:base;
    if(m[3]&&base<1000&&m[4]) v+= (/ربع/.test(m[4])?0.25:0.5)*mu;   // "مليونين ونص" = 2,500,000
    if(m[3]&&base<1000&&m[6]) v+= +m[6]*(m[8]?mul[m[8]]:(mu>=1e6?1e3:1));   // "مليون و200" = 1,200,000; "15 مليون و500 الف" = 15,500,000
    var c=m[9]||m[2]; var cur=c?(/(دولار|دولر|دلار|\$|usd)/.test(c)?"USD":"SYP"):null;
    var key=/(سعر|السعر|سعرو|سعرها|المطلوب|بسعر|الطلب|الثمن|بدل|💰)/.test(bef);
    if(!cur&&!key&&!m[3]) continue;
    pr.push({v:Math.round(v),cur:cur,key:key,mu:!!m[3],unit:unitPrice,perD:/(دونم|دنم)/.test(after+" "+bef.slice(-12)),i:m.index}) }
  var curAll=/(دولار|دولر|دلار|\$| usd)/.test(t)?"USD":(/ (ليره|ل\.?س|ل س|syp)/.test(t)?"SYP":null);
  pr.sort(function(a,b){ return a.unit-b.unit || (b.cur==="USD")-(a.cur==="USD") || (!!b.cur)-(!!a.cur) || b.key-a.key || b.mu-a.mu || a.i-b.i });
  var pUnits=pr.filter(function(x){ return x.unit && x.v>0 }).sort(function(a,b){ return a.i-b.i }), pUnit=pUnits[pUnits.length-1];   // two unit prices: the later one corrects the first («سعر المتر 150$ … السعر 170$ المتر»)
  pr=pr.filter(function(x){ return !x.unit });
  var p0=pr.filter(function(x){ return x.v>=50 && (x.cur||x.mu||x.v>=1000) })[0];
  if(p0){ f.price=p0.v; f.currency=p0.cur||curAll||"USD";
    // no currency written and an amount no dollar price reaches (5 مليون بالشهر, 150 مليون للبيع): Syrian pounds
    if(!p0.cur && !curAll && ((f.deal==="rent" && f.price>=50000) || (f.deal!=="rent" && f.price>=10000000))) f.currency="SYP" }
  if(f.price==null && pUnit && f.area_m2 && f.deal!=="rent"){ var tot=Math.round(pUnit.v*(pUnit.perD?f.area_m2/1000:f.area_m2));
    if(tot>=500){ f.price=tot; f.currency=pUnit.cur||curAll||"USD"; f.priceFromUnit=true; f.priceUnit=pUnit.perD?"dunam":"m2"; f.priceUnitValue=pUnit.v } }
  // rent paid ahead: «دفع ست شهور», «دفعة 6 اشهر», «سلف سنه»
  var adv=new RegExp(" (?:دفع|دفعه|سلف|مقدم|الدفع) ?"+wn+"? ?(شهر|شهور|اشهر|سنه)"+W).exec(t)||/ (?:دفع|دفعه|سلف) (سنه) /.exec(t);
  if(f.deal==="rent" && adv){ var an=adv[2]?adv[1]:null, au=adv[2]||adv[1]; f.advance_months = au==="سنه" ? 12 : (an?num(an):1) }
  if(has(/ و?(بازار|قابل للتفاوض|قابل للنقاش|قابل للبازار)/)) f.negotiable=true; else if(has(/ (منهي|نهائي|غير قابل للتفاوض)/)) f.negotiable=false;
  // place: the governorate written in the text, then the longest area name of Balkoun's list found in it
  var govs=Object.keys(geo), gIdx={}, aIdx={};
  var bare=function(s){ return N(s).replace(/[^؀-ۿ0-9 ]/g," ").replace(/\s+/g," ").trim().split(" ").map(function(w){ return w.replace(/^ال/,"") }).join(" ") };
  govs.forEach(function(g){ gIdx[bare(g)]=g; (geo[g]||[]).forEach(function(a){ String(a).split("/").forEach(function(p){ var k=bare(p); if(k.length<3) return; (aIdx[k]=aIdx[k]||[]).push({g:g,a:a}); var ks=k.replace(/ /g,""); if(ks!==k && ks.length>=5) (aIdx[ks]=aIdx[ks]||[]).push({g:g,a:a});
        var kw=k.split(" "); if(kw.length===2&&/^(اوتوستراد|طريق)$/.test(kw[1])){ var rk=kw[1]+" "+kw[0]; (aIdx[rk]=aIdx[rk]||[]).push({g:g,a:a}) } }) }) });
  gIdx["شام"]="دمشق"; if(geo["حماة"]) gIdx["حماه"]="حماة";
  // other spellings of an area, as senders write them (2026-11-08): «القميرية», «الديرخبية», «المزة شرقية»
  [["قميريه","دمشق","القيمرية"],["ديرخبيه","ريف دمشق","درخبية"],["مزه شرقيه","دمشق","مزة فيلات شرقية"],["مزه غربيه","دمشق","مزة فيلات غربية"],["ابن ساكر","دمشق","ابن عساكر"],["كروم مضايا","ريف دمشق","مضايا"],["شام جديده","دمشق","مشروع دمر"],["توسع دمر","دمشق","مشروع دمر"]].forEach(function(x){
    if((geo[x[1]]||[]).indexOf(x[2])>-1 && !aIdx[x[0]]) aIdx[x[0]]=[{g:x[1],a:x[2]}] });
  var words=t.trim().split(" "), stripW=function(w){ return w.replace(/^(و|ف)?(بال|لل|ال|بل(?=[^ ]{4})|ب|ل)(?=..)/,"").replace(/^ال/,"") };   // «بلميدان» = بالميدان (2026-11-08)
  // a hashtag or a missing space glues an area to the word before/after it: split it there (2026-11-08)
  var GH=/^(و|ف)?(ب|بال|في)?(دوار|شارع|حي|منطقه|شقه|بيت|منزل|ارض|محل|بعد|قبل|قرب|جانب|مقابل|خلف|عند|ساحه|طريق|اول|اخر|نزله|دخله|بلده|قريه|مدينه|مقسم|جامع|مشفي|مستشفي|كازيه|مول)$/,
      GT=/^(عالشارع|علشارع|عالاوتستراد|علاوتستراد|عالطريق|علطريق|عالزفت|دخله|جانب|قرب|مقابل|حديقه|شارع|الشارع|العام|حي|حاره|[0-9]+)$/;
  var isKey=function(p){ var k=stripW(p); return k.length>=4 && aIdx[k] ? k : null };
  words=[].concat.apply([],words.map(function(w){ if(w.length<7 || aIdx[w.replace(/^ال/,"")] || isKey(w)) return [w];
    for(var j=3;j<=w.length-4;j++){ var a=w.slice(0,j), b=w.slice(j);
      if(GH.test(a)){ if(isKey(b)) return [a,b];
        for(var q=4;q<=b.length-1;q++){ var b1=b.slice(0,q), b2=b.slice(q); if(isKey(b1)&&GT.test(b2)) return [a,b1,b2] } }
      if(isKey(a)&&GT.test(b)) return [a,b] }
    if(/^(بعد|قبل|قرب|جانب|بجانب|مقابل|خلف|عند)(مقسم|دوار|جامع|مشفي|مستشفي|ساحه|كازيه|مدرسه|مول|فندق)/.test(w)){ var m=/^(بعد|قبل|قرب|جانب|بجانب|مقابل|خلف|عند)(.+)$/.exec(w); return [m[1],m[2]] }
    return [w] }));
  var gHits={}, aHits=[];
  for(var i=0;i<words.length;i++){
    for(var n=4;n>=1;n--){ if(i+n>words.length) continue;
      var seg=words.slice(i,i+n), k1=seg.map(function(w,j){ return j===0?stripW(w):w.replace(/^ال/,"") }).join(" "), k0=seg.map(function(w){ return w.replace(/^ال/,"") }).join(" ");
      var prev=words.slice(Math.max(0,i-2),i).join(" ");
      [k0,k1].forEach(function(k){ if(gIdx[k]&&!(gIdx[k]==="دمشق"&&/ريف$/.test(prev))) gHits[gIdx[k]]=Math.min(gHits[gIdx[k]]||1e9,i);
        if(k==="ريف دمشق"||k==="ريف شام") gHits["ريف دمشق"]=Math.min(gHits["ريف دمشق"]||1e9,i) });
      var k=aIdx[k0]?k0:(aIdx[k1]?k1:(n>1&&aIdx[k0.replace(/ /g,"")]?k0.replace(/ /g,""):(n>1&&aIdx[k1.replace(/ /g,"")]?k1.replace(/ /g,""):null))); if(!k) continue;
      var prev3=words.slice(Math.max(0,i-3),i).join(" ");
      var way=/(^| )(مكرو|ميكرو|خط|سرفيس|باص|كراج|قرب|قريب|قريبه|مقابل|تجاه|جانب|بجانب|خلف|بعد|جنب|عند|اوتستراد|دوار|جامع|مدرسه|مشفي|مستشفي|كنيسه|حديقه|فرن|صيدليه|ساحه|مفرق|موقف|كازيه|مول|فندق|مطعم|الى|الي|نحو|باتجاه|مقسم|اطلاله|مطل|مطله|يطل|تطل)( من)?( [^ ]+)?$/.test(prev3) && !/(^| )(في|بحي|حي|منطقه|بمنطقه)$/.test(prev);
      if(words[i-1]==="دوار") way=false;   // «قرب دوار البيطرة»: a roundabout is named after its neighbourhood (2026-11-08)
      aHits.push({k:k,i:i,n:n,len:k.length,way:way,c:aIdx[k],afterGov:!!gIdx[stripW(words[i-1]||"")]}); }
  }
  var gNamed=Object.keys(gHits).sort(function(a,b){ return gHits[a]-gHits[b] });
  if(/ ريف (حماه|حلب|ادلب|حمص|اللاذقيه|طرطوس|درعا) /.test(t) && gNamed.indexOf("ريف دمشق")>-1 && !/ ريف (دمشق|الشام) /.test(t)) gNamed.splice(gNamed.indexOf("ريف دمشق"),1);
  var BLOCK={}; "وحده طيبه ورود كفر حفيان خريطه نموذجيه قسمين عرقوب بابان حارات سعر كسوه سهم قبو جامع شمسيه رئيسي جديده دوار حمام مشروع مزرعه فيلات مدرسه كبيره نادي جسر مزارع حاره جيد داخليه اسكان كورنيش صور طوال فسحه دور حره ابين ذهبيه وادي كروم ملعب جميله شهداء رشيد جنينه عفش عاليه صغيره عريض شماليه شجره سيده ناعم مطله عمر عليه عيون صنع باب حلوه معامل عباره كليه عماره معزوله ساحه سوق طريق شارع حديقه بساتين ابراج ادخار مضافه زراعه مدينه قريه بلده ضيعه مركز منطقه حي سكن جبل بحر نهر سهل تل".split(" ").forEach(function(w){ BLOCK[w]=1 });
  var NEVER={"علي":1,"في":1,"من":1,"الي":1,"مع":1,"عن":1};   // «على» normalises to «علي»: a preposition, never a place
  var IN=/(^| )(في|بحي|حي|منطقه|بمنطقه|المنطقه|الموقع|العنوان|بلده|قريه|ضاحيه|بضاحيه|ببلده|بقريه|مدينه|بمدينه)$/;
  aHits=aHits.filter(function(h){ return !NEVER[h.k] });
  // «كسوة» is the finishing; «الكسوة» is also a town (ريف دمشق). It is the town only with «ال» and nothing describing a finish
  // after it: «بالكسوة», «في الكسوة», «الكسوة ريف دمشق» — never «كسوة ممتازة», «بكسوة جيدة», «الكسوة: سوبر ديلوكس», «كسوة 85%»
  var FIN=/^(ممتاز|ممتازه|جيد|جيده|جديد|جديده|سوبر|ديلوكس|لوكس|قديم|قديمه|عادي|عاديه|نظيف|نظيفه|حلوه|ملكي|ملكيه|حديث|حديثه|خارجي|خارجيه|داخلي|داخليه|كامل|كامله|فخم|فخمه|راقي|راقيه|مميز|مميزه|بحاجه|نص|نصف|متوسط|متوسطه|عاليه|ممتاذه|علي|عل|ع|عالعظم|عالعضم|مكسي|مكسيه|مكسوه|او|vip|\d+%?)$/;   // «الكسوة: على العظم أو مكسي» is the finishing
  aHits=aHits.filter(function(h){ if(h.k!=="كسوه") return true;
    var w=words[h.i]||"", nx=(words[h.i+1]||"").replace(/^:/,""), nx2=words[h.i+2]||"";
    if(!/^(و)?(ب|في|ف)?ال?كسوه$/.test(w) || !/الكسوه$/.test(w)) return false;   // «كسوة» / «بكسوة» without «ال»: the finishing
    if(FIN.test(nx) || (nx===":"&&FIN.test(nx2)) || /^(اكساء|كسوه)$/.test(words[h.i-1]||"")) return false;
    h.kisTown=true; return true });
  // places the bot learned from earlier messages ("جامع المصطفى" → الصناعة): each part of a learned phrase, without its
  // «قرب / جانب / مقابل…», is looked for as whole words; a part made only of everyday words is ignored
  if(learned.length){ var GEN=/^(اوتستراد|اوتوستراد|شارع|طريق|عام|رئيسي|كورنيش|جسر|دوار|ساحه|جامع|مسجد|مشفي|مستشفي|مدرسه|حديقه|سوق|مطعم|فرن|حي|منطقه|اول|اخر|الشارع|غربي|شرقي|شمالي|جنوبي|قديم|جديد|جديده|قديمه|نزله|دخله|حاره)$/;
    var bw=" "+words.map(function(w){ return w.replace(/^ال/,"") }).join(" ")+" ";
    var lc={};   // core → its area; a core learned for two different areas is dropped
    learned.forEach(function(L){ var g=L[1], a=L[2]; if(!geo[g]||(geo[g]||[]).indexOf(a)<0) return;
      var whole=bare(L[0]), oneWord=whole.split(" ").length===1;
      String(L[0]).split(/[،,–-]| و(?=[^ ]+ )/).forEach(function(part){ var core=bare(part).replace(/^((بالقرب من|قريب من|قرب|جانب|بجانب|مقابل|خلف|بعد|عند|دخله|نزله|طلعه|اول|امام|فوق|تحت|على|علي|الى|الي|بين|مواجه|ضمن|داخل|تقاطع|امتداد) )+/,"").replace(/[a-z0-9 ]+$/,"").trim();
        var cw=core?core.split(" "):[]; if(!cw.length||core.length<4) return;
        if(cw.every(function(w){ return GEN.test(w)||BLOCK[w]||NEVER[w] })) return;
        if(cw.length<=3 && /^(طريق|شارع|اوتستراد|اوتوستراد|كورنيش)$/.test(cw[0])) return;   // a road alone («طريق حماة») runs past many neighbourhoods: one listing on it says nothing about the next (2026-11-04)
        if(cw.length===1&&!(oneWord&&core.length>=4)) return;   // one word only when the learned phrase is that word («غواص», «أميسا»)
        if(aIdx[core]&&!(aIdx[core].length===1&&aIdx[core][0].a===a)) return;   // an area's own name is matched by the area list, not here
        var key=core, prevA=lc[key]; if(prevA&&prevA.a!==a){ lc[key]={bad:1}; return } lc[key]={g:g,a:a,n:cw.length} }) });
    Object.keys(lc).forEach(function(core){ var v=lc[core]; if(v.bad) return; var at=bw.indexOf(" "+core+" "); if(at<0) return;
        var wi=bw.slice(0,at).trim()?bw.slice(0,at).trim().split(" ").length:0, g=v.g, a=v.a, cw=core.split(" ");
        aHits.push({k:core,i:wi,n:cw.length,len:core.length,way:false,c:[{g:g,a:a}],learned:true}) }) }
  // «في / بـ» before a name = the property is in it (owner's rule, every area); «على» before a road = it is on that road
  aHits.forEach(function(h){ var pw=words[h.i-1]||"";
    h.one=h.n===1; var mk=!!h.kisTown || IN.test(words.slice(Math.max(0,h.i-1),h.i).join(" ")) || pw==="ب" || (!BLOCK[h.k] && /^(و)?(ب|بال|في)/.test(words[h.i]) && words[h.i].length>h.k.length+1); h.marked=mk||!!h.afterGov; h.agOnly=!mk&&!!h.afterGov;
    h.road=/^(طريق|شارع|اوتستراد|اوتوستراد|كورنيش|جسر|دوار) /.test(h.k);
    if(h.road && /^(علي|عل|ع|عالـ?)$/.test(pw)){ h.road=false; h.way=false; h.marked=true }
    if(h.road && h.marked && !h.one) h.road=false; });
  // a real neighbourhood beats a road named like an area («طريق المطار»), a landmark is a last resort, «في / حي / منطقة» before a name counts
  var score=function(h){ return (h.way?-30:0) + (h.road?-45:0) + (h.marked?(h.agOnly?6:15):0) + (h.learned?-25:0) + h.n*10 + Math.min(h.len,20) - h.i/50 };
  aHits.sort(function(a,b){ return score(b)-score(a) });
  var near=function(g){ return g==="دمشق"?["دمشق","ريف دمشق"]:g==="ريف دمشق"?["ريف دمشق","دمشق"]:[g] };   // people write «دمشق» for places of its countryside
  var pick=null, covered=function(h){ return aHits.some(function(o){ return o!==h && !o.learned && o.n>1 && o.i<=h.i && h.i<o.i+o.n }) };
  for(var j=0;j<aHits.length&&!pick;j++){ var h=aHits[j];
    if(h.one && BLOCK[h.k] && !h.marked) continue;   // an area named like an everyday word ("مدرسة", "الكبيرة") counts only after «في / حي / منطقة»
    if(!h.one && !h.learned && !h.marked && h.k.split(" ").every(function(w){ return /^(مركز|وسط|مدينه|بلده|قريه|ضيعه|منطقه|حي)$/.test(w) })) continue;   // same for a name that only says «the centre / the town»: «8 كم عن مركز مدينة حمص» is not the area «مركز المدينة» (2026-11-04)
    var inG=h.c.filter(function(c){ return gNamed.indexOf(c.g)>-1 });
    if(!inG.length&&gNamed.length) inG=h.c.filter(function(c){ return near(gNamed[0]).indexOf(c.g)>-1 });
    if(inG.length===1) pick=inG[0];
    // no governorate written: the poster's own governorate (the agency's, from its profile) when the area is there (owner 2026-11-01)
    else if(!gNamed.length && home.length && (!h.one || h.marked || (h.len>=4&&!BLOCK[h.k])) && h.c.some(function(c){ return home.indexOf(c.g)>-1 })){
      var inH=h.c.filter(function(c){ return home.indexOf(c.g)>-1 }).sort(function(x,y){ return home.indexOf(x.g)-home.indexOf(y.g) }); pick=inH[0] }
    else if(!gNamed.length && h.c.length===1 && (!h.one || h.marked || (h.len>=5&&!BLOCK[h.k]))) pick=h.c[0];
    // a name found in several governorates and no governorate written («الميدان»): the one where most of Balkoun's
    // listings are, when the name is clearly the place (after «في / بـ / حي», or several words)
    else if(!gNamed.length && h.c.length>1 && (!h.one || h.marked || (h.len>=5 && !h.way && !covered(h) && h.c.some(function(c){ return c.g==="دمشق"||c.g==="ريف دمشق" }))) && !BLOCK[h.k]){   // «تنظيم شرق الميدان»: a clear one-word Damascus name too, unless it is part of a longer name («كورنيش الميدان») (2026-11-08)
      var GP=["دمشق","ريف دمشق","حلب","حمص","حماة","اللاذقية","طرطوس","إدلب","درعا","السويداء","القنيطرة","دير الزور","الرقة","الحسكة"];
      var byP=h.c.slice().sort(function(x,y){ var a=GP.indexOf(x.g), b=GP.indexOf(y.g); return (a<0?99:a)-(b<0?99:b) });
      pick=byP[0]; f.placeGuess=true }
  }
  if(pick){ f.governorate=pick.g; f.area=pick.a }
  else if(gNamed.length){ f.governorate=gNamed[0];
  }
  // nearest landmark / street, as the sender wrote it («عند جسر الميدان - خلف فلافل الجسر»): up to two short pieces
  var LMK=/^(?:و ?)?(عند|خلف|قرب|بالقرب من|قريب من|قريبه من|جانب|بجانب|مقابل|امام|شارع|بشارع|دخله|نزله|طلعه|بعد|علي (?:طريق|اوتستراد|اوتوستراد|الشارع|شارع|كورنيش|جسر|دوار|الحزام)|عل (?:طريق|اوتستراد|اوتوستراد|الشارع|شارع)|مفرق|تقاطع|دوار|ساحه) /;
  var lm=[], LJUNK=/(خدمات|الخدمات|المدارس|مدارس|كل شي|جميع|المواصلات|السوق والمدارس|التواصل|الاتصال|درج|سكان)/;
  String(lat).split(/\n|[،,؛]| - | – /).forEach(function(seg){
    if(lm.length>=2) return;
    var clean=seg.replace(/[\u{1F000}-\u{1FFFF}☀-➿️#*•▪]/gu," ").replace(/\s+/g," ").trim().replace(/[.:]+$/,"").trim();
    if(!clean) return;
    var nc=N(clean).replace(/^[^؀-ۿ]+/,"");
    if(LJUNK.test(nc)) return;   // «قريب من الخدمات» says nothing about where
    if(clean.length<=70 && LMK.test(nc+" ") && !/\d/.test(clean)){ lm.push(clean); return }
    // a landmark inside a longer line («للبيع شقة على طريق المطار جانب كازية الأوكتان 90 متر»): from its first word,
    // up to six words, stopping at a number
    var ow=clean.split(" "), nw=ow.map(function(w){ return N(w).replace(/[^؀-ۿ]/g,"") });
    for(var x=0;x<nw.length;x++){ var two=nw[x]+" "+(nw[x+1]||"");
      if(!LMK.test(two+" ") && !LMK.test(nw[x]+" ")) continue;
      var out=[]; for(var y=x;y<ow.length&&out.length<6;y++){ if(/\d/.test(ow[y])||/^(طابق|ط|الطابق|غرف|غرفه|مساحه|المساحه|السعر|سعر|للبيع|للايجار|للاجار|بسعر|طابو|كسوه|اكساء|بناء|البناء|بنايه|قبو|غرفه|غرفتين|منزل|شقه|مفروش|مفروشه|مخدم|مخدمه|في|مع|يوجد|فيه|فيها)$/.test(nw[y])) break; out.push(ow[y]) }
      if(out.length>=2) lm.push(out.join(" ").replace(/[.:،,]+$/,"")); break } });
  lm=lm.filter(function(v,i){ return lm.indexOf(v)===i });
  if(lm.length) f.landmark=lm.join(" - ").slice(0,90);
  // a «منزل» with a garden or its own entrance in the «فيلات» neighbourhoods is a villa (2026-11-08)
  if(f.property_type==="house" && /فيلات/.test(f.area||"") && / (حديقه|حديقة|سويت|مدخل مستقل) /.test(t)) f.property_type="villa";
  if(!f.deal && f.price!=null && !/ (ايجار|اجار|للايجار|للاجار|استئجار|استثمار) /.test(t)) f.deal="sale";   // 2026-11-08
  // what the reader could not find (same keys as the server read)
  var miss=[]; ["deal","property_type","governorate","price","area_m2"].forEach(function(k){ if(f[k]==null && !(k==="area_m2"&&f.deal==="rent")) miss.push(k) });   // a rental needs no size
  if(f.deal==="sale"&&!f.tabu&&!land) miss.push("tabu");
  return {fields:f, missing:miss};
}
/* QF-LOCAL-END */
  return qfLocalRead;
}
