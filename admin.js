/* the page and this script are published together; a tab that kept an older page in memory would show raw label keys — reload it once */
if(typeof GX_T!=="undefined" && !GX_T.tmHowPair){ try{ if(!sessionStorage.getItem("bk_adm_reload")){ sessionStorage.setItem("bk_adm_reload","1"); location.reload() } }catch(e){} }
var ADM_FOLDS=(function(){ try{ return JSON.parse(localStorage.getItem("bk_adm_folds")||"{}")||{} }catch(e){ return {} } })();   // which sidebar groups the admin folded, per browser
/* Balkoun admin panel + homepage studio. Loaded on demand by ensureAdminJs() in index.html. Same global scope as the shell. */
async function storageCall(body){
  var ctx = (ADM&&ADM.token) ? {role:"admin",token:ADM.token} : {role:"member",token:(USER&&USER.token)||null};
  var r = await fetch(CONFIG.supabaseUrl+"/functions/v1/bk-storage",{method:"POST",
    headers:{"Content-Type":"application/json","apikey":CONFIG.supabaseKey,"Authorization":"Bearer "+CONFIG.supabaseKey},
    body:JSON.stringify(Object.assign({},body,ctx))});
  var j = null; try{ j = await r.json() }catch(e){ j = {} }
  // an admin whose panel session expired may still be a valid member — retry once as one
  if(r.status===401 && ctx.role==="admin" && USER && USER.token){
    r = await fetch(CONFIG.supabaseUrl+"/functions/v1/bk-storage",{method:"POST",
      headers:{"Content-Type":"application/json","apikey":CONFIG.supabaseKey,"Authorization":"Bearer "+CONFIG.supabaseKey},
      body:JSON.stringify(Object.assign({},body,{role:"member",token:USER.token}))});
    try{ j = await r.json() }catch(e){ j = {} }
  }
  if(!r.ok || (j&&j.error)) throw new Error((j&&j.error) || ("storage "+r.status));
  return j }
async function storageRemove(paths){
  try{ var j = await storageCall({action:"remove", paths:paths});
       return {data:(j.removed||[]).map(function(n){ return {name:n} }), error:null} }
  catch(e){ return {data:null, error:e} } }
async function storageRestore(paths){
  try{ var j = await storageCall({action:"restore", paths:paths});
       if(j && j.error) return {data:null, error:{message:j.error}};
       return {data:{restored:j.restored||[], failed:j.failed||[]}, error:null} }
  catch(e){ return {data:null, error:e} } }
var TAB_PERM={dashboard:"dashboard",stats:"stats",countries:"super",listings:"listings",photos:"listings",wanted_adm:"listings",users:"users",agencies_adm:["users","listings"],reviews:"reviews",engage:["ads","featured"],projects_adm:["listings","ads"],ads:"ads",featured:"featured",banners:"homepage",mainpage:"homepage",design:"settings",geo:"settings",contact:"settings",reports:"reports",feedback:"feedback",tickets:"feedback",intake:"listings",msgs:"msgs",settings:"settings",storage:"settings",admins:"super",danger:"super",campaigns:"campaigns"};
function canTab(k){ var p=TAB_PERM[k]; if(p===undefined) return can(k); if(p==="super") return !!ADM.isSuper; if(Array.isArray(p)) return p.some(can); return can(p) }
function admGo(tab){ if(!tab) return; if(!canTab(tab)){ admToast(GX("noPermTab"),"bad"); return } if(tab!==ADM.tab && admDirty() && !confirm(GX("hsDiscardConfirm"))) return; ADM.tab=tab; window._admMobileDetail=false; render(); try{ window.scrollTo(0,0) }catch(e){} }
function admToast(msg,kind){ var el=$("#admToast"); if(!el){ el=document.createElement("div"); el.id="admToast"; document.body.appendChild(el) } el.textContent=msg; el.className="on "+(kind||"ok"); clearTimeout(el._t); el._t=setTimeout(function(){ el.className="" },2600) }
function tkReload(){ ADM._ticketsLoaded=false; render() }
function tkScopeKey(){ return admScope() }
function adminBellHtml(){
  var td=ADM.todo||{}, n=adminTodoTotal();
  var rows=[["listings:pending",AICO.listings,GX("bellListings"),td.pending_listings],["agencies_adm",AICO.building,GX("bellAgencies"),td.pending_agencies],["wanted_adm",AICO.search,GX("bellWanted"),td.pending_wanted],["intake",AICO.contact||AICO.bell,GX("bellIntake"),td.intake_review],["users",AICO.users,GX("bellVerify"),td.verify_pending],["reports",AICO.shield,GX("bellReports"),td.open_reports],["feedback",AICO.chart,GX("bellFeedback"),td.open_feedback],["msgs",AICO.bell,GX("bellAlerts"),td.unread_alerts]].filter(function(r){ return +r[3]>0 });
  var latest=(td.latest||[]).slice(0,6);
  var kindTab={listing:"listings:pending",agency:"agencies_adm",wanted:"wanted_adm",intake:"intake",verify:"users",report:"reports",feedback:"feedback"};
  return '<div class="adbell-w"><button class="ab adbell'+(n?' has':'')+'" id="adBell" title="'+GX("bellT")+'" aria-label="'+GX("bellT")+'">'+AICO.bell+(n?'<b class="adbell-n ltr">'+(n>99?"99+":n)+'</b>':'')+'</button>'+
    '<div class="adbell-m'+(ADM.bellOpen?' on':'')+'" id="adBellMenu"><div class="adbell-h">'+GX("bellT")+(n?' <span class="ltr">('+n+')</span>':'')+'</div>'+
    (rows.length ? rows.map(function(r){ return '<a class="adbell-r" data-goto="'+r[0]+'"><span class="adbell-i">'+r[1]+'</span><span class="adbell-l">'+r[2]+'</span><b class="ltr">'+r[3]+'</b></a>' }).join("") : '<div class="adbell-empty">'+GX("bellNone")+'</div>')+
    (latest.length ? '<div class="adbell-sub">'+GX("bellLatest")+'</div>'+latest.map(function(x){ return '<a class="adbell-r small" data-goto="'+(kindTab[x.kind]||"dashboard")+'"><span class="adbell-l">'+esc(String(x.label||"")).slice(0,60)+'</span><small class="ltr">'+when(x.at)+'</small></a>' }).join("") : '')+
    '</div></div>' }
function wireAdminBell(){
  var b=$("#adBell"), m=$("#adBellMenu"); if(!b||!m) return;
  b.onclick=function(e){ e.stopPropagation(); ADM.bellOpen=!m.classList.contains("on"); m.classList.toggle("on",ADM.bellOpen); if(ADM.bellOpen) syncAdminTodo() };
  m.onclick=function(e){ e.stopPropagation() };
  $$("#adBellMenu [data-goto]").forEach(function(a){ a.onclick=function(){ ADM.bellOpen=false; var g=this.dataset.goto.split(":"); ADM.tab=g[0]; if(g[0]==="listings" && g[1]) ADM.lstatus=g[1]; if(g[0]==="agencies_adm") ADM._agLoaded=false; render() } });
  if(!window._adBellDoc){ window._adBellDoc=true; document.addEventListener("click",function(){ var mm=$("#adBellMenu"); if(mm){ mm.classList.remove("on"); ADM.bellOpen=false } }) }
}
var REC=ADM.rec||(ADM.rec={mode:null});
function adminRecoveryHtml(){
  var m=REC.mode, phoneRow='<div class="fl"><label>'+t("mobile")+'</label><div class="pw">'+ccSelect("adCC",REC.cc||phoneCC())+'<input id="adPhone" inputmode="numeric" autocomplete="off" value="'+esc(REC.phone||"")+'"></div></div>';
  var back='<div class="aun"><a id="adRecBack">'+GX("admRecBack")+'</a></div>', err='<div class="auerr" id="adErr">'+(ADM.msg||"")+'</div>';
  if(m==="pick") return '<p class="vlead">'+GX("admRecP")+'</p>'+phoneRow+
    '<div class="vopts"><button type="button" class="vopt" id="adRecTg"><span class="vico tg">'+VICO.tg+'</span><span class="vtxt"><b>'+GX("admRecTg")+'</b><small>'+GX("admRecTgP")+'</small></span></button>'+
    '<button type="button" class="vopt" id="adRecCode"><span class="vico" style="background:var(--navy)">'+AICO.key+'</span><span class="vtxt"><b>'+GX("admRecCode")+'</b><small>'+GX("admRecCodeP")+'</small></span></button></div>'+err+back;
  if(m==="tg"){ var link="https://t.me/"+encodeURIComponent(REC.bot||"")+"?start=v"+String(REC.ticket||"").replace(/-/g,"");
    return '<a class="auw vtg" href="'+link+'" target="_blank" rel="noopener"><span class="vico">'+VICO.tg+'</span>'+GX("vOpenTg")+'</a>'+
    '<ol class="vsteps"><li>'+GX("vTg1")+'</li><li>'+GX("vTg2")+'</li><li>'+GX("vTg3")+'</li></ol><div class="vwait"><i class="vspin"></i><span>'+GX("vWaiting")+'</span></div>'+err+back }
  if(m==="newpass") return '<div class="vok">✓ '+GX("vVerifiedNow")+'</div>'+
    '<div class="fl"><label>'+t("newPass")+'</label>'+pwField("adNew1","new-password",t("min6"))+'</div><div class="fl"><label>'+t("password2")+'</label>'+pwField("adNew2","new-password")+'</div>'+
    '<button class="btn-n" id="adRecSave" style="width:100%">'+t("savePass")+'</button>'+err;
  if(m==="code") return '<p class="vlead">'+GX("admRecCodeL")+'</p>'+phoneRow+
    '<div class="fl"><label>'+GX("admRecCode")+'</label><input id="adRecCodeIn" class="ltr" autocomplete="off" placeholder="XXXX-XXXX" style="letter-spacing:2px;font-weight:700"></div>'+
    '<div class="fl"><label>'+t("newPass")+'</label>'+pwField("adNew1","new-password",t("min6"))+'</div><div class="fl"><label>'+t("password2")+'</label>'+pwField("adNew2","new-password")+'</div>'+
    '<button class="btn-n" id="adRecCodeGo" style="width:100%">'+t("savePass")+'</button>'+err+back;
  if(m==="done") return '<div class="vok">✓ '+GX("admRecDone")+'</div><button class="btn-n" id="adRecBack" style="width:100%">'+t("login")+'</button>';
  return '' }
function adminView(){
 if(!ADM.token) return ''+
  '<div class="wrap adlogin" style="max-width:440px;padding:56px 18px 80px"><div class="blk">'+
  '<h3><span class="n">⚑</span>'+(REC.mode?GX("admRecT"):t("adminLogin"))+'</h3><div class="in">'+
  (REC.mode ? adminRecoveryHtml() :
  '<div class="fl"><label>'+t("mobile")+'</label><div class="pw">'+ccSelect("adCC",phoneCC())+
   '<input id="adPhone" inputmode="numeric" autocomplete="off"></div></div>'+
  '<div class="fl"><label>'+t("password")+'</label>'+
   pwField("adPass","off")+'</div>'+
  '<button class="btn-n" id="adGo" style="width:100%">'+t("login")+'</button>'+
  '<div class="auerr" id="adErr">'+(ADM.msg||"")+'</div>'+
  '<div class="aun"><a id="adForgot">'+GX("admForgot")+'</a></div>'+
  '<div class="hintx">'+t("adminHint")+'</div>')+
  '</div></div></div>';

  var d=ADM.data||{stats:{},listings:[],users:[],reports:[],feedback:[],reviews:[]};
 var refFor=function(listingId){
   var match=(d.listings||[]).filter(function(l){return String(l.id)===String(listingId)})[0];
   return match&&match.ref ? match.ref : (listingId!=null ? String(listingId) : "—");
 };
 var s=d.stats||{};
 var PRIOS=["low","normal","high","urgent"];
 var ticketFor=function(kind,id){ return (ADM.tickets||[]).filter(function(x){ return x.source_kind===kind && String(x.source_id)===String(id) })[0] };
 var msgFooter=function(kind,id,thread,who,adminReply,solved,canReply){
   canReply = canReply!==false;   // a visitor without an account cannot receive a reply inside the site
   var tk=ticketFor(kind,id);
   var tkBtn = tk ? '<a class="ab" data-goto="tickets" data-tkopen="'+tk.id+'" style="text-decoration:none">'+GX("tkTransferred").replace("{c}",esc(tk.code))+'</a>'
                  : '<button class="ab" data-toticket="'+kind+':'+id+'">'+GX("tkTransfer")+'</button>';
   return (thread&&thread.length ? '<div class="msgthread" style="margin-top:8px">'+thread.map(function(m){
      return '<div class="msgbubble '+(m.sender==="admin"?"mine":"theirs")+'"><div class="msgwho">'+
        (m.sender==="admin"?t("you"):who)+'</div>'+
        '<div class="msgbody">'+m.body+'</div><div class="msgts">'+when(m.created_at)+'</div></div>'}).join("")+'</div>'
     : (adminReply ? '<div class="fbreply"><b>'+t("yourReply")+':</b> '+adminReply+'</div>' : ''))+
   '<div class="fbreplybox" style="margin-top:8px">'+(canReply?'<textarea data-replybox="'+kind+':'+id+'" placeholder="'+t("replyPH")+'"></textarea>':'<div class="hintx">'+GX("msgVisitorNoReply")+'</div>')+
     '<div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:6px;align-items:center">'+
     (canReply?'<button class="ab ok" data-replysend="'+kind+':'+id+'">'+t("sendReply")+'</button>':'')+
     '<button class="ab '+(solved?"":"ok")+'" data-tosolved="'+kind+':'+id+'" data-val="'+(solved?"0":"1")+'">'+
       (solved?t("reopenIt"):t("markSolved"))+'</button>'+tkBtn+
     '<span class="priopick" data-priowrap="'+kind+':'+id+'" style="margin-inline-start:auto;display:flex;gap:4px">'+
       PRIOS.map(function(p){return '<button type="button" class="priobtn prio-'+p+'" data-setprio="'+kind+':'+id+'" data-prioval="'+p+'">'+t("prio_"+p)+'</button>'}).join("")+
     '</span></div></div>' };
 var stat=function(k,v,c,goto){return '<button type="button" class="astat" '+(goto?'data-goto="'+goto+'"':'')+'><b class="ltr" '+(c?'style="color:'+c+'"':'')+'>'+
   (v===undefined?0:v).toLocaleString("en")+'</b><span>'+k+'</span></button>'};
 var tab=function(k,l,n2,icon){return '<a class="'+(ADM.tab===k?"on":"")+'" data-atab="'+k+'">'+
   (icon?'<span class="aicon">'+icon+'</span>':'')+'<span>'+l+'</span>'+(n2?'<span class="abadge2">'+n2+'</span>':'')+'</a>'};

 var emailInbox=function(kind, items, filterKey, selKey, buildRow, buildDetail, emptyText, deleteRpc){
   var filter=ADM[filterKey]||"all";
   var shown=filter==="open"?items.filter(function(x){return !(x.resolved||x.handled)}):
             filter==="solved"?items.filter(function(x){return x.resolved||x.handled}):items;
   var selId=ADM[selKey];
   var selItem=selId?shown.filter(function(x){return String(x.id)===String(selId)})[0]:null;
   if(!selItem && shown.length) selItem=shown[0];
   return '<div class="inbox'+(window._admMobileDetail?' inbox-mobiledetail':'')+'">'+
    '<div class="inbox-list">'+
     '<div class="msgfilters">'+
      ["all","open","solved"].map(function(fk){return '<button class="mfbtn'+(filter===fk?" on":"")+'" data-emailfilter="'+kind+':'+fk+'">'+t("mf_"+fk)+'</button>'}).join("")+
     '</div>'+
     '<input id="aq'+kind+'" placeholder="'+t("searchPH")+'" class="asearch" style="margin:10px 0">'+
     '<div class="inbox-rows" id="inboxRows'+kind+'">'+
      (shown.length ? shown.map(function(x){ return buildRow(x, selItem&&String(selItem.id)===String(x.id)) }).join("")
       : '<div class="done2"><b>'+emptyText+'</b></div>')+
     '</div>'+
    '</div>'+
    '<div class="inbox-detail" id="inboxDetail'+kind+'">'+
     (selItem ? '<button class="ab inbox-back" data-emailback="'+kind+'">‹ '+t("backToList")+'</button>'+
       buildDetail(selItem)+
       '<button class="ab bad" style="margin-top:12px" data-emaildelete="'+kind+':'+selItem.id+'">'+t("deleteItem")+'</button>'
      : '<div class="done2"><b>'+t("selectAnItem")+'</b></div>')+
    '</div>'+
   '</div>'};

 var body="";

 if(ADM.tab==="dashboard"){ body = adminDashboardBody(s); }
 else if(ADM.tab==="listings"){
  body='<div class="afilters"><input id="aqL" placeholder="'+t("searchPH")+'" class="asearch">'+
   '<select id="afStatus"><option value="">'+t("allStatus")+'</option>'+
   ["pending","rejected","live","hidden","sold","rented","expired","removed"].map(function(k){
     return '<option value="'+k+'">'+(k==="hidden"?GX("st_hidden"):k==="rejected"?GX("st_rejected"):t("st_"+k))+'</option>'}).join("")+'</select>'+
   '<select id="afDeal"><option value="">'+t("allDeals")+'</option>'+
   '<option value="sale">'+t("buy")+'</option><option value="rent">'+t("rent")+'</option></select>'+
   '<select id="afTabu"><option value="">'+t("allDeeds")+'</option>'+
   Object.keys(D.TABU).map(function(k){
     return '<option value="'+k+'">'+D.TABU[k][li()]+'</option>'}).join("")+'</select>'+
   '<select id="afSort"><option value="new"'+(ADM.listSort!=="views"&&ADM.listSort!=="contacts"?" selected":"")+'>'+GX("sortNewest")+'</option><option value="views"'+(ADM.listSort==="views"?" selected":"")+'>'+GX("sortViews")+'</option><option value="contacts"'+(ADM.listSort==="contacts"?" selected":"")+'>'+GX("sortContacts")+'</option></select></div>'+
  '<div class="dash-top" style="margin:8px 0">'+rangeTabs()+'</div>'+
  '<div style="font-size:12.5px;color:var(--grey);margin:8px 0"><span id="aListCount"><span class="ltr">'+(d.listings||[]).length+'</span> '+t("listingsTab")+'</span></div>'+
  '<div class="atable ltable"><table><thead><tr>'+
   [t("listingsTab"),t("deed"),GX("colViews"),t("postedBy"),t("status"),''].map(function(h){return '<th>'+h+'</th>'}).join("")+
   '</tr></thead><tbody id="aListBody">'+
   (d.listings||[]).slice().sort(function(a,b){ var A=(ADM.lstats||{})[a.id]||{}, B=(ADM.lstats||{})[b.id]||{}; if(ADM.listSort==="views") return (+B.views||0)-(+A.views||0); if(ADM.listSort==="contacts") return (+B.contacts||0)-(+A.contacts||0); return 0 }).map(function(l){
     var ls=(ADM.lstats||{})[l.id]||{}, typeName=(D.TYPES[l.property_type]?D.TYPES[l.property_type][li()]:(l.property_type||""));
     var stLabel = l.status==="hidden"?GX("st_hidden"):l.status==="rejected"?GX("st_rejected"):(t("st_"+l.status)||l.status);
     return '<tr data-row-status="'+l.status+'" data-row-tabu="'+(l.tabu||"")+'" data-row-deal="'+(l.deal||"")+'" data-row-text="'+((l.gov||"")+" "+(l.area||"")+" "+(l.poster_name||"")+" "+l.ref).toLowerCase()+'">'+
     '<td><div class="lcell"><b class="ltr adlink" data-open="'+l.id+'">'+scopeFlag(l.country_code)+(l.ref||l.id)+'</b>'+
       '<div class="lsub">'+typeName+' · <span class="ltr">$'+Number(l.price_usd).toLocaleString("en")+'</span>'+(l.deal==="rent"?' · '+t("rent"):'')+'</div>'+
       '<div class="lsub">'+(l.area?l.area+"، ":"")+(l.gov||"")+'</div></div></td>'+
     '<td><span class="tag '+cls(l.tabu)+'">'+(D.TABU[l.tabu]?D.TABU[l.tabu][li()]:(l.tabu||"—"))+'</span><div class="lsub"><span class="ltr">'+(l.photos||0)+'</span> '+t("photos")+'</div></td>'+
     '<td><div class="lperf"><span><b class="ltr">'+(ls.views!=null?ls.views:"…")+'</b> '+GX("colViews")+(ls.views_total!=null?' <small class="ltr">/ '+ls.views_total+'</small>':'')+'</span>'+
       '<span><b class="ltr">'+(ls.contacts!=null?ls.contacts:"…")+'</b> '+GX("colContacts")+'</span>'+
       '<span><b class="ltr">'+(ls.saves!=null?ls.saves:"…")+'</b> '+GX("colSaves")+'</span></div></td>'+
     '<td>'+(l.poster_id?'<a data-byuser="'+l.poster_id+'" data-name="'+(l.poster_name||"")+'" class="uname">'+(l.poster_name||"—")+'</a>':'<span>'+(l.poster_name||"—")+'</span>')+(l.poster_phone?'<div class="lsub ltr">'+l.poster_phone+'</div>':'')+'</td>'+
     '<td><span class="st st-'+l.status+'">'+stLabel+'</span>'+(l.is_featured?'<div class="lsub" style="color:#8A6522">★ '+t("featuredBadgeDefault")+'</div>':'')+'</td>'+
     '<td class="lacts">'+
       '<button class="ab" data-adopen="'+l.id+'">'+t("edit")+'</button>'+
       (l.status==="pending"?'<button class="ab ok" data-alive="'+l.id+'">'+t("approve")+'</button><button class="ab bad" data-areject="'+l.id+'">'+GX("rejectBtn")+'</button>':'')+
       (l.status==="rejected"?'<button class="ab ok" data-alive="'+l.id+'">'+t("approve")+'</button>':'')+
       (l.status==="hidden"?'<button class="ab ok" data-alive="'+l.id+'">'+GX("unhide")+'</button>':'')+
       (l.status==="live"?'<button class="ab" data-apend="'+l.id+'">'+t("hide")+'</button>':'')+
       '<button class="ab bad" data-adel="'+l.id+'">'+t("del")+'</button></td></tr>'}).join("")+
   '</tbody></table></div>';
 }

 else if(ADM.tab==="users"){
  body = adminUsersBody(d);
 }

 else if(ADM.tab==="reports"){
  body = emailInbox("report", d.reports||[], "msgFilterReport", "selReportId",
   function(r,isSel){
     return '<div class="inbox-row'+(isSel?' on':'')+(r.resolved?' solved':'')+'" data-emailrow="report:'+r.id+'" data-row-text="'+
      ((r.reporter_name||"")+" "+(r.listing_ref||"")+" "+(r.reason||"")+" "+(r.note||"")).toLowerCase()+'">'+
      '<div class="inbox-row-top"><b>'+(r.reporter_name||t("anonGuest"))+'</b>'+
       (r.priority&&r.priority!=="normal"?'<span class="priotag prio-'+r.priority+'">'+t("prio_"+r.priority)+'</span>':'')+
       '<span class="fbwhen">'+when(r.created_at)+'</span></div>'+
      '<div class="inbox-row-sub"><span class="ltr">'+(r.listing_ref||r.listing_id)+'</span> · '+(t("r"+capitalize(r.reason))||r.reason)+'</div>'+
      (r.resolved?'<span class="inbox-row-badge">'+t("mf_solved")+'</span>':'')+
     '</div>';
   },
   function(r){
     return '<div class="fbtop"><b>'+t("rListing")+' <span class="ltr">'+(r.listing_ref||r.listing_id)+'</span></b>'+
      '<span class="fbwhen">'+when(r.created_at)+'</span></div>'+
     '<div class="fbwho">'+t("rBy")+' '+
      (r.reporter_id
        ? '<a data-byuser="'+r.reporter_id+'" data-name="'+(r.reporter_name||"")+'" style="text-decoration:underline;cursor:pointer">'+(r.reporter_name||t("anonGuest"))+'</a>'
        : (r.reporter_name||t("anonGuest")))+
      (r.reporter_phone?' · <span class="ltr">'+r.reporter_phone+'</span>':'')+'</div>'+
     '<div class="fbreason">'+(t("r"+capitalize(r.reason))||r.reason)+'</div>'+
     (r.note?'<div class="fbbody">'+r.note+'</div>':'')+
     msgFooter("report",r.id,r.thread,r.reporter_name||t("anonGuest"),r.admin_reply,r.resolved,!!r.reporter_id);
   }, t("noReports"), "bk_admin_delete_report");
 }

 else if(ADM.tab==="tickets"){
  var TK=(ADM.tickets||[]).map(function(x){ x.handled = x.status==="done"; return x });
  var tkStatus=function(st){ return GX("tkSt_"+st) };
  var tkSrc=function(x){ return '<span class="fbkind fbkind-'+(x.source_kind==="report"?"complaint":x.source_kind==="feedback"?"suggestion":"other")+'">'+GX("tkSrc_"+x.source_kind)+'</span>' };
  var addForm=!ADM.tkAddOpen ? '<div style="margin-bottom:14px"><button class="ab ok" id="tkAddOpen">+ '+GX("tkNew")+'</button></div>' : '<div class="blk" style="margin-bottom:14px"><h3>'+GX("tkNew")+'</h3><div class="in"><div class="row"><div class="fl"><label>'+GX("tkTitle")+'</label><input id="tkTitle" autocomplete="off"></div><div class="fl"><label>'+GX("tkContact")+'</label><input id="tkContact" autocomplete="off" class="ltr"></div></div>'+
    '<div class="fl"><label>'+GX("tkBody")+'</label><textarea id="tkBody" rows="3"></textarea></div><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><select id="tkPrio">'+PRIOS.map(function(p){ return '<option value="'+p+'"'+(p==="normal"?' selected':'')+'>'+t("prio_"+p)+'</option>' }).join("")+'</select><button class="ab ok" id="tkAdd">'+GX("tkAddBtn")+'</button><span class="xmsg" id="tkAddMsg"></span></div></div></div>';
  body = addForm + emailInbox("ticket", TK, "msgFilterTicket", "selTicketId",
   function(x,isSel){
     return '<div class="inbox-row'+(isSel?' on':'')+(x.status==="done"?' solved':'')+'" data-emailrow="ticket:'+x.id+'" data-row-text="'+((x.code||"")+" "+(x.title||"")+" "+(x.body||"")).toLowerCase()+'">'+
      '<div class="inbox-row-top"><b class="ltr">'+escOnce(x.code)+'</b><span class="fbkind prio-'+x.priority+'">'+t("prio_"+x.priority)+'</span><span class="fbwhen">'+when(x.created_at)+'</span></div>'+
      '<div class="inbox-row-sub">'+escOnce(x.title||"")+'</div>'+
      '<span class="inbox-row-badge'+(x.status==="done"?'':' tk-open')+'">'+tkStatus(x.status)+'</span></div>' },
   function(x){
     return '<div class="fbtop"><b class="ltr" style="font-size:18px;color:var(--navy)">'+escOnce(x.code)+'</b>'+tkSrc(x)+(ADM.scope==="ALL"&&x.country_code?'<span class="fbkind">'+escOnce(x.country_code)+'</span>':'')+'<span class="fbwhen">'+when(x.created_at)+(x.created_by_name?' · '+escOnce(x.created_by_name):'')+'</span></div>'+
      '<div class="fl" style="margin-top:10px"><label>'+GX("tkTitle")+'</label><input data-tktitle="'+x.id+'" value="'+escOnce(x.title||"")+'"></div>'+
      (x.body?'<div class="fbbody">'+escOnce(x.body)+'</div>':'')+
      (x.contact?'<div class="fbwho">'+GX("tkContact")+': <span class="ltr">'+escOnce(x.contact)+'</span></div>':'')+
      (x.link?'<div class="fbwho"><a href="'+escOnce(x.link)+'" data-tklink="'+escOnce(x.link)+'" style="text-decoration:underline;cursor:pointer">'+GX("tkOpenSource")+'</a></div>':'')+
      '<div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:12px;align-items:center"><b style="font-size:12.5px">'+GX("tkStatus")+':</b>'+["open","progress","done"].map(function(st){ return '<button type="button" class="ab'+(x.status===st?' ok':'')+'" data-tkstatus="'+x.id+':'+st+'">'+tkStatus(st)+'</button>' }).join("")+
      '<span class="priopick" style="margin-inline-start:auto;display:flex;gap:4px">'+PRIOS.map(function(p){ return '<button type="button" class="priobtn prio-'+p+(x.priority===p?' on':'')+'" data-tkprio="'+x.id+':'+p+'">'+t("prio_"+p)+'</button>' }).join("")+'</span></div>'+
      '<div class="fl" style="margin-top:12px"><label>'+GX("tkNotes")+'</label><textarea data-tknotes="'+x.id+'" rows="4" placeholder="'+escOnce(GX("tkNotesPH"))+'">'+escOnce(x.notes||"")+'</textarea></div>'+
      '<div style="display:flex;gap:8px;align-items:center"><button class="ab ok" data-tksave="'+x.id+'">'+GX("tkSave")+'</button><span class="xmsg" id="tkMsg'+x.id+'"></span>'+(x.done_at?'<span class="hintx">'+GX("tkDoneAt")+' '+when(x.done_at)+'</span>':'')+'</div>' },
   GX("noTickets"), "bk_admin_ticket_delete");
 }
 else if(ADM.tab==="feedback"){
  body = emailInbox("feedback", d.feedback||[], "msgFilterFeedback", "selFeedbackId",
   function(f,isSel){
     return '<div class="inbox-row'+(isSel?' on':'')+(f.handled?' solved':'')+'" data-emailrow="feedback:'+f.id+'" data-row-text="'+
      ((f.sender_name||"")+" "+f.kind+" "+f.body).toLowerCase()+'">'+
      '<div class="inbox-row-top">'+scopeFlag(f.country_code)+'<b>'+(f.sender_name||t("anonGuest"))+'</b>'+
       '<span class="fbkind fbkind-'+f.kind+'">'+t("k"+capitalize(f.kind))+'</span>'+
       '<span class="fbwhen">'+when(f.created_at)+'</span></div>'+
      '<div class="inbox-row-sub">'+(f.body||"").slice(0,70)+'</div>'+
      (f.handled?'<span class="inbox-row-badge">'+t("mf_solved")+'</span>':'')+
     '</div>';
   },
   function(f){
     return '<div class="fbtop"><span class="fbkind fbkind-'+f.kind+'">'+t("k"+capitalize(f.kind))+'</span>'+
      '<span class="fbwhen">'+when(f.created_at)+'</span></div>'+
     '<div class="fbwho">'+t("rBy")+' '+
      (f.sender_id
        ? '<a data-byuser="'+f.sender_id+'" data-name="'+(f.sender_name||"")+'" style="text-decoration:underline;cursor:pointer">'+(f.sender_name||t("anonGuest"))+'</a>'
        : (f.sender_name||t("anonGuest")))+
      (f.sender_contact?' · <span class="ltr">'+f.sender_contact+'</span>':'')+'</div>'+
     '<div class="fbbody">'+f.body+'</div>'+
     msgFooter("feedback",f.id,f.thread,f.sender_name||t("anonGuest"),f.admin_reply,f.handled,!!f.sender_id);
   }, t("noFeedback"), "bk_admin_delete_feedback");
 }

 else if(ADM.tab==="reviews"){
  body=(d.reviews||[]).length
   ? '<div class="atable"><table><thead><tr>'+
     [t("targetCol"),t("byCol"),t("ratingCol"),t("fbBody"),''].map(function(h){return '<th>'+h+'</th>'}).join("")+
     '</tr></thead><tbody>'+
     d.reviews.map(function(r){
       return '<tr><td>'+(r.target_name||"—")+'</td><td>'+(r.author_name||"—")+'</td>'+
       '<td class="ltr" style="color:var(--gold)">'+stars(r.stars)+'</td>'+
       '<td style="max-width:260px">'+(r.body||"")+'</td>'+
       '<td><button class="ab bad" data-delreview="'+r.id+'">'+t("del")+'</button></td></tr>'}).join("")+
     '</tbody></table></div>'
   : '<div class="done2"><b>'+t("noReviewsAdmin")+'</b></div>';
 }

 else if(ADM.tab==="stats"){ body = adminAnalyticsBody(); }

 else if(ADM.tab==="geo"){ body = geoAdminBody(); }
 else if(ADM.tab==="countries"){ body = adminCountriesBody(); }
 else if(ADM.tab==="banners"){ body = hsStudioHtml("banners"); }
 else if(ADM.tab==="contact"){ body = hsStudioHtml("contact"); }
 else if(ADM.tab==="design"){ body = hsStudioHtml("design"); }
 else if(ADM.tab==="storage"){
  body = adminStorageBody('<div class="blk" style="margin-top:16px"><h3>'+t("storageLimitH")+'</h3><div class="in">'+
    '<div class="hintx" style="margin-bottom:10px">'+t("storageLimitHint")+'</div>'+
    '<div class="fl"><label>'+t("storageLimitL")+'</label>'+
     '<input id="scStorageLimit" type="number" min="1" value="'+(SITE.storage_limit_mb!=null?SITE.storage_limit_mb:1024)+'"></div>'+
    '<button class="ab ok" id="scStorageLimitSave">'+t("save")+'</button>'+
    '<span style="font-size:12.5px;color:var(--ok);margin-inline-start:8px" id="scStorageLimitMsg"></span>'+
   '</div></div>'+
   '<div class="blk"><h3>'+GX("videoSetH")+'</h3><div class="in">'+
    '<div class="hintx" style="margin-bottom:10px">'+GX("videoSetHint")+'</div>'+
    '<label style="display:flex;gap:8px;align-items:center;font-size:14px;margin-bottom:10px"><input type="checkbox" id="scVideoOn"'+(videoCfg().on?' checked':'')+'>'+GX("videoEnabledL")+'</label>'+
    '<div class="row"><div class="fl"><label>'+GX("videoMaxMbL")+'</label><input id="scVideoMb" type="number" min="5" max="50" value="'+videoCfg().mb+'"></div>'+
    '<div class="fl"><label>'+GX("videoMaxSL")+'</label><input id="scVideoS" type="number" min="10" max="600" value="'+videoCfg().s+'"></div>'+
    '<div class="fl"><label>'+GX("videoMaxNL")+'</label><input id="scVideoN" type="number" min="1" max="5" value="'+videoCfg().n+'"></div></div>'+
    '<button class="ab ok" id="scVideoSave">'+t("save")+'</button>'+
    '<span style="font-size:12.5px;color:var(--ok);margin-inline-start:8px" id="scVideoMsg"></span>'+
   '</div></div>'+
   '');
 }
 else if(ADM.tab==="settings"){
  var st2=ADM.settings;
  body = !st2 ? '<div class="done2"><b>'+t("loading")+'</b></div>' :
   (st2._error?'<div class="done2" style="margin-bottom:12px;border-color:var(--danger)"><b>'+GX("loadFailed")+'</b><div class="hintx">'+esc(st2._error)+'</div></div>':'')+
   '<div class="blk"><h3>'+t("approvalModeH")+'</h3><div class="in">'+
    '<label style="display:flex;align-items:center;gap:10px;cursor:pointer">'+
     '<input type="checkbox" id="aReqApproval"'+(st2.require_approval?" checked":"")+'>'+
     '<span>'+t("approvalModeL")+'</span></label>'+
    '<div class="hintx" style="margin-top:8px">'+t("approvalModeH2")+'</div>'+
    '<div style="font-size:12.5px;color:var(--ok);margin-top:8px" id="aSettingsMsg"></div>'+
   '</div></div>'+
   '<div class="blk" style="margin-top:16px"><h3>'+t("perMemberApproval")+'</h3><div class="in">'+
    '<div class="hintx">'+t("perMemberApprovalH")+'</div>'+
    (canTab("users")?'<button type="button" class="ab" data-goto="users" style="margin-top:8px">'+t("usersTab")+' ↗</button>':'')+
   '</div></div>'+
   (COUNTRY==="SY" ? '<div class="blk" style="margin-top:16px"><h3>'+t("sypRateH")+'</h3><div class="in">'+
    '<div class="hintx">'+t("sypRateHint")+'</div>'+
    '<div class="fl"><label>'+t("sypRateL")+'</label><input id="scSypRate" type="number" min="1" value="'+(SITE.syp_rate!=null?SITE.syp_rate:13500)+'"></div>'+
    '<div class="xactions"><button class="ab ok" id="scSypRateSave">'+t("save")+'</button><span class="xmsg" id="scSypRateMsg"></span></div>'+
   '</div></div>'
   : '<div class="blk" style="margin-top:16px"><h3>'+GX("cRates")+'</h3><div class="in"><div class="hintx">'+GX("ratesInCountries").replace("{c}",esc(countryName(countryOf(COUNTRY)||{})))+'</div>'+
    (ADM.isSuper?'<button type="button" class="ab" data-goto="countries" style="margin-top:8px">'+GX("countriesTab")+' ↗</button>':'')+'</div></div>');
 }

 else if(ADM.tab==="msgs"){
  var alerts = ADM.alerts||[];
  body = '<div class="blk"><h3>'+t("recentAlertsH")+'</h3><div class="in">'+
   (alerts.length ? '<div class="onlinelist">'+alerts.map(function(n){
     var lbl = n.title==="new_feedback"?t("newFeedbackAlert"):n.title==="new_report"?t("newReportAlert"):n.title;
     return '<div class="onlinerow" style="align-items:center">'+
       '<a data-goto="'+(n.link||"").replace("/#/admin:","")+'" style="display:flex;align-items:center;gap:8px;flex:1;min-width:0">'+
       '<span class="onlinedot" style="background:'+(n.is_read?"var(--light)":"var(--danger)")+'"></span>'+
       '<span><b style="font-size:13px">'+lbl+'</b><br><span style="font-size:12px;color:var(--grey)">'+(n.body||"").slice(0,80)+'</span></span>'+
       '</a>'+
       '<span class="ltr" style="color:var(--light);font-size:11px;white-space:nowrap">'+when(n.created_at)+'</span>'+
       '<button class="ab bad" style="margin-inline-start:8px" data-delalert="'+n.id+'">'+t("deleteItem")+'</button>'+
      '</div>'}).join("")+'</div>'
    : '<div class="done2"><b>'+t("noAlerts")+'</b></div>')+
   '</div></div>'+
   '<div class="blk" style="margin-top:16px"><h3>'+t("sendNotifH")+'</h3><div class="in">'+
    '<label style="display:flex;align-items:center;gap:8px;cursor:pointer;margin-bottom:10px">'+
     '<input type="checkbox" id="notifAll"><span>'+t("sendToAll")+'</span></label>'+
    '<div class="fl" id="notifTargetWrap"><label>'+t("sendToOne")+'</label><select id="notifTarget">'+
     '<option value="">'+t("chooseMember")+'</option>'+
     (d.users||[]).map(function(u){return '<option value="'+u.id+'"'+(ADM.notifTargetUid===u.id?' selected':'')+'>'+((u.name||"")+" "+(u.family_name||"")).trim()+' — '+u.phone+'</option>'}).join("")+
    '</select></div>'+
    '<div class="fl"><label>'+t("notifTitleL")+'</label><input id="notifTitle" autocomplete="off"></div>'+
    '<div class="fl"><label>'+t("notifBodyL")+'</label><textarea id="notifBody" maxlength="300"></textarea></div>'+
    '<div style="display:flex;gap:10px;align-items:center;margin-top:6px">'+
    '<button class="ab ok" id="notifSend">'+t("send")+'</button>'+
    '<span style="font-size:12.5px;color:var(--ok)" id="notifSendMsg"></span></div>'+
   '</div></div>';
 }

 else if(ADM.tab==="mainpage"){
  body = hsStudioHtml("home");
 }
 else if(ADM.tab==="photos"){
  // one media library covering every category the site stores files
  // for. "Listings" keeps the existing gallery (every listing photo,
  // click to open that listing) unchanged; the other three show
  // whatever's actually sitting in that category's own storage
  // folder — photos and videos together — with delete access, since
  // those aren't tied to a database row the way listing photos are.
  var mediaCat = ADM.mediaCategory||"listings";
  var catTabs = [["listings",t("listingsTab")],["ads",t("adsTab")],["banners",t("topBannerH")],["background",t("heroBgH")]];
  body = '<div class="pick" style="margin-bottom:14px">'+catTabs.map(function(c){
      return '<label><input type="radio" name="mediaCat" value="'+c[0]+'"'+(mediaCat===c[0]?" checked":"")+'><span>'+c[1]+'</span></label>'
    }).join("")+'</div>';
  ADM.mediaSearch = ADM.mediaSearch||{};
  var msKey = mediaCat, ms = ADM.mediaSearch[msKey] = ADM.mediaSearch[msKey]||{q:"",used:"",sort:"newest"};
  // one shared filter bar + grid renderer for all four categories, so
  // "search by number, used status, and upload date" behaves exactly
  // the same everywhere instead of four separately-built versions
  // that could each drift out of sync with each other over time
  ADM.mediaSelected = ADM.mediaSelected||{};
  var selSet = ADM.mediaSelected[msKey] = ADM.mediaSelected[msKey]||{};
  var renderMediaSection = function(items, opts){
    var q = (ms.q||"").trim().toLowerCase();
    var filtered = items.filter(function(it){
      if(q && (it.label||"").toLowerCase().indexOf(q)===-1) return false;
      if(ms.used==="used" && !it.isUsed) return false;
      if(ms.used==="unused" && it.isUsed) return false;
      if(ms.type==="photo" && it.isVideo) return false;
      if(ms.type==="video" && !it.isVideo) return false;
      return true;
    });
    filtered.sort(function(a,b){
      var da=new Date(a.uploadedAt||0), db=new Date(b.uploadedAt||0);
      return ms.sort==="oldest" ? da-db : db-da;
    });
    var dateFmt = function(d){ if(!d) return ""; var dt=new Date(d); return isNaN(dt) ? "" : dt.toISOString().slice(0,10) };
    // only a genuinely deletable (not-in-use) item is ever selectable
    // in the first place — an "in use" item never gets a checkbox at
    // all, so "select all" physically cannot catch one, filtered view
    // or not
    var selectable = filtered.filter(function(it){ return it.deletePath && !it.isUsed });
    var selectedCount = selectable.filter(function(it){ return selSet[it.deletePath] }).length;
    return '<div class="afilters" style="margin-bottom:10px">'+
      '<input id="msQ" value="'+(ms.q||"").replace(/"/g,"&quot;")+'" placeholder="'+opts.searchPh+'" class="asearch">'+
      '<select id="msUsed"><option value="">'+t("allFiles")+'</option>'+
       '<option value="used"'+(ms.used==="used"?" selected":"")+'>'+t("adStorageInUse")+'</option>'+
       '<option value="unused"'+(ms.used==="unused"?" selected":"")+'>'+t("notUsed")+'</option></select>'+
      '<select id="msType"><option value="">'+t("allTypes")+'</option>'+
       '<option value="photo"'+(ms.type==="photo"?" selected":"")+'>'+t("photosOnly")+'</option>'+
       '<option value="video"'+(ms.type==="video"?" selected":"")+'>'+t("videosOnly")+'</option></select>'+
      '<select id="msSort"><option value="newest"'+(ms.sort!=="oldest"?" selected":"")+'>'+t("newestFirst")+'</option>'+
       '<option value="oldest"'+(ms.sort==="oldest"?" selected":"")+'>'+t("oldestFirst")+'</option></select>'+
     '</div>'+
     (selectable.length ? '<div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">'+
       '<label style="display:flex;align-items:center;gap:6px;font-size:13px;cursor:pointer">'+
        '<input type="checkbox" id="msSelectAll"'+(selectedCount>0 && selectedCount===selectable.length?" checked":"")+
        '> '+t("selectAll")+' ('+selectable.length+')</label>'+
       (selectedCount ? '<button type="button" class="ab bad" id="msDeleteSelected">'+t("deleteSelectedN").replace("{n}",selectedCount)+'</button>' : '')+
      '</div>' : '')+
     (opts.loading ? '<div class="hintx">'+t("loading")+'</div>' :
      (!items.length ? '<div class="hintx">'+opts.emptyMsg+'</div>' :
       !filtered.length ? '<div class="hintx">'+t("noMatchingFiles")+'</div>' :
       '<div class="thumbs" style="grid-template-columns:repeat(auto-fill,minmax('+opts.thumbSize+'px,1fr))">'+
        filtered.map(function(it){
          var canSelect = it.deletePath && !it.isUsed;
          return '<div style="position:relative">'+
            (canSelect ? '<input type="checkbox" class="msItemCheck" data-selpath="'+it.deletePath+'"'+(selSet[it.deletePath]?" checked":"")+
              ' style="position:absolute;top:4px;inset-inline-start:4px;z-index:1;width:16px;height:16px">' : '')+
            '<a'+(it.viewerAttr||'')+' style="cursor:pointer;display:block;aspect-ratio:1/1;border-radius:8px;overflow:hidden;background:var(--page)">'+
             (it.isVideo ? '<video src="'+it.thumbUrl+'" muted style="width:100%;height:100%;object-fit:cover"></video>'
                         : '<img src="'+it.thumbUrl+'" alt="" loading="lazy" style="width:100%;height:100%;object-fit:cover">')+
            '</a>'+
            (it.label?'<span style="position:absolute;bottom:2px;inset-inline-start:4px;inset-inline-end:4px;font-size:10px;color:#fff;background:rgba(9,14,26,.65);border-radius:4px;padding:1px 4px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" class="ltr">'+it.label+(it.uploadedAt?' · '+dateFmt(it.uploadedAt):'')+'</span>':'')+
            (it.isUsed
             ? '<span style="position:absolute;top:4px;inset-inline-start:4px;font-size:9px;font-weight:600;color:#fff;background:var(--ok);border-radius:4px;padding:1px 5px">'+t("adStorageInUse")+'</span>'
             : (it.deletePath?'<button type="button" class="ab bad" data-delfile="'+it.deletePath+'" style="position:absolute;top:4px;inset-inline-end:4px;padding:2px 7px;font-size:11px">'+t("del")+'</button>':''))+
          '</div>';
        }).join("")+
       '</div>'));
  };
  if(mediaCat==="listings"){
    var photos = ADM.photosList||[];
    // listing_photos itself doesn't carry the listing's own reference
    // number, so it's looked up here from the dashboard's already-
    // loaded listings data rather than adding a second query. A photo
    // whose listing no longer shows up there (deleted/removed) is the
    // "not used" case — everything else is still attached to a real,
    // present listing
    var refById = {};
    (d.listings||[]).forEach(function(l){ refById[l.id] = l.ref||String(l.id) });
    var listingItems = photos.map(function(p,i){
      var ref = refById[p.listing_id]||p.ref||"";
      return {thumbUrl:p.thumb_url||p.url, isVideo:false, label:ref, uploadedAt:p.created_at,
        isUsed:!!ref, viewerAttr:' data-openphoto="'+i+'"'};
    });
    body += renderMediaSection(listingItems, {searchPh:t("searchByListingNo"), emptyMsg:t("noPhotosYet"), thumbSize:130, loading:ADM._photosLoading});
    if(ADM.viewingPhotoIdx!=null && photos[ADM.viewingPhotoIdx]){
      var vp = photos[ADM.viewingPhotoIdx];
      body += '<div class="lightbox" id="photoViewerOverlay">'+
        '<button type="button" class="lb-close" id="photoViewerClose" aria-label="'+t("cancel")+'">✕</button>'+
        '<img class="lb-img" src="'+vp.url+'" alt="">'+
        '<div style="position:absolute;bottom:60px;display:flex;gap:10px">'+
         '<a class="btn-n" href="'+vp.url+'" download target="_blank" rel="noopener">'+t("saveToDevice")+'</a>'+
         '<button type="button" class="ab bad" id="photoViewerDelete">'+t("del")+'</button>'+
        '</div></div>';
    }
  } else {
    // "in use" is only a meaningful concept for ads (a photo can
    // still be attached to a live ad slot) — banners/background just
    // hold whatever the current setting points at, computed the same
    // way, so a stray older upload doesn't get wrongly protected.
    // Ad squares also get a slot-number label when one is attached.
    var usedUrls = ((ADM.mediaUsed||{})[mediaCat]||[]).slice(), slotByUrl = {};
    if(mediaCat==="ads"){
      (ADM.adSlots||[]).forEach(function(a){
        if(a.image_url){ usedUrls.push(a.image_url); slotByUrl[a.image_url]=a.position||a.id }
        if(a.image_urls) a.image_urls.forEach(function(u){ usedUrls.push(u); slotByUrl[u]=a.position||a.id });
      });
    } else if(mediaCat==="banners"){
      bannersConfig().forEach(function(cfg,bi){ (cfg.items||[]).forEach(function(it){ if(it.url){ usedUrls.push(it.url); slotByUrl[it.url]=bi+1 } }) });
    } else if(mediaCat==="background"){
      if(SITE.hero_bg_video_url) usedUrls.push(SITE.hero_bg_video_url);
      if(SITE.hero_bg_photo_url) usedUrls.push(SITE.hero_bg_photo_url);
    }
    var files = (ADM.mediaFiles&&ADM.mediaFiles[mediaCat])||[];
    var otherItems = files.map(function(f){
      var used = usedUrls.indexOf(f.publicUrl)>-1;
      return {thumbUrl:f.publicUrl, isVideo:f.isVideo, uploadedAt:f.uploadedAt, isUsed:used,
        label: mediaCat==="ads" && slotByUrl[f.publicUrl]!=null ? "#"+slotByUrl[f.publicUrl] : "",
        deletePath: f.path};
    });
    body += renderMediaSection(otherItems, {searchPh: mediaCat==="ads" ? t("searchByAdNo") : t("searchFiles"),
      emptyMsg:t("adStorageEmpty"), thumbSize:110, loading:ADM._mediaLoading===mediaCat});
  }
 }

 else if(ADM.tab==="ads"){ body = hsStudioHtml("ads"); }

 else if(ADM.tab==="engage"){ body = adminEngageBody(); }
 else if(ADM.tab==="campaigns"){ body = adminCampaignsBody(); }
 else if(ADM.tab==="intake"){ body = adminIntakeBody(); }
 else if(ADM.tab==="agencies_adm"){ body = adminAgenciesBody(); }
 else if(ADM.tab==="projects_adm"){ body = adminProjectsBody(); }
 else if(ADM.tab==="wanted_adm"){ body = adminWantedBody(); }
 else if(ADM.tab==="featured"){
  var flist = ADM.featuredList||[];
  var now = new Date();
  body = '<div class="blk"><h3>'+t("featureNewH")+'</h3><div class="in">'+
   '<div class="fl"><label>'+t("adPickListingL")+'</label>'+
    '<div class="chipsel"><div class="chipsel-box">'+
     '<input class="chipsel-input" id="ftListingSearch" autocomplete="off" placeholder="'+t("adSearchListingPH")+'">'+
    '</div><div class="chipsel-drop" id="ftListingDrop"></div></div>'+
    '<input type="hidden" id="ftListing" value="">'+
   '</div>'+
   '<div class="row">'+
    '<div class="fl"><label>'+t("featureStartL")+'</label><input type="date" id="ftFrom" value="'+now.toISOString().slice(0,10)+'"></div>'+
    '<div class="fl"><label>'+t("featureDaysL")+'</label><input type="number" id="ftDays" min="1" value="7"></div>'+
   '</div>'+
   '<button class="ab ok" id="ftSave">'+t("featureBtn")+'</button>'+
   '<span id="ftMsg" style="font-size:12.5px;color:var(--danger);margin-inline-start:8px"></span>'+
   (ADM._featCode?'<div class="ecodebox">'+GX("engCodeIs")+' <b class="ltr" data-ecopy="'+escOnce(ADM._featCode)+'">'+escOnce(ADM._featCode)+'</b> <button type="button" class="ab" data-ecopy="'+escOnce(ADM._featCode)+'">'+GX("engCopy")+'</button></div>':'')+
  '</div></div>'+
  '<div class="blk" style="margin-top:16px"><h3>'+t("featuredListH")+'</h3><div class="in">'+
   (flist.length ? '<div class="atable"><table><thead><tr><th>BK</th><th>'+t("postedBy")+'</th><th>'+t("featureStartL")+'</th><th>'+t("featureEndL")+'</th><th>'+t("status")+'</th><th></th></tr></thead><tbody>'+
     flist.map(function(f){
       var from=new Date(f.featured_from), until=new Date(f.featured_until);
       var isActive = now>=from && now<=until;
       var isExpired = now>until;
       var statusClass = isActive?"live":isExpired?"expired":"pending";
       var statusText = isActive?t("featureActiveNow"):isExpired?t("featureExpired"):t("featureScheduled");
       return '<tr><td class="ltr">'+scopeFlag(f.country_code)+(f.ref||f.id)+'</td><td>'+(f.poster_name||'—')+'</td>'+
        '<td class="ltr">'+from.toLocaleDateString()+'</td><td class="ltr">'+until.toLocaleDateString()+'</td>'+
        '<td><span class="st st-'+statusClass+'">'+statusText+'</span></td>'+
        '<td><button class="ab bad" data-unfeat="'+f.id+'">'+t("unfeature")+'</button></td></tr>'}).join("")+
     '</tbody></table></div>'
    : '<div class="done2"><b>'+t("noFeatured")+'</b></div>')+
  '</div></div>';
 }

 else if(ADM.tab==="danger"){
  body = '<div class="done2" style="margin-bottom:14px;text-align:start"><b>'+GX("dzScopeNote").replace("{c}", ADM.scope==="ALL"?GX("cAll"):esc(countryName(countryOf(COUNTRY)||{})))+'</b></div>'+
   '<div class="blk"><h3>'+t("backupH")+'</h3><div class="in">'+
   '<div class="hintx" style="margin-bottom:10px">'+t("backupHint")+'</div>'+
   '<button class="btn-n" id="dzBackupBtn">'+t("backupBtn")+'</button>'+
   '<span id="dzBackupMsg" style="font-size:12.5px;color:var(--ok);margin-inline-start:8px"></span>'+
  '</div></div>'+
  '<div class="blk dzblk" style="margin-top:16px"><h3 style="color:var(--danger)">'+t("restoreH")+'</h3><div class="in">'+
   '<div class="hintx" style="margin-bottom:14px">'+t("restoreHint")+'</div>'+
   (!ADM.restoreUnlocked ?
    '<button class="ab bad" id="dzRestoreUnlockBtn">'+t("restoreUnlockBtn")+'</button>'
    :
    '<div class="dzconfirm">'+
     '<div class="fl"><label>'+t("restoreFileL")+'</label><input type="file" id="dzRestoreFile" accept="application/json"></div>'+
     '<div class="hintx" id="dzRestorePreview" style="margin-bottom:8px">'+ADM.restoreFileInfo+'</div>'+
     '<div class="hintx" style="margin-bottom:8px;color:var(--danger)">'+t("dangerTypeHintRestore")+'</div>'+
     '<input id="dzRestoreConfirmText" placeholder="RESTORE FROM BACKUP" class="ltr" style="margin-bottom:10px">'+
     '<div style="display:flex;gap:10px">'+
      '<button class="ab bad" id="dzRestoreBtn" disabled>'+t("restoreBtn")+'</button>'+
      '<button class="ab" id="dzRestoreCancelBtn">'+t("cancel")+'</button>'+
     '</div>'+
     '<span id="dzRestoreMsg" style="font-size:12.5px;color:var(--danger);display:block;margin-top:8px"></span>'+
    '</div>')+
  '</div></div>'+
  '<div class="blk dzblk" style="margin-top:24px"><h3 style="color:var(--danger)">'+t("dangerH")+'</h3><div class="in">'+
   '<div class="hintx" style="margin-bottom:14px">'+t("dangerHint")+'</div>'+
   (!ADM.dangerUnlocked ?
    '<button class="ab bad" id="dzUnlockBtn">'+t("dangerUnlockBtn")+'</button>'
    :
    '<div class="dzconfirm" style="max-width:420px">'+
     '<button class="ab" id="dzCancelBtn" style="margin-bottom:16px">'+t("cancel")+'</button>'+

     '<div style="margin-bottom:20px"><b style="display:block;margin-bottom:6px;font-size:13.5px">'+t("dangerResetBtn")+'</b>'+
     '<div class="hintx" style="margin-bottom:8px;color:var(--danger)">'+t("dangerTypeHint")+'</div>'+
     '<input id="dzConfirmText" placeholder="DELETE ALL LISTINGS" class="ltr" style="margin-bottom:8px">'+
     '<button class="ab bad" id="dzResetBtn" disabled>'+t("dangerResetBtn")+'</button>'+
     '<span id="dzResetMsg" style="font-size:12.5px;color:var(--danger);display:block;margin-top:6px"></span></div>'+

     '<div style="margin-bottom:20px;padding-top:16px;border-top:1px solid var(--line)"><b style="display:block;margin-bottom:6px;font-size:13.5px">'+t("dangerAdsBtn")+'</b>'+
     '<div class="hintx" style="margin-bottom:8px;color:var(--danger)">'+t("dangerTypeHintAds")+'</div>'+
     '<input id="dzAdsConfirmText" placeholder="DELETE ALL AD SQUARES" class="ltr" style="margin-bottom:8px">'+
     '<button class="ab bad" id="dzAdsBtn" disabled>'+t("dangerAdsBtn")+'</button>'+
     '<span id="dzAdsMsg" style="font-size:12.5px;color:var(--danger);display:block;margin-top:6px"></span></div>'+

     '<div style="padding-top:16px;border-top:1px solid var(--line)"><b style="display:block;margin-bottom:6px;font-size:13.5px">'+t("dangerUsersBtn")+'</b>'+
     '<div class="hintx" style="margin-bottom:8px;color:var(--danger)">'+t("dangerTypeHintUsers")+'</div>'+
     '<input id="dzUsersConfirmText" placeholder="DELETE ALL USERS" class="ltr" style="margin-bottom:8px">'+
     '<button class="ab bad" id="dzUsersBtn" disabled>'+t("dangerUsersBtn")+'</button>'+
     '<span id="dzUsersMsg" style="font-size:12.5px;color:var(--danger);display:block;margin-top:6px"></span></div>'+
    '</div>')+
  '</div></div>';
 }

 else if(ADM.tab==="admins"){
  var admins = ADM.admins||[];
  var permKeys=["listings","featured","homepage","ads","campaigns","users","passwords","reports","feedback","reviews","msgs","stats","settings"];
  body = '<button class="btn-n" id="aNewAdminBtn" style="margin-bottom:14px">'+t("createAdmin")+'</button>'+
   (ADM.newAdminOpen ? '<div class="blk" style="margin-bottom:16px"><h3>'+t("createAdmin")+'</h3><div class="in">'+
     '<div class="row"><div class="fl"><label class="req">'+t("contactName")+'</label><input id="naName" autocomplete="off"></div>'+
     '<div class="fl"><label class="req">'+t("mobile")+'</label><div class="pw">'+ccSelect("naCC",phoneCC())+
      '<input id="naPhone" inputmode="numeric" autocomplete="off"></div></div></div>'+
     '<div class="fl"><label class="req">'+t("password")+'</label><input id="naPass" type="text" autocomplete="off" placeholder="'+t("min6")+'"></div>'+
     '<div class="fl"><label>'+t("permissionsL")+'</label><div class="chkgrid">'+
      permKeys.map(function(p){return '<label><input type="checkbox" class="naPerm" value="'+p+'"> '+t("perm_"+p)+'</label>'}).join("")+
     '</div></div>'+
     '<div class="fl"><label>'+GX("admCountriesL")+'</label><div class="hintx" style="margin-bottom:6px">'+GX("admCountriesHint")+'</div><div class="chkgrid">'+
      (ADM.countries||[]).map(function(c){return '<label><input type="checkbox" class="naCountry" value="'+esc(c.code)+'"> '+flagOf(c.code)+' '+esc(countryName(c))+'</label>'}).join("")+
     '</div></div>'+
     '<div style="display:flex;gap:10px;align-items:center;margin-top:6px">'+
     '<button class="ab ok" id="aNewAdminSave">'+t("save")+'</button>'+
     '<button class="ab" id="aNewAdminCancel">'+t("cancel")+'</button>'+
     '<span style="font-size:12.5px;color:var(--danger)">'+(ADM.newAdminMsg||"")+'</span></div>'+
    '</div></div>' : '')+
   '<div class="blk" style="margin-bottom:16px"><div class="in hintx" style="font-size:13px;line-height:1.8">'+GX("tmHowPair")+'</div></div>'+
   (!admins.length ? '<div class="done2"><b>'+(ADM._adminsErr?esc(ADM._adminsErr):ADM._adminsDone?GX("noAdminsYet"):t("loading"))+'</b></div>' :
   '<div class="tmlist">'+admins.map(function(a){
      var nm=((a.name||"")+" "+(a.family_name||"")).trim(), editing=ADM.editPermsFor===a.id, groups=[["tmGroupContent",["listings","featured","homepage","ads","campaigns"]],["tmGroupPeople",["users","passwords","reviews"]],["tmGroupInbox",["reports","feedback","msgs"]],["tmGroupSystem",["stats","settings"]]];
      var perms=a.is_super_admin?'<span class="chip gold">'+t("allPermissions")+'</span>':((a.permissions||[]).length?a.permissions.map(function(p){ return '<span class="chip">'+t("perm_"+p)+'</span>' }).join(""):'<span class="chip muted">—</span>');
      var countries=(a.admin_countries&&a.admin_countries.length)?a.admin_countries.map(function(cc){ return '<span class="chip">'+flagOf(cc)+' '+esc(countryName(countryOf(cc)||{code:cc})||cc)+'</span>' }).join(""):'<span class="chip gold">'+GX("tmAllCountries")+'</span>';
      var card='<div class="tmcard'+(editing?' open':'')+'">'+
        '<div class="tmid"><span class="ava2 big">'+esc((a.name||"?").charAt(0))+'</span><div><b>'+esc(nm)+'</b>'+(a.is_super_admin?' <span class="lvl lvl-vip">'+t("superAdmin")+'</span>':'')+
          '<div class="usub"><span class="ltr">'+esc(a.member_no||"")+'</span> · <span class="ltr">'+esc(a.phone||"")+'</span>'+(a.last_seen_at?' · '+GX("tmLastSeen")+' '+when(a.last_seen_at):'')+'</div></div></div>'+
        '<div class="tmcol"><small>'+GX("admCountriesL")+'</small><div class="chips">'+countries+'</div></div>'+
        '<div class="tmcol"><small>'+t("permissionsL")+'</small><div class="chips">'+perms+'</div></div>'+
        '<div class="tmcol"><small>Telegram</small>'+(a.tg_paired?'<span class="st st-live">✓ '+GX("tmPaired")+(a.tg_name?' · '+esc(a.tg_name):'')+'</span>':'<span class="st st-removed">'+GX("tmNotPaired")+'</span>')+
          '<label class="xswitch" title="'+esc(GX("tmAlerts"))+'" style="margin-top:6px"><input type="checkbox" data-tmnotify="'+a.id+'"'+(a.notify_tg!==false?' checked':'')+(a.is_super_admin&&a.id!==ADM.meId?' disabled':'')+'><i></i></label><small style="display:block">'+GX("tmAlerts")+(a.recovery_left?' · '+GX("admMeRecLeft").replace("{n}",a.recovery_left):'')+'</small></div>'+
        '<div class="tmacts">'+(a.is_super_admin?'':'<button class="ab" data-editperms="'+a.id+'">'+t("edit")+'</button>'+(can("passwords")?'<button class="ab" data-tmpw="'+a.id+'">'+t("resetPass")+'</button>':''))+
          (a.tg_paired?'<button class="ab" data-tmunpair="'+a.id+'">'+GX("tmUnpair")+'</button>':'')+(a.is_super_admin?'':'<button class="ab bad" data-removeadmin="'+a.id+'">'+t("removeAdmin")+'</button>')+'</div>'+
        (editing?'<div class="tmedit"><b>'+t("permissionsL")+'</b>'+groups.map(function(g){ return '<div class="tmgroup"><small>'+GX(g[0])+'</small><div class="chkgrid">'+g[1].map(function(p){ return '<label class="xcheck"><input type="checkbox" class="editPerm" value="'+p+'"'+((a.permissions||[]).indexOf(p)>-1?" checked":"")+'><span>'+t("perm_"+p)+'</span></label>' }).join("")+'</div></div>' }).join("")+
          '<b style="display:block;margin-top:12px">'+GX("admCountriesL")+'</b><div class="hintx">'+GX("admCountriesHint")+'</div><div class="chkgrid" style="margin-top:6px">'+(ADM.countries||[]).map(function(c){ return '<label class="xcheck"><input type="checkbox" class="editCountry" value="'+esc(c.code)+'"'+((a.admin_countries||[]).indexOf(c.code)>-1?" checked":"")+'><span>'+flagOf(c.code)+' '+esc(countryName(c))+'</span></label>' }).join("")+'</div>'+
          '<div class="xactions"><button class="ab ok" data-saveperms="'+a.id+'">'+t("save")+'</button><button class="ab" id="aEditPermsCancel">'+t("cancel")+'</button></div></div>':'')+
        '</div>';
      return card }).join("")+'</div>');
 }
 if(false){ body=(0,'<div class="atable"><table><thead><tr>'+
    [t("contactName"),t("mobile"),t("permissionsL"),GX("admCountriesL"),''].map(function(h){return '<th>'+h+'</th>'}).join("")+
    '</tr></thead><tbody>'+
    admins.map(function(a){
      var nm=((a.name||"")+" "+(a.family_name||"")).trim();
      var editing = ADM.editPermsFor===a.id;
      var rows='<tr><td>'+nm+(a.is_super_admin?' <span class="lvl lvl-vip">'+t("superAdmin")+'</span>':'')+'</td>'+
        '<td class="ltr">'+a.phone+'</td>'+
        '<td>'+(a.is_super_admin?t("allPermissions"):(a.permissions&&a.permissions.length?a.permissions.map(function(p){return t("perm_"+p)}).join(", "):"—"))+'</td>'+
        '<td>'+(a.admin_countries&&a.admin_countries.length?a.admin_countries.map(function(cc){ return flagOf(cc)+' '+esc(cc) }).join(" · "):GX("cAll"))+'</td>'+
        '<td style="white-space:nowrap">'+
         (a.is_super_admin?"":'<button class="ab" data-editperms="'+a.id+'">'+t("edit")+'</button>'+
          '<button class="ab bad" data-removeadmin="'+a.id+'">'+t("removeAdmin")+'</button>')+
        '</td></tr>';
      if(editing){
        rows += '<tr><td colspan="5" style="background:var(--page)"><div style="padding:14px 10px">'+
         '<b style="font-size:13.5px">'+t("permissionsL")+' — '+nm+'</b>'+
         '<div class="chkgrid" style="margin-top:8px">'+
          permKeys.map(function(p){return '<label><input type="checkbox" class="editPerm" value="'+p+'"'+
            ((a.permissions||[]).indexOf(p)>-1?" checked":"")+'> '+t("perm_"+p)+'</label>'}).join("")+
         '</div>'+
         '<b style="font-size:13.5px;display:block;margin-top:12px">'+GX("admCountriesL")+'</b><div class="hintx">'+GX("admCountriesHint")+'</div>'+
         '<div class="chkgrid" style="margin-top:6px">'+(ADM.countries||[]).map(function(c){return '<label><input type="checkbox" class="editCountry" value="'+esc(c.code)+'"'+((a.admin_countries||[]).indexOf(c.code)>-1?" checked":"")+'> '+flagOf(c.code)+' '+esc(countryName(c))+'</label>'}).join("")+'</div>'+
         '<div style="display:flex;gap:10px;align-items:center;margin-top:8px">'+
         '<button class="ab ok" data-saveperms="'+a.id+'">'+t("save")+'</button>'+
         '<button class="ab" id="aEditPermsCancel">'+t("cancel")+'</button></div>'+
        '</div></td></tr>';
      }
      return rows}).join("")+'</tbody></table></div>');
 }

 var sec=function(label,items,key,hasActive){ if(!items.some(Boolean)) return ''; var folded=!!ADM_FOLDS[key] && !hasActive;
   return '<div class="asidebar-group'+(folded?' folded':'')+'" data-gkey="'+key+'"><button type="button" class="asidebar-label" aria-expanded="'+(folded?'false':'true')+'">'+label+'<span class="asidebar-chev" aria-hidden="true">›</span></button>'+
   '<div class="asidebar-items">'+items.join("")+'</div></div>' };

 var NAV=[
   {g:t("navOverview"), items:[["dashboard",t("dashboardTab"),null,AICO.dash,true],["stats",t("visitorStats"),null,AICO.chart,can("stats")]]},
   {g:GX("navCountries"), items:[["countries",GX("countriesTab"),null,AICO.globe,ADM.isSuper]]},
   {g:GX("navListings"), items:[["listings",t("listingsTab"),s.listings,AICO.listings,can("listings")],["photos",GX("tMedia"),null,AICO.image,can("listings")],["wanted_adm",GX("tWanted"),(ADM.todo||{}).pending_wanted||null,AICO.search,can("listings")],["intake",GX("tIntake"),(ADM.todo||{}).intake_review||null,AICO.contact||AICO.bell,can("listings")]]},
   {g:t("navPeople"), items:[["users",t("usersTab"),(ADM.todo||{}).verify_pending||s.users,AICO.users,can("users")],["agencies_adm",GX("tAgencies"),null,AICO.building,can("users")||can("listings")],["reviews",t("reviewsTab"),s.reviews,AICO.shield,can("reviews")]]},
   {g:GX("navMarketing"), items:[["engage",GX("tEngage"),null,AICO.ledger,can("ads")||can("featured")],["projects_adm",GX("tProjects"),null,AICO.building,can("listings")||can("ads")],["ads",t("adsTab"),null,AICO.ads,can("ads")],["featured",t("featuredTab"),null,AICO.star,can("featured")],["banners",GX("tBanners"),null,AICO.banner,can("homepage")],["campaigns",GX("tCampaigns"),null,AICO.megaphone,can("campaigns")]]},
   {g:GX("navWebsite"), items:[["mainpage",t("mainPageTab"),null,AICO.home2,can("homepage")],["design",GX("tDesign"),null,AICO.palette,can("settings")],["geo",GX("geoTab"),null,AICO.map,can("settings")],["contact",GX("tContact"),null,AICO.contact,can("settings")]]},
   {g:t("navInboxH"), items:[["reports",t("reportsTab"),s.openReports,AICO.shield,can("reports")],["feedback",t("feedbackTab"),s.openFeedback,AICO.shield,can("feedback")],["tickets",GX("ticketsTab"),(ADM.tickets||[]).filter(function(x){ return x.status!=="done" }).length,AICO.gear,can("feedback")],["msgs",t("msgsNotifTab"),ADM.alertsUnread,AICO.bell,can("msgs")]]},
   {g:GX("navSystem"), items:[["settings",GX("tSystem"),null,AICO.gear,can("settings")],["storage",GX("tStorage"),null,AICO.disk,can("settings")],["admins",t("adminsTab"),null,AICO.key,ADM.isSuper],["danger",t("dangerTab"),null,AICO.lock,ADM.isSuper]]}
 ];
 NAV.forEach(function(g){ g.items.forEach(function(it){ it[4]=canTab(it[0]) }) });   // the sidebar follows the same permission map as every other way into a tab
 var curLabel=t("adminPanel"), curGroup="";
 NAV.forEach(function(g){ g.items.forEach(function(it){ if(it[0]===ADM.tab){ curLabel=it[1]; curGroup=g.g } }) });
 var initial=((ADM.meName||"?").trim().charAt(0)||"?");
 return '<div class="adm">'+
  '<header class="adm-top">'+
   '<button class="adm-burger" id="aSidebarToggle" aria-label="'+t("menu")+'">≡</button>'+
   '<div class="adm-brand"><span class="adm-logo">'+CONFIG.brand+'</span><span class="adm-sub">'+t("adminPanel")+'</span></div>'+
   '<label class="adm-q">'+AICO.search+'<input id="aNavQ" placeholder="'+GX("aNavSearch")+'" autocomplete="off"></label>'+
   '<div class="adm-actions">'+
    adminCountrySelHtml()+'<select class="adm-lang" id="aLang" aria-label="'+GX("aLang")+'">'+["ar","en","de"].map(function(k){ return '<option value="'+k+'"'+(k===L?' selected':'')+'>'+D.I18N[k].name+'</option>' }).join("")+'</select>'+
    adminBellHtml()+
    '<button class="ab" id="adViewSite" title="'+t("viewSiteAsUser")+'">'+AICO.eye+'<span>'+t("viewSiteAsUser")+'</span></button>'+
    '<button class="ab" id="adRefresh" title="'+t("refresh")+'">'+AICO.refresh+'</button>'+
    '<button class="adm-me" id="aMyAccount" title="'+t("myAdminAccount")+'"><span class="ava2">'+initial+'</span><span class="adm-me-n">'+(ADM.meName||"")+'</span>'+(ADM.isSuper?'<i class="adm-super">'+t("superAdmin")+'</i>':'')+'</button>'+
    '<button class="ab" id="adOut" title="'+t("logout")+'">'+AICO.out+'<span>'+t("logout")+'</span></button>'+
   '</div></header>'+
  (ADM.myAccountOpen ? adminMeCard() : '')+
  '<div class="ashell">'+
   '<nav class="asidebar" id="aSidebar">'+NAV.map(function(g){ return sec(g.g, g.items.map(function(it){ return it[4] ? tab(it[0],it[1],it[2],it[3]) : "" }), g.items[0][0], g.items.some(function(it){ return it[0]===ADM.tab })) }).join("")+'</nav>'+
   '<main class="acontent">'+(ADM.token&&!ADM.data?'<div class="aloading">'+t("loading")+'</div>':'')+'<div class="apage-h"><div>'+'<div class="apage-crumb">'+curGroup+(ADM.scope==="ALL"?(curGroup?' · ':'')+'🌍 '+GX("cAll")+'</div>':COUNTRY!=="SY"?(curGroup?' · ':'')+flagOf(COUNTRY)+' '+esc(countryName(countryOf(COUNTRY)))+'</div>':'</div>')+'<h1>'+curLabel+'</h1>'+
    (GX_T["desc_"+ADM.tab]?'<p>'+GX("desc_"+ADM.tab)+'</p>':'')+'</div></div>'+adminCountryBar()+body+'</main>'+
  '</div></div>'}
function adminWantedBody(){
  var list=ADM_W; if(!list) return '<div class="blk"><div class="in adashempty">'+t("loading")+'</div></div>';
  if(!list.length) return '<div class="blk"><div class="in adashempty">'+GX("wNone")+'</div></div>';
  var pend=list.filter(function(w){ return w.status==="pending" }).length;
  return '<div class="blk"><h3>'+GX("tWanted")+(pend?' <span class="n">'+pend+'</span>':'')+'</h3><div class="in eng-in"><div class="elist">'+list.map(function(w){
    return '<div class="erow wrow"><div class="pjtitle">'+avatar(w.user_avatar,w.user_name,40,"aglogo")+'<div><b>'+scopeFlag(w.country_code)+wTitle(w)+'</b><small>'+esc(w.user_name||"")+' · <span class="ltr">'+esc(w.user_phone||"")+'</span></small></div></div>'+
      '<div class="ewho">'+(w.deal==="rent"?GX("wRent"):GX("wBuy"))+' · '+(w.gov_name?gN(w.gov_name):GX("wAnywhere"))+'<small>'+(w.area_names||[]).map(aN).join("، ")+'</small></div>'+
      '<div class="eclient">'+wBudgetText(w)+'<small>'+[wTypeName(w.property_type),w.rooms_min?GX("wRoomsN").replace("{n}",w.rooms_min):""].filter(Boolean).join(" · ")+'</small></div>'+
      '<div class="eperiod"><span class="ltr">'+String(w.created_at||"").slice(0,10)+'</span><small>'+GX("wViews").replace("{n}",'<span class="ltr">'+(w.views||0)+'</span>')+'</small></div>'+
      '<div class="est">'+wStatusPill(w.status,w.expired)+(w.featured?' <span class="vbadge">★</span>':'')+'</div>'+
      '<div class="eacts">'+(w.status!=="open"?'<button type="button" class="ab ok" data-wadm="'+w.id+':open">'+(w.status==="pending"?GX("agApprove"):GX("wOpenBtn"))+'</button>':'')+(w.status==="open"?'<button type="button" class="ab" data-wadm="'+w.id+':hidden">'+GX("agHide")+'</button>':'')+
        (w.status==="pending"?'<button type="button" class="ab bad" data-wadm="'+w.id+':rejected">'+GX("agReject")+'</button>':'')+'<button type="button" class="ab" data-wfeat="'+w.id+':'+(w.featured?"0":"1")+'">'+(w.featured?GX("wUnfeature"):GX("wFeature"))+'</button>'+
        (w.status==="open"?'<a class="ab" href="/wanted/'+w.id+'" target="_blank" rel="noopener">'+GX("agView")+'</a>':'')+'<button type="button" class="ab bad" data-wadel="'+w.id+'">'+t("del")+'</button></div></div>' }).join("")+'</div></div></div>' }
function adminProjectsBody(){
  var list=ADM_PJ, ed=ADM.pjEdit;
  var editor = ed ? adminProjectEditor(ed) : '';
  var rows = !list ? '<div class="adashempty">'+t("loading")+'</div>' : !list.length ? '<div class="adashempty">'+GX("pjEmpty")+'</div>' :
    '<div class="elist">'+list.map(function(p){ var ph=(p.photos&&p.photos[0])||null; return '<div class="erow pjrow"><div class="pjtitle">'+(ph?'<img class="aglogo" src="'+esc(ph)+'" alt="">':'<span class="aglogo">'+AICO.building+'</span>')+'<div><b>'+scopeFlag(p.country_code)+esc(p.name)+'</b><small class="usub">'+esc(p.developer_name||"")+'</small></div></div>'+
      '<div class="ewho">'+[p.area_name?aN(p.area_name):"",p.gov_name?gN(p.gov_name):""].filter(Boolean).join("، ")+'<small>'+pjSt(p.status)+(p.delivery?' · '+esc(p.delivery):'')+'</small></div>'+
      '<div class="eclient">'+(p.price_from?'<span class="ltr">'+pjFmt(p.price_from)+'</span>':'—')+'<small>'+(Array.isArray(p.units)?p.units.length:0)+' '+GX("pjUnits")+'</small></div>'+
      '<div class="eperiod"><span class="ltr">'+(p.leads||0)+'</span> '+GX("pjLeads")+(p.new_leads?' <b class="mdw-badge" style="display:inline-grid">'+p.new_leads+'</b>':'')+'</div>'+
      '<div class="est"><span class="st st-'+(p.published?"live":"pending")+'">'+(p.published?GX("pjPublished"):GX("pjDraft"))+'</span>'+(p.featured?' <span class="vbadge">★</span>':'')+'</div>'+
      '<div class="eacts"><button type="button" class="ab" data-pjedit="'+p.id+'">'+t("edit")+'</button>'+(p.published?'<a class="ab" href="/project/'+p.id+'" target="_blank" rel="noopener">'+GX("agView")+'</a>':'')+'<button type="button" class="ab bad" data-pjdel="'+p.id+'">'+t("del")+'</button></div></div>' }).join("")+'</div>';
  var leads = ADM_PJL===null ? '' : '<div class="blk" style="margin-top:16px"><h3>'+GX("pjLeads")+(ADM_PJL.filter(function(l){ return !l.handled }).length?' <span class="n">'+ADM_PJL.filter(function(l){ return !l.handled }).length+'</span>':'')+'</h3><div class="in eng-in">'+
    (ADM_PJL.length?'<div class="elist">'+ADM_PJL.map(function(l){ return '<div class="erow pjlrow'+(l.handled?' done':'')+'"><div class="ewho"><b>'+esc(l.project_name||"")+'</b><small>'+esc(l.unit||"")+(l.plan?' · '+esc(l.plan):'')+'</small></div><div class="eclient">'+esc(l.name||"—")+'<small class="ltr">'+esc(l.phone||"")+'</small></div><div class="ewho"><small>'+esc(l.note||"")+'</small></div><div class="eperiod"><span class="ltr">'+String(l.created_at||"").slice(0,16).replace("T"," ")+'</span></div><div class="est"><span class="st st-'+(l.handled?"expired":"live")+'">'+(l.handled?GX("pjHandled"):GX("pjUnhandled"))+'</span></div><div class="eacts">'+(l.phone?'<a class="ab" href="https://wa.me/'+esc(l.phone.replace(/\D/g,""))+'" target="_blank" rel="noopener">WhatsApp</a>':'')+'<button type="button" class="ab" data-pjlead="'+l.id+':'+(l.handled?"0":"1")+'">'+(l.handled?GX("pjUnhandled"):GX("pjHandled"))+'</button></div></div>' }).join("")+'</div>':'<div class="adashempty">'+GX("pjNoLeads")+'</div>')+'</div></div>';
  return '<div class="dash-top"><button type="button" class="ab ok" id="pjNewBtn">'+GX("pjNew")+'</button></div>'+editor+'<div class="blk" style="margin-top:16px"><h3>'+GX("tProjects")+(list?' <span class="n">'+list.length+'</span>':'')+'</h3><div class="in eng-in">'+rows+'</div></div>'+leads;
}
function adminProjectEditor(p){
  var govs=Object.keys(D.GEO), areas=p.gov_name&&D.GEO[p.gov_name]?D.GEO[p.gov_name]:[];
  var f=function(label,key,type,attrs){ return '<div class="fl"><label>'+label+'</label><input data-allow-autofill data-pj="'+key+'" type="'+(type||"text")+'" value="'+escOnce(String(p[key]==null?"":p[key]))+'"'+(attrs||"")+'></div>' };
  var units=Array.isArray(p.units)?p.units:[], plans=Array.isArray(p.plans)?p.plans:[];
  return '<div class="blk" id="pjEditor" style="margin-top:16px"><h3>'+GX("pjEditT")+(p.id?' <small class="ltr" style="color:var(--light)">#'+p.id+'</small>':'')+'</h3><div class="in">'+
    '<div class="row">'+f(GX("pjName")+" *","name")+f(GX("pjDevName"),"developer_name")+'</div>'+
    '<div class="row"><div class="fl"><label>'+GX("pjDevLink")+'</label><select data-pj="developer_user_id"><option value="">—</option>'+(ADM_AG||[]).filter(function(a){ return a.status==="approved" }).map(function(a){ return '<option value="'+a.user_id+'"'+(p.developer_user_id===a.user_id?' selected':'')+'>'+escOnce(a.name)+'</option>' }).join("")+'</select></div>'+
     '<div class="fl"><label>'+GX("engStatus")+'</label><select data-pj="status">'+PJ_STATUSES.map(function(k){ return '<option value="'+k+'"'+((p.status||"soon")===k?' selected':'')+'>'+pjSt(k)+'</option>' }).join("")+'</select></div></div>'+
    '<div class="row3x"><div class="fl"><label>'+t("gov")+'</label><select data-pj="gov_name"><option value="">—</option>'+govs.map(function(g){ return '<option value="'+escOnce(g)+'"'+(p.gov_name===g?' selected':'')+'>'+gN(g)+'</option>' }).join("")+'</select></div>'+
     '<div class="fl"><label>'+t("area")+'</label><select data-pj="area_name"><option value="">—</option>'+areas.map(function(a){ return '<option value="'+escOnce(a)+'"'+(p.area_name===a?' selected':'')+'>'+aN(a)+'</option>' }).join("")+'</select></div>'+f(GX("f_agAddress"),"address")+'</div>'+
    '<div class="row3x">'+f("Lat","lat","number",' step="any" class="ltr"')+f("Lng","lng","number",' step="any" class="ltr"')+f(GX("pjDelivery"),"delivery",'text',' placeholder="'+(L==="ar"?"مثال: الربع الأول 2027":"e.g. Q1 2027")+'"')+'</div>'+
    '<div class="fsub">'+GX("pjHeadPlan")+'</div>'+
    '<div class="row3x">'+f(GX("pjFrom")+" (USD)","price_from","number",' min="0" class="ltr"')+f(GX("pjDown")+" ٪","down_pct","number",' min="0" max="100" class="ltr"')+f(GX("pjMonths").replace("{n}","").trim(),"months","number",' min="0" class="ltr"')+f(GX("pjHandover")+" ٪","handover_pct","number",' min="0" max="100" class="ltr"')+'</div>'+
    '<div class="fl"><label>'+GX("pjAbout")+'</label><textarea data-pj="description" data-allow-autofill>'+escOnce(p.description||"")+'</textarea></div>'+
    '<div class="fsub">'+GX("pjPhotos")+'</div>'+
    '<div class="hs-thumbs">'+(p.photos||[]).map(function(u,i){ return '<span class="pjthumb"><img src="'+escOnce(u)+'" alt=""><button type="button" data-pjrm="'+i+'">×</button></span>' }).join("")+'</div>'+
    '<div class="fl"><div class="hs-up"><input type="file" accept="image/*" multiple id="pjPhotoUp"></div><div class="hintx" id="pjUpMsg"></div></div>'+
    '<div class="fsub">'+GX("pjUnits")+'</div>'+
    '<div class="pjtbl"><div class="pjtr h"><span>'+GX("pjUnitType")+'</span><span>'+GX("pjArea")+'</span><span>'+GX("pjRooms")+'</span><span>'+GX("pjPrice")+' USD</span><span>'+GX("pjCount")+'</span><span></span></div>'+
     units.map(function(u,i){ return '<div class="pjtr"><input data-allow-autofill data-pju="'+i+':type" value="'+escOnce(u.type||"")+'"><input data-allow-autofill data-pju="'+i+':area_m2" type="number" class="ltr" value="'+escOnce(String(u.area_m2||""))+'"><input data-allow-autofill data-pju="'+i+':rooms" type="number" class="ltr" value="'+escOnce(String(u.rooms||""))+'"><input data-allow-autofill data-pju="'+i+':price_usd" type="number" class="ltr" value="'+escOnce(String(u.price_usd||""))+'"><input data-allow-autofill data-pju="'+i+':count" type="number" class="ltr" value="'+escOnce(String(u.count||""))+'"><button type="button" class="ab" data-pjurm="'+i+'">×</button></div>' }).join("")+
     '<button type="button" class="ab" id="pjAddUnit">'+GX("pjAddUnit")+'</button></div>'+
    '<div class="fsub">'+GX("pjPlan")+'</div>'+
    '<div class="pjtbl plans"><div class="pjtr h"><span>'+GX("pjPlanName")+'</span><span>'+GX("pjDown")+' ٪</span><span>'+GX("pjMonths").replace("{n}","").trim()+'</span><span>'+GX("pjHandover")+' ٪</span><span></span></div>'+
     plans.map(function(u,i){ return '<div class="pjtr"><input data-allow-autofill data-pjp="'+i+':name" value="'+escOnce(u.name||"")+'"><input data-allow-autofill data-pjp="'+i+':down_pct" type="number" class="ltr" value="'+escOnce(String(u.down_pct||""))+'"><input data-allow-autofill data-pjp="'+i+':months" type="number" class="ltr" value="'+escOnce(String(u.months||""))+'"><input data-allow-autofill data-pjp="'+i+':handover_pct" type="number" class="ltr" value="'+escOnce(String(u.handover_pct||""))+'"><button type="button" class="ab" data-pjprm="'+i+'">×</button></div>' }).join("")+
     '<button type="button" class="ab" id="pjAddPlan">'+GX("pjAddPlan")+'</button></div>'+
    '<div class="row"><label class="xcheck"><input type="checkbox" data-pj="published" data-pjbool="1"'+(p.published?' checked':'')+'><span>'+GX("pjPublished")+'</span></label><label class="xcheck"><input type="checkbox" data-pj="featured" data-pjbool="1"'+(p.featured?' checked':'')+'><span>'+GX("pjFeatured")+'</span></label></div>'+
    '<div class="xactions"><button class="ab ok" id="pjSave">'+t("save")+'</button><button class="ab" id="pjCancel">'+t("cancel")+'</button><span class="xmsg" id="pjMsg"></span></div>'+
   '</div></div>' }
function adminAgenciesBody(){
  var list=ADM_AG; if(!list) return '<div class="blk"><div class="in adashempty">'+t("loading")+'</div></div>';
  if(!list.length) return '<div class="blk"><div class="in adashempty">'+(ADM.agErr?'<span style="color:var(--danger)">'+esc(ADM.agErr)+'</span>':GX("agNone"))+'</div></div>';
  var pend=list.filter(function(a){ return a.status==="pending" }).length, sep=L==="ar"?"، ":", ";
  // one card per agency: identity | coverage and numbers | status + actions, and a second line for message intake
  return '<div class="blk"><h3>'+GX("tAgencies")+(pend?' <span class="n">'+pend+'</span>':'')+'</h3><div class="in eng-in"><div class="elist">'+list.map(function(a){
    var meta=[(a.gov_names||[]).map(gN).join(sep)||"—", (a.specialties||[]).map(agSpecLabel).join(" · "), ((a.area_names||[]).length?a.area_names.length+' '+GX("f_agAreas"):'')].filter(Boolean);
    return '<div class="agcard2">'+
      '<div class="agc-id">'+avatar(a.logo_url,a.name,44,"aglogo")+'<div><b>'+scopeFlag(a.country_code)+esc(a.name)+(a.verified?' <span class="vbadge">✓</span>':'')+'</b><small>'+esc(a.user_name||"")+(a.user_phone?' · <span class="ltr">'+esc(a.user_phone)+'</span>':'')+'</small></div></div>'+
      '<div class="agc-meta"><span>'+meta.join(' <i>·</i> ')+'</span><small><span class="ltr">'+(a.live||0)+'</span> '+t("liveAds")+' · '+GX("agSinceDate")+' <span class="ltr">'+String(a.created_at||"").slice(0,10)+'</span></small></div>'+
      '<div class="agc-acts">'+agStatusPill(a.status)+
        (a.status!=="approved"?'<button type="button" class="ab ok" data-agset="'+a.id+':approved">'+GX("agApprove")+'</button>':'')+
        (a.status==="pending"?'<button type="button" class="ab bad" data-agset="'+a.id+':rejected">'+GX("agReject")+'</button>':'')+
        (a.status==="approved"?'<button type="button" class="ab" data-agset="'+a.id+':hidden">'+GX("agHide")+'</button>':'')+
        '<button type="button" class="ab" data-agver="'+a.id+':'+(a.verified?"0":"1")+'">'+(a.verified?GX("agUnverify"):GX("agVerify"))+'</button>'+
        (a.status==="approved"?'<a class="ab" href="/agency/'+a.id+'" target="_blank" rel="noopener">'+GX("agView")+'</a>':'')+'</div>'+
      (a.status==="approved"?'<div class="agintk"><b>'+GX("tIntake")+'</b>'+
        '<button type="button" class="ab'+(a.intake_enabled?' on':'')+'" data-agintake="'+a.id+':'+(a.intake_enabled?"0":"1")+'">'+(a.intake_enabled?GX("agIntakeOn"):GX("agIntakeOff"))+'</button>'+
        (a.intake_enabled?'<button type="button" class="ab'+(a.intake_trusted?' on':'')+'" data-agtrust="'+a.id+':'+(a.intake_trusted?"0":"1")+'">'+(a.intake_trusted?GX("agTrustOn"):GX("agTrustOff"))+'</button>'+
          (a.intake_telegram?'<span class="st st-live">'+GX("agPairedTg")+(a.intake_telegram_name?' · '+esc(a.intake_telegram_name):'')+'</span>':'<span class="st st-pending">'+GX("agNotPaired")+'</span>')+
          (a.intake_code?'<small class="ltr">'+GX("agIntakeCode")+' <b>'+esc(a.intake_code)+'</b></small><button type="button" class="ab" data-agcode="'+a.id+'" title="'+esc(GX("agNewCodeHint"))+'">'+GX("agNewCode")+'</button>':''):'<small>'+GX("agIntakeHint")+'</small>')+'</div>':'')+
      '</div>' }).join("")+'</div></div></div>' }
async function adminLoad(){
  ADM._reviewsLoaded=false; ADM._cardLogosLoaded=false; ADM._storageReportLoaded=false; ADM._anLoaded=false; ADM._uactLoaded=false; ADM._lstatsLoaded=false; ADM._statsLoaded=false; ADM._settingsLoaded=false; ADM._alertsLoaded=false; ADM._adSlotsLoaded=false; ADM._featuredListLoaded=false;
  ADM._storageUsageLoaded=false;
  ["_adminsLoaded","_agLoaded","_geoLoaded","_ikLoaded","_meLoaded","_mediaUsedLoaded","_photosLoaded","_pjLoaded","_ticketsLoaded","_vfLoaded","_wLoaded"].forEach(function(k){ ADM[k]=false }); ADM._mediaLoadedCats={};   // every page re-fetches on refresh, not only the shared data
  ADM.dangerUnlocked=false;
  ADM.restoreUnlocked=false; ADM.restoreFileInfo=""; ADM.restoreData=null;
  try{
    var gen=ADM._gen||0, fresh=await rpc("bk_admin_data",{p_token:ADM.token,p_country:admScope()});
    if(gen!==(ADM._gen||0)) return;   // the admin switched country meanwhile; that load renders its own answer
    ADM.data = fresh; ADM.msg="";
    var me = ADM.data && ADM.data.me;
    if(me){
      ADM.meId=me.id; ADM.meName=((me.name||"")+" "+(me.family_name||"")).trim();
      ADM.perms=me.permissions||[]; ADM.isSuper=!!me.is_super_admin; ADM.myCountries=me.admin_countries||[];
      if(ADM.myCountries.length && ADM.myCountries.indexOf(COUNTRY)<0 && ADM.scope!=="ALL"){ var sc0=ADM.data.scope||ADM.myCountries[0]; admResetScope(); switchCountry(sc0,{keepView:true}) }   // the server answered for the first allowed country
      if(ADM.myCountries.length===1) ADM.scope=null;
    }
    if(!canTab(ADM.tab)){ ADM.tab = Object.keys(TAB_PERM).filter(canTab)[0] || "dashboard" }
    if(can("msgs")){
      rpc("bk_admin_notifications",{p_token:ADM.token}).then(function(r){
        if(r){ ADM.alerts=r.items||[]; ADM.alertsUnread=r.unread||0; ADM._alertsLoaded=true; render() }
      }).catch(function(){});
      startAdminAlertsPolling();
    }
    if(ADM.token){ syncAdminTodo();
    }
  }
  catch(e){ ADM.token=null; ADM.msg=e.message||"error"; try{localStorage.removeItem("balkoun_adm")}catch(x){} }
  render();
}
function GSX(k,d){ var g=(ADM.data&&ADM.data.gx)||{}; var v=g[k]; return (v===undefined||v===null||v==="") ? d : v }
function saveGlobalExtras(patch){ return rpc("bk_admin_set_content",{p_token:ADM.token,p_patch:{extras:patch},p_country:"SY"}).then(function(){ if(ADM.data){ ADM.data.gx=Object.assign({},ADM.data.gx||{},patch) } }) }
function adminMeCard(){
  var me=ADM.me;
  if(!me) return '<div class="adm-acct"><div class="blk"><div class="in adashempty">'+t("loading")+'</div></div></div>';
  var link="https://t.me/"+encodeURIComponent(me.bot||"")+"?start="+encodeURIComponent(String(me.tg_code||"").replace(/^ADM-/i,"adm-"));
  var countries=(me.admin_countries||[]).length?me.admin_countries.map(function(cc){ return flagOf(cc)+' '+esc(countryName(countryOf(cc)||{code:cc})||cc) }).join(" · "):GX("tmAllCountries");
  var codes=ADM.recCodes;
  return '<div class="adm-acct-ov" id="meOv"><div class="adm-acct adm-acct2">'+'<div class="meov-h"><b>'+GX("admMeT")+'</b><button type="button" class="ab" id="myPwCancel">✕</button></div>'+
   '<div class="blk"><h3>'+GX("admMeT")+'</h3><div class="in">'+
    '<div class="tmid"><span class="ava2 big">'+esc((me.name||"?").charAt(0))+'</span><div><b>'+esc(((me.name||"")+" "+(me.family_name||"")).trim())+'</b>'+(me.is_super_admin?' <span class="lvl lvl-vip">'+t("superAdmin")+'</span>':'')+
     '<div class="usub"><span class="ltr">'+esc(me.member_no||"")+'</span> · <span class="ltr">'+esc(me.phone||"")+'</span></div><div class="usub">'+countries+'</div></div></div>'+
   '</div></div>'+
   '<div class="blk"><h3>'+GX("admMeTgT")+'</h3><div class="in">'+
    (me.tg_paired ? '<div class="tmrow"><span class="st st-live">✓ '+GX("tmPaired")+(me.tg_name?' · '+esc(me.tg_name):'')+'</span><button type="button" class="ab" id="meTgUnpair">'+GX("tmUnpair")+'</button></div>'
                  : '<div class="hintx" style="margin-bottom:10px">'+GX("admMeTgHint")+'</div><div class="tmrow"><a class="ab ok" href="'+link+'" target="_blank" rel="noopener"'+(me.bot?'':' style="pointer-events:none;opacity:.5"')+'>'+GX("admMeTgLink")+'</a><b class="ltr" style="user-select:all">'+esc(me.tg_code||"")+'</b><button type="button" class="ab" id="meTgNew" title="'+esc(GX("agNewCodeHint"))+'">'+GX("agNewCode")+'</button></div>')+
    '<label class="xcheck" style="margin-top:12px"><input type="checkbox" id="meNotify"'+(me.notify_tg!==false?' checked':'')+'><span>'+GX("admMeAlerts")+'</span></label>'+
   '</div></div>'+
   '<div class="blk"><h3>'+t("changeMyPass")+'</h3><div class="in">'+
    '<div class="row"><div class="fl"><label>'+t("currentPass")+'</label><input id="myOldPass" type="password" autocomplete="off"></div>'+
    '<div class="fl"><label>'+t("newPass")+'</label><input id="myNewPass" type="password" autocomplete="off" placeholder="'+t("min6")+'"></div></div>'+
    '<div class="xactions"><button class="ab ok" id="myPwSave">'+t("savePass")+'</button><span class="xmsg">'+(ADM.myPwMsg||"")+'</span></div>'+
   '</div></div>'+
   '<div class="blk"><h3>'+GX("admMeRecT")+'</h3><div class="in">'+
    '<div class="hintx" style="margin-bottom:10px">'+GX("admMeRecHint")+'</div>'+
    (codes ? '<div class="reccodes">'+codes.map(function(c){ return '<span class="ltr">'+esc(c)+'</span>' }).join("")+'</div><div class="hintx" style="color:var(--danger);margin:8px 0">'+GX("admMeRecWarn")+'</div><div class="xactions"><button type="button" class="ab" data-ecopy="'+esc(codes.join("\n"))+'">'+GX("engCopy")+'</button><button type="button" class="ab" id="meRecHide">'+GX("admMeRecHide")+'</button></div>'
           : '<div class="tmrow"><span>'+(me.recovery_left?GX("admMeRecLeft").replace("{n}",me.recovery_left):GX("admMeRecNone"))+'</span><button type="button" class="ab '+(me.recovery_left?'':'ok')+'" id="meRecGen">'+(me.recovery_left?GX("admMeRecRegen"):GX("admMeRecGen"))+'</button></div>')+
   '</div></div>'+
  '</div></div>' }
function wireAdmin(){
  var doAdminLogin=async function(){
    var btn=$("#adGo"); if(!btn) return;
    var ph="+"+$("#adCC").value+($("#adPhone").value||"").replace(/\D/g,"");
    var pw=$("#adPass").value||"";
    btn.disabled=true; btn.textContent=t("saving");
    try{
      var r=await rpc("bk_admin_login",{p_phone:ph,p_hash:await sha(pw)});
      ADM.token=r.token; try{localStorage.setItem("balkoun_adm",r.token)}catch(x){}
      await adminLoad();
    }catch(e){ btn.disabled=false; btn.textContent=t("login");
      ADM.msg = e.message==="notadmin"?t("notAdmin"):e.message==="badpass"?t("wrongPass"):e.message==="locked"?GX("loginLocked"):e.message;
      render() }
  };
  if($("#adGo")) $("#adGo").onclick=doAdminLogin;
  /* ── recovery ── */
  var recPhone=function(){ var cc=($("#adCC")||{}).value||REC.cc||"963", p=(($("#adPhone")||{}).value||REC.phone||"").replace(/\D/g,""); REC.cc=cc; REC.phone=p; return "+"+cc+p };
  var recErr=function(m){ ADM.msg=m; var e=$("#adErr"); if(e) e.textContent=m };
  if($("#adForgot")) $("#adForgot").onclick=function(){ REC.mode="pick"; ADM.msg=""; render() };
  if($("#adRecBack")) $("#adRecBack").onclick=function(){ verifyPollStop(); AU.pollKeep=false; REC.mode=null; ADM.msg=""; render() };
  var recStart=async function(){ var ph=recPhone(); if(ph.length<9){ recErr(t("badPhone")||"phone"); return null }
    try{ var s=await rpc("bk_admin_verify_start",{p_phone:ph}); REC.ticket=s.ticket; REC.secret=s.secret; REC.bot=s.bot||SX("intake_bot",""); return s }
    catch(e){ var m=e.message||""; recErr(m==="notadmin"?GX("admRecNotAdmin"):m==="locked"?GX("loginLocked"):m==="throttled"?GX("vThrottled"):m); return null } };
  var recPoll=function(){ AU.pollKeep=true; AU.ticket=REC.ticket; AU.secret=REC.secret;
    verifyPollStart(function(){ AU.pollKeep=false; REC.mode="newpass"; ADM.msg=""; render() }, function(){ AU.pollKeep=false; recErr(GX("vExpired")) }) };
  if($("#adRecTg")) $("#adRecTg").onclick=async function(){ this.disabled=true; var s=await recStart(); if(!s){ this.disabled=false; return } if(!s.telegram){ recErr(GX("admRecNoTg")); this.disabled=false; return } REC.mode="tg"; render(); recPoll() };
  if($("#adRecCode")) $("#adRecCode").onclick=function(){ recPhone(); REC.mode="code"; ADM.msg=""; render() };
  if($("#adRecSave")) $("#adRecSave").onclick=async function(){ var p1=$("#adNew1").value||"", p2=$("#adNew2").value||""; if(p1.length<6) return recErr(t("shortPass")); if(p1!==p2) return recErr(t("noMatch"));
    this.disabled=true; try{ await rpc("bk_admin_set_password_by_ticket",{p_ticket:REC.ticket,p_secret:REC.secret,p_hash:await sha(p1)}); REC.mode="done"; ADM.msg=""; render() }catch(e){ this.disabled=false; recErr(e.message==="notverified"||e.message==="expired"?GX("vExpired"):e.message) } };
  if($("#adRecCodeGo")) $("#adRecCodeGo").onclick=async function(){ var ph=recPhone(), code=($("#adRecCodeIn").value||"").trim(), p1=$("#adNew1").value||"", p2=$("#adNew2").value||"";
    if(ph.length<9) return recErr("phone"); if(code.replace(/[^A-Za-z0-9]/g,"").length<8) return recErr(GX("admRecBadCode")); if(p1.length<6) return recErr(t("shortPass")); if(p1!==p2) return recErr(t("noMatch"));
    this.disabled=true; try{ await rpc("bk_admin_recover",{p_phone:ph,p_code:code,p_hash:await sha(p1)}); REC.mode="done"; ADM.msg=""; render() }
    catch(e){ this.disabled=false; var m=e.message||""; recErr(m==="badcode"?GX("admRecBadCode"):m==="notadmin"?GX("admRecNotAdmin"):m==="locked"?GX("loginLocked"):m) } };
  if($("#adPass")) $("#adPass").addEventListener("keydown",function(e){
    if(e.key==="Enter"){ e.preventDefault(); doAdminLogin() }
  });
  if($("#adOut")) $("#adOut").onclick=async function(){
    try{ await rpc("bk_admin_logout",{p_token:ADM.token}) }catch(e){}
    stopAdminAlertsPolling();
    ADM.token=null; ADM.data=null; ADM.editId=null; ADM.editRow=null;
    try{localStorage.removeItem("balkoun_adm")}catch(x){}
    VIEW="home"; render();
  };
  if($("#adViewSite")) $("#adViewSite").onclick=async function(){
    // logs the admin into their own account (every admin is also a
    // real row in the users table) rather than just showing an
    // anonymous, logged-out homepage — that only happened to look
    // like "viewing as a user" if the admin separately already had
    // their own regular session open, which usually isn't the case
    this.disabled = true;
    try{
      if(!USER){
        var u = await rpc("bk_admin_switch_to_user",{p_token:ADM.token});
        if(u && !u.error){ USER=u; saveSession(USER); loadSaved(); loadNotifications(); startNotifPolling(); }
      }
      VIEW="home"; scrollTo(0,0); render();
    }catch(e){ VIEW="home"; scrollTo(0,0); render(); }
  };
  if($("#adRefresh")) $("#adRefresh").onclick=function(){ var b=this; b.disabled=true; b.classList.add("spin"); adminLoad().then(function(){ admToast(t("refresh")+" ✓") }) };
  if($("#adBack")) $("#adBack").onclick=function(){ ADM.editId=null; ADM.editRow=null; render() };
  $$("[data-atab]").forEach(function(e){ e.onclick=function(){
    if(e.dataset.atab!==ADM.tab && admDirty() && !confirm(GX("hsDiscardConfirm"))) return;
    ADM.tab=e.dataset.atab;
    window._admMobileDetail=false;
    var sb=$("#aSidebar"); if(sb) sb.classList.remove("on"); // auto-close on mobile after picking a section
    render();
    try{ window.scrollTo({top:0,behavior:"instant"}) }catch(e2){ try{ window.scrollTo(0,0) }catch(e3){} }
  } });
  if($("#aSidebarToggle")) $("#aSidebarToggle").onclick=function(e){
    e.stopPropagation(); var sb=$("#aSidebar"); if(sb) sb.classList.toggle("on");
  };
  if(!window._admSbClose){ window._admSbClose=true;   // tap outside or Escape closes the phone sidebar (once per page, not per render)
    document.addEventListener("click",function(e){ var sb=$("#aSidebar"); if(sb && sb.classList.contains("on") && !e.target.closest("#aSidebar,#aSidebarToggle")) sb.classList.remove("on") });
    document.addEventListener("keydown",function(e){ if(e.key==="Escape"){ var sb=$("#aSidebar"); if(sb) sb.classList.remove("on") } }) }
  $$("#aSidebar .asidebar-label").forEach(function(b){ b.onclick=function(){ var g=this.closest(".asidebar-group"); if(!g) return; g.classList.toggle("folded"); var f=g.classList.contains("folded"); ADM_FOLDS[g.dataset.gkey]=f; this.setAttribute("aria-expanded",f?"false":"true"); try{ localStorage.setItem("bk_adm_folds",JSON.stringify(ADM_FOLDS)) }catch(e){} } });
  var nq=$("#aNavQ"); if(nq){ nq.oninput=function(){ var q=this.value.trim().toLowerCase();
    $$("#aSidebar .asidebar-group").forEach(function(g){ g.classList.toggle("folded", !q && !!ADM_FOLDS[g.dataset.gkey] && !g.querySelector("a.on")) });   // a search opens every group; clearing it restores the folds
    $$("#aSidebar a[data-atab]").forEach(function(a){ a.hidden = !!q && a.textContent.toLowerCase().indexOf(q)===-1 });
    $$("#aSidebar .asidebar-group").forEach(function(g){ g.hidden = !!q && !g.querySelector("a[data-atab]:not([hidden])") }) };
    nq.onkeydown=function(e){ if(e.key==="Enter"){ var a=$("#aSidebar a[data-atab]:not([hidden])"); if(a) a.click() } } }
  if($("#aLang")) $("#aLang").onchange=function(){ L=this.value; try{localStorage.setItem("balkoun_lang",L)}catch(err){} render() };
  if(!ADM.countries && !ADM._cLoading && DB && ADM.token){ ADM._cLoading=true; DB.rpc("bk_admin_countries",{p_token:ADM.token}).then(function(r){ ADM._cLoading=false; if(r&&r.data&&r.data.length>1){ ADM.countries=r.data; render() } else if(r&&r.data) ADM.countries=r.data }) }
  if($("#aCountry")) $("#aCountry").onchange=function(){ admPickCountry(this.value) }
  $$("[data-cgo]").forEach(function(b){ b.onclick=function(){ var a=b.dataset.cgo.split(":"); admPickCountry(a[0],a[1]==="undefined"?null:a[1]); scrollTo(0,0) } });   // the switch card + the countries page tiles, on every page;

  var act=async function(fn,args){
    try{ await rpc(fn,args); await adminLoad(); admToast(t("savedOk")) }
    catch(e){ admToast(e.message||"error","bad") } };

  $$("[data-alive]").forEach(function(e){ e.onclick=function(){
    act("bk_admin_set_status",{p_token:ADM.token,p_listing:+e.dataset.alive,p_status:"live"}) }});
  $$("[data-apend]").forEach(function(e){ e.onclick=function(){
    act("bk_admin_set_status",{p_token:ADM.token,p_listing:+e.dataset.apend,p_status:"hidden"}) }});
  $$("[data-areject]").forEach(function(e){ e.onclick=function(){
    var reason=prompt(GX("rejectReasonQ"),""); if(reason===null) return;   // cancel keeps the listing pending
    act("bk_admin_set_status",{p_token:ADM.token,p_listing:+e.dataset.areject,p_status:"rejected",p_reason:reason.trim()||null}) }});
  $$("[data-adel]").forEach(function(e){ e.onclick=async function(){
    if(!confirm(t("confirmDel"))) return;
    var id=e.dataset.adel;
    await trashListingFiles(id);
    act("bk_admin_delete_listing",{p_token:ADM.token,p_listing:+id});
  }});
  $$("[data-ablock]").forEach(function(e){ e.onclick=function(){
    if(e.dataset.on==="1" && !confirm(GX("confirmBlock"))) return;
    act("bk_admin_block_user",{p_token:ADM.token,p_user:e.dataset.ablock,p_blocked:e.dataset.on==="1"}) }});

  $$(".lvlpick").forEach(function(sel){ if(!sel.dataset.uid) return; sel.onchange=function(){
    act("bk_admin_set_level",{p_token:ADM.token,p_user:this.dataset.uid,p_level:this.value}) }});
  if($("#uSortPick")) $("#uSortPick").onchange=function(){ ADM.userSort=this.value; render() };
  if($("#uLevelPick")) $("#uLevelPick").onchange=function(){ ADM.userLevelFilter=this.value; render() };
  if($("#uBlockPick")) $("#uBlockPick").onchange=function(){ ADM.userBlockedFilter=this.value; render() };

  $$("[data-uopen]").forEach(function(e){ e.onclick=function(){ ADM.userOpen = ADM.userOpen===e.dataset.uopen ? null : e.dataset.uopen; ADM.rateTarget=null; ADM.pwTarget=null; render() }});
  $$("[data-umsg]").forEach(function(e){ e.onclick=function(){ ADM.notifTargetUid=e.dataset.umsg; admGo("msgs") }});
  $$("[data-arate]").forEach(function(e){ e.onclick=function(){
    ADM.rateTarget=e.dataset.arate; ADM.rateStars=0; ADM.rateMsg=""; ADM.pwTarget=null; render() }});
  $$("[data-apw]").forEach(function(e){ e.onclick=function(){
    ADM.pwTarget=e.dataset.apw; ADM.pwMsg=""; ADM.rateTarget=null; render() }});
  if($("#aRevCancel")) $("#aRevCancel").onclick=function(){ ADM.rateTarget=null; render() };
  if($("#aPwCancel")) $("#aPwCancel").onclick=function(){ ADM.pwTarget=null; render() };
  $$("[data-astar]").forEach(function(s){ s.onclick=function(){ ADM.rateStars=+this.dataset.astar; render() } });
  if($("#aRevSave")) $("#aRevSave").onclick=async function(){
    if(!ADM.rateStars){ ADM.rateMsg=t("pickStars"); render(); return }
    try{
      await rpc("bk_admin_review_set",{p_token:ADM.token,p_target:ADM.rateTarget,
        p_stars:ADM.rateStars,p_body:($("#aRevBody")||{}).value||""});
      ADM.rateTarget=null; await adminLoad();
    }catch(e){ ADM.rateMsg=e.message||"error"; render() }
  };
  if($("#aPwSave")) $("#aPwSave").onclick=async function(){
    var pw=($("#aNewPass")||{}).value||"";
    if(pw.length<6){ ADM.pwMsg=t("shortPass"); render(); return }
    try{
      await rpc("bk_admin_reset_password",{p_token:ADM.token,p_user:ADM.pwTarget,p_new_pass:pw});
      ADM.pwMsg=t("savedOk"); ADM.pwTarget=null; render();
    }catch(e){ ADM.pwMsg=e.message||"error"; render() }
  };

  // open the full listing editor
  $$("[data-adopen]").forEach(function(e){ e.onclick=async function(){
    // full parity with a member's own "Edit listing" page — location,
    // every detail field, all of it — rather than the old handful-
    // of-fields inline form. bk_admin_listing already returns every
    // raw column (select ll.*), and fromRow() is the exact same
    // normalizer the rest of the site uses to turn that raw row into
    // the shape editView() expects, so this is genuinely the same
    // form a member sees, just reached from the admin side
    var id=+e.dataset.adopen;
    EDIT={id:id, row:null, msg:"", photos:[], lat:null, lng:null, locTouched:false, isAdmin:true};
    VIEW="edit"; scrollTo(0,0); render();
    try{
      var r=await rpc("bk_admin_listing",{p_token:ADM.token,p_id:id});
      if(r&&r.error) throw new Error(r.error);
      var row=fromRow(r);
      EDIT.row=row; EDIT.lat=row.lat||null; EDIT.lng=row.lng||null;
      render();
    }catch(err){ alert(err.message||"error"); VIEW="admin"; render() }
  }});

      // reply to a report or piece of feedback
  $$("[data-replysend]").forEach(function(btn){ btn.onclick=async function(){
    var key=btn.dataset.replysend, kind=key.split(":")[0], id=+key.split(":")[1];
    var box=$('[data-replybox="'+key+'"]');
    var txt=box?box.value.trim():"";
    if(!txt){ if(box) box.focus(); return }
    btn.disabled=true; btn.textContent=t("saving");
    try{ await rpc("bk_admin_reply",{p_token:ADM.token,p_kind:kind,p_id:id,p_reply:txt}); await adminLoad() }
    catch(e){ alert(e.message||"error"); btn.disabled=false; btn.textContent=t("sendReply") } }});
    $$("[data-tosolved]").forEach(function(e){ e.onclick=async function(){
    var key=this.dataset.tosolved, kind=key.split(":")[0], id=+key.split(":")[1], val=this.dataset.val==="1";
    try{ await rpc("bk_admin_set_solved",{p_token:ADM.token,p_kind:kind,p_id:id,p_solved:val}); await adminLoad() }
    catch(e){ alert(e.message||"error") }
  }});
  $$("[data-setprio]").forEach(function(e){ e.onclick=async function(){
    var key=this.dataset.setprio, kind=key.split(":")[0], id=+key.split(":")[1], val=this.dataset.prioval;
    try{ await rpc("bk_admin_set_priority",{p_token:ADM.token,p_kind:kind,p_id:id,p_priority:val}); await adminLoad() }
    catch(e){ alert(e.message||"error") }
  }});

  // reviews moderation
  $$("[data-delreview]").forEach(function(e){ e.onclick=function(){
    if(confirm(t("confirmDelReview"))) act("bk_admin_delete_review",{p_token:ADM.token,p_id:+e.dataset.delreview}) }});
  if(ADM.tab==="reviews" && !ADM._reviewsLoaded){
    ADM._reviewsLoaded=true;
    rpcScoped("bk_admin_reviews",{p_token:ADM.token,p_country:admScope()}).then(function(r){
      if(ADM.data){ ADM.data.reviews=r||[]; render() } }).catch(function(){});
  }
  if((ADM.tab==="stats"||ADM.tab==="dashboard") && !ADM._statsLoaded){
    ADM._statsLoaded=true;
    rpcScoped("bk_admin_stats",{p_token:ADM.token,p_country:admScope()}).then(function(r){
      ADM.stats=r||null; ADM.statsErr=""; render()
    }).catch(function(e){
      ADM.stats=null; ADM.statsErr=(e&&e.message)||"error"; render()
    });
  }
  if(!ADM.range) ADM.range=7;
  if((ADM.tab==="dashboard"||ADM.tab==="stats"||ADM.tab==="ads") && (!ADM._anLoaded || ADM._anRange!==ADM.range)){
    ADM._anLoaded=true; ADM._anRange=ADM.range;
    rpcScoped("bk_admin_analytics",{p_token:ADM.token,p_days:ADM.range,p_country:admScope()}).then(function(r){ ADM.an=r; render() }).catch(function(e){ ADM.anErr=e.message||String(e); render() });
  }
  if(ADM.tab==="users" && !ADM._uactLoaded){
    ADM._uactLoaded=true;
    rpcScoped("bk_admin_user_activity",{p_token:ADM.token,p_country:admScope()}).then(function(r){ var m={}; (r||[]).forEach(function(u){ m[u.id]=u }); ADM.uact=m; render() }).catch(function(){});
  }
  if(ADM.tab==="listings" && (!ADM._lstatsLoaded || ADM._lstatsRange!==ADM.range)){
    ADM._lstatsLoaded=true; ADM._lstatsRange=ADM.range;
    rpcScoped("bk_admin_listing_stats",{p_token:ADM.token,p_days:ADM.range,p_country:admScope()}).then(function(r){ var m={}; (r||[]).forEach(function(x){ m[x.id]=x }); ADM.lstats=m; render() }).catch(function(){});
  }
  $$("[data-arange]").forEach(function(b){ b.onclick=function(){ ADM.range=+this.dataset.arange; render() } });
  if($("#afSort")) $("#afSort").onchange=function(){ ADM.listSort=this.value; render() };
  if($("#uActPick")) $("#uActPick").onchange=function(){ ADM.userActFilter=this.value; render() };
  if(ADM.tab==="storage" && !ADM._storageReportLoaded){
    ADM._storageReportLoaded=true;
    rpc("bk_admin_storage_report",{p_token:ADM.token}).then(function(r){ ADM.storageReport=r; render() }).catch(function(e){ ADM.storageReport={error:e.message||"error"}; render() });
  }
  if($("#stRefresh")) $("#stRefresh").onclick=function(){ ADM._storageReportLoaded=false; ADM._storageUsageLoaded=false; ADM.storageReport=null; ADM.storageUsage=null; render() };
  if($("#stEmptyTrash")) $("#stEmptyTrash").onclick=async function(){
    var n=this.dataset.n, btn=this, msg=$("#stTrashMsg");
    if(!confirm(GX("stTrashConfirm").replace("{n}",n))) return;
    btn.disabled=true; if(msg) msg.textContent=GX("stDeleting");
    var paths=((ADM.storageReport&&ADM.storageReport.trash_paths)||[]).slice();
    for(var i=0;i<paths.length;i+=100){ await storageRemove(paths.slice(i,i+100)); if(msg) msg.textContent=GX("stDeleting")+" "+Math.min(i+100,paths.length)+"/"+paths.length }
    ADM._storageReportLoaded=false; ADM._storageUsageLoaded=false; ADM.storageReport=null; ADM.storageUsage=null; render();
  };
  var stReload=function(){ ADM._storageReportLoaded=false; ADM._storageUsageLoaded=false; ADM.storageReport=null; ADM.storageUsage=null; render() };
  $$("[data-stdel]").forEach(function(b){ b.onclick=async function(){ var pth=this.dataset.stdel; if(!confirm(GX("stDelOneConfirm"))) return; this.disabled=true; var r=await storageRemove([pth]); if(r&&r.error){ alert(r.error.message||r.error); this.disabled=false; return } stReload() } });
  $$("[data-strestore]").forEach(function(b){ b.onclick=async function(){ var pth=this.dataset.strestore; this.disabled=true; var r=await storageRestore([pth]); if(r&&r.error){ alert(r.error.message||r.error); this.disabled=false; return } if(r&&r.data&&r.data.failed&&r.data.failed.length){ alert(GX("stRestoreFailed")); this.disabled=false; return } stReload() } });
  if($("#stDelOrphans")) $("#stDelOrphans").onclick=async function(){
    var n=this.dataset.n, btn=this, msg=$("#stDelMsg");
    if(!confirm(GX("stDelConfirm").replace("{n}",n))) return;
    btn.disabled=true; if(msg) msg.textContent=GX("stDeleting");
    var folders=((ADM.storageReport&&ADM.storageReport.orphans)||[]).map(function(o){ return String(o.folder) });
    for(var i=0;i<folders.length;i++){ await clearStorageFolder(folders[i]); if(msg) msg.textContent=GX("stDeleting")+" "+(i+1)+"/"+folders.length }
    ADM._storageReportLoaded=false; ADM._storageUsageLoaded=false; ADM.storageReport=null; ADM.storageUsage=null; render();
  };
  if((ADM.tab==="dashboard"||ADM.tab==="stats"||ADM.tab==="storage") && !ADM._storageUsageLoaded){
    ADM._storageUsageLoaded=true;
    rpc("bk_admin_storage_usage",{p_token:ADM.token}).then(function(r){
      ADM.storageUsage=r||null; render()
    }).catch(function(){});
  }
  if(ADM.tab==="msgs" && ADM.alertsUnread){
    ADM.alertsUnread=0; ADM.alerts.forEach(function(n){n.is_read=true});
    rpc("bk_admin_mark_notifications_read",{p_token:ADM.token}).catch(function(){});
  }
  // also needed for the Media Library's own "ads" category, not just
  // the dedicated Ad Squares tab — without this, navigating straight
  // to Photos > Ads never loads the slot data the "in use" check
  // depends on, so every file looks unused regardless of whether it
  // actually is (the exact bug reported: everything shown as unused)
  if((ADM.tab==="ads" || (ADM.tab==="photos" && ADM.mediaCategory==="ads")) && !ADM._adSlotsLoaded){
    ADM._adSlotsLoaded=true;
    rpc("bk_admin_list_ads",{p_token:ADM.token,p_country:COUNTRY}).then(function(r){
      ADM.adSlots=r||[]; render()
    }).catch(function(){});
  }
  if(ADM.tab==="photos" && !ADM._photosLoaded){
    ADM._photosLoaded=true;
    ADM._photosLoading=true;
    rpcScoped("bk_admin_photos",{p_token:ADM.token,p_country:admScope(),p_limit:600}).then(function(r){
        ADM._photosLoading=false; ADM.photosList = r||[]; render();
      }).catch(function(){ ADM._photosLoading=false; ADM.photosList=[]; render() });
  }
  // the three non-listing media categories (ads/banners/background)
  // each get their own storage folder pair (photos/<cat> and
  // videos/<cat>) — fetched together and cached per category the
  // first time that tab is opened, so switching between them doesn't
  // re-fetch every time
  if(ADM.tab==="photos" && !ADM._mediaUsedLoaded){ ADM._mediaUsedLoaded=true; rpc("bk_admin_media_used",{p_token:ADM.token}).then(function(r){ ADM.mediaUsed=r||{}; render() }).catch(function(){}) }
  if(ADM.tab==="photos" && ADM.mediaCategory && ADM.mediaCategory!=="listings" && DB
     && !(ADM._mediaLoadedCats||{})[ADM.mediaCategory]){
    var cat = ADM.mediaCategory;
    // the OLD flat folder each category used before this reorganization
    // (banners' old folder was singular: "banner", not "banners") —
    // anything uploaded before this change is still sitting there, so
    // it has to be included too or it would look like it vanished
    var oldFolder = {ads:"ads", banners:"banner", background:"hero"}[cat];
    ADM._mediaLoadedCats = ADM._mediaLoadedCats||{};
    ADM._mediaLoadedCats[cat] = true;
    ADM._mediaLoading = cat;
    var isVideoName = function(name){ return /\.(mp4|webm|mov|m4v)$/i.test(name) };
    Promise.all([
      DB.storage.from("photos").list("photos/"+cat,{limit:200,sortBy:{column:"created_at",order:"desc"}}),
      DB.storage.from("photos").list("videos/"+cat,{limit:200,sortBy:{column:"created_at",order:"desc"}}),
      DB.storage.from("photos").list(oldFolder,{limit:200,sortBy:{column:"created_at",order:"desc"}})
    ]).then(function(results){
      if(ADM._mediaLoading===cat) ADM._mediaLoading=null;
      var combined = [];
      (results[0]&&results[0].data||[]).forEach(function(f){
        if(!f.name || f.name===".emptyFolderPlaceholder") return;
        var path = "photos/"+cat+"/"+f.name;
        combined.push({name:f.name, path:path, isVideo:false, publicUrl:DB.storage.from("photos").getPublicUrl(path).data.publicUrl,
          uploadedAt:f.created_at});
      });
      (results[1]&&results[1].data||[]).forEach(function(f){
        if(!f.name || f.name===".emptyFolderPlaceholder") return;
        var path = "videos/"+cat+"/"+f.name;
        combined.push({name:f.name, path:path, isVideo:true, publicUrl:DB.storage.from("photos").getPublicUrl(path).data.publicUrl,
          uploadedAt:f.created_at});
      });
      (results[2]&&results[2].data||[]).forEach(function(f){
        if(!f.name || f.name===".emptyFolderPlaceholder") return;
        var path = oldFolder+"/"+f.name;
        combined.push({name:f.name, path:path, isVideo:isVideoName(f.name), publicUrl:DB.storage.from("photos").getPublicUrl(path).data.publicUrl,
          uploadedAt:f.created_at});
      });
      combined.sort(function(a,b){ return new Date(b.uploadedAt||0) - new Date(a.uploadedAt||0) });
      ADM.mediaFiles = ADM.mediaFiles||{};
      ADM.mediaFiles[cat] = combined;
      render();
    }).catch(function(){ if(ADM._mediaLoading===cat) ADM._mediaLoading=null; render() });
  }
  // the agencies and engagements lists reload every time their tab is opened, so a request made a minute ago is there
  wireAdminBell();
  if(ADM.tab!=="agencies_adm"){ ADM._agLoaded=false } if(ADM.tab!=="engage"){ ADM._engDays=null }
  if(ADM.tab!=="wanted_adm"){ ADM._wLoaded=false }
  if(ADM.tab==="wanted_adm"){
    if(!ADM._wLoaded){ ADM._wLoaded=true; rpcScoped("bk_admin_wanted",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM_W=r||[]; render() }).catch(function(e){ ADM_W=[]; render() }) }
    $$("[data-wadm]").forEach(function(b){ b.onclick=async function(){ var q=this.dataset.wadm.split(":"); if(q[1]==="rejected" && !confirm(GX("confirmReject"))) return; try{ await rpc("bk_admin_wanted_set",{p_token:ADM.token,p_id:+q[0],p_status:q[1]}); ADM._wLoaded=false; WANTED=null; syncAdminTodo(); render() }catch(e){ alert(e.message||"error") } } });
    $$("[data-wfeat]").forEach(function(b){ b.onclick=async function(){ var q=this.dataset.wfeat.split(":"); try{ await rpc("bk_admin_wanted_set",{p_token:ADM.token,p_id:+q[0],p_featured:q[1]==="1"}); ADM._wLoaded=false; WANTED=null; render() }catch(e){ alert(e.message||"error") } } });
    $$("[data-wadel]").forEach(function(b){ b.onclick=async function(){ if(!confirm(GX("wDelConfirm"))) return; try{ await rpc("bk_admin_wanted_delete",{p_token:ADM.token,p_id:+this.dataset.wadel}); ADM._wLoaded=false; WANTED=null; render() }catch(e){ alert(e.message||"error") } } });
  }
  if(ADM.tab!=="projects_adm"){ ADM._pjLoaded=false }
  if(ADM.tab==="projects_adm"){
    if(!ADM._pjLoaded){ ADM._pjLoaded=true; rpcScoped("bk_admin_projects",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM_PJ=r||[]; render() }).catch(function(){ ADM_PJ=[]; render() }); rpcScoped("bk_admin_project_leads",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM_PJL=r||[]; render() }).catch(function(){ ADM_PJL=[] }); if(!ADM_AG) rpcScoped("bk_admin_agencies",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM_AG=r||[] }).catch(function(){}) }
    if($("#pjNewBtn")) $("#pjNewBtn").onclick=function(){ ADM.pjEdit={status:"soon",photos:[],units:[],plans:[],published:false,country_code:COUNTRY}; render(); var ed=$("#pjEditor"); if(ed) ed.scrollIntoView({behavior:"smooth"}) };
    $$("[data-pjedit]").forEach(function(b){ b.onclick=function(){ var p=(ADM_PJ||[]).filter(function(x){ return String(x.id)===this.dataset.pjedit }.bind(this))[0]; if(p){ ADM.pjEdit=JSON.parse(JSON.stringify(p)); render(); var ed=$("#pjEditor"); if(ed) ed.scrollIntoView({behavior:"smooth"}) } } });
    $$("[data-pjdel]").forEach(function(b){ b.onclick=async function(){ if(!confirm(GX("pjDelConfirm"))) return; try{ await rpc("bk_admin_project_delete",{p_token:ADM.token,p_id:+this.dataset.pjdel}); ADM._pjLoaded=false; PROJECTS=null; render() }catch(e){ alert(e.message||"error") } } });
    $$("[data-pjlead]").forEach(function(b){ b.onclick=async function(){ var q=this.dataset.pjlead.split(":"); try{ await rpc("bk_admin_project_lead_set",{p_token:ADM.token,p_id:+q[0],p_handled:q[1]==="1"}); ADM._pjLoaded=false; render() }catch(e){ alert(e.message||"error") } } });
    var ed=$("#pjEditor"); if(ed && ADM.pjEdit){ var P=ADM.pjEdit;
      ed.oninput=function(e){ var el=e.target; if(el.dataset.pj){ P[el.dataset.pj]=el.dataset.pjbool?el.checked:el.value } var u=el.dataset.pju, q=el.dataset.pjp; if(u){ var a=u.split(":"); P.units[+a[0]][a[1]]=el.type==="number"?(el.value===""?"":+el.value):el.value } if(q){ var c=q.split(":"); P.plans[+c[0]][c[1]]=el.type==="number"?(el.value===""?"":+el.value):el.value } };
      ed.onchange=function(e){ var el=e.target; if(el.dataset.pj){ P[el.dataset.pj]=el.dataset.pjbool?el.checked:el.value; if(el.dataset.pj==="gov_name"){ P.area_name=""; render() } }
        if(el.id==="pjPhotoUp" && el.files && el.files.length){ var files=Array.prototype.slice.call(el.files), msg=$("#pjUpMsg"); el.disabled=true;
          (async function(){ try{ for(var i=0;i<files.length;i++){ if(msg) msg.textContent=hsT("uploading")+" "+(i+1)+"/"+files.length; var url=await hsUpload(files[i],"projects"); P.photos=(P.photos||[]).concat([url]) } render() }catch(err){ if(msg) msg.textContent=err.message||"error"; el.disabled=false } })() } };
      ed.onclick=async function(e){ var rm=e.target.closest("[data-pjrm]"); if(rm){ P.photos.splice(+rm.dataset.pjrm,1); render(); return }
        var urm=e.target.closest("[data-pjurm]"); if(urm){ P.units.splice(+urm.dataset.pjurm,1); render(); return }
        var prm=e.target.closest("[data-pjprm]"); if(prm){ P.plans.splice(+prm.dataset.pjprm,1); render(); return }
        if(e.target.closest("#pjAddUnit")){ P.units.push({type:"",area_m2:"",rooms:"",price_usd:"",count:""}); render(); return }
        if(e.target.closest("#pjAddPlan")){ P.plans.push({name:"",down_pct:P.down_pct||"",months:P.months||"",handover_pct:P.handover_pct||""}); render(); return }
        if(e.target.closest("#pjCancel")){ ADM.pjEdit=null; render(); return }
        if(e.target.closest("#pjSave")){ var m=$("#pjMsg"); if(!P.name||!String(P.name).trim()){ if(m){ m.style.color="var(--danger)"; m.textContent=GX("pjName") } return }
          var data=Object.assign({},P); delete data.leads; delete data.new_leads; delete data.created_at; delete data.updated_at; delete data.id;
          var N=function(v){ return v===""||v==null?null:(isNaN(+v)?null:+v) }; ["price_from","down_pct","months","handover_pct","lat","lng"].forEach(function(k){ data[k]=N(data[k]) }); if(!data.developer_user_id) data.developer_user_id=null;
          data.units=(P.units||[]).filter(function(u){ return u.type||u.price_usd }).map(function(u){ return {type:u.type||"",area_m2:N(u.area_m2),rooms:N(u.rooms),price_usd:N(u.price_usd),count:N(u.count)} }); data.plans=(P.plans||[]).filter(function(x){ return x.name||x.months }).map(function(x){ return {name:x.name||"",down_pct:N(x.down_pct),months:N(x.months),handover_pct:N(x.handover_pct)} });
          try{ await rpc("bk_admin_project_save",{p_token:ADM.token,p_id:P.id||null,p_data:data}); ADM.pjEdit=null; ADM._pjLoaded=false; PROJECTS=null; render() }catch(err){ if(m){ m.style.color="var(--danger)"; m.textContent=err.message||"error" } } } } }
  }
  if(ADM.tab!=="intake"){ ADM._ikLoaded=false }
  if(ADM.tab==="intake"){ wireAdminIntake() }
  if(ADM.tab==="agencies_adm"){
    if(!ADM._agLoaded){ ADM._agLoaded=true; ADM.agErr=null; rpcScoped("bk_admin_agencies",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM_AG=r||[]; render() }).catch(function(e){ ADM_AG=[]; ADM.agErr=e.message||"error"; render() }) }
    $$("[data-agset]").forEach(function(b){ b.onclick=async function(){ var p=this.dataset.agset.split(":"); if(p[1]==="rejected" && !confirm(GX("confirmReject"))) return; try{ await rpc("bk_admin_agency_set",{p_token:ADM.token,p_id:+p[0],p_status:p[1]}); ADM._agLoaded=false; render() }catch(e){ alert(e.message||"error") } } });
    $$("[data-agver]").forEach(function(b){ b.onclick=async function(){ var p=this.dataset.agver.split(":"); try{ await rpc("bk_admin_agency_set",{p_token:ADM.token,p_id:+p[0],p_verified:p[1]==="1"}); ADM._agLoaded=false; render() }catch(e){ alert(e.message||"error") } } });
    $$("[data-agintake]").forEach(function(b){ b.onclick=async function(){ var p=this.dataset.agintake.split(":"); try{ await rpc("bk_admin_agency_set",{p_token:ADM.token,p_id:+p[0],p_intake:p[1]==="1"}); ADM._agLoaded=false; admToast(t("savedOk")); render() }catch(e){ admToast(e.message||"error","bad") } } });
    $$("[data-agcode]").forEach(function(b){ b.onclick=async function(){ if(!confirm(GX("agNewCodeConfirm"))) return; try{ await rpc("bk_admin_agency_set",{p_token:ADM.token,p_id:+this.dataset.agcode,p_newcode:true}); ADM._agLoaded=false; admToast(t("savedOk")); render() }catch(e){ admToast(e.message||"error","bad") } } });
    $$("[data-agtrust]").forEach(function(b){ b.onclick=async function(){ var p=this.dataset.agtrust.split(":"); try{ await rpc("bk_admin_agency_set",{p_token:ADM.token,p_id:+p[0],p_trusted:p[1]==="1"}); ADM._agLoaded=false; admToast(t("savedOk")); render() }catch(e){ admToast(e.message||"error","bad") } } });
  }
  if(ADM.tab==="engage"){
    var edays=ADM.erange==null?30:ADM.erange;
    if(ADM._engDays!==edays){ ADM._engDays=edays; ADM.eng=null; rpcScoped("bk_admin_engagements",{p_token:ADM.token,p_days:edays===0?null:edays,p_country:admScope()}).then(function(r){ ADM.eng=r||[]; render() }).catch(function(e){ ADM.eng=[]; ADM.engErr=e.message; render() }) }
    $$("[data-erange]").forEach(function(b){ b.onclick=function(){ ADM.erange=+this.dataset.erange; render() } });
    var eq=$("#engQ"); if(eq){ eq.oninput=function(){ ADM.eq=this.value; clearTimeout(window._eqT); window._eqT=setTimeout(function(){ var pos=eq.selectionStart; render(); var n=$("#engQ"); if(n){ n.focus(); try{ n.setSelectionRange(pos,pos) }catch(e){} } },260) } }
    $$("[data-eedit]").forEach(function(b){ b.onclick=function(){ ADM.eopen = String(ADM.eopen)===this.dataset.eedit ? null : this.dataset.eedit; render() } });
    $$("[data-eend]").forEach(function(b){ b.onclick=async function(){ if(!confirm(GX("engEndConfirm"))) return; try{ await rpc("bk_admin_engagement_update",{p_token:ADM.token,p_id:+this.dataset.eend,p_status:"ended"}); ADM._engDays=null; render() }catch(e){ alert(e.message||"error") } } });
    $$("[data-esave]").forEach(function(b){ b.onclick=async function(){ var m=$("#eeMsg"); try{ var ends=($("#eeEnds")||{}).value;
        await rpc("bk_admin_engagement_update",{p_token:ADM.token,p_id:+this.dataset.esave,p_client:($("#eeClient")||{}).value||null,p_phone:($("#eePhone")||{}).value||null,p_notes:($("#eeNotes")||{}).value||null,p_ends:ends?new Date(ends+"T23:59:59").toISOString():null});
        ADM.eopen=null; ADM._engDays=null; render() }catch(e){ if(m) m.textContent=e.message||"error" } } });
    if($("#engAddBtn")) $("#engAddBtn").onclick=function(){ ADM.engAdd=!ADM.engAdd; render() };
    if($("#engAddCancel")) $("#engAddCancel").onclick=function(){ ADM.engAdd=false; render() };
    if($("#engAddSave")) $("#engAddSave").onclick=async function(){ var m=$("#eaMsg"), kind=$("#eaKind").value, ref=($("#eaRef").value||"").trim(), refId=null;
      if(/^\d+$/.test(ref)) refId=+ref; else if(ref){ var l=((ADM.data&&ADM.data.listings)||[]).filter(function(x){ return String(x.ref||"").toLowerCase()===ref.toLowerCase() })[0]; if(l) refId=+l.id }
      var from=$("#eaFrom").value, to=$("#eaTo").value;
      try{ var r=await rpc("bk_admin_engage",{p_token:ADM.token,p_kind:kind,p_ref_id:refId,p_ref_text:ref||null,p_title:($("#eaTitle").value||ref||null),p_client:$("#eaClient").value||null,p_phone:$("#eaPhone").value||null,
          p_starts:from?new Date(from+"T00:00:00").toISOString():null,p_ends:to?new Date(to+"T23:59:59").toISOString():null,p_notes:$("#eaNotes").value||null,p_country:COUNTRY});
        ADM.engAdd=false; ADM._engDays=null; ADM._featCode=null; ADM.engLastCode=r&&r.code||null; render() }catch(e){ if(m) m.textContent=e.message||"error" } };
  }
  $$("[data-ecopy]").forEach(function(b){ b.onclick=function(){ var c=this.dataset.ecopy, btn=this, old=btn.textContent; try{ navigator.clipboard.writeText(c).then(function(){ if(btn.tagName==="BUTTON"){ btn.textContent=GX("engCopied"); setTimeout(function(){ btn.textContent=old },1200) } }) }catch(e){ prompt(GX("engCode"),c) } } });
  var reloadFeaturedList=async function(){
    try{ var r=await rpcScoped("bk_admin_list_featured",{p_token:ADM.token,p_country:admScope()}); ADM.featuredList=r||[] }catch(e){}
  };
  if(ADM.tab==="featured" && !ADM._featuredListLoaded){
    ADM._featuredListLoaded=true;
    reloadFeaturedList().then(render);
  }
  if($("#ftSave")) $("#ftSave").onclick=async function(){
    var listingId=($("#ftListing")||{}).value;
    var fromVal=($("#ftFrom")||{}).value;
    var days=parseInt(($("#ftDays")||{}).value,10);
    var msgEl=$("#ftMsg");
    if(!listingId){ if(msgEl) msgEl.textContent=t("adPickListingL"); return }
    if(!fromVal || !days || days<1){ if(msgEl) msgEl.textContent=t("featureInvalidDates"); return }
    this.disabled=true;
    try{
      var fr=await rpc("bk_admin_feature_listing",{p_token:ADM.token,p_listing:+listingId,
        p_from:new Date(fromVal+"T00:00:00Z").toISOString(),p_days:days});
      ADM._featCode = fr && fr.code ? fr.code : null;
      await reloadFeaturedList();
      syncFeaturedFromServer();
      var si=$("#ftListingSearch"); if(si) si.value="";
      var hi=$("#ftListing"); if(hi) hi.value="";
      if(msgEl) msgEl.textContent="";
      ADM._engDays=null;
      render();
    }catch(e){ if(msgEl) msgEl.textContent=e.message||"error"; this.disabled=false }
  };
  $$("[data-unfeat]").forEach(function(e){ e.onclick=async function(){
    if(!confirm(t("confirmUnfeature"))) return;
    try{
      await rpc("bk_admin_unfeature_listing",{p_token:ADM.token,p_listing:+e.dataset.unfeat});
      await reloadFeaturedList();
      syncFeaturedFromServer();
      render();
    }catch(err){ alert(err.message||"error") }
  }});
  wireGeoAdmin(); wireAdminCountries(); wireAdminCampaigns();
  if(ADM.tab==="settings" && !ADM._settingsLoaded){
    ADM._settingsLoaded=true;
    rpc("bk_admin_get_settings",{p_token:ADM.token}).then(function(r){
      ADM.settings=r||{require_approval:true}; render()
    }).catch(function(e){ ADM.settings={require_approval:true,_error:e.message||"error"}; render() });
  }
  if(ADM.tab==="admins" && !ADM._adminsLoaded){
    ADM._adminsLoaded=true;
    ADM._adminsErr=null;
    rpc("bk_admin_list_admins",{p_token:ADM.token}).then(function(r){
      ADM.admins=r||[]; ADM._adminsDone=true; render()
    }).catch(function(e){ ADM.admins=[]; ADM._adminsDone=true; ADM._adminsErr=e.message||"error"; render() });
  }

  if($("#aMyAccount")) $("#aMyAccount").onclick=function(){
    ADM.myAccountOpen=!ADM.myAccountOpen; ADM.myPwMsg=""; ADM.recCodes=null; render() };
  if(ADM.myAccountOpen && ADM.token && !ADM._meLoaded){ ADM._meLoaded=true; rpc("bk_admin_me",{p_token:ADM.token}).then(function(r){ ADM.me=r; render() }).catch(function(){ ADM._meLoaded=false }) }
  var meReload=async function(){ try{ ADM.me=await rpc("bk_admin_me",{p_token:ADM.token}); render() }catch(e){ admToast(e.message||"error","bad") } };
  if($("#meTgUnpair")) $("#meTgUnpair").onclick=async function(){ if(!confirm(GX("tmUnpairConfirm"))) return; try{ await rpc("bk_admin_tg_unpair",{p_token:ADM.token}); meReload() }catch(e){ admToast(e.message||"error","bad") } };
  if($("#meTgNew")) $("#meTgNew").onclick=async function(){ try{ ADM.me=await rpc("bk_admin_me_set",{p_token:ADM.token,p_new_code:true}); render() }catch(e){ admToast(e.message||"error","bad") } };
  if($("#meNotify")) $("#meNotify").onchange=async function(){ try{ ADM.me=await rpc("bk_admin_me_set",{p_token:ADM.token,p_notify:this.checked}); admToast(t("savedOk")) }catch(e){ admToast(e.message||"error","bad") } };
  if($("#meRecGen")) $("#meRecGen").onclick=async function(){ if(ADM.me&&ADM.me.recovery_left&&!confirm(GX("admMeRecRegenConfirm"))) return; this.disabled=true; try{ var r=await rpc("bk_admin_recovery_new",{p_token:ADM.token}); ADM.recCodes=r.codes||[]; ADM._meLoaded=false; ADM.me=await rpc("bk_admin_me",{p_token:ADM.token}); render() }catch(e){ admToast(e.message||"error","bad"); this.disabled=false } };
  if($("#meRecHide")) $("#meRecHide").onclick=function(){ ADM.recCodes=null; render() };
  if($("#myPwCancel")) $("#myPwCancel").onclick=function(){ ADM.myAccountOpen=false; ADM.recCodes=null; render() };
  if($("#meOv")) $("#meOv").onclick=function(e){ if(e.target.id==="meOv"){ ADM.myAccountOpen=false; ADM.recCodes=null; render() } };
  if($("#myPwSave")) $("#myPwSave").onclick=async function(){
    var oldP=($("#myOldPass")||{}).value||"", newP=($("#myNewPass")||{}).value||"";
    if(newP.length<6){ ADM.myPwMsg=t("shortPass"); render(); return }
    try{
      var r=await rpc("bk_admin_change_own_password",{p_token:ADM.token,p_old:oldP,p_new:newP});
      if(r&&r.error){ ADM.myPwMsg=t("wrongPass"); render(); return }
      ADM.myPwMsg=t("savedOk"); ADM.myAccountOpen=false; render();
    }catch(e){ ADM.myPwMsg=e.message||"error"; render() }
  };

  $$(".skipRev").forEach(function(cb){ cb.onchange=function(){
    rpc("bk_admin_set_skip_review",{p_token:ADM.token,p_user:this.dataset.uid,p_skip:this.checked}).catch(function(){}) }});
  $$(".cardLogo").forEach(function(cb){ cb.onchange=function(){
    var id=this.dataset.uid, on=this.checked, box=this;
    ADM.cardLogos=(ADM.cardLogos||[]).filter(function(x){return x!==id}); if(on) ADM.cardLogos.push(id);
    rpc("bk_admin_set_card_logo",{p_token:ADM.token,p_user:id,p_on:on}).catch(function(){ box.checked=!on }) }});
  if(ADM.tab==="users" && !ADM._vfLoaded){ ADM._vfLoaded=true;
    rpcScoped("bk_admin_verify_list",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM.vf=Array.isArray(r)?r:[]; render() }).catch(function(){ ADM.vf=[]; render() }) }
  if($("#vfSetSave")) $("#vfSetSave").onclick=async function(){ var m=$("#vfSetMsg"), patch={}; this.disabled=true;
    $$("#vfSet [data-gk]").forEach(function(i){ var k=i.dataset.gk, ty=i.dataset.gt; patch[k] = ty==="bool" ? !!i.checked : ty==="num" ? (i.value===""?null:+i.value) : (String(i.value).trim()===""?null:String(i.value).trim()) });
    try{ await saveGlobalExtras(patch); admToast(t("savedOk")); if(m) m.textContent="" }catch(e){ if(m){ m.style.color="var(--danger)"; m.textContent=e.message||"error" } } this.disabled=false };
  $$("[data-vfok],[data-vfno]").forEach(function(b){ b.onclick=async function(){ var ok=!!this.dataset.vfok, id=this.dataset.vfok||this.dataset.vfno; if(!ok && !confirm(GX("confirmReject"))) return; this.disabled=true;
    try{ await rpc("bk_admin_verify_set",{p_token:ADM.token,p_ticket:id,p_ok:ok}); admToast(t("savedOk")); ADM._vfLoaded=false; syncAdminTodo(); render() }catch(e){ admToast(e.message||"error","bad"); this.disabled=false } } });
  if(ADM.tab==="users" && !ADM._cardLogosLoaded){
    ADM._cardLogosLoaded=true;
    rpc("bk_admin_card_logos",{p_token:ADM.token}).then(function(r){ ADM.cardLogos=Array.isArray(r)?r:[]; render() }).catch(function(){});
  }

  if($("#aReqApproval")) $("#aReqApproval").onchange=async function(){
    var box=this;
    try{
      await rpc("bk_admin_set_approval_mode",{p_token:ADM.token,p_require:box.checked});
      var m=$("#aSettingsMsg"); if(m) m.textContent=t("savedOk");
    }catch(e){ box.checked=!box.checked }
  };

  var saveSiteContent=async function(patch, msgId, btn){
    var msgEl=$("#"+msgId);
    if(btn){ btn.disabled=true; btn.textContent=t("saving") }
    try{
      await rpc("bk_admin_set_content",{p_token:ADM.token,p_patch:patch,p_country:COUNTRY});
      Object.keys(patch).forEach(function(k){
        if(k==="extras"){ var ex=SITE.extras; if(typeof ex==="string"){ try{ ex=JSON.parse(ex) }catch(e){ ex={} } } ex=Object.assign({},ex||{},patch.extras); Object.keys(ex).forEach(function(kk){ if(ex[kk]===null) delete ex[kk] }); SITE.extras=ex; applySiteExtras() }
        else SITE[k]=patch[k] });
      try{ localStorage.setItem(siteCacheKey(), JSON.stringify(SITE)) }catch(e){}
      if(msgEl) msgEl.textContent=t("savedOk");
    }catch(e){ if(msgEl) msgEl.textContent=e.message||"error" }
    if(btn){ btn.disabled=false; btn.textContent=t("save") }
  };
  $$("[data-xsave]").forEach(function(b){ b.onclick=async function(){
    var f=this.closest("[data-xform]"); if(!f) return; var patch={};
    f.querySelectorAll("[data-xkey]").forEach(function(i){ var k=i.dataset.xkey, ty=i.dataset.xtype;
      patch[k] = ty==="bool" ? !!i.checked : ty==="num" ? (i.value===""?null:+i.value) : (String(i.value).trim()===""?null:String(i.value).trim()) });
    await saveSiteContent({extras:patch}, f.dataset.xform+"Msg", this);
  } });
                // ad squares page: one save per card; the preview follows every edit
        hsWire();
              var reloadAdSlots=async function(){
    try{ var r=await rpc("bk_admin_list_ads",{p_token:ADM.token,p_country:COUNTRY}); ADM.adSlots=r||[] }catch(e){}
    loadAdSlots(); // also refresh the public list, so the home page reflects the change immediately
  };
    if($("#dzBackupBtn")) $("#dzBackupBtn").onclick=async function(){
    var msgEl=$("#dzBackupMsg"); var btn=this;
    btn.disabled=true; btn.textContent=t("backingUp");
    try{
      var data = await rpc("bk_admin_backup",{p_token:ADM.token});
      var blob = new Blob([JSON.stringify(data,null,2)], {type:"application/json"});
      var url = URL.createObjectURL(blob);
      var a = document.createElement("a");
      a.href = url; a.download = "balkoun-backup-"+new Date().toISOString().slice(0,10)+".json";
      document.body.appendChild(a); a.click(); document.body.removeChild(a);
      URL.revokeObjectURL(url);
      if(msgEl) msgEl.textContent=t("backupDone");
    }catch(e){ if(msgEl) msgEl.textContent=e.message||"error" }
    btn.disabled=false; btn.textContent=t("backupBtn");
  };
  if($("#dzRestoreUnlockBtn")) $("#dzRestoreUnlockBtn").onclick=function(){
    if(!confirm(t("restoreConfirm1"))) return;
    ADM.restoreUnlocked=true; render();
  };
  if($("#dzRestoreCancelBtn")) $("#dzRestoreCancelBtn").onclick=function(){
    ADM.restoreUnlocked=false; ADM.restoreFileInfo=""; ADM.restoreData=null; render();
  };
  if($("#dzRestoreFile")) $("#dzRestoreFile").onchange=function(){
    var file=this.files && this.files[0];
    var msgEl=$("#dzRestoreMsg");
    var previewEl=$("#dzRestorePreview");
    var confirmInput=$("#dzRestoreConfirmText");
    var restoreBtn=$("#dzRestoreBtn");
    // deliberately update these elements directly rather than calling
    // render() — a full re-render replaces the <input type="file">
    // itself via innerHTML, which resets its displayed filename back
    // to "no file chosen" even though the file was read successfully
    var refreshBtn=function(){
      if(restoreBtn) restoreBtn.disabled = !ADM.restoreData || (confirmInput||{}).value!=="RESTORE FROM BACKUP";
    };
    ADM.restoreData=null; ADM.restoreFileInfo="";
    if(previewEl) previewEl.textContent="";
    refreshBtn();
    if(!file) return;
    var reader=new FileReader();
    reader.onload=function(){
      try{
        var parsed=JSON.parse(reader.result);
        if(!parsed || !Array.isArray(parsed.listings)){
          if(msgEl) msgEl.textContent=t("restoreInvalidFile");
          refreshBtn(); return;
        }
        ADM.restoreData=parsed;
        ADM.restoreFileInfo=t("restorePreview")
          .replace("{n}", parsed.listings.length)
          .replace("{d}", parsed.exported_at ? new Date(parsed.exported_at).toLocaleDateString() : "—");
        if(previewEl) previewEl.textContent=ADM.restoreFileInfo;
        if(msgEl) msgEl.textContent="";
        refreshBtn();
      }catch(e){
        if(msgEl) msgEl.textContent=t("restoreInvalidFile");
        refreshBtn();
      }
    };
    reader.readAsText(file);
  };
  if($("#dzRestoreConfirmText")) $("#dzRestoreConfirmText").addEventListener("input",function(){
    var btn=$("#dzRestoreBtn"); if(btn) btn.disabled = this.value!=="RESTORE FROM BACKUP" || !ADM.restoreData;
  });
  if($("#dzRestoreBtn")) $("#dzRestoreBtn").onclick=async function(){
    if(($("#dzRestoreConfirmText")||{}).value!=="RESTORE FROM BACKUP" || !ADM.restoreData) return;
    if(!confirm(t("restoreConfirm2"))) return;
    var msgEl=$("#dzRestoreMsg"); var btn=this;
    btn.disabled=true; btn.textContent=t("saving");
    try{
      var r = await rpc("bk_admin_restore_backup",{p_token:ADM.token, p_data:ADM.restoreData, p_confirm:"RESTORE FROM BACKUP"});
      ADM.restoreUnlocked=false; ADM.restoreFileInfo=""; ADM.restoreData=null;
      D.LIST=[]; // clear stale public-facing data the admin's own session already loaded
      await adminLoad(); render();
      alert(t("restoreDone")+" ("+(r&&r.restored_listings!=null?r.restored_listings:"?")+")");
    }catch(e){ if(msgEl) msgEl.textContent=e.message||"error"; btn.disabled=false; btn.textContent=t("restoreBtn") }
  };
  if($("#dzUnlockBtn")) $("#dzUnlockBtn").onclick=function(){
    if(!confirm(t("dangerConfirm1"))) return;
    ADM.dangerUnlocked=true; render();
  };
  if($("#dzCancelBtn")) $("#dzCancelBtn").onclick=function(){
    ADM.dangerUnlocked=false; render();
  };
  if($("#dzConfirmText")) $("#dzConfirmText").addEventListener("input",function(){
    var btn=$("#dzResetBtn"); if(btn) btn.disabled = this.value!=="DELETE ALL LISTINGS";
  });
  if($("#dzResetBtn")) $("#dzResetBtn").onclick=async function(){
    if(($("#dzConfirmText")||{}).value!=="DELETE ALL LISTINGS") return;
    if(!confirm(t("dangerConfirm2Listings"))) return;
    var msgEl=$("#dzResetMsg"); var btn=this;
    btn.disabled=true; btn.textContent=t("saving");
    try{
      // clean up every listing's photo folder in storage BEFORE the
      // database rows disappear — same gap as the single-listing
      // delete had, fixed here too
      var idsToClean=(ADM.data&&ADM.data.listings||[]).map(function(l){return String(l.id)});
      for(var i=0;i<idsToClean.length;i++){ await trashListingFiles(idsToClean[i]); }
      var r = await rpc("bk_admin_reset_listings",{p_token:ADM.token, p_confirm:"DELETE ALL LISTINGS", p_country:admScope()});
      ADM.dangerUnlocked=false;
      D.LIST=[]; // clear the public-facing listings the admin's own session already loaded
      await adminLoad(); render();
      alert(t("dangerDone")+" ("+(r&&r.deleted!=null?r.deleted:"?")+")");
    }catch(e){ if(msgEl) msgEl.textContent=e.message||"error"; btn.disabled=false; btn.textContent=t("dangerResetBtn") }
  };
  if($("#dzAdsConfirmText")) $("#dzAdsConfirmText").addEventListener("input",function(){
    var btn=$("#dzAdsBtn"); if(btn) btn.disabled = this.value!=="DELETE ALL AD SQUARES";
  });
  if($("#dzAdsBtn")) $("#dzAdsBtn").onclick=async function(){
    if(($("#dzAdsConfirmText")||{}).value!=="DELETE ALL AD SQUARES") return;
    if(!confirm(t("dangerConfirm2Ads"))) return;
    var msgEl=$("#dzAdsMsg"); var btn=this;
    btn.disabled=true; btn.textContent=t("saving");
    try{
      if(ADM.scope==="ALL"){ await clearStorageFolder("photos/ads"); await clearStorageFolder("videos/ads"); }   // the folders are shared by every country: only an all-countries reset may empty them
      var r = await rpc("bk_admin_reset_ads",{p_token:ADM.token, p_confirm:"DELETE ALL AD SQUARES", p_country:admScope()});
      ADM.dangerUnlocked=false; ADM.adSlots=[]; AD_SLOTS=[];
      await adminLoad(); render();
      alert(t("dangerDone")+" ("+(r&&r.deleted!=null?r.deleted:"?")+")");
    }catch(e){ if(msgEl) msgEl.textContent=e.message||"error"; btn.disabled=false; btn.textContent=t("dangerAdsBtn") }
  };
  if($("#dzUsersConfirmText")) $("#dzUsersConfirmText").addEventListener("input",function(){
    var btn=$("#dzUsersBtn"); if(btn) btn.disabled = this.value!=="DELETE ALL USERS";
  });
  if($("#dzUsersBtn")) $("#dzUsersBtn").onclick=async function(){
    if(($("#dzUsersConfirmText")||{}).value!=="DELETE ALL USERS") return;
    if(!confirm(t("dangerConfirm2Users"))) return;
    var msgEl=$("#dzUsersMsg"); var btn=this;
    btn.disabled=true; btn.textContent=t("saving");
    try{
      var r = await rpc("bk_admin_reset_users",{p_token:ADM.token, p_confirm:"DELETE ALL USERS", p_country:admScope()});
      ADM.dangerUnlocked=false;
      await adminLoad(); render();
      alert(t("dangerDone")+" ("+(r&&r.deleted!=null?r.deleted:"?")+")");
    }catch(e){ if(msgEl) msgEl.textContent=e.message||"error"; btn.disabled=false; btn.textContent=t("dangerUsersBtn") }
  };

  // mode toggle (upload vs. link-to-a-listing) for every ad editor form
  // currently on screen, existing or new
  $$('input[name$="Mode"]').forEach(function(r){ r.onchange=function(){
    var pfx=this.name.replace(/Mode$/,"");
    var up=$("#"+pfx+"UploadWrap"), lk=$("#"+pfx+"LinkedWrap"), ve=$("#"+pfx+"VideoEmbedWrap");
    if(up) up.style.display = this.value==="upload" ? "" : "none";
    if(lk) lk.style.display = this.value==="linked" ? "" : "none";
    if(ve) ve.style.display = this.value==="video_embed" ? "" : "none";
  }});

  // file upload: read the file, shrink images (reusing the same helper
  // listing photos use), upload to Supabase Storage, and populate the
  // hidden fields the save handler reads from
                          (function wireFeaturedListingSearch(){
    var input=$("#ftListingSearch"), drop=$("#ftListingDrop"), hidden=$("#ftListing");
    if(!input||!drop||!hidden) return;
    var allListings=(ADM.data&&ADM.data.listings)||[];
    var renderMatches=function(q){
      var qq=(q||"").trim().toLowerCase();
      var matches = !qq ? allListings.slice(0,30) : allListings.filter(function(l){
        var ref=(l.ref||String(l.id)).toLowerCase();
        var name=(l.poster_name||"").toLowerCase();
        return ref.indexOf(qq)>-1 || name.indexOf(qq)>-1;
      }).slice(0,30);
      drop.innerHTML = matches.length ? matches.map(function(l){
        return '<div class="chipsel-opt" data-ftpicklisting="1" data-lid="'+l.id+'" data-lref="'+((l.ref||l.id)+"").replace(/"/g,"&quot;")+'" data-lname="'+((l.poster_name||"").replace(/"/g,"&quot;"))+'">'+
          (l.ref||l.id)+' — '+(l.poster_name||"")+' ($'+(l.price_usd||0).toLocaleString("en")+')</div>'}).join("")
        : '<div class="chipsel-empty">'+t("noResultsFor")+'</div>';
      $$(".chipsel-drop.on").forEach(function(d){ if(d!==drop) d.classList.remove("on") });
      drop.classList.add("on");
      $$('[data-ftpicklisting="1"]').forEach(function(opt){ opt.onclick=function(){
        hidden.value=this.dataset.lid;
        input.value=this.dataset.lref+(this.dataset.lname?" — "+this.dataset.lname:"");
        drop.classList.remove("on");
      }});
    };
    input.addEventListener("focus",function(){ renderMatches(this.value.indexOf("BK-")===0?"":this.value) });
    input.addEventListener("input",function(){ hidden.value=""; renderMatches(this.value); });
    input.addEventListener("click",function(e){ e.stopPropagation() });

  })();
  if(!window._adListingDropCloserAdded){
    window._adListingDropCloserAdded=true;
    document.addEventListener("click",function(){
      $$(".chipsel-drop.on").forEach(function(d){ d.classList.remove("on") });
    });
  }

      $$("[data-canceladedit]").forEach(function(e){ e.onclick=function(){
    if(this.dataset.canceladedit==="New") ADM.newAdOpen=false; else ADM.editAdId=null;
    render() }});
        if($("#scHeroGap")) $("#scHeroGap").oninput=function(){
    var lbl=$("#scHeroGapVal"); if(lbl) lbl.textContent=this.value+"px";
  };
  if($("#scHeroGapM")) $("#scHeroGapM").oninput=function(){ this.removeAttribute("data-empty"); var lbl=$("#scHeroGapMVal"); if(lbl) lbl.textContent=this.value+"px";
  };
                if($("#scVideoSave")) $("#scVideoSave").onclick=function(){
    var mb=Math.min(50, Math.max(5, parseInt(($("#scVideoMb")||{}).value,10)||50)), sec=Math.max(10, parseInt(($("#scVideoS")||{}).value,10)||90), n=Math.max(1, parseInt(($("#scVideoN")||{}).value,10)||1);
    saveSiteContent({extras:{video_enabled:!!($("#scVideoOn")||{}).checked, video_max_mb:mb, video_max_s:sec, video_max:n}},"scVideoMsg",this);
  };
  if($("#scStorageLimitSave")) $("#scStorageLimitSave").onclick=function(){
    var mb=parseInt(($("#scStorageLimit")||{}).value,10);
    if(isNaN(mb)||mb<1) mb=1024;
    saveSiteContent({storage_limit_mb:mb},"scStorageLimitMsg",this);
  };
  if($("#scSypRateSave")) $("#scSypRateSave").onclick=function(){
    var rate=parseInt(($("#scSypRate")||{}).value,10);
    if(isNaN(rate)||rate<1) rate=13500;
    saveSiteContent({syp_rate:rate},"scSypRateMsg",this);
  };

  if($("#notifAll")) $("#notifAll").onchange=function(){
    var w=$("#notifTargetWrap"); if(w) w.style.display=this.checked?"none":""
  };
  if($("#notifSend")) $("#notifSend").onclick=async function(){
    var all=($("#notifAll")||{}).checked;
    var target=($("#notifTarget")||{}).value;
    var title=($("#notifTitle")||{}).value||"";
    var bodyTxt=($("#notifBody")||{}).value||"";
    var msgEl=$("#notifSendMsg");
    if(!title.trim()){ if(msgEl) msgEl.textContent=t("nameRequired"); return }
    if(!all && !target){ if(msgEl) msgEl.textContent=t("chooseMember"); return }
    if(all && !confirm(GX("confirmSendAll").replace("{c}", ADM.scope==="ALL"?GX("cAll"):countryName(countryOf(COUNTRY)||{})))) return;
    this.disabled=true; this.textContent=t("saving");
    try{
      var r=await rpc("bk_admin_send_notification",{p_token:ADM.token,p_user:all?null:target,
        p_all:!!all, p_title:title, p_body:bodyTxt, p_country:admScope()});
      if(msgEl) msgEl.textContent=t("notifSentOk").replace("{n}", (r&&r.sent)||0);
      var ti=$("#notifTitle"); if(ti) ti.value=""; var bo=$("#notifBody"); if(bo) bo.value="";
    }catch(e){ if(msgEl) msgEl.textContent=e.message||"error" }
    this.disabled=false; this.textContent=t("send");
  };

  if($("#aNewAdminBtn")) $("#aNewAdminBtn").onclick=function(){
    ADM.newAdminOpen=true; ADM.newAdminMsg=""; render() };
  if($("#aNewAdminCancel")) $("#aNewAdminCancel").onclick=function(){
    ADM.newAdminOpen=false; render() };
  if($("#aNewAdminSave")) $("#aNewAdminSave").onclick=async function(){
    var name=($("#naName")||{}).value||"", ph="+"+($("#naCC")||{}).value+(($("#naPhone")||{}).value||"").replace(/\D/g,"");
    var pass=($("#naPass")||{}).value||"";
    var perms=$$(".naPerm:checked").map(function(c){return c.value});
    if(!name.trim()){ ADM.newAdminMsg=t("nameRequired"); render(); return }
    if(pass.length<6){ ADM.newAdminMsg=t("shortPass"); render(); return }
    try{
      await rpc("bk_admin_create_admin",{p_token:ADM.token,p_phone:ph,p_name:name,p_family:"",p_pass:pass,p_permissions:perms,p_countries:$$(".naCountry:checked").map(function(c){return c.value})});
      ADM.newAdminOpen=false; ADM._adminsLoaded=false;
      var r=await rpc("bk_admin_list_admins",{p_token:ADM.token}); ADM.admins=r||[]; render();
    }catch(e){ ADM.newAdminMsg=e.message||"error"; render() }
  };
  $$("[data-editperms]").forEach(function(e){ e.onclick=function(){
    ADM.editPermsFor=this.dataset.editperms; render() }});
  if($("#aEditPermsCancel")) $("#aEditPermsCancel").onclick=function(){
    ADM.editPermsFor=null; render() };
  $$("[data-saveperms]").forEach(function(e){ e.onclick=async function(){
    var id=this.dataset.saveperms;
    var perms=$$(".editPerm:checked").map(function(c){return c.value});
    try{
      await rpc("bk_admin_set_permissions",{p_token:ADM.token,p_admin:id,p_permissions:perms,p_countries:$$(".editCountry:checked").map(function(c){return c.value})});
      ADM.editPermsFor=null; ADM._adminsLoaded=false;
      var r=await rpc("bk_admin_list_admins",{p_token:ADM.token}); ADM.admins=r||[]; render(); admToast(t("savedOk"));
    }catch(e){ admToast(e.message||"error","bad") }
  }});
  $$("[data-tmnotify]").forEach(function(cb){ cb.onchange=async function(){ var id=this.dataset.tmnotify, on=this.checked, box=this; try{ if(id===ADM.meId) await rpc("bk_admin_me_set",{p_token:ADM.token,p_notify:on}); else await rpc("bk_admin_set_permissions",{p_token:ADM.token,p_admin:id,p_permissions:null,p_countries:null,p_notify:on}); admToast(t("savedOk")) }catch(e){ box.checked=!on; admToast(e.message||"error","bad") } } });
  $$("[data-tmunpair]").forEach(function(b){ b.onclick=async function(){ if(!confirm(GX("tmUnpairConfirm"))) return; try{ await rpc("bk_admin_tg_unpair",{p_token:ADM.token,p_admin:this.dataset.tmunpair}); ADM._adminsLoaded=false; ADM._meLoaded=false; render() }catch(e){ admToast(e.message||"error","bad") } } });
  $$("[data-tmpw]").forEach(function(b){ b.onclick=async function(){ var p=prompt(GX("tmNewPwPrompt")); if(p===null) return; if(p.length<6){ admToast(t("shortPass"),"bad"); return } try{ await rpc("bk_admin_reset_password",{p_token:ADM.token,p_user:this.dataset.tmpw,p_new_pass:p}); admToast(t("savedOk")) }catch(e){ admToast(e.message||"error","bad") } } });
  $$("[data-removeadmin]").forEach(function(e){ e.onclick=async function(){
    if(!confirm(t("confirmRemoveAdmin"))) return;
    var btn=this;
    try{
      await rpc("bk_admin_remove_admin",{p_token:ADM.token,p_admin:btn.dataset.removeadmin});
      ADM._adminsLoaded=false;
      var r=await rpc("bk_admin_list_admins",{p_token:ADM.token}); ADM.admins=r||[]; render();
    }catch(e){ alert(t("removeAdminFailed")+": "+(e.message||"error")) }
  }});

  // profile moderation
  $$("[data-clravatar]").forEach(function(e){ e.onclick=function(){
    act("bk_admin_clear_avatar",{p_token:ADM.token,p_user:e.dataset.clravatar}) }});
  $$("[data-clrbio]").forEach(function(e){ e.onclick=function(){
    act("bk_admin_clear_bio",{p_token:ADM.token,p_user:e.dataset.clrbio}) }});

  // instant client-side search — no reload, every tab
  var filterRows=function(bodyId, q, statusSel, tabuSel, dealSel){
    var body=$("#"+bodyId); if(!body) return;
    var qq=(q||"").toLowerCase();
    var visible=0;
    $$("tr",body).forEach(function(tr){
      var okText = !qq || (tr.dataset.rowText||"").indexOf(qq)>-1;
      var okStatus = !statusSel || !tr.dataset.rowStatus || tr.dataset.rowStatus===statusSel;
      var okTabu = !tabuSel || !tr.dataset.rowTabu || tr.dataset.rowTabu===tabuSel;
      var okDeal = !dealSel || !tr.dataset.rowDeal || tr.dataset.rowDeal===dealSel;
      var show = okText&&okStatus&&okTabu&&okDeal;
      tr.style.display = show ? "" : "none";
      if(show) visible++;
    });
    var countEl=$("#aListCount");
    if(countEl) countEl.innerHTML = '<span class="ltr">'+visible+'</span> '+t("listingsTab");
  };
    if($("#aqL")) $("#aqL").oninput=function(){ filterRows("aListBody", this.value, ($("#afStatus")||{}).value, ($("#afTabu")||{}).value, ($("#afDeal")||{}).value) };
  if($("#afStatus")) $("#afStatus").onchange=function(){ filterRows("aListBody", ($("#aqL")||{}).value, this.value, ($("#afTabu")||{}).value, ($("#afDeal")||{}).value) };
  if($("#afTabu")) $("#afTabu").onchange=function(){ filterRows("aListBody", ($("#aqL")||{}).value, ($("#afStatus")||{}).value, this.value, ($("#afDeal")||{}).value) };
  if($("#afDeal")) $("#afDeal").onchange=function(){ filterRows("aListBody", ($("#aqL")||{}).value, ($("#afStatus")||{}).value, ($("#afTabu")||{}).value, this.value) };
  if($("#aqU")) $("#aqU").oninput=function(){ filterRows("aUserBody", this.value, "") };
  ["report","feedback","ticket"].forEach(function(k){ var q=$("#aq"+k); if(!q) return; q.oninput=function(){ var v=this.value.trim().toLowerCase();
    $$("#inboxRows"+k+" [data-emailrow]").forEach(function(r){ r.style.display = (!v || ((r.dataset.rowText||"")+" "+r.textContent).toLowerCase().indexOf(v)>-1) ? "" : "none" }) } });

  $$("[data-goto]").forEach(function(e){ e.onclick=function(){
    var parts=e.dataset.goto.split(":");
    if(!canTab(parts[0])){ admToast(GX("noPermTab"),"bad"); return }
    ADM.tab=parts[0]; window._admMobileDetail=false; render();
    if(parts[1]){
      setTimeout(function(){
        var sel=$("#afStatus"); if(sel){ sel.value=parts[1];
          var ev=new Event("change"); sel.dispatchEvent(ev); }
      },0);
    }
    if(parts[2]){
      setTimeout(function(){
        var sel=$("#afTabu"); if(sel){ sel.value=parts[2];
          var ev=new Event("change"); sel.dispatchEvent(ev); }
      },0);
    }
  }});
  $$('input[name="mediaCat"]').forEach(function(e){ e.onchange=function(){
    ADM.mediaCategory = this.value; render();
  }});
  if($("#msQ")) $("#msQ").oninput=function(){
    ADM.mediaSearch = ADM.mediaSearch||{};
    var ms = ADM.mediaSearch[ADM.mediaCategory||"listings"] = ADM.mediaSearch[ADM.mediaCategory||"listings"]||{};
    ms.q = this.value; render();
    setTimeout(function(){ var el=$("#msQ"); if(el){ el.focus(); el.selectionStart=el.selectionEnd=el.value.length } },0);
  };
  if($("#msUsed")) $("#msUsed").onchange=function(){
    ADM.mediaSearch = ADM.mediaSearch||{};
    var ms = ADM.mediaSearch[ADM.mediaCategory||"listings"] = ADM.mediaSearch[ADM.mediaCategory||"listings"]||{};
    ms.used = this.value; render();
  };
  if($("#msSort")) $("#msSort").onchange=function(){
    ADM.mediaSearch = ADM.mediaSearch||{};
    var ms = ADM.mediaSearch[ADM.mediaCategory||"listings"] = ADM.mediaSearch[ADM.mediaCategory||"listings"]||{};
    ms.sort = this.value; render();
  };
  if($("#msType")) $("#msType").onchange=function(){
    ADM.mediaSearch = ADM.mediaSearch||{};
    var ms = ADM.mediaSearch[ADM.mediaCategory||"listings"] = ADM.mediaSearch[ADM.mediaCategory||"listings"]||{};
    ms.type = this.value; render();
  };
  $$(".msItemCheck").forEach(function(e){ e.onchange=function(){
    ADM.mediaSelected = ADM.mediaSelected||{};
    var cat = ADM.mediaCategory||"listings";
    var sel = ADM.mediaSelected[cat] = ADM.mediaSelected[cat]||{};
    if(this.checked) sel[this.dataset.selpath]=true; else delete sel[this.dataset.selpath];
    render();
  }});
  if($("#msSelectAll")) $("#msSelectAll").onchange=function(){
    // toggles only the checkboxes actually rendered right now — every
    // one of them already excludes "in use" items at render time, so
    // there is no path by which this can ever pick up a used file
    ADM.mediaSelected = ADM.mediaSelected||{};
    var cat = ADM.mediaCategory||"listings";
    var sel = ADM.mediaSelected[cat] = ADM.mediaSelected[cat]||{};
    var checked = this.checked;
    $$(".msItemCheck").forEach(function(box){
      if(checked) sel[box.dataset.selpath]=true; else delete sel[box.dataset.selpath];
    });
    render();
  };
  if($("#msDeleteSelected")) $("#msDeleteSelected").onclick=async function(){
    var cat = ADM.mediaCategory||"listings";
    var sel = (ADM.mediaSelected||{})[cat]||{};
    var paths = Object.keys(sel);
    if(!paths.length) return;
    if(!confirm(t("confirmDelMultiple").replace("{n}",paths.length))) return;
    this.disabled = true;
    var failed = [];
    for(var i=0;i<paths.length;i++){
      try{
        var r = await storageTrash([paths[i]]);
        // Supabase reports a storage RLS policy silently blocking a
        // delete as a normal-looking, error-free response with an
        // EMPTY data array — not an error. Checking only r.error, as
        // this used to, treats that as success. r.data must contain
        // the file that was actually removed.
        if((r && r.error) || !(r && r.data && r.data.length)) throw new Error();
      }catch(e){ failed.push(paths[i]); continue }
      ADM.mediaFiles[cat] = (ADM.mediaFiles[cat]||[]).filter(function(f){ return f.path!==paths[i] });
      delete sel[paths[i]];
    }
    if(failed.length) alert(t("someFilesFailedToDelete").replace("{n}",failed.length));
    render();
  };
  $$("[data-openphoto]").forEach(function(e){ e.onclick=function(){
    ADM.viewingPhotoIdx = +this.dataset.openphoto; render();
  }});
  if($("#photoViewerClose")) $("#photoViewerClose").onclick=function(){
    ADM.viewingPhotoIdx = null; render();
  };
  if($("#photoViewerOverlay")) $("#photoViewerOverlay").onclick=function(ev){
    if(ev.target===this){ ADM.viewingPhotoIdx = null; render() } // click the dark backdrop to close, same as clicking the visible X
  };
  if($("#photoViewerDelete")) $("#photoViewerDelete").onclick=async function(){
    if(!confirm(t("confirmDelFile"))) return;
    var photos = ADM.photosList||[];
    var idx = ADM.viewingPhotoIdx;
    var p = photos[idx]; if(!p) return;
    this.disabled = true;
    try{
      // database row goes first — if this fails, nothing else runs,
      // so a failed delete never leaves a listing pointing at a photo
      // file that's already gone (a broken image is worse than a
      // leftover orphaned file, which is what the reverse order risks)
      await rpc("bk_admin_photo_del",{p_token:ADM.token, p_photo:p.id});
      var okFull = await replaceStorageFile(p.url);
      var okThumb = p.thumb_url ? await replaceStorageFile(p.thumb_url) : true;
      ADM.photosList = photos.filter(function(x,i){ return i!==idx });
      ADM.viewingPhotoIdx = null;
      render();
      // the database record is genuinely gone either way (that part
      // can't silently fail here), but if the underlying file(s)
      // didn't actually delete, this photo has no listing anymore and
      // nowhere left to browse to and clean it up — worth a heads-up
      // rather than a quietly wasted upload sitting in storage forever
      if(!okFull || !okThumb) alert(t("photoRowDeletedFileNot"));
    }catch(err){ alert(err.message||"error"); this.disabled=false }
  };
  $$("[data-delfile]").forEach(function(e){ e.onclick=async function(){
    if(!confirm(t("confirmDelFile"))) return;
    var path = this.dataset.delfile;
    var cat = ADM.mediaCategory;
    this.disabled = true;
    // remove just this one thumbnail's own wrapper directly, instead
    // of calling the full render() — a full re-render rebuilds every
    // <img> in the gallery from scratch, forcing the browser to
    // re-decode all of them at once, which is what was showing up as
    // every other photo flashing/fading right after a single delete
    var card = this.parentElement;
    try{
      var r = await storageTrash([path]);
      // an RLS policy silently blocking the delete looks identical to
      // success here — no error, just an empty data array — so the
      // real check is that r.data actually contains the removed file
      if(r && r.error) throw new Error(r.error.message||"delete failed");
      if(!(r && r.data && r.data.length)) throw new Error(t("delBlockedByPolicy"));
      ADM.mediaFiles = ADM.mediaFiles||{};
      ADM.mediaFiles[cat] = (ADM.mediaFiles[cat]||[]).filter(function(f){ return f.path!==path });
      if(!ADM.mediaFiles[cat].length){ render(); return } // nothing left to disrupt — safe to switch to the "no files" message
      if(card && card.parentElement) card.parentElement.removeChild(card);
    }catch(err){ alert(err.message||"error"); this.disabled=false }
  }});
  $$("[data-delalert]").forEach(function(e){ e.onclick=function(){
    if(!confirm(t("confirmDeleteItem"))) return;
    act("bk_admin_delete_alert",{p_token:ADM.token,p_id:+this.dataset.delalert});
  }});
  $$("[data-emailfilter]").forEach(function(e){ e.onclick=function(){
    var parts=this.dataset.emailfilter.split(":");
    ADM["msgFilter"+(parts[0]==="report"?"Report":"Feedback")]=parts[1];
    render();
  }});
  $$("[data-emailrow]").forEach(function(e){ e.onclick=function(){
    var parts=this.dataset.emailrow.split(":");
    ADM[parts[0]==="report"?"selReportId":parts[0]==="feedback"?"selFeedbackId":"selTicketId"]=parts[1];
    window._admMobileDetail=true;
    render();
  }});
  $$("[data-emailback]").forEach(function(e){ e.onclick=function(){
    window._admMobileDetail=false;
    render();
  }});
  $$("[data-emaildelete]").forEach(function(e){ e.onclick=function(){
    if(!confirm(t("confirmDeleteItem"))) return;
    var parts=this.dataset.emaildelete.split(":");
    var kind=parts[0], id=parts[1];
    if(kind==="report"){ ADM.selReportId=null; act("bk_admin_delete_report",{p_token:ADM.token,p_id:+id}); }
    else if(kind==="feedback"){ ADM.selFeedbackId=null; act("bk_admin_delete_feedback",{p_token:ADM.token,p_id:+id}); }
    else if(kind==="ticket"){ ADM.selTicketId=null; rpc("bk_admin_ticket_delete",{p_token:ADM.token,p_id:+id}).then(tkReload).catch(function(e){ alert(e.message||"error") }) }
  }});
  // tech tickets
  if((ADM.tab==="tickets"||ADM.tab==="feedback"||ADM.tab==="reports") && (!ADM._ticketsLoaded || ADM._ticketsScope!==tkScopeKey())){ ADM._ticketsLoaded=true; ADM._ticketsScope=tkScopeKey(); rpcScoped("bk_admin_tickets",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM.tickets=r||[]; render() }).catch(function(){}) }
  $$("[data-toticket]").forEach(function(b){ b.onclick=async function(){ var k=this.dataset.toticket.split(":"); this.disabled=true; try{ var tk=await rpc("bk_admin_ticket_from",{p_token:ADM.token,p_kind:k[0],p_id:+k[1],p_country:admScope()}); ADM._ticketsLoaded=false; await adminLoad(); alert(GX("tkCreated").replace("{c}",tk&&tk.code||"")) }catch(e){ alert(e.message||"error"); this.disabled=false } } });
  $$("[data-tkopen]").forEach(function(a){ a.onclick=function(){ ADM.selTicketId=this.dataset.tkopen; admGo("tickets") } });
  $$("[data-tkstatus]").forEach(function(b){ b.onclick=function(){ var k=this.dataset.tkstatus.split(":"); rpc("bk_admin_ticket_set",{p_token:ADM.token,p_id:+k[0],p_status:k[1]}).then(tkReload).catch(function(e){ alert(e.message||"error") }) } });
  $$("[data-tkprio]").forEach(function(b){ b.onclick=function(){ var k=this.dataset.tkprio.split(":"); rpc("bk_admin_ticket_set",{p_token:ADM.token,p_id:+k[0],p_priority:k[1]}).then(tkReload).catch(function(e){ alert(e.message||"error") }) } });
  $$("[data-tksave]").forEach(function(b){ b.onclick=function(){ var id=+this.dataset.tksave, m=$("#tkMsg"+id), notes=($('[data-tknotes="'+id+'"]')||{}).value||"", title=($('[data-tktitle="'+id+'"]')||{}).value||""; if(m) m.textContent=t("saving"); rpc("bk_admin_ticket_set",{p_token:ADM.token,p_id:id,p_notes:notes,p_title:title}).then(function(){ if(m) m.textContent=t("savedOk"); tkReload() }).catch(function(e){ if(m) m.textContent=e.message||"error" }) } });
  $$("[data-tklink]").forEach(function(a){ a.onclick=function(e){ e.preventDefault(); var l=this.dataset.tklink; if(l.indexOf("#/admin:")>-1){ admGo(l.split("#/admin:")[1]) } else if(l.indexOf("#/listing/")>-1){ window.open(location.origin+"/listing/"+l.split("/listing/")[1],"_blank") } } });
  if($("#tkAddOpen")) $("#tkAddOpen").onclick=function(){ ADM.tkAddOpen=true; render(); var e=$("#tkTitle"); if(e) e.focus() };
  if($("#tkAdd")) $("#tkAdd").onclick=function(){ var m=$("#tkAddMsg"), ti=($("#tkTitle")||{}).value||""; if(ti.trim().length<2){ if(m) m.textContent=GX("tkTitleReq"); return } if(m) m.textContent=t("saving"); rpc("bk_admin_ticket_add",{p_token:ADM.token,p_title:ti,p_body:($("#tkBody")||{}).value||null,p_contact:($("#tkContact")||{}).value||null,p_priority:($("#tkPrio")||{}).value||"normal",p_country:COUNTRY}).then(function(tk){ ADM.selTicketId=tk&&tk.id; ADM.tkAddOpen=false; tkReload() }).catch(function(e){ if(m) m.textContent=e.message||"error" }) };
}
async function clearStorageFolder(folder){
  if(!DB || !DB.storage) return;
  try{
    var listed = await DB.storage.from("photos").list(folder);
    if(listed.error || !listed.data || !listed.data.length) return;
    var paths = listed.data.map(function(f){ return folder+"/"+f.name });
    await storageRemove(paths);
  }catch(e){}
}
function xNum(key,label,def,min,max,step){ return '<div class="fl"><label>'+label+'</label><input type="number" data-xkey="'+key+'" data-xtype="num" value="'+SX(key,"")+'" placeholder="'+def+'"'+(min!=null?' min="'+min+'"':'')+(max!=null?' max="'+max+'"':'')+(step?' step="'+step+'"':'')+'></div>' }
function xSelect(key,label,def,opts){ return '<div class="fl"><label>'+label+'</label><select data-xkey="'+key+'" data-xtype="str">'+opts.map(function(o){ return '<option value="'+o[0]+'"'+(SX(key,def)===o[0]?' selected':'')+'>'+o[1]+'</option>' }).join("")+'</select></div>' }
var HS_PAGES={home:{url:"/",sel:"hero_text"},ads:{url:"/",sel:"row"},banners:{url:"/",sel:"b:0"},design:{url:"/search?deal=sale",sel:"cards"},contact:{url:"/?view=contactus",sel:"social"}};
function hsPvUrl(){ var u=HS_PAGES[HS.page].url; return u+(u.indexOf("?")>-1?"&":"?")+"preview=1&country="+COUNTRY+"&lang="+hsLang() }
var HS_T={
 desk:{ar:"كمبيوتر",en:"Desktop",de:"Desktop"}, phone:{ar:"جوال",en:"Phone",de:"Handy"},
 saveAll:{ar:"حفظ التغييرات",en:"Save changes",de:"Änderungen speichern"}, discard:{ar:"تراجع",en:"Discard",de:"Verwerfen"},
 dirty:{ar:"تغييرات غير محفوظة — تظهر في المعاينة فقط",en:"Unsaved changes — preview only",de:"Ungespeicherte Änderungen – nur Vorschau"}, clean:{ar:"كل شيء محفوظ",en:"Everything saved",de:"Alles gespeichert"},
 openSite:{ar:"فتح الموقع",en:"Open site",de:"Seite öffnen"}, reload:{ar:"تحديث المعاينة",en:"Reload preview",de:"Vorschau neu laden"},
 sections:{ar:"أقسام الصفحة",en:"Page sections",de:"Seitenabschnitte"},
 sectionsHint:{ar:"اضغط قسماً لتعديله. العين تُظهر أو تُخفي القسم، والأسهم تغيّر ترتيبه في الصفحة. الأول (الترحيب) ثابت في الأعلى.",en:"Click a section to edit it. The eye shows or hides it, the arrows move it up or down the page. The hero stays first.",de:"Abschnitt anklicken zum Bearbeiten. Das Auge zeigt oder versteckt ihn, die Pfeile verschieben ihn. Der Hero bleibt oben."},
 hero:{ar:"القسم الأول (الترحيب)",en:"Hero",de:"Hero"}, hero_text:{ar:"العنوان الرئيسي",en:"Headline",de:"Überschrift"},
 hero_bg:{ar:"الخلفية والرسم",en:"Background and drawing",de:"Hintergrund und Zeichnung"}, hero_search:{ar:"شريط البحث",en:"Search bar",de:"Suchleiste"},
 hero_stats:{ar:"سطر الإحصائيات",en:"Stats line",de:"Statistikzeile"},
 ads:{ar:"المربعات الإعلانية",en:"Ad squares",de:"Werbekacheln"}, banners:{ar:"البانرات",en:"Banners",de:"Banner"},
 ticker:{ar:"نبض السوق",en:"Market pulse",de:"Marktpuls"}, colls:{ar:"مجموعات مختارة",en:"Collections",de:"Sammlungen"},
 types:{ar:"أنواع العقارات",en:"Property types",de:"Objektarten"},
 trust:{ar:"لماذا بلكون",en:"Why Balkoun",de:"Warum Balkoun"}, expl:{ar:"استكشف المناطق",en:"Explore areas",de:"Gebiete entdecken"},
 band:{ar:"شريط المالكين",en:"Owners band",de:"Eigentümer-Band"}, guides:{ar:"دليل المشتري",en:"Buyer's guide",de:"Käuferratgeber"},
 projects:{ar:"مشاريع جديدة",en:"New projects",de:"Neubau"}, f_pjN:{ar:"عدد المشاريع في القسم",en:"Projects shown in the section",de:"Projekte im Abschnitt"},
 wanted:{ar:"مطلوب",en:"Wanted",de:"Gesucht"}, f_wN:{ar:"عدد الطلبات في القسم",en:"Requests shown in the section",de:"Anfragen im Abschnitt"}, g_wanted:{ar:"إعدادات قسم مطلوب",en:"Wanted section settings",de:"Einstellungen Gesucht"}, f_wEnabled:{ar:"تفعيل قسم مطلوب في الموقع (الصفحة والقائمة)",en:"Enable the Wanted section (page and menu)",de:"Gesucht-Bereich aktivieren (Seite und Menü)"}, f_wApproval:{ar:"نشر الطلبات الجديدة",en:"New requests go live",de:"Neue Anfragen erscheinen"}, wa_auto:{ar:"فوراً بدون مراجعة",en:"immediately",de:"sofort"}, wa_manual:{ar:"بعد موافقة الإدارة",en:"after admin approval",de:"nach Freigabe"},
 page:{ar:"الحركة والمسافات",en:"Motion and spacing",de:"Bewegung und Abstände"},
 editing:{ar:"القيم الآن لـ",en:"Editing values for",de:"Werte für"}, same:{ar:"مثل الكمبيوتر",en:"Same as desktop",de:"Wie Desktop"},
 useDesk:{ar:"استخدم قيمة الكمبيوتر",en:"Use the desktop value",de:"Desktop-Wert verwenden"},
 show:{ar:"إظهار / إخفاء",en:"Show / hide",de:"Zeigen / verstecken"}, up:{ar:"أعلى",en:"Up",de:"Nach oben"}, down:{ar:"أسفل",en:"Down",de:"Nach unten"},
 showSec:{ar:"إظهار هذا القسم في الصفحة",en:"Show this section on the page",de:"Diesen Abschnitt anzeigen"},
 textsHint:{ar:"النصوص تُعدَّل بلغة المعاينة المختارة في الأعلى. اترك الحقل فارغاً للنص الافتراضي.",en:"Texts are edited in the preview language chosen above. Leave a field empty for the default text.",de:"Texte werden in der oben gewählten Vorschausprache bearbeitet. Leer = Standardtext."},
 dualHint:{ar:"قيم الموضع والحجم تُحفظ مرتين: للكمبيوتر وللجوال. بدّل الجهاز في الأعلى لتعديل كل منهما؛ الجوال يرث قيمة الكمبيوتر إن تركته فارغاً.",en:"Position and size values are stored twice, for desktop and phone. Switch the device above to edit each; an empty phone value inherits the desktop one.",de:"Positions- und Größenwerte werden doppelt gespeichert (Desktop/Handy). Oben umschalten; leerer Handy-Wert erbt vom Desktop."},
 f_heroOn:{ar:"إظهار العنوان الرئيسي",en:"Show the headline",de:"Überschrift anzeigen"}, g_text:{ar:"النص",en:"Text",de:"Text"},
 f_h1:{ar:"العنوان",en:"Headline",de:"Überschrift"}, f_h1b:{ar:"الجزء المميّز (يتقلّب إلى اسم المنصة)",en:"Highlighted part (flips to the brand)",de:"Hervorgehobener Teil (wechselt zur Marke)"},
 f_flipAr:{ar:"الكلمة قبل «بلكون» بعد التقلّب (عربي)",en:"Word before “Balkoun” after the flip (Arabic)",de:"Wort vor „Balkoun“ nach dem Wechsel (Arabisch)"}, f_flipLatin:{ar:"النص اللاتيني بعد التقلّب",en:"Latin text after the flip",de:"Lateinischer Text nach dem Wechsel"},
 g_look:{ar:"الشكل والموضع",en:"Look and position",de:"Aussehen und Position"}, f_h1Color:{ar:"لون العنوان",en:"Headline color",de:"Farbe der Überschrift"}, f_h1bColor:{ar:"لون الجزء المميّز",en:"Highlight color",de:"Farbe der Hervorhebung"},
 f_size:{ar:"حجم الخط (px)",en:"Font size (px)",de:"Schriftgröße (px)"}, f_x:{ar:"إزاحة أفقية (px)",en:"Horizontal offset (px)",de:"Horizontaler Versatz (px)"}, f_y:{ar:"إزاحة رأسية (px)",en:"Vertical offset (px)",de:"Vertikaler Versatz (px)"},
 f_heroGap:{ar:"المسافة تحت القسم الأول",en:"Space below the hero",de:"Abstand unter dem Hero"},
 f_bgType:{ar:"نوع الخلفية",en:"Background type",de:"Hintergrundart"}, f_bgCredit:{ar:"سطر حقوق الصورة (يظهر صغيراً في الزاوية)",en:"Photo credit line (small, in the corner)",de:"Bildnachweis (klein, in der Ecke)"}, bg_none:{ar:"بدون خلفية (لون كحلي)",en:"None (navy color)",de:"Keiner (Marineblau)"}, bg_video:{ar:"فيديو",en:"Video",de:"Video"}, bg_photo:{ar:"صورة",en:"Photo",de:"Foto"}, bg_dawn:{ar:"رسم فجر دمشق المتحرك",en:"Animated Damascus dawn",de:"Animierte Damaskus-Dämmerung"}, bg_sketch:{ar:"رسم دمشق بخطوط ذهبية",en:"Damascus in gold lines",de:"Damaskus in Goldlinien"}, bg_sketch_LB:{ar:"رسم الروشة في بيروت بخطوط ذهبية",en:"Raouché, Beirut, in gold lines",de:"Raouché, Beirut, in Goldlinien"}, bg_scene3d_LB:{ar:"مشهد الروشة ثلاثي الأبعاد (حيّ)",en:"Raouché live 3D scene",de:"Raouché als 3D-Szene"},
 f_speed:{ar:"سرعة الفيديو",en:"Video speed",de:"Videogeschwindigkeit"}, f_upVideo:{ar:"فيديو الخلفية",en:"Background video",de:"Hintergrundvideo"}, f_upPhoto:{ar:"صورة الخلفية",en:"Background photo",de:"Hintergrundfoto"}, f_upPhotoM:{ar:"نسخة الهاتف (اختيارية)",en:"Phone version (optional)",de:"Handy-Version (optional)"}, f_upPhotoMHint:{ar:"صورة أصغر أو مقصوصة تُحمَّل على الهواتف بدل الصورة الكبيرة. إن تُركت فارغة تُستخدم الصورة الكبيرة.",en:"A smaller or cropped copy served to phones instead of the large photo. Leave empty to use the large photo everywhere.",de:"Eine kleinere oder beschnittene Kopie für Handys. Leer lassen, um überall das große Foto zu verwenden."},
 g_draw:{ar:"الرسم (الجامع الأموي والساحة)",en:"The drawing (mosque and square)",de:"Die Zeichnung (Moschee und Platz)"}, f_scale:{ar:"المقياس (%)",en:"Scale (%)",de:"Skalierung (%)"},
 f_heroMax:{ar:"أقصى ارتفاع للقسم الأول على الكمبيوتر (px)",en:"Maximum hero height on desktop (px)",de:"Maximale Hero-Höhe am Desktop (px)"},
 f_sbY:{ar:"الموضع الرأسي (px)",en:"Vertical position (px)",de:"Vertikale Position (px)"}, f_sbGlow:{ar:"وميض ذهبي متحرك حول شريط البحث",en:"Moving golden shine around the search bar",de:"Wandernder Goldglanz um die Suchleiste"}, g_aiBar:{ar:"شريط البحث الذكي (AI)",en:"AI search bar",de:"KI-Suchleiste"}, f_aiOn:{ar:"إظهار شريط البحث الذكي تحت شريط البحث",en:"Show the AI search bar under the search bar",de:"KI-Suchleiste unter der Suchleiste anzeigen"}, f_aiY:{ar:"موضع الشريط الذكي عمودياً (px)",en:"AI bar vertical position (px)",de:"Vertikale Position der KI-Leiste (px)"}, f_aiGlass:{ar:"شريط ذكي شفاف (زجاجي)",en:"Glass (transparent) AI bar",de:"Transparente (Glas-)KI-Leiste"}, f_aiHint:{ar:"الشريط الذكي يتبع شريط البحث الرئيسي (العرض والارتفاع وإزاحته العمودية) ثم يُضاف إليه موضعه الخاص أعلاه: موجب = أسفل، سالب = أعلى.",en:"The AI bar follows the main bar (width, height and its vertical offset), then adds its own position above: positive = down, negative = up.",de:"Die KI-Leiste folgt der Hauptleiste (Breite, Höhe, vertikaler Versatz) und addiert dann ihre eigene Position: positiv = nach unten, negativ = nach oben."}, f_sbGlass:{ar:"شريط بحث شفاف (زجاجي) على الكمبيوتر",en:"Transparent (glass) search bar on desktop",de:"Transparente (Glas-)Suchleiste am Computer"}, f_sbGlassM:{ar:"شريط بحث شفاف (زجاجي) على الهاتف",en:"Transparent (glass) search bar on phones",de:"Transparente (Glas-)Suchleiste am Handy"}, f_sbGlassHint:{ar:"يظهر الشريط زجاجياً فوق صورة الخلفية مع إبقاء الحقول بإطار صلب واضح للقراءة.",en:"The bar turns to glass over the background photo while the fields keep a solid, readable frame.",de:"Die Leiste wird über dem Hintergrundfoto glasig, die Felder behalten einen festen, lesbaren Rahmen."}, f_sbW:{ar:"أقصى عرض (px)",en:"Maximum width (px)",de:"Maximale Breite (px)"}, f_sbH:{ar:"ارتفاع الحقول (px)",en:"Field height (px)",de:"Feldhöhe (px)"},
 f_statsOn:{ar:"إظهار سطر الإحصائيات",en:"Show the stats line",de:"Statistikzeile anzeigen"}, f_realCount:{ar:"استخدام العدد الحقيقي للإعلانات",en:"Use the real listing count",de:"Echte Anzeigenzahl verwenden"},
 f_areasNum:{ar:"رقم عدد المناطق",en:"Areas number",de:"Anzahl Gebiete"}, f_listNum:{ar:"رقم عدد الإعلانات",en:"Listings number",de:"Anzahl Anzeigen"}, f_stats1:{ar:"العبارة الأولى",en:"First phrase",de:"Erste Phrase"}, f_stats2:{ar:"العبارة الثانية",en:"Second phrase",de:"Zweite Phrase"},
 f_adsOn:{ar:"إظهار صف المربعات تحت شريط البحث",en:"Show the ad row under the search bar",de:"Werbereihe unter der Suchleiste zeigen"}, f_adsTitle:{ar:"عنوان الصف",en:"Row title",de:"Titel der Reihe"}, f_adsSponsored:{ar:"كلمة «إعلان مدفوع»",en:"“Sponsored” word",de:"Wort „Gesponsert“"},
 f_adSize:{ar:"حجم المربع (px)",en:"Square size (px)",de:"Kachelgröße (px)"}, f_adGap:{ar:"موضع الصف رأسياً",en:"Row vertical position",de:"Vertikale Position der Reihe"}, f_adGlide:{ar:"ثوانٍ لكل مربع",en:"Seconds per square",de:"Sekunden pro Kachel"},
 go_ads:{ar:"كل إعدادات المربعات والإعلانات",en:"All ad square settings",de:"Alle Kachel-Einstellungen"}, go_banners:{ar:"إدارة البانرات",en:"Manage banners",de:"Banner verwalten"},
 bannersHint:{ar:"البانرات الثلاثة ومحتواها تُدار في صفحة البانرات. هنا فقط تُظهر أو تُخفي شريط البانرات من الصفحة الرئيسية.",en:"The three banners and their content live on the Banners page. Here you only show or hide the banner strip on the homepage.",de:"Die drei Banner werden auf der Banner-Seite verwaltet. Hier nur Ein-/Ausblenden auf der Startseite."},
 f_eyebrow:{ar:"السطر الصغير فوق العنوان",en:"Small line above the title",de:"Kleine Zeile über dem Titel"}, f_h:{ar:"العنوان",en:"Title",de:"Titel"}, f_sub:{ar:"الوصف",en:"Description",de:"Beschreibung"},
 f_credit:{ar:"إظهار سطر مصدر الصور",en:"Show the photo credit line",de:"Fotonachweis anzeigen"}, card:{ar:"البطاقة",en:"Card",de:"Karte"}, f_cardOn:{ar:"إظهار البطاقة",en:"Show the card",de:"Karte anzeigen"},
 f_cardT:{ar:"عنوان البطاقة",en:"Card title",de:"Kartentitel"}, f_cardS:{ar:"السطر الثاني",en:"Second line",de:"Zweite Zeile"}, f_gov:{ar:"المحافظة التي تُفتح عند الضغط",en:"Governorate opened on click",de:"Gouvernement beim Klick"}, f_img:{ar:"الصورة",en:"Photo",de:"Foto"},
 f_p:{ar:"النص",en:"Text",de:"Text"}, point:{ar:"النقطة",en:"Point",de:"Punkt"}, f_map:{ar:"إظهار خريطة سوريا بجانب القائمة",en:"Show the Syria map beside the list",de:"Syrien-Karte neben der Liste zeigen"},
 f_b:{ar:"العبارة",en:"Phrase",de:"Phrase"}, f_btn:{ar:"نص الزر",en:"Button text",de:"Button-Text"}, bandHint:{ar:"يظهر هذا الشريط للزوار غير المسجّلين فقط.",en:"This band shows to visitors who are not logged in.",de:"Dieses Band sehen nur nicht angemeldete Besucher."},
 tickerHint:{ar:"يظهر فقط عندما تتوفر أسعار كافية (٤ مناطق على الأقل بثلاثة إعلانات فأكثر).",en:"Shows only when enough prices exist (at least 4 areas with 3+ listings).",de:"Erscheint nur bei genug Preisen (mind. 4 Gebiete mit 3+ Anzeigen)."},
 devOnlyHint:{ar:"تظهر هنا خيارات الجهاز المختار في الأعلى فقط؛ بدّل إلى الجوال لترى خياراته.",en:"Only the options for the device chosen above are shown; switch to Phone to see its options.",de:"Nur die Optionen des oben gewählten Geräts werden gezeigt; auf Handy umschalten für dessen Optionen."},
 f_opening:{ar:"مشهد الافتتاح (كلمة بلكون تصعد ثم يهبط الرأس)",en:"Opening scene (the word rises, then the header drops in)",de:"Eröffnungsszene (Wort steigt, Kopfzeile fällt ein)"}, f_cursor:{ar:"نقطة المؤشر الذهبية (كمبيوتر)",en:"Gold cursor dot (desktop)",de:"Goldener Cursorpunkt (Desktop)"},
 f_phMode:{ar:"العنوان على الجوال",en:"Headline on the phone",de:"Überschrift am Handy"}, ph_after:{ar:"يدخل بعد انتهاء الرسم ويدفعه جانباً",en:"Enters after the drawing rests and pushes it aside",de:"Kommt nach der Zeichnung und schiebt sie beiseite"}, ph_now:{ar:"يظهر مباشرة فوق الرسم",en:"Shows immediately over the drawing",de:"Sofort über der Zeichnung"},
 f_secPad:{ar:"المسافة بين الأقسام (px)",en:"Space between sections (px)",de:"Abstand zwischen Abschnitten (px)"},
 g_logo:{ar:"الشعار",en:"Logo",de:"Logo"}, g_pwa:{ar:"التطبيق على الهاتف",en:"Phone app",de:"Handy-App"}, f_pwaBanner:{ar:"إظهار شريط «ثبّت التطبيق» على الهاتف",en:"Show the install-app bar on phones",de:"Leiste 'App installieren' auf Handys zeigen"}, f_pwaDays:{ar:"إعادة إظهاره بعد (أيام)",en:"Show again after (days)",de:"Erneut zeigen nach (Tagen)"}, f_logoVar:{ar:"شكل الشعار في الترويسة والقائمة",en:"Logo in the header and menu",de:"Logo in Kopfzeile und Menü"}, lv_full:{ar:"الرمز + بلكون + BALKOUN",en:"Mark + بلكون + BALKOUN",de:"Zeichen + بلكون + BALKOUN"}, lv_mw:{ar:"الرمز + بلكون",en:"Mark + بلكون",de:"Zeichen + بلكون"}, lv_word:{ar:"الاسم فقط",en:"Name only",de:"Nur der Name"}, f_logoH:{ar:"ارتفاع الرمز (px)",en:"Mark height (px)",de:"Höhe des Zeichens (px)"}, g_motion:{ar:"الحركة",en:"Motion",de:"Bewegung"}, g_spacing:{ar:"المسافات",en:"Spacing",de:"Abstände"},
 upload:{ar:"رفع ملف…",en:"Upload…",de:"Hochladen…"}, uploading:{ar:"جارٍ الرفع…",en:"Uploading…",de:"Lädt hoch…"}, clearImg:{ar:"الافتراضية",en:"Default",de:"Standard"},
 previewNote:{ar:"المعاينة هي الصفحة الحقيقية بإعداداتك غير المحفوظة. لا تُسجَّل زياراتها في الإحصائيات.",en:"The preview is the real page with your unsaved settings. Its visits are not counted in analytics.",de:"Die Vorschau ist die echte Seite mit ungespeicherten Einstellungen. Ihre Aufrufe zählen nicht."},
 row:{ar:"إعدادات الصف",en:"Row settings",de:"Reihe"}, look:{ar:"شكل المربع",en:"Square design",de:"Kachel-Design"}, perf:{ar:"الأداء",en:"Performance",de:"Leistung"},
 squares:{ar:"المربعات",en:"The squares",de:"Die Kacheln"}, adNew:{ar:"مربع جديد",en:"New square",de:"Neue Kachel"}, addSquare:{ar:"+ إضافة مربع",en:"+ Add a square",de:"+ Kachel hinzufügen"},
 delSquare:{ar:"حذف هذا المربع",en:"Delete this square",de:"Diese Kachel löschen"}, unsaved:{ar:"غير محفوظ",en:"unsaved",de:"ungespeichert"},
 adMedia:{ar:"الوسائط",en:"Media",de:"Medien"}, adSchedule:{ar:"الجدولة",en:"Schedule",de:"Zeitplan"}, adTexts:{ar:"النصوص",en:"Texts",de:"Texte"}, adInfo:{ar:"الأساسيات",en:"Basics",de:"Grundlagen"},
 adClearMedia:{ar:"إزالة الوسائط",en:"Remove media",de:"Medien entfernen"}, adSaveHint:{ar:"يُحفظ المربع مع زر «حفظ التغييرات» في الأعلى. المعاينة تعرضه فوراً.",en:"The square is saved with the “Save changes” button at the top. The preview shows it right away.",de:"Die Kachel wird mit „Änderungen speichern“ oben gespeichert. Die Vorschau zeigt sie sofort."},
 adMoveHint:{ar:"الأسهم تغيّر ترتيب المربعات فوراً (بعد الحفظ للمربع الجديد).",en:"The arrows reorder the squares immediately (a new square must be saved first).",de:"Die Pfeile ändern die Reihenfolge sofort (neue Kachel zuerst speichern)."},
 strip:{ar:"شريط البانرات في الصفحة",en:"Banner strip on the page",de:"Bannerleiste auf der Seite"}, banner:{ar:"بانر",en:"Banner",de:"Banner"},
 bSlot:{ar:"مكان الشريط",en:"Where the strip sits",de:"Position der Leiste"}, bSlotFlow:{ar:"بين أقسام الصفحة (حسب الترتيب بالأسهم)",en:"Between the page sections (ordered with the arrows)",de:"Zwischen den Abschnitten (Reihenfolge per Pfeile)"}, bSlotTop:{ar:"أعلى الصفحة، فوق العنوان الرئيسي",en:"Top of the page, above the headline",de:"Ganz oben, über der Überschrift"},
 bItems:{ar:"الصور والفيديوهات (تتبدّل بالتناوب)",en:"Photos and videos (rotate in turn)",de:"Fotos und Videos (wechseln ab)"}, bItemLink:{ar:"رابط هذه الصورة",en:"Link for this item",de:"Link für dieses Element"},
 bSize:{ar:"الحجم",en:"Size",de:"Größe"}, bSizeM:{ar:"الحجم على الجوال",en:"Size on the phone",de:"Größe am Handy"}, bFull:{ar:"بعرض الشاشة",en:"Full width",de:"Volle Breite"}, bCustom:{ar:"مخصص",en:"Custom",de:"Eigene Größe"},
 bPos:{ar:"الموضع",en:"Position",de:"Position"}, bHPos:{ar:"الموضع الأفقي (%)",en:"Horizontal position (%)",de:"Horizontale Position (%)"}, bVOff:{ar:"الإزاحة الرأسية (px)",en:"Vertical offset (px)",de:"Vertikaler Versatz (px)"},
 bRot:{ar:"التناوب والحركة",en:"Rotation and motion",de:"Wechsel und Bewegung"}, bText:{ar:"نص فوق البانر",en:"Text over the banner",de:"Text über dem Banner"}, bLink:{ar:"الرابط الافتراضي عند الضغط",en:"Default link on click",de:"Standard-Link beim Klick"},
 stripHint:{ar:"يظهر شريط البانرات بين أقسام الصفحة الرئيسية؛ موضعه بينها يُضبط بالأسهم في استوديو الصفحة الرئيسية.",en:"The banner strip sits between the homepage sections; its place among them is set with the arrows in the homepage studio.",de:"Die Bannerleiste liegt zwischen den Startseiten-Abschnitten; ihre Position wird im Startseiten-Studio festgelegt."},
 goHome:{ar:"استوديو الصفحة الرئيسية",en:"Homepage studio",de:"Startseiten-Studio"}, bEmptyHint:{ar:"ارفع صورة أو فيديو ليظهر البانر في المعاينة.",en:"Upload a photo or video and the banner appears in the preview.",de:"Foto oder Video hochladen, dann erscheint das Banner in der Vorschau."},
 rsMapDef:{ar:"إظهار الخريطة بجانب النتائج على الكمبيوتر (افتراضياً)",en:"Show the map beside the results on desktop (by default)",de:"Karte neben den Ergebnissen am Desktop (Standard)"},
 rsMarket:{ar:"إظهار متوسط سعر المتر تحت عنوان النتائج",en:"Show the average price per m² under the results title",de:"Ø Preis pro m² unter dem Ergebnistitel zeigen"},
 rsHint:{ar:"الزائر يستطيع إخفاء الخريطة أو إظهارها بنفسه؛ يُحفظ اختياره في جهازه.",en:"Visitors can hide or show the map themselves; the choice is remembered on their device.",de:"Besucher können die Karte selbst ein- oder ausblenden; die Wahl wird im Gerät gespeichert."},
 welcome:{ar:"رسالة الترحيب",en:"Welcome message",de:"Willkommensnachricht"},
 watermark:{ar:"العلامة المائية والحماية",en:"Watermark and protection",de:"Wasserzeichen und Schutz"}, wmHint:{ar:"يُطبع شعار بلكون داخل صور الإعلانات وصور الفيديو عند رفعها، فيبقى حتى لو حُفظت الصورة. الصور المرفوعة قبل التشغيل لا تتغيّر.",en:"The Balkoun mark is stamped into listing photos and video posters at upload, so it stays even if the image is saved. Photos uploaded before this was on are not changed.",de:"Das Balkoun-Zeichen wird beim Hochladen in Anzeigenfotos und Videoposter gestempelt und bleibt auch beim Speichern erhalten. Früher hochgeladene Fotos ändern sich nicht."},
 wmOn:{ar:"طباعة الشعار في الصور عند الرفع",en:"Stamp the mark into photos at upload",de:"Zeichen beim Hochladen in Fotos stempeln"}, wmPos:{ar:"موضع الشعار",en:"Mark position",de:"Position des Zeichens"}, wm_br:{ar:"أسفل اليمين",en:"Bottom right",de:"Unten rechts"}, wm_bl:{ar:"أسفل اليسار",en:"Bottom left",de:"Unten links"}, wm_tr:{ar:"أعلى اليمين",en:"Top right",de:"Oben rechts"}, wm_tl:{ar:"أعلى اليسار",en:"Top left",de:"Oben links"},
 wmSize:{ar:"حجم الشعار (% من عرض الصورة)",en:"Mark size (% of photo width)",de:"Größe (% der Fotobreite)"}, wmOp:{ar:"شفافية الشعار",en:"Mark opacity",de:"Deckkraft"}, wmVideoH:{ar:"الفيديو",en:"Video",de:"Video"}, wmVideo:{ar:"إظهار الشعار فوق مشغّل الفيديو",en:"Show the mark over the video player",de:"Zeichen über dem Videoplayer zeigen"},
 wmLockH:{ar:"حماية الوسائط",en:"Media protection",de:"Medienschutz"}, wmLock:{ar:"منع الحفظ بالزر الأيمن والسحب والضغط المطوّل",en:"Block right-click, drag and long-press saving",de:"Speichern per Rechtsklick, Ziehen und langem Drücken blockieren"}, wmLockHint:{ar:"يصعّب الحفظ ولا يمنعه تماماً: لقطة الشاشة تبقى ممكنة، لذلك الحماية الحقيقية هي الشعار المطبوع.",en:"Makes saving harder but cannot prevent it: a screenshot is always possible, so the stamped mark is the real protection.",de:"Erschwert das Speichern, verhindert es aber nicht: ein Screenshot bleibt möglich, der echte Schutz ist das gestempelte Zeichen."}, wlOn:{ar:"إرسال رسالة ترحيب لكل عضو جديد",en:"Send a welcome message to every new member",de:"Jedem neuen Mitglied eine Willkommensnachricht senden"}, wlHint:{ar:"تظهر في جرس الإشعارات بعد إنشاء الحساب مباشرة، بلغة الزائر نفسها. اتركي الحقول فارغة لاستخدام النص الافتراضي.",en:"Shows in the notification bell right after sign-up, in the visitor's own language. Leave the fields empty to use the default text.",de:"Erscheint direkt nach der Registrierung in der Glocke, in der Sprache des Besuchers. Leer lassen für den Standardtext."}, wlTitle:{ar:"العنوان",en:"Title",de:"Titel"}, wlBody:{ar:"النص",en:"Text",de:"Text"},
 cards:{ar:"بطاقات النتائج",en:"Result cards",de:"Ergebniskarten"}, badges:{ar:"الشارات",en:"Badges",de:"Abzeichen"}, results:{ar:"صفحة النتائج",en:"Results page",de:"Ergebnisseite"}, nav:{ar:"الرأس والقائمة",en:"Header and menu",de:"Kopfzeile und Menü"},
 cardW:{ar:"أصغر عرض للبطاقة (px)",en:"Minimum card width (px)",de:"Mindestbreite der Karte (px)"}, cardHint:{ar:"كلما صغُر الرقم زاد عدد البطاقات في الصف.",en:"The smaller the number, the more cards fit in a row.",de:"Je kleiner die Zahl, desto mehr Karten pro Reihe."},
 social:{ar:"حسابات التواصل",en:"Social accounts",de:"Soziale Konten"}, numbers:{ar:"أرقام التواصل",en:"Contact numbers",de:"Kontaktnummern"},
 contactHint:{ar:"تظهر في صفحة «تواصل معنا» (المعاينة) وفي أزرار الاتصال عبر الموقع. يظهر الحساب فقط عندما يُملأ الرابط والاسم معاً.",en:"Shown on the “Contact us” page (the preview) and in the contact buttons across the site. An account appears only when both its link and name are filled.",de:"Erscheint auf der Kontaktseite (Vorschau) und in den Kontakt-Buttons. Ein Konto erscheint nur mit Link und Name."}
};
var HS_SEL={hero_text:".hero h1",hero_bg:".hero-outer",hero_search:".sbar",hero_stats:".hnote",ads:".adsec",banners:".topbanner-wrap",ticker:".mkt",projects:"#projectsSec",wanted:"#wantedSec",colls:"#collsSec",types:"#typesSec",trust:"#trustSec",expl:"#explSec",band:"#bandSec",guides:"#guidesSec",page:".hero-outer",
  row:".adsec",look:".adsec",perf:".adsec",strip:".topbanner-wrap",cards:".res",badges:".res",results:".rs-head",nav:"header",social:".changrid",numbers:".changrid"};
var HS_EYE={ads:"x:ads_row_enabled"};
var HS_VARKEYS=/^(sk_|h1_|sbar_|hero_gap|ad_carousel_gap|ad_square_size|hero_title_size_m|sec_pad|hero_max_height|card_min_width)/;
var HS_ICO_EYEOFF='<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3l18 18M10.6 10.6a3 3 0 0 0 4.2 4.2M9.9 5.2A10.4 10.4 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4M6.6 6.6C3.8 8.6 2 12 2 12s3.5 6 10 6c1.4 0 2.6-.3 3.7-.7"/></svg>';
function hsParts(key){ return {col:key.indexOf("c:")===0,name:key.slice(2)} }
function hsBase(key){ var p=hsParts(key); if(p.col){ var v=SITE[p.name]; return v==null?"":v } return SX(p.name,"") }
function hsSet(key,val){ var p=hsParts(key); (p.col?HS.draft.site:HS.draft.extras)[p.name]=val; hsDirtyUI() }
function hsDirty(){ return Object.keys(HS.draft.site).length+Object.keys(HS.draft.extras).length+Object.keys(HS.adDraft).length>0 || !!HS.adNew }
function hsAdBase(id){ return (ADM.adSlots||[]).filter(function(a){ return String(a.id)===String(id) })[0] }
function hsAdRow(id){ if(id==="new") return HS.adNew; var b=hsAdBase(id); return b ? Object.assign({},b,HS.adDraft[id]||{}) : null }
function hsAdSet(id,field,val){ if(id==="new"){ if(!HS.adNew) HS.adNew={id:"new",enabled:true}; HS.adNew[field]=val } else { (HS.adDraft[id]=HS.adDraft[id]||{})[field]=val } hsDirtyUI() }
function hsAdList(){ var rows=(ADM.adSlots||[]).map(function(a){ return Object.assign({},a,HS.adDraft[a.id]||{}) }); if(HS.adNew) rows.push(Object.assign({id:"new",position:rows.length+1},HS.adNew)); return rows }
function hsAdMode(a){ return a._mode||(a.linked_listing_id?"linked":a.video_embed_url?"video_embed":"upload") }
function hsAdName(a,i){ var lst=a.linked_listing_id?((ADM.data&&ADM.data.listings||[]).filter(function(l){ return String(l.id)===String(a.linked_listing_id) })[0]):null; return a.label||a.sponsor_name||(lst&&lst.ref)||(a.linked_listing_id?"BK "+a.linked_listing_id:"")||(a.id==="new"?hsT("adNew"):"#"+(i+1)) }
function hsAdPayload(a){
  var mode=hsAdMode(a), p={p_token:ADM.token,p_country:COUNTRY,p_id:a.id==="new"?null:+a.id,p_position:null,p_enabled:a.enabled!==false,p_label:a.label||"",p_image_url:null,p_link_url:null,p_media_type:"image",p_linked_listing_id:null,p_image_urls:[],p_video_embed_url:null,
    p_sponsor_name:a.sponsor_name||null,p_overlay_top:a.overlay_top||null,p_overlay_bottom:a.overlay_bottom||null,p_starts_at:a.starts_at||null,p_expires_at:a.expires_at||null};
  if(mode==="linked"){ if(!a.linked_listing_id) throw new Error(t("adPickListingL")); p.p_linked_listing_id=+a.linked_listing_id }
  else if(mode==="video_embed"){ if(!a.video_embed_url || !videoEmbedInfo(a.video_embed_url)) throw new Error(t("adInvalidVideoUrl")); p.p_video_embed_url=a.video_embed_url; p.p_link_url=a.link_url||null }
  else { p.p_image_url=a.image_url||null; p.p_image_urls=a.image_urls||[]; p.p_link_url=a.link_url||null; p.p_media_type=a.media_type||"image" }
  return p }
function hsBDraft(){ if(!HS.bDraft){ HS.bDraft=JSON.parse(JSON.stringify(bannersConfig())); HS.bBefore=JSON.parse(JSON.stringify(HS.bDraft)) } return HS.bDraft }
function hsBSet(i,field,val){ var cfg=hsBDraft()[i]; if(val===null||val===undefined) delete cfg[field]; else cfg[field]=val; HS.draft.site.banners_config=JSON.stringify(HS.bDraft); hsDirtyUI() }
function hsMerged(){ var ex=SITE.extras; if(typeof ex==="string"){ try{ ex=JSON.parse(ex) }catch(e){ ex={} } } ex=Object.assign({},ex||{},HS.draft.extras); Object.keys(ex).forEach(function(k){ if(ex[k]===null||ex[k]===""||ex[k]===undefined) delete ex[k] }); var site={}; Object.keys(SITE).forEach(function(k){ if(k!=="extras") site[k]=SITE[k] }); Object.assign(site,HS.draft.site); return {site:site,extras:ex} }
function hsOrder(ex){ var o=ex.home_order; if(typeof o==="string"){ try{ o=JSON.parse(o) }catch(e){ o=null } } var r=Array.isArray(o)?o.filter(function(k){ return HOME_SECS.indexOf(k)>-1 }):[]; HOME_SECS.forEach(function(k){ if(r.indexOf(k)<0) r.push(k) }); return r }
function hsPush(rerender,delay){ clearTimeout(_hsPushT); _hsPushT=setTimeout(function(){ var f=$("#hsFrame"); if(!f||!f.contentWindow) return; var m=hsMerged(); var msg={type:"bk-preview",site:m.site,extras:m.extras,lang:hsLang(),rerender:!!rerender};
  if(HS.page==="ads" || Object.keys(HS.adDraft).length || HS.adNew) msg.adSlots=hsAdList();
  try{ f.contentWindow.postMessage(msg,location.origin) }catch(e){} }, delay||0) }
function hsScrollTo(){ var f=$("#hsFrame"), sel=HS_SEL[HS.sel]||(HS.sel.indexOf("ad:")===0?".adsec":HS.sel.indexOf("b:")===0?".topbanner-wrap":null); if(!f||!f.contentWindow||!sel) return; try{ f.contentWindow.postMessage({type:"bk-preview-scroll",sel:sel},location.origin) }catch(e){} }
function fNum(label,key,min,max,step,ph,rer){ return '<div class="fl"><label>'+label+'</label>'+hsIn(key,"num",' min="'+min+'" max="'+max+'" step="'+(step||1)+'" placeholder="'+esc(String(ph==null?"":ph))+'"'+(rer?' data-hsr="1"':''),hsVal(key))+'</div>' }
function fSwitch(label,key,def,rer){ var v=hsVal(key); var on=v===""?def!==false:(v!==false&&v!=="false"); return '<label class="hs-sw"><input type="checkbox" data-hsk="'+key+'" data-hst="bool"'+(on?' checked':'')+(rer?' data-hsr="1"':'')+'><span>'+label+'</span></label>' }
function fSel(label,key,opts,def,rer){ var v=hsVal(key); if(v==="") v=def; return '<div class="fl"><label>'+label+'</label><select data-hsk="'+key+'" data-hst="str"'+(rer?' data-hsr="1"':'')+'>'+opts.map(function(o){ return '<option value="'+esc(o[0])+'"'+(String(v)===o[0]?' selected':'')+'>'+o[1]+'</option>' }).join("")+'</select></div>' }
function fColor(label,key,def){ var v=hsVal(key)||def; return '<div class="fl"><label>'+label+'</label>'+hsIn(key,"color",' data-hsr="1"',v)+'</div>' }
function fUpload(label,key,folder,accept,fallback){ var v=hsVal(key), url=v||fallback||"", isV=/\.(mp4|webm|mov)(\?|$)/i.test(String(url)); var src=esc(safeUrl(unesc(String(url))));
  return '<div class="fl"><label>'+label+'</label><div class="hs-up">'+(src?(isV?'<video src="'+src+'" muted></video>':'<img src="'+src+'" alt="">'):'')+'<input type="file" accept="'+accept+'" data-hsup="'+key+'" data-hsfolder="'+folder+'">'+(v?'<button type="button" class="ab" data-hsclear="'+key+'" data-hsr="1">'+hsT("clearImg")+'</button>':'')+'</div><div class="hintx hs-upmsg"></div></div>' }
function fGrp(title){ return '<div class="fsub">'+title+'</div>' }
function aIn(field,type,val,attrs){ return '<input data-allow-autofill data-hsa="'+field+'" data-hst="'+type+'" type="'+(type==="num"?"number":type==="date"?"date":type==="color"?"color":"text")+'" value="'+esc(String(val==null?"":val))+'"'+(attrs||"")+'>' }
function aText(label,field,val,ph){ return '<div class="fl"><label>'+label+'</label>'+aIn(field,"str",val,' placeholder="'+esc(String(ph||""))+'"')+'</div>' }
function hsInspectorHtml(){
  var phone=HS.device==="phone", r = HS.page==="ads"?hsInspAds():HS.page==="banners"?hsInspBanners():HS.page==="design"?hsInspDesign():HS.page==="contact"?hsInspContact():hsInspHome();
  return '<h3>'+r.title+(r.badge||'')+'<span class="hs-badge">'+(phone?AICO.phone:AICO.desk)+' '+hsT(phone?"phone":"desk")+'</span></h3><div class="in">'+r.H.join("")+'</div>';
}
function hsInspAds(){
  var sd=HS.sel, H=[], title=hsT(sd);
  if(sd==="row"){
    H.push(fSwitch(hsT("f_adsOn"),"x:ads_row_enabled",true,true), fHint(hsT("textsHint")),
      fText(hsT("f_adsTitle"),"x:ads_row_title",GX_T.adsH[hsLang()]), fText(hsT("f_adsSponsored"),"x:ads_sponsored",GX_T.sponsored[hsLang()]),
      fGrp(hsT("g_look")), fHint(hsT("dualHint")),
      fDual(hsT("f_adSize"),"c:ad_square_size","x:ad_square_size_m",90,260,5,true), fHint(GX("adSizeHint")),
      fSlider(hsT("f_adGap"),"c:ad_carousel_gap","x:ad_carousel_gap_m",-60,80,2,"px",0),
      '<div class="row">'+fNum(hsT("f_adGlide"),"x:ad_glide_seconds",1,15,0.5,3.5,true)+fNum(GX("xAdVideoMax"),"x:ad_video_max_mb",1,100,1,8)+'</div>');
  } else if(sd==="look"){
    H.push(fGrp(GX("adColorsSub")), '<div class="row">'+fColor(t("adTextColorL"),"c:ad_text_color","#ffffff")+fColor(t("adShadeColorL"),"c:ad_shade_color","#090e1a")+'</div>',
      fGrp(GX("adInfoSub")), fHint(hsT("dualHint")), fSwitch(t("adStyleIcons"),"c:ad_use_icons",true,true), fDual(t("adTextSizeL"),"c:ad_roominfo_size","x:ad_roominfo_size_m",7,20,1,true),
      fSwitch(t("showAdLocation"),"c:ad_location_enabled",true,true), fDual(t("adTextSizeL")+" — "+t("adLocationH"),"c:ad_location_size","x:ad_location_size_m",7,20,1,true),
      fGrp(GX("adTagSub")), fSwitch(t("showAdTag"),"c:ad_tag_enabled",true,true), fHint(hsT("textsHint")), fText(t("adTagTextL"),"c:ad_tag",t("adTag")), fDual(t("adTextSizeL")+" — "+GX("adTagSub"),"c:ad_tag_size","x:ad_tag_size_m",7,20,1,true));
  } else if(sd==="perf"){
    H.push('<div class="dash-top" style="margin-bottom:0">'+rangeTabs()+'</div>', fHint(GX("adsPerfHint")), ADM.an?adsPerfTable(ADM.an,true):'<div class="adashempty">'+t("loading")+'</div>');
  } else if(sd.indexOf("ad:")===0){
    var id=sd.slice(3), a=hsAdRow(id); if(!a){ HS.sel="row"; return hsInspAds() }
    var idx=hsAdList().findIndex(function(x){ return String(x.id)===String(id) }); title=hsAdName(a,idx); var mode=hsAdMode(a);
    var imgs=(a.image_urls&&a.image_urls.length)?a.image_urls:(a.image_url?[a.image_url]:[]);
    var lst=(ADM.data&&ADM.data.listings)||[];
    H.push(fHint(hsT("adSaveHint")), fGrp(hsT("adInfo")), aSwitch(t("enabled"),"enabled",a.enabled!==false),
      '<div class="row">'+aText(t("adLabelL"),"label",a.label,"")+aText(t("adSponsorNameL"),"sponsor_name",a.sponsor_name,t("adSponsorNamePH"))+'</div>',
      fGrp(hsT("adMedia")),
      '<div class="pick">'+[["upload",t("adModeUpload")],["linked",t("adModeLinked")],["video_embed",t("adModeVideoEmbed")]].map(function(m){ return '<label><input type="radio" name="hsAdMode" data-hsa="_mode" data-hst="str" value="'+m[0]+'"'+(mode===m[0]?' checked':'')+'><span>'+m[1]+'</span></label>' }).join("")+'</div>');
    if(mode==="upload"){
      H.push((imgs.length?'<div class="hs-thumbs">'+imgs.map(function(u){ return a.media_type==="video"&&u===a.image_url?'<video src="'+esc(u)+'" muted></video>':'<img src="'+esc(u)+'" alt="">' }).join("")+'</div>':''),
        '<div class="fl"><label>'+t("adModeUpload")+'</label><div class="hs-up"><input type="file" accept="image/*,video/mp4,video/webm" multiple data-hsaup="1">'+(imgs.length?'<button type="button" class="ab" data-hsaclear="1">'+hsT("adClearMedia")+'</button>':'')+'</div><div class="hintx hs-upmsg"></div></div>',
        fHint(GX("adVideoHint").replace("{max}",adVideoMaxMb())+" "+t("adMultiUploadHint")), aText(t("adLinkUrlL"),"link_url",a.link_url,"https://..."));
    } else if(mode==="linked"){
      H.push('<div class="fl"><label>'+t("adPickListingL")+'</label><select data-hsa="linked_listing_id" data-hst="str"><option value="">—</option>'+lst.map(function(l){ return '<option value="'+l.id+'"'+(String(l.id)===String(a.linked_listing_id||"")?' selected':'')+'>'+esc(String(l.ref||l.id))+' — '+esc(String(l.poster_name||""))+' ($'+Number(l.price_usd||0).toLocaleString("en")+')</option>' }).join("")+'</select></div>', fHint(t("adLinkedHint")));
    } else {
      H.push(aText(t("adVideoUrlL"),"video_embed_url",a.video_embed_url,"https://www.youtube.com/watch?v=..."), fHint(t("adVideoEmbedHint")), aText(t("adVideoLinkL"),"link_url",a.link_url,"https://..."));
    }
    H.push(fGrp(hsT("adTexts")), '<div class="row">'+aText(t("adTopTextL"),"overlay_top",a.overlay_top,t("adOverlayPH"))+aText(t("adBottomTextL"),"overlay_bottom",a.overlay_bottom,t("adOverlayPH"))+'</div>', fHint(t("adOverlayHint")),
      fGrp(hsT("adSchedule")), '<div class="row">'+aDate(t("featureStartL"),"starts_at",a.starts_at,false)+aDate(t("adExpiresL"),"expires_at",a.expires_at,true)+'</div>', fHint(t("adScheduleHint")));
    if(id!=="new") H.push('<button type="button" class="ab bad" id="hsAdDel">'+hsT("delSquare")+'</button>');
    return {title:title,H:H,badge:(id==="new"||HS.adDraft[id])?'<i class="hs-unsaved">'+hsT("unsaved")+'</i>':''};
  }
  return {title:title,H:H};
}
function hsInspBanners(){
  var sd=HS.sel, H=[], title=hsT(sd);
  if(sd==="strip"){ H.push(fSwitch(hsT("showSec"),"x:home_banners_on",true,true), fSel(hsT("bSlot"),"x:banners_slot",[["flow",hsT("bSlotFlow")],["top",hsT("bSlotTop")]],"flow",true), fHint(hsT("stripHint")), fGo(hsT("goHome"),"mainpage")); return {title:title,H:H} }
  var i=+sd.slice(2), cfg=hsBDraft()[i]; title=hsT("banner")+" "+(i+1);
  var sizeOpts=Object.keys(BANNER_SIZES).map(function(k){ return [k,k+" — "+t("bannerSizeLabel_"+k)] }).concat([["custom",t("bannerSizeCustomL")]]);
  H.push(bSwitch(t("topBannerEnableL"),"enabled",!!cfg.enabled), fGrp(hsT("bItems")),
    (cfg.items.length ? '<div class="hs-items">'+cfg.items.map(function(it,k){ return '<div class="hs-item-row">'+(it.type==="video"?'<video src="'+esc(it.url)+'" muted></video>':'<img src="'+esc(it.url)+'" alt="">')+'<input type="text" data-allow-autofill data-hsbi="'+k+'" value="'+esc(it.link||"")+'" placeholder="'+esc(hsT("bItemLink"))+'"><button type="button" class="ab" data-hsbrm="'+k+'" title="'+t("del")+'">✕</button></div>' }).join("")+'</div>' : fHint(hsT("bEmptyHint"))),
    '<div class="fl"><label>'+t("adModeUpload")+'</label><div class="hs-up"><input type="file" accept="image/*,video/mp4,video/webm" multiple data-hsbup="1"></div><div class="hintx hs-upmsg"></div></div>', fHint(t("topBannerUploadHint")),
    fGrp(hsT("bSize")), fHint(hsT("dualHint")), bSel(hsT("bSize"),"size",cfg.size||"728x90",sizeOpts));
  if(cfg.size==="custom") H.push('<div class="row">'+bNum(t("bannerWidthL"),"customW",cfg.customW||728,120,1400,1)+bNum(t("bannerHeightL"),"customH",cfg.customH||90,30,600,1)+'</div>');
  H.push(bSel(hsT("bSizeM"),"sizeM",cfg.sizeM||"same",[["same",hsT("same")],["full",hsT("bFull")],["custom",hsT("bCustom")]]));
  if(cfg.sizeM==="custom") H.push('<div class="row">'+bNum(t("bannerWidthL"),"customWM",cfg.customWM||300,80,430,1)+bNum(t("bannerHeightL"),"customHM",cfg.customHM||100,30,600,1)+'</div>');
  H.push(fGrp(hsT("bPos")), bDual(hsT("bHPos"),cfg,"hPosition","hPositionM",0,100,5,"%",50,true), bDual(hsT("bVOff"),cfg,"vOffset","vOffsetM",-80,300,2,"px",0,false), bNum(t("bannerGapL"),"gap",cfg.gap!=null?cfg.gap:14,0,80,2),
    fGrp(hsT("bRot")), '<div class="row">'+bNum(t("bannerRotateSecL"),"rotationSeconds",cfg.rotationSeconds||5,2,60,1)+bSel(t("bannerTransitionL"),"transition",cfg.transition||"fade",["fade","slide-left","slide-right","slide-up","slide-down"].map(function(tr){ return [tr,t("bannerTransition_"+tr.replace(/-/g,"_"))] }))+'</div>',
    bText(hsT("bLink"),"link",cfg.link,"https://..."),
    fGrp(hsT("bText")), bSwitch(t("bannerTextEnableL"),"textEnabled",!!cfg.textEnabled));
  if(cfg.textEnabled) H.push(fHint(hsT("textsHint")), '<div class="fl"><label>'+t("bannerTextL")+' <i class="hs-lg">'+hsLang().toUpperCase()+'</i></label>'+bIn("text_"+hsLang(),"str",cfg["text_"+hsLang()]||"",'')+'</div>',
    '<div class="row">'+bNum(t("adTextSizeL"),"textSize",cfg.textSize||14,9,40,1)+'<div class="fl"><label>'+t("adTextColorL")+'</label>'+bIn("textColor","color",cfg.textColor||"#ffffff",'')+'</div></div>');
  return {title:title,H:H};
}
function hsInspDesign(){
  var sd=HS.sel, H=[], title=hsT(sd);
  if(sd==="cards"){ H.push(fHint(hsT("dualHint")), fDual(hsT("cardW"),"c:card_min_width","c:card_min_width_mobile",90,500,10), fHint(hsT("cardHint"))); }
  else if(sd==="badges"){ H.push(fGrp(t("featuredH")), fSwitch(t("showFeaturedBadge"),"c:featured_badge_enabled",true,true), fHint(hsT("textsHint")), fText(t("featuredBadgeTextL"),"c:featured_badge",t("featuredBadgeDefault")),
      fSlider(t("featuredBrightnessL"),"c:featured_brightness",null,0,100,5,"%",20,true), fHint(t("featuredBrightnessHint")), fGrp(t("newBadgeH")), fNum(t("newBadgeHoursL"),"c:new_badge_hours",0,720,1,24,true), fHint(t("newBadgeHint"))); }
  else if(sd==="watermark"){
    H.push(fHint(hsT("wmHint")), fSwitch(hsT("wmOn"),"x:wm_on",true,true), fSel(hsT("wmPos"),"x:wm_pos",[["br",hsT("wm_br")],["bl",hsT("wm_bl")],["tr",hsT("wm_tr")],["tl",hsT("wm_tl")]],"br",true),
      fSlider(hsT("wmSize"),"x:wm_size",null,6,40,1,"%",14,true), fSlider(hsT("wmOp"),"x:wm_opacity",null,20,100,5,"%",70,true),
      fGrp(hsT("wmVideoH")), fSwitch(hsT("wmVideo"),"x:wm_video",true,true), fGrp(hsT("wmLockH")), fSwitch(hsT("wmLock"),"x:wm_lock",true,true), fHint(hsT("wmLockHint"))); }
  else if(sd==="welcome"){ var lg=hsLang(), WT=GX_T.notif_welcomeT||{}, WB=GX_T.notif_welcomeB||{};
    H.push(fSwitch(hsT("wlOn"),"x:welcome_on",true,true), fHint(hsT("wlHint")), fHint(hsT("textsHint")), fText(hsT("wlTitle"),"x:welcome_t",WT[lg]||WT.en||""), fArea(hsT("wlBody"),"x:welcome_b",WB[lg]||WB.en||"")); }
  else if(sd==="results"){ H.push('<div class="row">'+fNum(GX("xPageSize"),"x:search_page_size",6,96,1,24,true)+fNum(GX("xSimilar"),"x:similar_count",0,24,1,12)+'</div>', fSwitch(hsT("rsMapDef"),"x:results_map_default",true,true), fSwitch(hsT("rsMarket"),"x:results_market_line",true,true), fHint(hsT("rsHint"))); }
  else if(sd==="nav"){
    var bv=function(key,def){ var v=hsVal(key); return v===""?def:(v!==false&&v!=="false") };
    var row=function(i){ var hid=i.hide&&i.hide(); return '<div class="navrow'+(hid?' navrow-off':'')+'"><span class="navname">'+(MI[i.ico]||'')+i.lab()+(hid?' <small class="hintx" style="display:inline">'+GX("navAutoHidden")+'</small>':'')+'</span>'+
      '<label class="xcheck navflag" title="'+GX("navInMenu")+'"><input type="checkbox" data-hsk="x:nav_'+i.k+'" data-hst="bool" data-hsr="1"'+(bv("x:nav_"+i.k,true)?' checked':'')+'><span>'+GX("navInMenu")+'</span></label>'+
      '<label class="xcheck navflag" title="'+GX("navInHeader")+'"><input type="checkbox" data-hsk="x:nav_'+i.k+'_h" data-hst="bool" data-hsr="1"'+(bv("x:nav_"+i.k+"_h",!!NAV_HEADER_DEF[i.k])?' checked':'')+'><span>'+GX("navInHeader")+'</span></label>'+
      '<span class="navord-w"><small>'+GX("navOrder")+'</small><input type="number" data-allow-autofill class="navord" data-hsk="x:nav_'+i.k+'_o" data-hst="num" data-hsr="1" value="'+esc(String(hsVal("x:nav_"+i.k+"_o")))+'" placeholder="'+i.o+'" min="0" max="999"></span></div>' };
    var g=function(gk,ttl){ return fGrp(ttl)+'<div class="navrows">'+NAVI.filter(function(i){ return i.g===gk }).map(row).join("")+'</div>' };
    H.push(fHint(GX("navHint")), fHint(GX("navHint2")), g("search",GX("mdSearch")), g("discover",GX("mdDiscover")), g("services",GX("mdServices")), fSwitch(GX("navSoonHeader"),"x:nav_soon_header",true,true), fSwitch(GX("navMapNew"),"x:nav_map_new",true,true), g("site",GX("mdSite")), fGrp(GX("navPhoneH")),
      fSwitch(GX("navLangHeader"),"x:nav_lang_header",true,true), fSwitch(GX("navBellPhone"),"x:nav_bell_phone",true,true), fSwitch(GX("navLoginPhone"),"x:nav_login_phone",false,true), fSwitch(GX("navAvatarPhone"),"x:nav_avatar_phone",false,true),
      fSwitch(GX("navLangDrawer"),"x:nav_lang_drawer",true,true), fSwitch(GX("navCurDrawer"),"x:nav_cur_drawer",true,true),
      fGrp(GX("navDeskH")), fSwitch(GX("navMenuDesk"),"x:nav_menu_desktop",true,true), fSwitch(GX("navLinksDesk"),"x:nav_links_desktop",true,true), fSwitch(GX("navMoreDesk"),"x:nav_more_desktop",false,true),
      fSwitch(GX("navCurHeader"),"x:nav_cur_header",false,true), fSwitch(GX("navLoginHeader"),"x:nav_login_header",false,true));
  }
  return {title:title,H:H};
}
function hsInspContact(){
  var sd=HS.sel, H=[], title=hsT(sd);
  var pair=function(name,uk,nk,ph){ return fGrp(name)+'<div class="row">'+fText(t("linkL"),"c:"+uk,ph,true)+fText(t("accountNameL"),"c:"+nk,"@balkoun",true)+'</div>' };
  if(sd==="social") H.push(fHint(hsT("contactHint")), pair("Facebook","fb_url","fb_name","https://facebook.com/..."), pair("Instagram","ig_url","ig_name","https://instagram.com/..."), pair("YouTube","yt_url","yt_name","https://youtube.com/..."), pair("TikTok","tiktok_url","tiktok_name","https://tiktok.com/@..."));
  else H.push(fHint(hsT("contactHint")), '<div class="row">'+fText(t("waNumberL"),"c:wa_number","+9639xxxxxxxx",true)+fText(t("phoneNumberL"),"c:phone_number","+9639xxxxxxxx",true)+'</div>', fText(t("emailAddressL"),"c:email_address","info@balkoun.com",true));
  return {title:title,H:H};
}
function hsInspHome(){
  var sd=HS.sel, H=[], title=hsT(sd), phone=HS.device==="phone";
  var govOpts=Object.keys(D.GEO).map(function(g){ return [g,gN(g)] });
  if(sd==="hero_text"){
    H.push(fSwitch(hsT("f_heroOn"),"c:hero_enabled",true,true), fGrp(hsT("g_text")), fHint(hsT("textsHint")),
      fText(hsT("f_h1"),"c:hero",t("h1a")), fText(hsT("f_h1b"),"c:hero_sub",t("h1b")),
      fText(hsT("f_flipAr"),"x:brand_flip_prefix_ar","منصة",true), fText(hsT("f_flipLatin"),"x:brand_flip_latin","balkoun.com",true),
      fGrp(hsT("g_look")), fHint(hsT("dualHint")),
      '<div class="row">'+fColor(hsT("f_h1Color"),"c:hero_title_color","#ffffff")+fColor(hsT("f_h1bColor"),"c:hero_sub_color","#C4881F")+'</div>',
      fDual(hsT("f_size"),"c:hero_title_size","x:hero_title_size_m",16,64,1,true),
      '<div class="row">'+fDual(hsT("f_x"),"x:h1_x","x:h1_x_m",-600,600,1)+fDual(hsT("f_y"),"x:h1_y","x:h1_y_m",-300,300,1)+'</div>',
      fSlider(hsT("f_heroGap"),"c:hero_gap","x:hero_gap_m",-60,80,2,"px",0));
  } else if(sd==="hero_bg"){
    var bt=hsVal("c:hero_bg_type")||"sketch";
    H.push(fSel(hsT("f_bgType"),"c:hero_bg_type",(SKETCH_BUILDERS[COUNTRY]?[["sketch",hsT(COUNTRY==="SY"?"bg_sketch":"bg_sketch_"+COUNTRY)]]:[]).concat(SCENE3D_BUILDERS[COUNTRY]?[["scene3d",hsT("bg_scene3d_"+COUNTRY)]]:[]).concat([["dawn",hsT("bg_dawn")],["video",hsT("bg_video")],["photo",hsT("bg_photo")],["none",hsT("bg_none")]]),SKETCH_BUILDERS[COUNTRY]?"sketch":"none",true));
    if(bt==="video") H.push(fUpload(hsT("f_upVideo"),"c:hero_bg_video_url","background","video/mp4,video/webm"), fSlider(hsT("f_speed"),"c:hero_bg_video_speed",null,10,300,5,"%",100,true));
    if(bt==="photo") H.push(fUpload(hsT("f_upPhoto"),"c:hero_bg_photo_url","background","image/*"), fUpload(hsT("f_upPhotoM"),"x:hero_bg_photo_m","background","image/*"), fHint(hsT("f_upPhotoMHint")), fText(hsT("f_bgCredit"),"x:hero_bg_credit","",true));
    if(bt==="sketch") H.push(fGrp(hsT("g_draw")), fHint(hsT("dualHint")),
      '<div class="row">'+fDual(hsT("f_x"),"x:sk_x","x:sk_x_m",-600,600,1)+fDual(hsT("f_y"),"x:sk_y","x:sk_y_m",-400,400,1)+'</div>',
      fSlider(hsT("f_scale"),"x:sk_scale","x:sk_scale_m",30,250,5,"%",100));
    if(!phone) H.push(fGrp(hsT("g_spacing")), fNum(hsT("f_heroMax"),"x:hero_max_height",420,900,10,640));
  } else if(sd==="hero_search"){
    H.push(fSwitch(hsT("f_sbGlow"),"x:sbar_glow",true,true), fSwitch(hsT("f_sbGlass"),"x:sbar_glass",true,true), fSwitch(hsT("f_sbGlassM"),"x:sbar_glass_m",true,true), fHint(hsT("f_sbGlassHint")), fHint(hsT("dualHint")), fDual(hsT("f_sbY"),"x:sbar_y","x:sbar_y_m",-300,300,1), fDual(hsT("f_sbW"),"x:sbar_w","x:sbar_w_m",320,1600,10), fDual(hsT("f_sbH"),"x:sbar_h","x:sbar_h_m",32,72,1));
    H.push(fGrp(hsT("g_aiBar")), fSwitch(hsT("f_aiOn"),"x:ai_bar_on",true,true), fSwitch(hsT("f_aiGlass"),"x:ai_bar_glass",false,true), fHint(hsT("dualHint")), fDual(hsT("f_aiY"),"x:ai_bar_y","x:ai_bar_y_m",-200,300,1), fHint(hsT("f_aiHint")));
  } else if(sd==="hero_stats"){
    H.push(fSwitch(hsT("f_statsOn"),"c:stats_enabled",true,true), fSwitch(hsT("f_realCount"),"c:stats_use_real_count",false,true),
      '<div class="row">'+fText(hsT("f_areasNum"),"c:stats_areas_num","657",true)+fText(hsT("f_listNum"),"c:stats_listings_num","",true)+'</div>',
      fHint(hsT("textsHint")), fText(hsT("f_stats1"),"c:stats1",t("note")), fText(hsT("f_stats2"),"c:stats2",t("note2")));
  } else if(sd==="ads"){
    H.push(fSwitch(hsT("f_adsOn"),"x:ads_row_enabled",true,true), fHint(hsT("textsHint")),
      fText(hsT("f_adsTitle"),"x:ads_row_title",GX_T.adsH[hsLang()]), fText(hsT("f_adsSponsored"),"x:ads_sponsored",GX_T.sponsored[hsLang()]),
      fGrp(hsT("g_look")), fHint(hsT("dualHint")),
      fDual(hsT("f_adSize"),"c:ad_square_size","x:ad_square_size_m",100,260,5), fSlider(hsT("f_adGap"),"c:ad_carousel_gap","x:ad_carousel_gap_m",-60,80,2,"px",0),
      fNum(hsT("f_adGlide"),"x:ad_glide_seconds",1,15,0.5,3.5,true), fGo(hsT("go_ads"),"ads"));
  } else if(sd==="banners"){
    H.push(fSwitch(hsT("showSec"),"x:home_banners_on",true,true), fSel(hsT("bSlot"),"x:banners_slot",[["flow",hsT("bSlotFlow")],["top",hsT("bSlotTop")]],"flow",true), fHint(hsT("bannersHint")), fGo(hsT("go_banners"),"banners"));
  } else if(sd==="ticker"){
    H.push(fSwitch(hsT("showSec"),"x:home_ticker_on",true,true), fHint(hsT("tickerHint")), fText(hsT("f_h"),"x:ticker_h",""), fText(hsT("f_sub"),"x:ticker_sub",""));
  } else if(sd==="colls"){
    H.push(fSwitch(hsT("showSec"),"x:home_colls_on",true,true), fHint(hsT("textsHint")), fSecTexts("colls",HX("collE"),HX("collH"),HX("collS")), fSwitch(hsT("f_credit"),"x:colls_credit_on",true,true));
    [["c1","c1s","دمشق","damascene"],["c2","c2s","دمشق","orchards"],["c3","c3s","اللاذقية","latakia"],["c4","c4s","ريف دمشق","bloudan"]].forEach(function(c,i){ var n=i+1;
      H.push('<div class="hs-card"><b>'+hsT("card")+' '+n+'</b>'+fSwitch(hsT("f_cardOn"),"x:coll"+n+"_on",true,true)+fText(hsT("f_cardT"),"x:coll"+n+"_t",HX(c[0]))+fText(hsT("f_cardS"),"x:coll"+n+"_s",HX(c[1]))+
        fSel(hsT("f_gov"),"x:coll"+n+"_gov",govOpts,c[2],true)+fUpload(hsT("f_img"),"x:coll"+n+"_img","home","image/*","/assets/home/"+c[3]+".jpg")+'</div>') });
  } else if(sd==="types"){
    H.push(fSwitch(hsT("showSec"),"x:home_types_on",true,true), fHint(hsT("textsHint")), fSecTexts("types",HX("pickE"),t("pickH")));
  } else if(sd==="trust"){
    H.push(fSwitch(hsT("showSec"),"x:home_trust_on",true,true), fHint(hsT("textsHint")), fText(hsT("f_eyebrow"),"x:trust_eyebrow",HX("trE")), fText(hsT("f_h"),"x:trust_h",HX("trH")), fArea(hsT("f_p"),"x:trust_p",HX("trP")));
    [1,2,3].forEach(function(n){ H.push('<div class="hs-card"><b>'+hsT("point")+' '+n+'</b>'+fText(hsT("f_h"),"x:trust_t"+n,HX("t"+n))+fArea(hsT("f_p"),"x:trust_t"+n+"p",HX("t"+n+"p"))+'</div>') });
  } else if(sd==="expl"){
    H.push(fSwitch(hsT("showSec"),"x:home_expl_on",true,true), fSwitch(hsT("f_map"),"x:expl_map_enabled",true,true), fHint(hsT("textsHint")), fSecTexts("expl",HX("govE"),t("govH"),t("govS")));
  } else if(sd==="band"){
    H.push(fSwitch(hsT("showSec"),"x:home_band_on",true,true), fHint(hsT("bandHint")), fHint(hsT("textsHint")), fText(hsT("f_eyebrow"),"x:band_eyebrow",HX("ownE")), fText(hsT("f_h"),"x:band_h",t("bandH")), fArea(hsT("f_p"),"x:band_p",t("bandP")),
      fText(hsT("f_b")+" 1","x:band_b1",t("b1")), fText(hsT("f_b")+" 2","x:band_b2",t("b2")), fText(hsT("f_b")+" 3","x:band_b3",t("b3")), fText(hsT("f_btn"),"x:band_btn",t("bandBtn")),
      fUpload(hsT("f_img"),"x:band_img","home","image/*","/assets/home/umayyad.jpg"));
  } else if(sd==="guides"){
    H.push(fSwitch(hsT("showSec"),"x:home_guides_on",true,true), fHint(hsT("textsHint")), fSecTexts("guides",HX("guideE"),t("guideH"),t("guideS")));
  } else if(sd==="wanted"){
    H.push(fSwitch(hsT("showSec"),"x:home_wanted_on",true,true), fNum(hsT("f_wN"),"x:home_wanted_n",1,12,1,6,true), fHint(hsT("textsHint")), fSecTexts("wanted",GX("wSecEyebrow"),GX("wSecH"),GX("wSecSub")),
      fGrp(hsT("g_wanted")), fSwitch(hsT("f_wEnabled"),"x:wanted_enabled",true,true), fSel(hsT("f_wApproval"),"x:wanted_approval",[["auto",hsT("wa_auto")],["manual",hsT("wa_manual")]],"auto",false));
  } else if(sd==="projects"){
    H.push(fSwitch(hsT("showSec"),"x:home_projects_on",true,true), fNum(hsT("f_pjN"),"x:home_projects_n",1,12,1,6,true), fHint(hsT("textsHint")), fSecTexts("projects",GX("pjSecEyebrow"),GX("pjSecH"),GX("pjSecSub")));
  } else if(sd==="page"){
    H.push(fGrp(hsT("g_pwa")), fSwitch(hsT("f_pwaBanner"),"x:pwa_banner",true,false), fNum(hsT("f_pwaDays"),"x:pwa_banner_days",1,90,1,14,false));
    H.push(fGrp(hsT("g_logo")), fSel(hsT("f_logoVar"),"x:logo_variant",[["full",hsT("lv_full")],["markword",hsT("lv_mw")],["word",hsT("lv_word")]],"full",true), fSlider(hsT("f_logoH"),"x:logo_h","x:logo_h_m",22,48,1,"px",phone?30:34));
    H.push(fGrp(hsT("g_motion")), fHint(hsT("devOnlyHint")), fSwitch(hsT("f_opening"),"x:opening_enabled",true));
    if(!phone) H.push(fSwitch(hsT("f_cursor"),"x:cursor_dot_enabled",true,true));
    if(phone) H.push(fSel(hsT("f_phMode"),"x:phone_headline_mode",[["after",hsT("ph_after")],["immediate",hsT("ph_now")]],"after",true));
    H.push(fGrp(hsT("g_spacing")), fHint(hsT("dualHint")), fSlider(hsT("f_secPad"),"x:sec_pad","x:sec_pad_m",0,120,2,"px",phone?22:40));
  }
  return {title:title,H:H};
}
function hsOutlineHtml(){
  if(HS.page==="ads") return hsOutlineAds();
  if(HS.page==="banners") return hsOutlineBanners();
  if(HS.page==="design") return hsOutlineSimple([["cards",ICON_GRID],["badges",AICO.star],["results",AICO.search],["nav",AICO.home2],["welcome",AICO.contact],["watermark",AICO.star]]);
  if(HS.page==="contact") return hsOutlineSimple([["social",AICO.users],["numbers",AICO.contact]]);
  return hsOutlineHome();
}
function hsOutlineSimple(list){ return list.map(function(x){ return '<div class="hs-item'+(HS.sel===x[0]?' on':'')+'" data-hssel="'+x[0]+'"><span class="hs-ico">'+x[1]+'</span><span class="hs-name">'+hsT(x[0])+'</span></div>' }).join("") }
function hsOutlineAds(){
  var rows=hsAdList(), n=rows.length;
  var fixed=[["row",AICO.ads],["look",AICO.palette],["perf",AICO.chart]].map(function(x){ return '<div class="hs-item'+(HS.sel===x[0]?' on':'')+'" data-hssel="'+x[0]+'"><span class="hs-ico">'+x[1]+'</span><span class="hs-name">'+hsT(x[0])+'</span></div>' }).join("");
  var items=rows.map(function(a,i){ var on=a.enabled!==false, k="ad:"+a.id, th=a.image_url||(a.image_urls&&a.image_urls[0]); var isNew=a.id==="new";
    return '<div class="hs-item'+(HS.sel===k?' on':'')+(on?'':' off')+'" data-hssel="'+k+'"><span class="hs-ico hs-th">'+(th&&a.media_type!=="video"?'<img src="'+esc(th)+'" alt="">':AICO.image)+'</span><span class="hs-name">'+esc(String(hsAdName(a,i)))+(isNew||HS.adDraft[a.id]?' <i class="hs-dot"></i>':'')+'</span>'+
      (isNew?'':'<button type="button" class="hs-mv" data-hsamv="'+a.id+':up"'+(i===0?' disabled':'')+' title="'+hsT("up")+'">▲</button><button type="button" class="hs-mv" data-hsamv="'+a.id+':down"'+(i>=n-1||rows[i+1].id==="new"?' disabled':'')+' title="'+hsT("down")+'">▼</button>')+
      '<button type="button" class="hs-eye'+(on?'':' off')+'" data-hsaeye="'+a.id+'" title="'+hsT("show")+'">'+(on?AICO.eye:HS_ICO_EYEOFF)+'</button></div>' }).join("");
  return fixed+'<div class="hs-out-h">'+hsT("squares")+' <span class="hs-count ltr">'+n+'</span></div>'+items+(HS.adNew?'':'<button type="button" class="ab hs-outbtn" id="hsAdNew">'+hsT("addSquare")+'</button>')+'<div class="hintx" style="padding:4px 14px 0">'+hsT("adMoveHint")+'</div>';
}
function hsOutlineBanners(){
  var d=hsBDraft();
  return '<div class="hs-item'+(HS.sel==="strip"?' on':'')+'" data-hssel="strip"><span class="hs-ico">'+AICO.banner+'</span><span class="hs-name">'+hsT("strip")+'</span></div>'+
    d.map(function(cfg,i){ var k="b:"+i, on=!!cfg.enabled; return '<div class="hs-item'+(HS.sel===k?' on':'')+(on?'':' off')+'" data-hssel="'+k+'"><span class="hs-ico hs-th">'+(cfg.items[0]?(cfg.items[0].type==="video"?AICO.image:'<img src="'+esc(cfg.items[0].url)+'" alt="">'):AICO.image)+'</span><span class="hs-name">'+hsT("banner")+' '+(i+1)+' <small class="hs-sub">'+cfg.items.length+' · '+(cfg.size==="custom"?(cfg.customW||728)+"×"+(cfg.customH||90):(cfg.size||"728x90"))+'</small></span>'+
      '<button type="button" class="hs-eye'+(on?'':' off')+'" data-hsbeye="'+i+'" title="'+hsT("show")+'">'+(on?AICO.eye:HS_ICO_EYEOFF)+'</button></div>' }).join("");
}
function hsOutlineHome(){
  var m=hsMerged(), ex=m.extras, site=m.site;
  var isOn=function(key){ var p=hsParts(key), v=p.col?site[p.name]:ex[p.name]; return v==null||v===""?true:(v!==false&&v!=="false") };
  var ICO={ads:AICO.ads,banners:AICO.banner,ticker:AICO.chart,projects:AICO.building,wanted:AICO.search,colls:ICON_GRID,types:AICO.listings,trust:AICO.shield,expl:AICO.map,band:AICO.users,guides:AICO.star};
  var item=function(k,o){ o=o||{}; var on=o.eye?isOn(o.eye):o.bgEye?((site.hero_bg_type||"sketch")!=="none"):true; var selK=o.selAs||k; var isSel=HS.sel===selK || (k==="hero" && HS.sel.indexOf("hero_")===0);
    return '<div class="hs-item'+(isSel?' on':'')+(o.child?' child':'')+(on?'':' off')+'" data-hssel="'+selK+'">'+(o.ico?'<span class="hs-ico">'+o.ico+'</span>':'')+'<span class="hs-name">'+hsT(k)+(o.sub?'<small class="hs-sub">'+o.sub+'</small>':'')+'</span>'+
      (o.mv?'<button type="button" class="hs-mv" data-hsmv="'+k+':-1" title="'+hsT("up")+'">▲</button><button type="button" class="hs-mv" data-hsmv="'+k+':1" title="'+hsT("down")+'">▼</button>':'')+
      ((o.eye||o.bgEye)?'<button type="button" class="hs-eye'+(on?'':' off')+'" data-hseye="'+k+'" title="'+hsT("show")+'">'+(on?AICO.eye:HS_ICO_EYEOFF)+'</button>':'')+'</div>' };
  return item("hero",{ico:AICO.home2,selAs:"hero_text"})+item("hero_text",{child:true,eye:"c:hero_enabled"})+item("hero_bg",{child:true,bgEye:true})+item("hero_search",{child:true})+item("hero_stats",{child:true,eye:"c:stats_enabled"})+
    hsOrder(ex).map(function(k){ return item(k,{eye:HS_EYE[k]||("x:home_"+k+"_on"),mv:k!=="banners"||ex.banners_slot!=="top",ico:ICO[k],sub:k==="banners"&&ex.banners_slot==="top"?hsT("bSlotTop"):""}) }).join("")+item("page",{ico:AICO.gear});
}
function hsStudioHtml(page){
  HS.page=page||"home"; if(!HS.lang) HS.lang=L; HS.sel=HS.selBy[HS.page]||HS_PAGES[HS.page].sel;
  return '<div class="hs">'+
   '<div class="hs-bar"><div class="hs-seg" id="hsDev">'+[["desk",AICO.desk],["phone",AICO.phone]].map(function(d){ return '<button type="button" data-dev="'+d[0]+'" class="'+(HS.device===d[0]?"on":"")+'">'+d[1]+' '+hsT(d[0])+'</button>' }).join("")+'</div>'+
   '<div class="hs-seg" id="hsLang">'+["ar","en","de"].map(function(l){ return '<button type="button" data-lang="'+l+'" class="'+(HS.lang===l?"on":"")+'">'+(LANG_SHORT[l]||l)+'</button>' }).join("")+'</div>'+
   '<span class="hs-state" id="hsState"><i></i><span></span></span>'+
   '<div class="hs-actions"><button type="button" class="ab" id="hsReload" title="'+hsT("reload")+'">'+AICO.refresh+'</button><a class="ab" href="/" target="_blank" rel="noopener">'+AICO.eye+' '+hsT("openSite")+'</a><button type="button" class="ab" id="hsDiscard">'+hsT("discard")+'</button><button type="button" class="ab ok" id="hsSave">'+hsT("saveAll")+'</button><span class="xmsg" id="hsMsg"></span></div></div>'+
   '<div class="hs-grid"><aside class="hs-out"><div class="hs-out-h">'+hsT("sections")+'</div><div id="hsOutline">'+hsOutlineHtml()+'</div><div class="hintx" style="padding:8px 14px 12px">'+hsT("sectionsHint")+'</div></aside>'+
   '<div class="hs-pv '+HS.device+'" id="hsPv"><div class="hs-pvwrap" id="hsPvWrap"><iframe id="hsFrame" src="'+hsPvUrl()+'" title="preview"></iframe></div><div class="hs-pvnote">'+hsT("previewNote")+'</div></div>'+
   '<div class="blk hs-insp" id="hsInsp">'+hsInspectorHtml()+'</div></div></div>';
}
function hsFit(){ var pv=$("#hsPv"), w=$("#hsPvWrap"), f=$("#hsFrame"); if(!pv||!w||!f) return; var W=pv.clientWidth-24, H=pv.clientHeight-52;
  if(HS.device==="phone"){ var pw=Math.min(390,W-20); w.style.width=pw+"px"; w.style.height=H+"px"; f.style.width=pw+"px"; f.style.height=H+"px"; f.style.transform="none" }
  else { var sc=Math.min(1,W/1280); w.style.width=Math.round(1280*sc)+"px"; w.style.height=H+"px"; f.style.width="1280px"; f.style.height=Math.round(H/sc)+"px"; f.style.transform="scale("+sc+")" } }
function hsDirtyUI(){ var st=$("#hsState"), sv=$("#hsSave"), d=hsDirty(); if(st){ st.classList.toggle("dirty",d); st.querySelector("span").textContent=hsT(d?"dirty":"clean") } if(sv) sv.disabled=!d; window.onbeforeunload = d ? function(){ return true } : null }
function hsRenderInsp(){ var el=$("#hsInsp"); if(el) el.innerHTML=hsInspectorHtml() }
function hsRenderOutline(){ var el=$("#hsOutline"); if(el) el.innerHTML=hsOutlineHtml() }
async function hsUpload(file,folder){ if(!DB) throw new Error("no client"); var isVideo=/^video\//.test(file.type);
  if(isVideo && file.size>8*1048576) throw new Error(GX("videoTooBig").replace("{mb}",8)); if(!isVideo && file.size>12*1048576) throw new Error(GX("imageTooBig")); var path=(isVideo?"videos/":"photos/")+folder+"/"+Date.now()+"_"+file.name.replace(/[^a-zA-Z0-9._-]/g,"_"); var body=file, ct=file.type;
  if(!isVideo){ var raw=await new Promise(function(res,rej){ var r=new FileReader(); r.onload=function(){res(r.result)}; r.onerror=function(){rej(new Error("read"))}; r.readAsDataURL(file) }); body=await shrink(raw,1600,0.85); ct="image/jpeg" }
  var up=await storageUpload(path,body,{contentType:ct,upsert:false}); if(up.error) throw up.error; return DB.storage.from("photos").getPublicUrl(path).data.publicUrl }
function hsWire(){
  var root=$(".hs"); if(!root) return;
  var frame=$("#hsFrame");
  if(HS._onMsg) window.removeEventListener("message",HS._onMsg);
  HS._onMsg=function(e){ if(e.origin!==location.origin||!e.data) return; if(e.data.type==="bk-preview-ready"){ hsPush(true); setTimeout(hsScrollTo,700) } };
  window.addEventListener("message",HS._onMsg);
  frame.addEventListener("load",function(){ hsPush(true,800) });
  hsFit(); if(HS._onResize) window.removeEventListener("resize",HS._onResize); HS._onResize=hsFit; window.addEventListener("resize",hsFit);
  $("#hsDev").onclick=function(e){ var b=e.target.closest("button"); if(!b) return; HS.device=b.dataset.dev; $$("#hsDev button").forEach(function(x){ x.classList.toggle("on",x===b) }); $("#hsPv").className="hs-pv "+HS.device; hsFit(); hsRenderInsp() };
  $("#hsLang").onclick=function(e){ var b=e.target.closest("button"); if(!b) return; HS.lang=b.dataset.lang; $$("#hsLang button").forEach(function(x){ x.classList.toggle("on",x===b) }); hsPush(true); hsRenderInsp() };
  $("#hsReload").onclick=function(){ frame.src=hsPvUrl()+"&r="+Date.now() };
  $("#hsDiscard").onclick=function(){ if(!confirm(GX("hsDiscardConfirm"))) return; HS.draft={site:{},extras:{}}; HS.adDraft={}; HS.adNew=null; HS.bDraft=null; HS.adPendingDel={}; HS.bPendingDel=[]; if(HS.sel==="ad:new") HS.sel="row"; hsPush(true); hsRenderInsp(); hsRenderOutline(); hsDirtyUI() };
  $("#hsSave").onclick=async function(){ var btn=this, msg=$("#hsMsg"); var patch=Object.assign({},HS.draft.site); var ex={}; Object.keys(HS.draft.extras).forEach(function(k){ var v=HS.draft.extras[k]; ex[k]=(v===""||v===undefined)?null:v }); if(Object.keys(ex).length) patch.extras=ex;
    btn.disabled=true; btn.textContent=t("saving");
    try{
      if(Object.keys(patch).length){ await rpc("bk_admin_set_content",{p_token:ADM.token,p_patch:patch,p_country:COUNTRY});
        Object.keys(patch).forEach(function(k){ if(k==="extras"){ var cur=SITE.extras; if(typeof cur==="string"){ try{ cur=JSON.parse(cur) }catch(e){ cur={} } } cur=Object.assign({},cur||{},patch.extras); Object.keys(cur).forEach(function(kk){ if(cur[kk]===null) delete cur[kk] }); SITE.extras=cur } else SITE[k]=patch[k] });
        try{ localStorage.setItem(siteCacheKey(),JSON.stringify(SITE)) }catch(e){} }
      var adsChanged=false, codes=[], ids=Object.keys(HS.adDraft);
      for(var i=0;i<ids.length;i++){ var a=hsAdRow(ids[i]); if(!a) continue; var rr=await rpc("bk_admin_save_ad",hsAdPayload(a)); if(rr&&rr.code) codes.push(rr.code); adsChanged=true; (HS.adPendingDel[ids[i]]||[]).forEach(function(u){ replaceStorageFile(u) }) }
      if(HS.adNew){ var rn=await rpc("bk_admin_save_ad",hsAdPayload(Object.assign({id:"new"},HS.adNew))); if(rn&&rn.code) codes.push(rn.code); adsChanged=true }
      if(HS.bDraft && HS.bBefore){ for(var bi=0;bi<3;bi++){ var A=HS.bBefore[bi]||{items:[]}, B=HS.bDraft[bi]||{items:[]};
          var aU=A.enabled?(A.items||[]).map(function(x){return x.url}):[], bU=B.enabled?(B.items||[]).map(function(x){return x.url}):[];
          for(var k1=0;k1<bU.length;k1++){ if(aU.indexOf(bU[k1])===-1){ try{ var er=await rpc("bk_admin_engage",{p_token:ADM.token,p_country:COUNTRY,p_kind:"banner",p_ref_id:bi+1,p_ref_text:bU[k1],p_title:GX("engBannerN").replace("{n}",bi+1)}); if(er&&er.code) codes.push(er.code) }catch(e){} } }
          for(var k2=0;k2<aU.length;k2++){ if(bU.indexOf(aU[k2])===-1){ try{ await rpc("bk_admin_engage_end",{p_token:ADM.token,p_kind:"banner",p_ref_id:bi+1,p_ref_text:aU[k2],p_status:"ended"}) }catch(e){} } } } }
      if(adsChanged){ try{ ADM.adSlots=(await rpc("bk_admin_list_ads",{p_token:ADM.token,p_country:COUNTRY}))||[] }catch(e){} HS.adDraft={}; HS.adNew=null; HS.adPendingDel={}; if(HS.sel==="ad:new") HS.sel="row"; try{ await loadAdSlots() }catch(e){}
        var f=$("#hsFrame"); if(f&&f.contentWindow){ try{ f.contentWindow.postMessage({type:"bk-preview",reloadAds:true},location.origin) }catch(e){} } }
      HS.bPendingDel.forEach(function(u){ replaceStorageFile(u) }); HS.bPendingDel=[]; HS.bDraft=null; HS.bBefore=null; ADM._engDays=null;
      HS.draft={site:{},extras:{}}; applySectionGapVars(); applySiteExtras(); applyBannerSizeVar(); if(msg) msg.textContent=t("savedOk")+(codes.length?' · '+GX("engCodeIs")+' '+codes.join(", "):''); hsRenderOutline(); hsRenderInsp(); if(!adsChanged) hsPush(true);
    }catch(e){ if(msg) msg.textContent=e.message||"error" }
    btn.textContent=hsT("saveAll"); hsDirtyUI() };
  /* outline: select, eye, move */
  $("#hsOutline").onpointerdown=async function(e){
    if(e.button!==0 || e.target.closest("input,select,textarea")) return;
    var eye=e.target.closest("[data-hseye]"), mv=e.target.closest("[data-hsmv]"), it=e.target.closest("[data-hssel]");
    var aeye=e.target.closest("[data-hsaeye]"), amv=e.target.closest("[data-hsamv]"), beye=e.target.closest("[data-hsbeye]"), anew=e.target.closest("#hsAdNew");
    if(anew){ HS.adNew={id:"new",enabled:true,_mode:"upload"}; HS.sel="ad:new"; HS.selBy[HS.page]=HS.sel; hsDirtyUI(); hsRenderOutline(); hsRenderInsp(); hsPush(true); return }
    if(aeye){ var id=aeye.dataset.hsaeye, a=hsAdRow(id); if(a){ hsAdSet(id,"enabled",a.enabled===false); hsPush(true); hsRenderOutline(); hsRenderInsp() } return }
    if(amv){ var p2=amv.dataset.hsamv.split(":"); amv.disabled=true; try{ await rpc("bk_admin_move_ad",{p_token:ADM.token,p_id:+p2[0],p_dir:p2[1]}); ADM.adSlots=(await rpc("bk_admin_list_ads",{p_token:ADM.token,p_country:COUNTRY}))||[]; try{ await loadAdSlots() }catch(e2){} }catch(err){} hsRenderOutline(); hsPush(true); return }
    if(beye){ var bi=+beye.dataset.hsbeye; hsBSet(bi,"enabled",!hsBDraft()[bi].enabled); hsPush(true); hsRenderOutline(); hsRenderInsp(); return }
    if(eye){ var k=eye.dataset.hseye; if(k==="hero_bg"){ var cur=hsVal("c:hero_bg_type")||"sketch"; if(cur!=="none"){ hsSet("x:hero_bg_prev",cur); hsSet("c:hero_bg_type","none") } else hsSet("c:hero_bg_type",hsVal("x:hero_bg_prev")||"sketch") }
      else { var key=k==="hero_text"?"c:hero_enabled":k==="hero_stats"?"c:stats_enabled":(HS_EYE[k]||("x:home_"+k+"_on")); var v=hsVal(key); var on=v===""?true:(v!==false&&v!=="false"); hsSet(key,!on) }
      hsPush(true); hsRenderOutline(); hsRenderInsp(); return }
    if(mv){ var p=mv.dataset.hsmv.split(":"), key2=p[0], dir=+p[1]; var ord=hsOrder(hsMerged().extras), i=ord.indexOf(key2), j=i+dir; if(i<0||j<0||j>=ord.length) return; ord.splice(i,1); ord.splice(j,0,key2); hsSet("x:home_order",ord); hsPush(true); hsRenderOutline(); return }
    if(it){ HS.sel=it.dataset.hssel; HS.selBy[HS.page]=HS.sel; hsRenderOutline(); hsRenderInsp(); hsScrollTo() }
  };
  /* inspector: every control writes the draft and updates the preview */
  var insp=$("#hsInsp"), tmr=null;
  var readEl=function(el,col){ var ty=el.dataset.hst; if(ty==="bool") return el.checked; if(ty==="num") return el.value===""?null:+el.value;
    if(ty==="date") return el.value ? new Date(el.value+(el.dataset.hsend==="1"?"T23:59:59":"T00:00:00")).toISOString() : null;
    var v=String(el.value); return v.trim()==="" ? (col?"":null) : v };
  var onEdit=function(el,now){ var rer=el.dataset.hsr==="1", k;
    if(el.dataset.hsk!==undefined){ k=el.dataset.hsk; hsSet(k,readEl(el,k.indexOf("c:")===0)) }
    else if(el.dataset.hsa!==undefined){ k="a:"+el.dataset.hsa; hsAdSet(HS.sel.slice(3),el.dataset.hsa,readEl(el,true)); rer=true }
    else if(el.dataset.hsb!==undefined){ k="b:"+el.dataset.hsb; var bv=readEl(el,true); if(bv==="") bv=null; hsBSet(+HS.sel.slice(2),el.dataset.hsb,bv); rer=true }
    else if(el.dataset.hsbi!==undefined){ var cfg=hsBDraft()[+HS.sel.slice(2)]; if(cfg.items[+el.dataset.hsbi]) cfg.items[+el.dataset.hsbi].link=el.value; hsBSet(+HS.sel.slice(2),"items",cfg.items); rer=true; k="bi" }
    else return;
    var lbl=insp.querySelector('[data-hsv="'+k+'"]'); if(lbl) lbl.textContent=el.value+(el.dataset.hsunit||"");
    clearTimeout(tmr); tmr=setTimeout(function(){ hsPush(rer) }, now?0:(rer?220:40)) };
  var SEL="[data-hsk],[data-hsa],[data-hsb],[data-hsbi]";
  insp.oninput=function(e){ var el=e.target.closest(SEL); if(el && el.type!=="checkbox" && el.type!=="radio" && el.tagName!=="SELECT") onEdit(el,false) };
  insp.onchange=function(e){ var el=e.target.closest(SEL);
    if(el){ onEdit(el,true); var d=el.dataset; if(d.hsk==="c:hero_bg_type"||d.hsa==="_mode"||d.hsa==="enabled"||d.hsa==="linked_listing_id"||d.hsb==="size"||d.hsb==="sizeM"||d.hsb==="textEnabled"||d.hsb==="enabled") hsRenderInsp(); hsRenderOutline() }
    var up=e.target.closest("[data-hsup]"); if(up && up.files && up.files[0]){ var key=up.dataset.hsup, msg=up.closest(".fl").querySelector(".hs-upmsg"); if(msg) msg.textContent=hsT("uploading"); up.disabled=true;
      hsUpload(up.files[0],up.dataset.hsfolder).then(function(url){ hsSet(key,url); hsPush(true); hsRenderInsp() }).catch(function(err){ if(msg) msg.textContent=err.message||"error"; up.disabled=false }); return }
    var aup=e.target.closest("[data-hsaup]"); if(aup && aup.files && aup.files.length){ var files=Array.prototype.slice.call(aup.files), amsg=aup.closest(".fl").querySelector(".hs-upmsg"), id=HS.sel.slice(3); aup.disabled=true;
      (async function(){ try{ if(files.length>1 && files.some(function(f){ return /^video\//.test(f.type) })) throw new Error(t("adNoMultiVideo"));
          var urls=[], anyVideo=false; for(var i=0;i<files.length;i++){ var f=files[i], isV=/^video\//.test(f.type); if(isV) anyVideo=true; if(isV && f.size>adVideoMaxMb()*1048576) throw new Error(GX("adVideoTooBig").replace("{mb}",(f.size/1048576).toFixed(0)).replace("{max}",adVideoMaxMb()));
            if(amsg) amsg.textContent=hsT("uploading")+" "+(i+1)+"/"+files.length; urls.push(await hsUpload(f,"ads")) }
          var a=hsAdRow(id)||{}; var old=[].concat(a.image_url?[a.image_url]:[],a.image_urls||[]); if(old.length && id!=="new") (HS.adPendingDel[id]=HS.adPendingDel[id]||[]).push.apply(HS.adPendingDel[id],old);
          var single=anyVideo&&urls.length===1; hsAdSet(id,"image_url",urls[0]||null); hsAdSet(id,"image_urls",single?[]:urls); hsAdSet(id,"media_type",single?"video":"image"); hsAdSet(id,"_mode","upload");
          hsPush(true); hsRenderInsp(); hsRenderOutline() }catch(err){ if(amsg) amsg.textContent=err.message||"error"; aup.disabled=false } })(); return }
    var bup=e.target.closest("[data-hsbup]"); if(bup && bup.files && bup.files.length){ var bfiles=Array.prototype.slice.call(bup.files), bmsg=bup.closest(".fl").querySelector(".hs-upmsg"), bi=+HS.sel.slice(2); bup.disabled=true;
      (async function(){ try{ for(var i=0;i<bfiles.length;i++){ var f=bfiles[i], isV=/^video\//.test(f.type), isGif=f.type==="image/gif"; if(bmsg) bmsg.textContent=hsT("uploading")+" "+(i+1)+"/"+bfiles.length;
            var path=(isV?"videos/banners/":"photos/banners/")+Date.now()+"_"+i+"_"+f.name.replace(/[^a-zA-Z0-9._-]/g,"_"), body=f, ct=f.type;
            if(!isV && !isGif){ var raw=await new Promise(function(res,rej){ var r=new FileReader(); r.onload=function(){res(r.result)}; r.onerror=function(){rej(new Error("read"))}; r.readAsDataURL(f) }); body=await shrink(raw,1600,0.85); ct="image/jpeg" }
            var upr=await storageUpload(path,body,{contentType:ct,upsert:false}); if(upr.error) throw upr.error;
            hsBDraft()[bi].items.push({type:isV?"video":"image",url:DB.storage.from("photos").getPublicUrl(path).data.publicUrl,link:""}) }
          hsBSet(bi,"items",hsBDraft()[bi].items); hsPush(true); hsRenderInsp(); hsRenderOutline() }catch(err){ if(bmsg) bmsg.textContent=err.message||"error"; bup.disabled=false } })(); return } };
  insp.onclick=async function(e){
    var c=e.target.closest("[data-hsclear]"); if(c){ hsSet(c.dataset.hsclear,null); hsPush(true); hsRenderInsp(); return }
    var bc=e.target.closest("[data-hsbclear]"); if(bc){ hsBSet(+HS.sel.slice(2),bc.dataset.hsbclear,null); hsPush(true); hsRenderInsp(); return }
    var brm=e.target.closest("[data-hsbrm]"); if(brm){ var bi=+HS.sel.slice(2), removed=hsBDraft()[bi].items.splice(+brm.dataset.hsbrm,1); if(removed[0]) HS.bPendingDel.push(removed[0].url); hsBSet(bi,"items",hsBDraft()[bi].items); hsPush(true); hsRenderInsp(); hsRenderOutline(); return }
    var ac=e.target.closest("[data-hsaclear]"); if(ac){ var id=HS.sel.slice(3), a=hsAdRow(id)||{}; var old=[].concat(a.image_url?[a.image_url]:[],a.image_urls||[]); if(old.length && id!=="new") (HS.adPendingDel[id]=HS.adPendingDel[id]||[]).push.apply(HS.adPendingDel[id],old); hsAdSet(id,"image_url",null); hsAdSet(id,"image_urls",[]); hsAdSet(id,"media_type","image"); hsPush(true); hsRenderInsp(); hsRenderOutline(); return }
    var del=e.target.closest("#hsAdDel"); if(del){ if(!confirm(t("confirmDel"))) return; var did=HS.sel.slice(3); del.disabled=true; var adRow=hsAdRow(did)||{}, adMedia=[].concat(adRow.image_url?[adRow.image_url]:[],adRow.image_urls||[]).map(function(u){ return storagePathFromUrl(u) }).filter(Boolean); try{ await rpc("bk_admin_delete_ad",{p_token:ADM.token,p_id:+did}); if(adMedia.length){ try{ await storageTrash(adMedia) }catch(e3){} } delete HS.adDraft[did]; ADM.adSlots=(await rpc("bk_admin_list_ads",{p_token:ADM.token,p_country:COUNTRY}))||[]; try{ await loadAdSlots() }catch(e2){} HS.sel="row"; HS.selBy[HS.page]=HS.sel; hsRenderOutline(); hsRenderInsp(); hsPush(true); hsDirtyUI() }catch(err){ alert(err.message||"error"); del.disabled=false } return }
    var ar=e.target.closest("[data-arange]"); if(ar){ ADM.range=+ar.dataset.arange; ADM._anLoaded=false; render(); return }
    var g=e.target.closest("[data-hsgo]"); if(g){ if(hsDirty() && !confirm(hsT("dirty"))) return; HS.draft={site:{},extras:{}}; HS.adDraft={}; HS.adNew=null; HS.bDraft=null; window.onbeforeunload=null; ADM.tab=g.dataset.hsgo; render() } };
  hsDirtyUI();
}
function kpiCard(label,cur,prev,color,sparkKey){
  var c=+cur||0, p=+prev||0, pct = p ? Math.round((c-p)/p*100) : (c?100:0), up=c>=p;
  var spark = sparkKey && ADM.an && ADM.an.series ? svgSpark(ADM.an.series, sparkKey, color||"var(--navy)") : "";
  return '<div class="kpi"><div class="kpi-l">'+label+'</div><div class="kpi-v ltr" '+(color?'style="color:'+color+'"':'')+'>'+fmtN(c)+'</div>'+
    (prev!==undefined && prev!==null ? '<div class="kpi-d '+(up?"up":"down")+'"><span class="ltr">'+(up?"▲":"▼")+' '+Math.abs(pct)+'%</span> <small>'+GX("vsPrev")+'</small></div>' : '')+spark+'</div>' }
function kpiGrid(an,full){
  var k=an.kpi||{};
  return '<div class="kpis">'+
    kpiCard(GX("kViews"),k.views,k.views_prev,"var(--navy)","views")+
    kpiCard(GX("kVisitors"),k.visitors,k.visitors_prev,"#2563EB","visitors")+
    kpiCard(GX("kListingViews"),k.listing_views,k.listing_views_prev,"#7C3AED")+
    kpiCard(GX("kNewUsers"),k.new_users,k.new_users_prev,"var(--ok)","new_users")+
    kpiCard(GX("kNewListings"),k.new_listings,k.new_listings_prev,"var(--gold)","new_listings")+
    kpiCard(GX("kContacts"),k.contacts,k.contacts_prev,"#0EA5A0","contacts")+
    kpiCard(GX("kAdClicks"),k.ad_clicks,k.ad_clicks_prev,"#D9463A","ad_clicks")+
    (full ? kpiCard(GX("kAdViews"),k.ad_views,null,"#8A6522")+kpiCard(GX("kSaves"),k.saves,null,"#DB2777")+kpiCard(GX("kActiveUsers"),k.active_users,null,"var(--ok)") : '')+
  '</div>' }
function adminEngageBody(){
  var all=ADM.eng, q=(ADM.eq||"").toLowerCase().trim();
  var R=[[7,GX("r7")],[30,GX("r30")],[90,GX("r90")],[365,GX("r365")],[0,GX("r0")]], cur=ADM.erange==null?30:ADM.erange;
  var head='<div class="dash-top"><div class="arange">'+R.map(function(r){ return '<button type="button" class="'+(cur===r[0]?"on":"")+'" data-erange="'+r[0]+'">'+r[1]+'</button>' }).join("")+'</div>'+
    '<input class="asearch" id="engQ" data-allow-autofill placeholder="'+esc(GX("engSearchPH"))+'" value="'+esc(ADM.eq||"")+'" style="max-width:340px">'+
    '<button type="button" class="ab" id="engAddBtn" style="margin-inline-start:auto">'+GX("engManual")+'</button></div>'+
    '<div class="hintx" style="margin-bottom:14px">'+GX("engHint")+'</div>'+
    (ADM.engLastCode?'<div class="ecodebox" style="margin-bottom:14px">'+GX("engCodeIs")+' <b class="ltr">'+esc(ADM.engLastCode)+'</b> <button type="button" class="ab" data-ecopy="'+esc(ADM.engLastCode)+'">'+GX("engCopy")+'</button></div>':'')+
    (ADM.engAdd ? engAddForm() : '');
  if(!all) return head+'<div class="blk"><div class="in adashempty">'+(ADM.engErr||t("loading"))+'</div></div>';
  var rows=all.filter(function(e){ if(!q) return true; var o=e.obj||{}; return [e.code,e.client_name,e.title,e.ref_text,e.phone,e.notes,o.poster,o.sponsor,o.ref,o.label].join(" ").toLowerCase().indexOf(q)>-1 });
  var live=function(k){ return rows.filter(function(e){ return e.kind===k && (e.live||e.scheduled) }) }, hist=function(k){ return rows.filter(function(e){ return e.kind===k && !(e.live||e.scheduled) }) };
  var kpis='<div class="kpis" style="margin-bottom:16px">'+["featured","ad","banner"].map(function(k){ return '<div class="kpi"><div class="kpi-l">'+engKindLabel(k)+' · '+GX("engLive")+'</div><div class="kpi-v ltr">'+live(k).length+'</div><div class="kpi-d"><small>'+GX("engHistory")+': <span class="ltr">'+hist(k).length+'</span></small></div></div>' }).join("")+'</div>';
  var sec=function(k,ico){ var lv=live(k), hs=hist(k); return '<div class="blk" style="margin-top:16px"><h3>'+ico+' '+engKindLabel(k)+' <span class="n">'+lv.length+'</span></h3><div class="in eng-in">'+
    '<div class="esub">'+GX("engLive")+'</div>'+(lv.length?'<div class="elist">'+lv.map(engRow).join("")+'</div>':'<div class="adashempty">'+GX("engNoneLive")+'</div>')+
    '<div class="esub">'+GX("engHistory")+' · '+(cur===0?GX("r0"):R.filter(function(r){ return r[0]===cur })[0][1])+'</div>'+(hs.length?'<div class="elist">'+hs.map(engRow).join("")+'</div>':'<div class="adashempty">'+GX("engEmpty")+'</div>')+'</div></div>' };
  return head+kpis+sec("featured",AICO.star)+sec("ad",AICO.ads)+sec("banner",AICO.banner);
}
function adminDashboardBody(s){
  var an=ADM.an;
  var head=admScopeNote()+'<div class="dash-top">'+rangeTabs()+'<span class="hintx">'+(an?'':(ADM.anErr?ADM.anErr:t("loading")))+'</span></div>';
  if(!an) return head+'<div class="blk"><div class="in adashempty">'+t("loading")+'</div></div>';
  var alerts='<div class="blk"><h3>'+t("recentAlertsH")+'</h3><div class="in">'+((ADM.alerts&&ADM.alerts.length) ? '<div class="onlinelist">'+ADM.alerts.slice(0,5).map(function(n){
       var lbl = n.title==="new_feedback"?t("newFeedbackAlert"):n.title==="new_report"?t("newReportAlert"):n.title;
       return '<a class="onlinerow" data-goto="'+(n.link||"").replace("/#/admin:","")+'"><span class="onlinedot" style="background:'+(n.is_read?"var(--light)":"var(--danger)")+'"></span><span style="font-size:13px">'+lbl+'</span><span class="ltr" style="margin-inline-start:auto;color:var(--light);font-size:11px">'+when(n.created_at)+'</span></a>' }).join("")+'</div>' : '<div class="adashempty">'+t("noAlerts")+'</div>')+'</div></div>';
  return head+kpiGrid(an,false)+scopeCountriesBlocks(an)+
    '<div class="blk" style="margin-top:16px"><h3>'+GX("chVisits")+'</h3><div class="in">'+svgLine(an.series,["views","visitors"],["#14213D","#2563EB"],[GX("kViews"),GX("kVisitors")])+'</div></div>'+
    '<div class="agrid2" style="margin-top:16px">'+
      '<div class="blk"><h3>'+GX("topListingsH")+'<button class="ab" data-atab="stats" style="margin-inline-start:auto">'+t("openFullAnalytics")+'</button></h3><div class="in" style="padding:0">'+topListingsTable(an,6)+'</div></div>'+
      '<div class="blk"><h3>'+GX("topAdsH")+'</h3><div class="in" style="padding:0">'+adsPerfTable(an,false)+'</div></div>'+
    '</div>'+
    '<div class="agrid3" style="margin-top:16px">'+
      '<div class="blk"><h3>'+GX("pagesH")+'</h3><div class="in">'+barList(an.pages,function(x){ return x.view },"n")+'</div></div>'+
      '<div class="blk"><h3>'+GX("countriesH")+'</h3><div class="in">'+barList(an.countries,function(x){ return x.country },"n","var(--gold)")+'</div></div>'+
      '<div class="blk"><h3>'+GX("usersActH")+'</h3><div class="in">'+barList([{k:GX("act24"),n:an.users_activity.last_24h},{k:GX("act7"),n:an.users_activity.last_7d},{k:GX("act30"),n:an.users_activity.last_30d},{k:GX("actOld"),n:an.users_activity.older}],function(x){ return x.k },"n","var(--ok)")+'</div></div>'+
    '</div>'+
    '<div class="agrid2" style="margin-top:16px">'+healthStrip(an)+alerts+'</div>'+
    '<div class="blk" style="margin-top:16px"><h3>'+t("storageUsageH")+'</h3><div class="in">'+storageUsageCardBody()+'</div></div>';
}
function adminAnalyticsBody(){
  var an=ADM.an, st=ADM.stats;
  var head=admScopeNote()+'<div class="dash-top">'+rangeTabs()+'</div>';
  if(!an) return head+'<div class="blk"><div class="in adashempty">'+(ADM.anErr||t("loading"))+'</div></div>';
  var ls=an.listings_status||{};
  return head+kpiGrid(an,true)+scopeCountriesBlocks(an)+
    '<div class="blk" style="margin-top:16px"><h3>'+GX("chVisits")+'</h3><div class="in">'+svgLine(an.series,["views","visitors"],["#14213D","#2563EB"],[GX("kViews"),GX("kVisitors")])+'</div></div>'+
    '<div class="agrid2" style="margin-top:16px">'+
      '<div class="blk"><h3>'+GX("chGrowth")+'</h3><div class="in">'+svgLine(an.series,["new_users","new_listings"],["#2E7D5B","#C4881F"],[GX("kNewUsers"),GX("kNewListings")])+'</div></div>'+
      '<div class="blk"><h3>'+GX("chEngage")+'</h3><div class="in">'+svgLine(an.series,["contacts","ad_clicks"],["#0EA5A0","#D9463A"],[GX("kContacts"),GX("kAdClicks")])+'</div></div>'+
    '</div>'+
    '<div class="blk" style="margin-top:16px"><h3>'+GX("topListingsH")+'</h3><div class="in" style="padding:0">'+topListingsTable(an,15)+'</div></div>'+
    '<div class="blk" style="margin-top:16px"><h3>'+GX("topAdsH")+'</h3><div class="in"><div class="hintx" style="margin-bottom:10px">'+GX("adsPerfHint")+'</div>'+adsPerfTable(an,true)+'</div></div>'+
    '<div class="agrid3" style="margin-top:16px">'+
      '<div class="blk"><h3>'+GX("pagesH")+'</h3><div class="in">'+barList(an.pages,function(x){ return x.view },"n")+'</div></div>'+
      '<div class="blk"><h3>'+GX("countriesH")+'</h3><div class="in">'+barList(an.countries,function(x){ return x.country },"n","var(--gold)")+'</div></div>'+
      '<div class="blk"><h3>'+GX("devicesH")+'</h3><div class="in">'+barList(an.devices,function(x){ return GX_T["device_"+x.device]?GX("device_"+x.device):x.device },"n","#7C3AED")+'</div></div>'+
      '<div class="blk"><h3>'+GX("referrersH")+'</h3><div class="in">'+barList(an.referrers,function(x){ return x.referrer==="direct"?GX("direct"):x.referrer },"n","#2563EB")+'</div></div>'+
      '<div class="blk"><h3>'+GX("contactKindsH")+'</h3><div class="in">'+barList(an.contact_kinds,function(x){ return GX_T["ck_"+x.kind]?GX("ck_"+x.kind):x.kind },"n","#0EA5A0")+'</div></div>'+
      '<div class="blk"><h3>'+GX("listingsStatusH")+'</h3><div class="in">'+barList(Object.keys(ls).map(function(k){ return {k:(k==="hidden"?GX("st_hidden"):t("st_"+k)||k), n:ls[k]} }),function(x){ return x.k },"n","var(--navy)")+'</div></div>'+
    '</div>'+
    '<div class="agrid2" style="margin-top:16px">'+
      '<div class="blk"><h3>'+GX("usersActH")+'</h3><div class="in">'+barList([{k:GX("act24"),n:an.users_activity.last_24h},{k:GX("act7"),n:an.users_activity.last_7d},{k:GX("act30"),n:an.users_activity.last_30d},{k:GX("actOld"),n:an.users_activity.older}],function(x){ return x.k },"n","var(--ok)")+'</div></div>'+
      '<div class="blk"><h3>'+t("onlineUsersH")+' <span class="ltr" style="color:var(--grey);font-weight:400">('+((an.kpi||{}).online_now||0)+')</span></h3><div class="in">'+
        ((st&&st.online_list&&st.online_list.length) ? '<div class="onlinelist">'+st.online_list.map(function(u){ return '<a data-byuser="'+u.id+'" data-name="'+(u.name||"")+'" class="onlinerow"><span class="onlinedot"></span>'+(u.name||t("anonGuest"))+'<span class="ltr" style="margin-inline-start:auto;color:var(--light);font-size:11.5px">'+when(u.last_seen)+'</span></a>' }).join("")+'</div>' : '<div class="adashempty">'+t("noOneOnline")+'</div>')+'</div></div>'+
    '</div>'+healthStrip(an);
}
function adminVerifyHtml(){
  var list=ADM.vf, purpose=function(p){ return GX(p==="reset"?"vfReset":"vfSignup") };
  var rows=list===undefined ? '<div class="hintx">'+t("loading")+'</div>' : !list.length ? '<div class="adashempty">'+GX("vfNone")+'</div>' :
    '<div class="elist">'+list.map(function(v){ return '<div class="agcard2 vfrow"><div class="agc-id"><b class="ltr">'+esc(v.phone)+'</b><small>'+purpose(v.purpose)+(v.name?' · '+esc(v.name):'')+' · '+when(v.wa_sent_at||v.created_at)+'</small></div>'+
      '<div class="agc-meta"><span class="vfcode ltr">'+esc(v.code)+'</span></div>'+
      '<div class="agc-acts"><button type="button" class="ab ok" data-vfok="'+v.id+'">'+GX("vfConfirm")+'</button><button type="button" class="ab" data-vfno="'+v.id+'">'+GX("vfReject")+'</button></div></div>' }).join("")+'</div>';
  var pending='<div class="blk"><h3>'+GX("vfT")+(list&&list.length?' <span class="n">'+list.length+'</span>':'')+'</h3><div class="in"><div class="hintx" style="margin-bottom:10px">'+GX("vfHint")+'</div>'+rows+'</div></div>';
  var ready=GSX("verify_wa_ready",false)===true||GSX("verify_wa_ready",false)==="true";
  var emailReady=GSX("verify_email_ready",false)===true||GSX("verify_email_ready",false)==="true";
  var gchk=function(k,l,d){ return '<label class="xcheck"><input type="checkbox" data-gk="'+k+'" data-gt="bool"'+(GSX(k,d)!==false&&GSX(k,d)!=="false"?' checked':'')+'><span>'+l+'</span></label>' };
  var gtxt=function(k,l,d){ return '<div class="fl"><label>'+l+'</label><input data-gk="'+k+'" data-gt="str" value="'+esc(String(GSX(k,"")))+'" placeholder="'+esc(String(d||""))+'"></div>' };
  var gnum=function(k,l,d,mn,mx){ return '<div class="fl"><label>'+l+'</label><input type="number" data-gk="'+k+'" data-gt="num" value="'+esc(String(GSX(k,"")))+'" placeholder="'+d+'" min="'+mn+'" max="'+mx+'"></div>' };
  // these are the DEFAULTS every country starts from; a country's own card on the "الدول" page can override on/off per channel
  var settings='<div class="blk"><h3>'+GX("vfSetT")+'</h3><div class="in" id="vfSet"><div class="chkgrid">'+gchk("verify_telegram_on",GX("vfSetTg"),true)+gchk("verify_whatsapp_on",GX("vfSetWa"),true)+gchk("verify_wa_code_on",GX("vfSetWaCode"),true)+gchk("verify_email_on",GX("vfSetEmail"),true)+gchk("verify_required_post",GX("vfSetReq"),true)+'</div>'+
    '<div class="hintx" style="margin:2px 0 8px;color:'+(ready?'var(--ok)':'var(--grey)')+'">'+(ready?'✓ ':'○ ')+GX(ready?"vfWaReady":"vfWaNotReady")+'</div>'+
    '<div class="hintx" style="margin:2px 0 8px;color:'+(emailReady?'var(--ok)':'var(--grey)')+'">'+(emailReady?'✓ ':'○ ')+GX(emailReady?"vfEmailReady":"vfEmailNotReady")+'</div>'+
    '<div class="row3">'+gtxt("verify_wa_template",GX("vfSetWaTpl"),"balkoun_code")+gtxt("verify_wa_lang",GX("vfSetWaLang"),"ar")+gnum("verify_ticket_hours",GX("vfSetHours"),48,1,168)+'</div>'+
    '<div class="hintx" style="margin:12px 0 6px"><b>'+GX("vfSignupT")+'</b></div><div class="chkgrid">'+gchk("signup_consent_on",GX("vfConsentOn"),true)+gchk("signup_consent_default",GX("vfConsentDef"),true)+gchk("account_tg_button",GX("vfTgBtn"),true)+'</div>'+
    '<div class="row3">'+gtxt("signup_consent_ar",GX("vfConsentTxt")+" (ar)",GX_T.auConsentL.ar)+gtxt("signup_consent_en",GX("vfConsentTxt")+" (en)",GX_T.auConsentL.en)+gtxt("signup_consent_de",GX("vfConsentTxt")+" (de)",GX_T.auConsentL.de)+'</div>'+
    '<div class="xactions"><button class="ab ok" id="vfSetSave">'+t("save")+'</button><span class="xmsg" id="vfSetMsg"></span></div></div></div>';
  return pending+settings }
function adminUsersBody(d){
  var list=(d.users||[]).slice();
  list.sort(function(a,b){ return ADM.userSort==="older" ? new Date(a.created_at)-new Date(b.created_at) : new Date(b.created_at)-new Date(a.created_at) });
  if(ADM.userLevelFilter) list=list.filter(function(u){ return u.level===ADM.userLevelFilter });
  if(ADM.userBlockedFilter==="blocked") list=list.filter(function(u){ return u.blocked });
  if(ADM.userBlockedFilter==="active") list=list.filter(function(u){ return !u.blocked });
  var uact=ADM.uact||{}, lastSeen=function(u){ var a=uact[u.id]; return a&&a.last_seen_at?new Date(a.last_seen_at):null };
  if(ADM.userActFilter){ var lim=ADM.userActFilter==="old"?null:Date.now()-(+ADM.userActFilter)*86400000; list=list.filter(function(u){ var d=lastSeen(u); return lim===null ? (!d || d.getTime()<Date.now()-30*86400000) : (d && d.getTime()>=lim) }) }
  var sw=function(cls,uid,on,title){ return '<label class="xswitch" title="'+esc(title||"")+'"><input type="checkbox" class="'+cls+'" data-uid="'+uid+'"'+(on?" checked":"")+'><i></i></label>' };
  var toolbar='<div class="rtop" style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">'+
    '<input id="aqU" placeholder="'+t("searchPH")+'" class="asearch" style="flex:1;min-width:200px;width:auto">'+
    '<select id="uSortPick" class="lvlpick"><option value="newer"'+(ADM.userSort!=="older"?" selected":"")+'>'+t("sortNewerUsers")+'</option><option value="older"'+(ADM.userSort==="older"?" selected":"")+'>'+t("sortOlderUsers")+'</option></select>'+
    '<select id="uLevelPick" class="lvlpick"><option value="">'+t("allLevels")+'</option>'+LEVELS_ALL.map(function(lv){ return '<option value="'+lv+'"'+(ADM.userLevelFilter===lv?" selected":"")+'>'+t("lv_"+lv)+'</option>' }).join("")+'</select>'+
    '<select id="uBlockPick" class="lvlpick"><option value="">'+t("allUsers")+'</option><option value="active"'+(ADM.userBlockedFilter==="active"?" selected":"")+'>'+t("activeOnly")+'</option><option value="blocked"'+(ADM.userBlockedFilter==="blocked"?" selected":"")+'>'+t("blockedOnly")+'</option></select>'+
    '<select id="uActPick" class="lvlpick"><option value="">'+GX("colLastSeen")+'</option><option value="1"'+(ADM.userActFilter==="1"?" selected":"")+'>'+GX("act24")+'</option><option value="7"'+(ADM.userActFilter==="7"?" selected":"")+'>'+GX("act7")+'</option><option value="30"'+(ADM.userActFilter==="30"?" selected":"")+'>'+GX("act30")+'</option><option value="old"'+(ADM.userActFilter==="old"?" selected":"")+'>'+GX("actOld")+'</option></select>'+
    '<span class="n" style="font-size:13px;color:var(--grey)"><span class="ltr">'+list.length+'</span> '+GX("uCount")+'</span></div>';
  toolbar=adminVerifyHtml()+toolbar;
  var rows=list.map(function(u){
    var nm=((u.name||"")+" "+(u.family_name||"")).trim()||"—", isAdmin=u.role==="admin", open=ADM.userOpen===u.id;
    var joined=u.created_at?new Date(u.created_at).toLocaleDateString(L==="ar"?"ar-SY":L==="de"?"de-DE":L==="fr"?"fr-FR":"en-GB",{year:"numeric",month:"short",day:"numeric"}):"";
    var html='<tr data-row-text="'+esc((nm+" "+(u.phone||"")+" "+(u.member_no||"")).toLowerCase())+'" class="'+(open?"uopen":"")+'">'+
      '<td data-label="'+t("contactName")+'"><div class="ucell">'+avatar(u.avatar_url,u.name,36)+'<div>'+scopeFlag(u.country)+'<a data-byuser="'+u.id+'" data-name="'+esc(nm)+'" class="uname">'+esc(nm)+'</a>'+levelBadge(u.level)+(u.phone_verified===false?' <span class="st st-removed" title="'+esc(GX("uUnverified"))+'">'+GX("uUnverified")+'</span>':'')+
        '<div class="usub">'+(u.member_no?'<b class="ltr">'+esc(u.member_no)+'</b> · ':'')+'<span class="ltr">'+(u.phone||GX("uNoPhone"))+'</span>'+(joined?' · '+GX("uJoined")+' '+joined:'')+'</div></div></div></td>'+
      '<td data-label="'+GX("colLastSeen")+'">'+(function(){ var d=lastSeen(u), a=uact[u.id]||{}; var fresh=d && (Date.now()-d.getTime())<86400000; return '<span class="'+(fresh?"useen-fresh":"useen")+'">'+(d?when(d.toISOString()):GX("never"))+'</span>'+(a.views_30d?'<div class="usub"><span class="ltr">'+a.views_30d+'</span> '+GX("kViews")+' · 30d</div>':'') })()+'</td>'+
      '<td data-label="'+t("myAds")+'" class="ltr unum">'+(u.countries?'<span class="sflag">'+String(u.countries).split(",").map(function(cc){ return flagSvg(cc) }).join("")+'</span>':'')+(u.listings||0)+(uact[u.id]&&uact[u.id].live_listings!=null?' <small style="color:var(--light)">('+uact[u.id].live_listings+' '+t("st_live")+')</small>':'')+'</td>'+
      '<td data-label="'+t("ratingCol")+'" class="ltr unum">'+(u.rating?'★ '+u.rating:'—')+'</td>'+
      '<td data-label="'+t("levelCol")+'">'+(isAdmin?'<span class="lvl lvl-vip">Admin</span>':'<select class="lvlpick" data-uid="'+u.id+'" title="'+GX("uLevelHint")+'">'+LEVELS_ALL.map(function(lv){ return '<option value="'+lv+'"'+(u.level===lv?" selected":"")+'>'+t("lv_"+lv)+'</option>' }).join("")+'</select>')+'</td>'+
      '<td data-label="'+t("autoApprove")+'">'+(isAdmin?'':sw("skipRev",u.id,u.skip_review,GX("uAutoHint")))+'</td>'+
      '<td data-label="'+GX("cardLogoCol")+'">'+(isAdmin?'':sw("cardLogo",u.id,(ADM.cardLogos||[]).indexOf(u.id)>-1,GX("cardLogoHint")))+'</td>'+
      '<td data-label="'+t("role")+'"><span class="st '+(u.blocked?"st-removed":"st-live")+'">'+(u.blocked?GX("uBlocked"):GX("uActive"))+'</span></td>'+
      '<td data-label="">'+(isAdmin?'':'<button class="ab" data-uopen="'+u.id+'">'+(open?GX("uClose"):GX("uActions")+' ▾')+'</button>')+'</td></tr>';
    if(open && !isAdmin){
      html+='<tr class="udetail"><td colspan="9"><div class="udrawer">'+
        '<div class="ugroup"><b>'+GX("uSummary")+'</b><div class="ubtns">'+
          '<button class="ab" data-byuser="'+u.id+'" data-name="'+esc(nm)+'">'+GX("uViewListings")+' ('+(u.listings||0)+')</button>'+
          '<button class="ab" data-umsg="'+u.id+'">'+GX("uMessage")+'</button>'+
          '<button class="ab" data-arate="'+u.id+'">★ '+t("rateMember")+'</button></div></div>'+
        '<div class="ugroup"><b>'+GX("uModeration")+'</b><div class="ubtns">'+
          (u.avatar_url?'<button class="ab" data-clravatar="'+u.id+'">'+t("clearPhoto")+'</button>':'')+
          (u.bio?'<button class="ab" data-clrbio="'+u.id+'">'+t("clearBio")+'</button>':'')+
          (can("passwords")?'<button class="ab" data-apw="'+u.id+'">'+t("resetPass")+'</button>':'')+
          (!u.avatar_url&&!u.bio&&!can("passwords")?'<span class="hintx">—</span>':'')+'</div></div>'+
        '<div class="ugroup"><b>'+GX("uDanger")+'</b><div class="ubtns">'+
          '<button class="ab '+(u.blocked?"ok":"bad")+'" data-ablock="'+u.id+'" data-on="'+(u.blocked?"0":"1")+'">'+(u.blocked?t("unblock"):t("block"))+'</button></div></div>'+
        '</div></td></tr>';
    }
    if(ADM.rateTarget===u.id){
      html+='<tr class="udetail"><td colspan="9"><div class="udrawer" style="display:block">'+
        '<b style="font-size:13.5px">'+t("rateMember")+' — '+esc(nm)+'</b>'+
        '<div class="starpick" id="astarpick" style="margin-top:8px">'+[1,2,3,4,5].map(function(nS){ return '<span data-astar="'+nS+'" class="'+(nS<=ADM.rateStars?"on":"")+'">★</span>' }).join("")+'</div>'+
        '<textarea id="aRevBody" maxlength="300" placeholder="'+t("reviewPH")+'" style="margin-top:8px;width:100%;max-width:420px"></textarea>'+
        '<div class="xactions"><button class="ab ok" id="aRevSave">'+t("submitReview")+'</button><button class="ab" id="aRevCancel">'+t("cancel")+'</button><span class="xmsg">'+(ADM.rateMsg||"")+'</span></div></div></td></tr>';
    }
    if(ADM.pwTarget===u.id){
      html+='<tr class="udetail"><td colspan="9"><div class="udrawer" style="display:block">'+
        '<b style="font-size:13.5px">'+t("resetPass")+' — '+esc(nm)+'</b>'+
        '<div class="xactions" style="flex-wrap:wrap"><input id="aNewPass" type="text" placeholder="'+t("min6")+'" style="max-width:220px">'+
        '<button class="ab ok" id="aPwSave">'+t("savePass")+'</button><button class="ab" id="aPwCancel">'+t("cancel")+'</button><span class="xmsg">'+(ADM.pwMsg||"")+'</span></div>'+
        '<div class="hintx" style="margin-top:6px">'+t("adminPwHint")+'</div></div></td></tr>';
    }
    return html }).join("");
  return toolbar+'<div class="atable atable-stack utable"><table><thead><tr>'+
    [t("contactName"),GX("colLastSeen"),t("myAds"),t("ratingCol"),t("levelCol"),t("autoApprove"),GX("cardLogoCol"),t("role"),''].map(function(h){ return '<th>'+h+'</th>' }).join("")+
    '</tr></thead><tbody id="aUserBody">'+rows+'</tbody></table></div>';
}
function stFileRow(f, actions, kindLabel){
  var full=String(f.name), inTrash=full.indexOf("trash/")===0, p=inTrash?full.slice(6):full, parts=p.split("/"), base=parts.pop(), folder=parts.join("/");
  var pub=CONFIG.supabaseUrl+"/storage/v1/object/public/photos/"+encodeURI(full);
  return '<div class="strow"><div class="strow-main"><b class="ltr" title="'+esc(base)+'">'+esc(base)+'</b><small class="ltr">'+esc(folder||"—")+' · '+stSize(f.bytes)+(f.created?' · '+esc(f.created):'')+(kindLabel?' · '+kindLabel:'')+'</small></div>'+
    '<div class="strow-acts"><a class="ab" href="'+pub+'" target="_blank" rel="noopener" style="text-decoration:none">'+GX("stOpen")+'</a>'+actions+'</div></div>' }
function adminStorageBody(limitBlock){
  if(ADM.storageReport && ADM.storageReport.error) return '<div class="done2"><b>'+GX("loadFailed")+'</b><div class="hintx">'+esc(ADM.storageReport.error)+'</div><button class="ab" id="stRefresh" style="margin-top:8px">'+GX("retryBtn")+'</button></div>';
  var r=ADM.storageReport, plan=String(SX("plan_name","pro")), pl=ST_PLANS[plan]||ST_PLANS.pro, usageUrl="https://supabase.com/dashboard/project/coajrqynjrptujmzjjdh/settings/billing/usage";
  var planCard=xForm("xPlan",GX("stPlanH"),GX("stEgressNote"),
    xSelect("plan_name",GX("stPlan"),"pro",[["free",GX("stPlanFree")],["pro",GX("stPlanPro")]])+
    '<div class="row"><div class="fl"><label>'+GX("stStorageLimit")+'</label><div class="stfact ltr">'+stSize(pl.storage*1048576)+'</div></div>'+
    '<div class="fl"><label>'+GX("stEgress")+'</label><div class="stfact ltr">'+stSize(pl.egress*1048576)+' / '+(L==="ar"?"شهر":L==="en"?"month":"Monat")+'</div></div></div>'+
    '<div style="display:flex;gap:8px;flex-wrap:wrap"><a class="ab" href="'+usageUrl+'" target="_blank" rel="noopener" style="display:inline-block;text-decoration:none">'+GX("stOpenUsage")+'</a>'+
    '<a class="ab" href="https://supabase.com/dashboard/project/coajrqynjrptujmzjjdh/reports/storage" target="_blank" rel="noopener" style="display:inline-block;text-decoration:none">'+GX("stOpenEgress")+'</a></div>');
  var usage='<div class="blk" style="margin-top:16px"><h3>'+GX("stUsageH")+'<button class="ab" id="stRefresh" style="margin-inline-start:auto">'+AICO.refresh+' '+GX("stRefresh")+'</button></h3><div class="in">'+storageUsageCardBody()+'</div></div>';
  if(!r) return planCard+usage+limitBlock+'<div class="blk" style="margin-top:16px"><div class="in adashempty">'+t("loading")+'</div></div>';
  var total=+r.total_bytes||1;
  var kinds='<div class="blk" style="margin-top:16px"><h3>'+GX("stByKindH")+'</h3><div class="atable"><table><thead><tr><th>'+GX("stKind")+'</th><th>'+GX("stFiles")+'</th><th>'+GX("stSize")+'</th><th style="width:40%">'+GX("stShare")+'</th></tr></thead><tbody>'+
    (r.groups||[]).map(function(g){ var pct=Math.round(g.bytes/total*100); return '<tr><td>'+(GX_T["k_"+g.kind]?GX("k_"+g.kind):g.kind)+'</td><td class="ltr">'+g.files+'</td><td class="ltr"><b>'+stSize(g.bytes)+'</b></td>'+
      '<td><div class="stbar"><i style="width:'+pct+'%;background:'+(g.kind==="orphans"?"var(--danger)":g.kind==="ad_videos"?"var(--gold)":"var(--navy)")+'"></i></div><span class="ltr stpct">'+pct+'%</span></td></tr>' }).join("")+
    '</tbody></table></div></div>';
  var orphanFiles=(r.orphans||[]).reduce(function(a,o){ return a+(+o.files||0) },0), orphanBytes=(r.orphans||[]).reduce(function(a,o){ return a+(+o.bytes||0) },0);
  var orphans='<div class="blk" style="margin-top:16px"><h3><span class="hd2"><span>'+GX("stOrphansH")+'</span>'+(orphanFiles?'<small class="ltr" style="color:var(--danger)">'+orphanFiles+' '+' · '+stSize(orphanBytes)+'</small>':'')+'</span></h3><div class="in">'+
    '<div class="hintx" style="margin-bottom:10px">'+GX("stOrphansHint")+'</div>'+
    (orphanFiles ? '<div class="stlist" style="margin-bottom:12px">'+
        (r.orphan_items||[]).map(function(f){ return stFileRow(f, (ADM.isSuper?'<button type="button" class="ab bad" data-stdel="'+esc(f.name)+'">'+t("del")+'</button>':'')) }).join("")+
        (orphanFiles>(r.orphan_items||[]).length?'<div class="hintx">+'+(orphanFiles-(r.orphan_items||[]).length)+'</div>':'')+'</div>'+
        (ADM.isSuper?'<div class="xactions"><button class="ab bad" id="stDelOrphans" data-n="'+orphanFiles+'">'+GX("stDelOrphans")+'</button><span class="xmsg" id="stDelMsg"></span></div>':'')
      : '<div class="adashempty" style="text-align:start;padding:6px 0;color:var(--ok)">✓ '+GX("stNoOrphans")+'</div>')+
    '</div></div>';
  var trashN=(r.trash_paths||[]).length, trashB=+r.trash_bytes||0;
  var trashItems=r.trash_items||[], pubT=CONFIG.supabaseUrl+"/storage/v1/object/public/photos/";
  var trashTable = trashItems.length ? '<div class="stlist" style="margin-bottom:12px">'+
      trashItems.map(function(f){ return stFileRow(f, (ADM.isSuper?'<button type="button" class="ab ok" data-strestore="'+esc(f.name)+'">'+GX("stRestore")+'</button><button type="button" class="ab bad" data-stdel="'+esc(f.name)+'">'+t("del")+'</button>':'')) }).join("")+
      (trashN>trashItems.length?'<div class="hintx">+'+(trashN-trashItems.length)+'</div>':'')+'</div>' : '';
  var trash='<div class="blk" style="margin-top:16px"><h3><span class="hd2"><span>'+GX("stTrashH")+'</span>'+(trashN?'<small class="ltr" style="color:#8A6522">'+trashN+' '+' · '+stSize(trashB)+'</small>':'')+'</span></h3><div class="in">'+
    '<div class="hintx" style="margin-bottom:10px">'+GX("stTrashHint")+'</div>'+trashTable+
    (trashN ? (ADM.isSuper?'<div class="xactions"><button class="ab bad" id="stEmptyTrash" data-n="'+trashN+'">'+GX("stEmptyTrash")+'</button><span class="xmsg" id="stTrashMsg"></span></div>':'')
            : '<div class="adashempty" style="text-align:start;padding:6px 0;color:var(--ok)">✓ '+GX("stTrashEmptyState")+'</div>')+
    '</div></div>';
  var pub=CONFIG.supabaseUrl+"/storage/v1/object/public/photos/";
  var top='<div class="blk" style="margin-top:16px"><h3>'+GX("stTopH")+'</h3><div class="atable"><table><thead><tr><th>'+GX("stFile")+'</th><th>'+GX("stKind")+'</th><th>'+GX("stSize")+'</th><th>'+GX("stDate")+'</th><th></th></tr></thead><tbody>'+
    (r.top||[]).map(function(f){ var base=String(f.name).split("/").pop(); return '<tr><td class="ltr" style="max-width:340px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="'+esc(f.name)+'">'+esc(base)+'</td><td>'+(GX_T["k_"+f.kind]?GX("k_"+f.kind):f.kind)+'</td><td class="ltr"><b>'+stSize(f.bytes)+'</b></td><td class="ltr">'+(f.created||"")+'</td>'+
      '<td style="white-space:nowrap"><a class="ab" href="'+pub+encodeURI(f.name)+'" target="_blank" rel="noopener" style="text-decoration:none">'+GX("stOpen")+'</a>'+(ADM.isSuper?' <button type="button" class="ab bad" data-stdel="'+esc(f.name)+'">'+t("del")+'</button>':'')+'</td></tr>' }).join("")+'</tbody></table></div></div>';
  var tips='<div class="blk" style="margin-top:16px"><h3>'+GX("stTipsH")+'</h3><div class="in"><ul class="sttips"><li>'+GX("stTip1")+'</li><li>'+GX("stTip2")+'</li><li>'+GX("stTip3")+'</li></ul></div></div>';
  return planCard+usage+limitBlock+kinds+trash+orphans+top+tips;
}
function geoAdminBody(){
  var G=ADM.geo; if(!G) return '<div class="done2"><b>'+t("loading")+'</b></div>';
  var govs=G.governorates||[], areas=G.areas||[];
  var CS=admCountries(); ADM.geoCountry=ADM.geoCountry||COUNTRY;
  if(ADM.geoGov && !govs.some(function(x){ return x.id===ADM.geoGov })) ADM.geoGov=null;
  if(!ADM.geoGov && govs.length) ADM.geoGov=govs[0].id;
  var countryBar=(CS.length>1?'<div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-bottom:12px"><b style="font-size:13.5px">'+GX("cCountry")+':</b>'+CS.map(function(c){ return '<button type="button" class="ab'+(c.code===ADM.geoCountry?' ok':'')+'" data-geocountry="'+c.code+'">'+flagOf(c.code)+' '+esc(countryName(c))+(c.enabled?'':' · '+GX("cOff"))+'</button>' }).join("")+'</div>':'');
  var govAdd=(ADM.geoGovAddOpen?'<div style="display:grid;grid-template-columns:1fr 1fr 1fr auto auto;gap:8px;align-items:center;padding:10px;border:1px dashed var(--gold);border-radius:8px;margin-bottom:12px">'+
     '<input id="geoGovNewAr" placeholder="'+GX("nameAr")+'"><input id="geoGovNewEn" placeholder="'+GX("nameEn")+'"><input id="geoGovNewSlug" placeholder="'+GX("slug")+'" class="ltr"><button class="ab ok" id="geoGovAddSave">'+GX("add")+'</button><button class="ab" id="geoGovAddCancel">'+t("cancel")+'</button></div>'
     :'');
  var g=govs.filter(function(x){return x.id===ADM.geoGov})[0]||govs[0];
  var rows=areas.filter(function(a){return g&&a.governorate_id===g.id});
  var kindSel=function(v,id){ return '<select data-gk="'+id+'">'+["city","area","village"].map(function(k){return '<option value="'+k+'"'+(v===k?" selected":"")+'>'+GX(k)+'</option>'}).join("")+'</select>' };
  return '<div class="blk"><h3>'+GX("geoH")+'</h3><div class="in"><div class="hintx" style="margin-bottom:10px">'+GX("geoHint")+'</div>'+countryBar+
   '<div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:12px"><select id="geoGov" style="padding:8px 12px;border:1px solid var(--line-2);border-radius:8px;font-size:14px">'+
     govs.map(function(x){return '<option value="'+x.id+'"'+(g&&x.id===g.id?" selected":"")+'>'+esc(x.name_ar)+' ('+x.areas+' · '+x.listings+' '+GX("listings")+')'+(x.enabled?"":" · ✕")+'</option>'}).join("")+'</select>'+
     '<button class="ab" id="geoGovAddOpen">+ '+GX("cGovAdd")+'</button>'+
     (g&&g.slug?'<a class="mini" style="color:var(--navy);border-color:var(--line-2)" href="/for-sale/'+esc(g.slug)+'/" target="_blank" rel="noopener">'+GX("pages")+' ↗</a>':'')+
     '<span id="geoMsg" style="font-size:12.5px;color:var(--ok)"></span></div>'+govAdd+
   (g?'<div class="geogov" style="display:grid;grid-template-columns:1fr 1fr 1fr auto auto;gap:8px;align-items:center;padding:10px;background:var(--page);border-radius:8px;margin-bottom:12px">'+
     '<input data-gg="name_ar" value="'+escOnce(g.name_ar)+'" placeholder="'+GX("nameAr")+'"><input data-gg="name_en" value="'+escOnce(g.name_en||"")+'" placeholder="'+GX("nameEn")+'"><input data-gg="slug" value="'+escOnce(g.slug||"")+'" placeholder="'+GX("slug")+'" class="ltr">'+
     '<label style="display:flex;gap:6px;align-items:center;font-size:13px"><input type="checkbox" data-gg="enabled"'+(g.enabled?" checked":"")+'>'+GX("shown")+'</label><button class="ab ok" id="geoGovSave">'+GX("save")+'</button></div>':'')+
   '<div class="geotable" style="display:grid;grid-template-columns:1.4fr 1fr 1fr .8fr .5fr .5fr auto auto;gap:6px 8px;align-items:center;font-size:13.5px">'+
     '<b>'+GX("nameAr")+'</b><b>'+GX("nameEn")+'</b><b>'+GX("slug")+'</b><b>'+GX("kind")+'</b><b>'+GX("order")+'</b><b>'+GX("shown")+'</b><b>'+GX("listings")+'</b><b></b>'+
     rows.map(function(a){ return '<input data-ga="name_ar:'+a.id+'" value="'+escOnce(a.name_ar)+'"><input data-ga="name_en:'+a.id+'" value="'+escOnce(a.name_en||"")+'"><input data-ga="slug:'+a.id+'" value="'+escOnce(a.slug||"")+'" class="ltr">'+kindSel(a.kind,a.id)+
       '<input data-ga="sort_order:'+a.id+'" value="'+(a.sort_order||100)+'" type="number" style="width:64px"><input type="checkbox" data-ga="enabled:'+a.id+'"'+(a.enabled?" checked":"")+'><span class="ltr">'+a.listings+'</span>'+
       '<span style="display:flex;gap:4px"><button class="ab ok" data-geosave="'+a.id+'">'+GX("save")+'</button>'+(a.listings>0?'':'<button class="ab" data-geodel="'+a.id+'" style="color:var(--danger)">'+GX("del")+'</button>')+'</span>' }).join("")+
     '<input id="geoNewName" placeholder="'+GX("nameAr")+'" style="border-color:var(--gold)"><input id="geoNewEn" placeholder="'+GX("nameEn")+'"><input id="geoNewSlug" placeholder="'+GX("slug")+'" class="ltr">'+kindSel("area","new")+'<input id="geoNewOrder" type="number" value="100" style="width:64px"><span></span><span></span><button class="ab ok" id="geoAdd">'+GX("add")+'</button>'+
   '</div></div></div>';
}
function admAllowed(code){ var m=ADM.myCountries||[]; return !m.length || m.indexOf(code)>-1 }
function admCountries(){ return (ADM.countries||[]).filter(function(c){ return admAllowed(c.code) }) }
function admResetScope(){   // everything that was loaded for one country scope is loaded again for the new one
  ADM._gen=(ADM._gen||0)+1;
  ADM.data=null; ADM.ikOpen=null; ADM.pjEdit=null; ADM_PJL=null; ADM.viewingPhotoIdx=null; ADM.eopen=null; ADM.geoCountry=null; ADM._geoLoadedFor=null; ADM._mediaLoadedCats={}; ADM._mediaUsedLoaded=false; ADM.mediaUsed=null;
  ADM._ikLoaded=false; ADM.ik=null; ADM._ticketsLoaded=false; ADM.tickets=null; ADM._vfLoaded=false; ADM.vf=undefined; ADM._reviewsLoaded=false; ADM._uactLoaded=false; ADM.uact=null; ADM._lstatsRange=null;
  ADM._photosLoaded=false; ADM.photosList=null;
  ADM._statsLoaded=false; ADM.stats=null; ADM._anLoaded=false; ADM.an=null; ADM.anErr=null; ADM._lstatsLoaded=false; ADM.lstats=null;
  ADM._featuredListLoaded=false; ADM.featuredList=null; ADM._wLoaded=false; ADM_W=null; ADM._pjLoaded=false; ADM_PJ=null; ADM._agLoaded=false; ADM_AG=null; ADM._engDays=null; ADM.eng=null; ADM.todo=null;
  ADM._geoLoaded=false; ADM.adSlots=null; ADM._adSlotsLoaded=false;
  ADM._cpgContactsLoaded=false; ADM.cpgContacts=null; ADM._cpgCampaignsLoaded=false; ADM.cpgCampaigns=null;
}
/* scoped reads: the answer is used only if no country switch happened while it was in flight */
function rpcScoped(name, args){ var g=ADM._gen||0; return rpc(name, args).then(function(r){ if(g!==(ADM._gen||0)) return new Promise(function(){}); return r }) }
function admPickCountry(code, tab){   // header select and the country buttons: a concrete country, or ALL
  if(tab && canTab(tab)) ADM.tab=tab;
  if(code==="ALL"){ if(ADM.scope==="ALL"){ render(); return } ADM.scope="ALL"; admResetScope(); adminLoad(); return }
  if(ADM.scope!=="ALL" && code===COUNTRY){ render(); return }   // same country again: nothing to reload
  ADM.scope=null; admResetScope();
  if(code!==COUNTRY){ var sel=$("#aCountry"); if(sel) sel.value=code; switchCountry(code,{keepView:true,fromAdmin:true}) }
  adminLoad();
}
function admScopeNote(){
  var all=ADM.scope==="ALL", m=ADM.myCountries||[], c=countryOf(COUNTRY)||{};
  return '<div class="ascope'+(all?' all':'')+'">'+(all?'<span class="ascope-globe">🌍</span>':flagSvg(COUNTRY))+'<span>'+GX("cScopeNote")+' <b>'+(all?GX("cAll"):esc(countryName(c)))+'</b></span>'+
    (m.length?'<span class="hintx" style="margin-inline-start:auto">'+GX("cMineOnly")+': '+m.map(function(x){ return flagOf(x) }).join(" ")+'</span>':'<span class="hintx" style="margin-inline-start:auto">'+GX("cScopeHintOne")+'</span>')+'</div>';
}
function scopeCountriesBlocks(an){
  if(ADM.scope!=="ALL") return "";
  var st=(ADM.data&&ADM.data.stats)||{}, byc=st.by_country||{}, nm=function(cc){ var c=countryOf(cc); return flagOf(cc)+" "+(c?countryName(c):cc) };
  var lst=Object.keys(byc).map(function(k){ return {cc:k,n:byc[k]} }).sort(function(a,b){ return b.n-a.n });
  return '<div class="agrid2" style="margin-top:16px">'+
    '<div class="blk"><h3>'+GX("cBySite")+'</h3><div class="in">'+barList(an.sites||[],function(x){ return nm(x.site) },"n","var(--gold)")+'</div></div>'+
    '<div class="blk"><h3>'+GX("cListingsBy")+'</h3><div class="in">'+barList(lst,function(x){ return nm(x.cc) },"n","var(--navy)")+'</div></div></div>';
}
function adminCountrySelHtml(){
  var CS=admCountries(); if(CS.length<2) return '';
  var all=ADM.scope==="ALL";
  return '<select class="adm-lang adm-country'+(all||COUNTRY!=="SY"?' nonsy':'')+'" id="aCountry" aria-label="'+esc(GX("cCountry"))+'">'+CS.map(function(c){ return '<option value="'+c.code+'"'+(!all&&c.code===COUNTRY?' selected':'')+'>'+esc(countryName(c))+(c.enabled?'':' · '+GX("cOff"))+'</option>' }).join("")+
    '<option value="ALL"'+(all?' selected':'')+'>🌍 '+esc(GX("cAll"))+'</option></select>';
}
function countrySetupPanel(c){
  var bgKey="bg_"+(c.bg||"none")+"_s", bgName=GX_T[bgKey]?GX(bgKey):(c.bg||"—"); if(c.code!=="SY"&&c.bg==="sketch") bgName=GX("bg_none_s");
  var tile=function(tab,label,value,icon){ return '<button type="button" class="csetup" data-cgo="'+c.code+':'+tab+'">'+icon+'<b>'+label+'</b><span>'+value+'</span></button>' };
  return '<div class="fl"><label>'+GX("cSetup").replace("{c}",esc(countryName(c)))+'</label><div class="hintx" style="margin-bottom:8px">'+GX("cSetupHint")+'</div><div class="csetup-grid">'+
    tile("mainpage", GX("cBg"), bgName+(c.bg_photo&&c.bg==="photo"?' ✓':''), AICO.home2)+
    tile("banners", GX("cBanners"), (c.banner_on?'':GX("cOffShort")+' · ')+(c.banners||0), AICO.banner)+
    tile("ads", GX("cAdsRow"), (c.ads||0), AICO.ads)+
    tile("featured", GX("cFeatured"), (c.featured||0), AICO.star)+
    tile("mainpage", t("mainPageTab"), '', AICO.palette)+
    tile("contact", GX("tContact"), '', AICO.contact)+
    tile("geo", GX("geoTab"), (c.govs||0)+' · '+(c.areas||0), AICO.map)+
    tile("listings", t("listingsTab"), (c.listings||0), AICO.listings)+
   '</div></div>' }
function adminCountryBar(){
  if(!PER_COUNTRY_TABS[ADM.tab]) return "";
  var CS=ADM.countries||[]; if(!CS.length){ if(!ADM._cbarLoading){ ADM._cbarLoading=true; DB.rpc("bk_admin_countries",{p_token:ADM.token}).then(function(r){ ADM._cbarLoading=false; if(r&&r.data){ ADM.countries=r.data; render() } }) } return "" }
  CS=admCountries(); var cur=countryOf(COUNTRY)||{}, all=ADM.scope==="ALL", editor=/^(mainpage|banners|ads|design|contact|geo)$/.test(ADM.tab);
  var now = all && !editor ? '<span class="ascope-globe">🌍</span><span>'+GX("cShowing")+': <b>'+GX("cAll")+'</b></span>'
          : flagSvg(COUNTRY)+'<span>'+GX(editor?"cEditing":"cShowing")+': <b>'+esc(countryName(cur))+'</b>'+(cur.enabled===false?' <i class="acbar-off">'+GX("cOffShort")+'</i>':'')+(all&&editor?' <i class="acbar-off">'+GX("cEditorAllNote")+'</i>':'')+'</span>';
  return '<div class="acbar'+(all?' all':'')+'"><div class="acbar-now">'+now+'</div>'+
   '<div class="acbar-list"><span>'+GX("cSwitchTo")+':</span>'+(CS.length>1&&!editor?'<button type="button" class="acbar-c'+(all?' on':'')+'" data-cgo="ALL:'+ADM.tab+'">🌍<span>'+GX("cAll")+'</span></button>':'')+
   CS.map(function(c){ return '<button type="button" class="acbar-c'+(!all&&c.code===COUNTRY?' on':'')+(c.enabled?'':' off')+'" data-cgo="'+c.code+':'+ADM.tab+'" title="'+esc(countryName(c))+(c.enabled?'':' · '+GX("cOffShort"))+'">'+flagSvg(c.code)+'<span>'+esc(countryName(c))+'</span></button>' }).join("")+'</div></div>';
}
function adminCountriesBody(){
  var CS=ADM.countries; if(!CS) return '<div class="done2"><b>'+t("loading")+'</b></div>';
  var LANGS=[["ar","العربية"],["en","English"],["de","Deutsch"],["fr","Français"],["tr","Türkçe"]];
  var chooser='<div class="blk" style="margin-bottom:14px"><h3>'+GX("cChooserH")+'</h3><div class="in"><div class="hintx" style="margin-bottom:8px">'+GX("cChooserHint")+'</div>'+
    '<div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap"><select id="cChooser"'+(ADM.isSuper?'':' disabled')+'>'+[["auto",GX("cChooserAuto")],["always",GX("cChooserAlways")],["off",GX("cChooserOff")]].map(function(o){ return '<option value="'+o[0]+'"'+(CHOOSER_MODE===o[0]?' selected':'')+'>'+o[1]+'</option>' }).join("")+'</select><span id="cChooserMsg" style="font-size:12.5px;color:var(--ok)"></span></div></div></div>';
  return (ADM.isSuper?'':'<div class="hintx" style="margin-bottom:12px">'+GX("cSuperOnly")+'</div>')+chooser+
   '<div id="cMsg" style="font-size:13px;min-height:18px;margin-bottom:6px;color:var(--ok)"></div>'+
   CS.map(function(c){
    var open=ADM.cOpen===c.code, ro=ADM.isSuper?'':' disabled';
    var counts=GX("cCounts").replace("{g}",c.govs).replace("{a}",c.areas).replace("{l}",c.listings).replace("{w}",c.wanted).replace("{ag}",c.agencies).replace("{ad}",c.ads);
    var rates=c.rates||{};
    return '<div class="blk" style="margin-bottom:14px"><h3 style="display:flex;align-items:center;gap:10px;flex-wrap:wrap;cursor:pointer" data-copen="'+c.code+'">'+
      '<span style="font-size:22px">'+flagOf(c.code)+'</span><span>'+esc(c.name_ar)+' · '+esc(c.name_en)+'</span><span class="ltr" style="font-size:12px;color:var(--grey)">'+c.code+'</span>'+
      (c.is_default?'<span class="lvl lvl-vip">'+GX("cDefault")+'</span>':'')+
      '<span style="margin-inline-start:auto;font-size:12.5px;font-weight:600;color:'+(c.enabled?'var(--ok)':'var(--danger)')+'">● '+(c.enabled?GX("cOn"):GX("cOff"))+'</span>'+
      '<button type="button" class="ab'+(c.enabled?'':' ok')+'" data-ctoggle="'+c.code+'" data-on="'+(c.enabled?'0':'1')+'"'+ro+'>'+(c.enabled?GX("cTurnOff"):GX("cTurnOn")).replace("{c}",esc(countryName(c)))+'</button></h3>'+
     '<div class="in"><div style="font-size:12.5px;color:var(--grey);margin-bottom:10px" class="ltrnum">'+counts+'</div>'+
     (open?'<div class="row"><div class="fl"><label>'+GX("nameAr")+'</label><input data-cf="name_ar:'+c.code+'" value="'+escOnce(c.name_ar)+'"'+ro+'></div><div class="fl"><label>'+GX("nameEn")+'</label><input data-cf="name_en:'+c.code+'" value="'+escOnce(c.name_en)+'"'+ro+'></div><div class="fl"><label>Deutsch</label><input data-cf="name_de:'+c.code+'" value="'+escOnce(c.name_de||"")+'"'+ro+'></div><div class="fl"><label>Français</label><input data-cf="name_fr:'+c.code+'" value="'+escOnce(c.name_fr||"")+'"'+ro+'></div></div>'+
       '<div class="row"><div class="fl"><label>'+GX("cCurrencies")+'</label><input data-cf="currencies:'+c.code+'" value="'+escOnce((c.currencies||[]).join(", "))+'" class="ltr"'+ro+'></div><div class="fl"><label>'+GX("cPhone")+'</label><input data-cf="phone_code:'+c.code+'" value="'+escOnce(c.phone_code||"")+'" class="ltr"'+ro+'></div><div class="fl"><label>'+GX("cSort")+'</label><input data-cf="sort_order:'+c.code+'" type="number" value="'+(c.sort_order||100)+'"'+ro+'></div></div>'+
       '<div class="row"><div class="fl"><label>'+GX("cRates")+'</label><div style="display:flex;gap:8px;flex-wrap:wrap">'+(c.currencies||[]).filter(function(x){ return x!=="USD" }).map(function(x){ return '<label style="display:flex;gap:6px;align-items:center;font-size:13px"><b class="ltr">1 USD = </b><input data-crate="'+x+':'+c.code+'" type="number" step="any" value="'+(rates[x]||"")+'" style="width:120px" class="ltr"'+ro+'><b class="ltr">'+x+'</b></label>' }).join("")+'</div></div>'+
       '<div class="fl"><label>'+GX("cTz")+'</label><input data-cf="tz:'+c.code+'" value="'+escOnce((c.tz||[]).join(", "))+'" class="ltr"'+ro+'></div></div>'+
       '<div class="fl"><label>'+GX("cLangs")+'</label><div class="chkgrid">'+LANGS.map(function(l){ return '<label><input type="checkbox" data-clang="'+l[0]+':'+c.code+'"'+((c.languages||[]).indexOf(l[0])>-1?' checked':'')+ro+'> '+l[1]+'</label>' }).join("")+'</div></div>'+
       '<div class="fl"><label>'+GX("cNotes")+'</label><textarea data-cf="notes:'+c.code+'" rows="2"'+ro+'>'+escOnce(c.notes||"")+'</textarea></div>'+
       '<div class="fl"><label>'+GX("cDeeds")+'</label><div class="hintx" style="margin-bottom:6px">'+GX("cStrongHint")+'</div>'+
        '<div style="display:grid;grid-template-columns:.7fr 1fr 1fr 1fr .5fr auto auto auto;gap:6px 8px;align-items:center;font-size:13px">'+
        '<b>'+GX("cDeedCode")+'</b><b>'+GX("nameAr")+'</b><b>'+GX("nameEn")+'</b><b>Français</b><b>'+GX("cSort")+'</b><b>'+GX("cStrong")+'</b><b>'+GX("shown")+'</b><b></b>'+
        (c.deeds||[]).map(function(d){ return '<span class="ltr" style="color:var(--grey)">'+escOnce(d.code)+'</span><input data-cd="ar:'+c.code+':'+d.code+'" value="'+escOnce(d.ar)+'"'+ro+'><input data-cd="en:'+c.code+':'+d.code+'" value="'+escOnce(d.en)+'"'+ro+'><input data-cd="fr:'+c.code+':'+d.code+'" value="'+escOnce(d.fr||"")+'"'+ro+'><input data-cd="sort_order:'+c.code+':'+d.code+'" type="number" value="'+(d.sort_order||100)+'" style="width:60px"'+ro+'><input type="checkbox" data-cd="strong:'+c.code+':'+d.code+'"'+(d.strong?' checked':'')+ro+'><input type="checkbox" data-cd="enabled:'+c.code+':'+d.code+'"'+(d.enabled?' checked':'')+ro+'><button class="ab ok" data-cdsave="'+c.code+':'+d.code+'"'+ro+'>'+GX("save")+'</button>' }).join("")+
        '<input data-cdnew="code:'+c.code+'" placeholder="'+GX("cDeedCode")+'" class="ltr" style="border-color:var(--gold)"'+ro+'><input data-cdnew="ar:'+c.code+'" placeholder="'+GX("nameAr")+'"'+ro+'><input data-cdnew="en:'+c.code+'" placeholder="'+GX("nameEn")+'"'+ro+'><input data-cdnew="fr:'+c.code+'" placeholder="Français"'+ro+'><input data-cdnew="sort_order:'+c.code+'" type="number" value="100" style="width:60px"'+ro+'><input type="checkbox" data-cdnew="strong:'+c.code+'"'+ro+'><span></span><button class="ab ok" data-cdadd="'+c.code+'"'+ro+'>'+GX("cAddDeed")+'</button>'+
        '</div></div>'+
       '<div class="fl"><label>'+GX("cTypes")+'</label><div style="display:grid;grid-template-columns:auto 1fr 1fr 1fr;gap:6px 8px;align-items:center;font-size:13px"><b></b><b>'+GX("nameAr")+'</b><b>'+GX("nameEn")+'</b><b>Français</b>'+
        Object.keys(D_TYPES_SY).map(function(k){ var cur=(c.types||[]).filter(function(x){ return x.code===k })[0], on=!c.types||!!cur, b=D_TYPES_SY[k];
          return '<label style="display:flex;gap:6px;align-items:center;white-space:nowrap"><input type="checkbox" data-cty="on:'+c.code+':'+k+'"'+(on?' checked':'')+ro+'><span class="ltr" style="color:var(--grey);font-size:12px">'+k+'</span></label><input data-cty="ar:'+c.code+':'+k+'" value="'+escOnce(cur?cur.ar:b[0])+'"'+ro+'><input data-cty="en:'+c.code+':'+k+'" value="'+escOnce(cur?cur.en:b[1])+'"'+ro+'><input data-cty="fr:'+c.code+':'+k+'" value="'+escOnce(cur?(cur.fr||""):(b[3]||""))+'"'+ro+'>' }).join("")+'</div></div>'+
       countrySetupPanel(c)+
       // per-country channel overrides, read from bk_admin_countries' own "verify" subset (site_content.extras
       // for this country); an unset key falls back to "on", same default bk_verify_cfg itself falls back to
       '<div class="fl"><label>'+GX("vfCountryChT")+'</label><div class="hintx" style="margin-bottom:6px">'+GX("vfCountryChHint")+'</div><div class="chkgrid">'+
        ["verify_telegram_on","verify_wa_code_on","verify_email_on"].map(function(k){ var lbl=k==="verify_telegram_on"?GX("vfSetTg"):k==="verify_wa_code_on"?GX("vfSetWaCode"):GX("vfSetEmail");
          return '<label class="xcheck"><input type="checkbox" data-vf="'+k+':'+c.code+'"'+((c.verify||{})[k]!==false?' checked':'')+ro+'><span>'+lbl+'</span></label>' }).join("")+
        '</div></div>'+
       '<div style="display:flex;gap:10px;align-items:center;margin-top:10px;flex-wrap:wrap"><button class="ab ok" data-csave="'+c.code+'"'+ro+'>'+GX("save")+'</button>'+(c.is_default?'':'<button class="ab" data-cdefault="'+c.code+'"'+ro+'>'+GX("cMakeDefault")+'</button>')+'</div>'
     :'')+'</div></div>' }).join("");
}
function wireAdminCountries(){
  if(ADM.tab!=="countries") return;
  if(!ADM.countries){ DB.rpc("bk_admin_countries",{p_token:ADM.token}).then(function(r){ if(r&&r.data){ ADM.countries=r.data; if(!ADM.cOpen) ADM.cOpen=r.data[0]&&r.data[0].code; render() } }); return }
  var msg=function(s,bad){ var m=$("#cMsg"); if(m){ m.textContent=s; m.style.color=bad?"var(--danger)":"var(--ok)" } };
  var reload=function(){ return DB.rpc("bk_admin_countries",{p_token:ADM.token}).then(function(r){ if(r&&r.data) ADM.countries=r.data; render() }) };
  var set=function(code,patch){ return DB.rpc("bk_admin_country_set",{p_token:ADM.token,p_code:code,p_patch:patch}).then(function(r){ if(r.error){ msg(r.error.message||"error",true); return reload() } msg(GX("saved")); return reload() }) };
  var byCode=function(code){ return (ADM.countries||[]).filter(function(c){ return c.code===code })[0] };
  if($("#cChooser")) $("#cChooser").onchange=function(){ var v=this.value; DB.rpc("bk_admin_set_content",{p_token:ADM.token,p_patch:{extras:{country_chooser:v}},p_country:"SY"}).then(function(r){ var m=$("#cChooserMsg"); if(r.error){ if(m){ m.textContent=r.error.message; m.style.color="var(--danger)" } return } CHOOSER_MODE=v; try{ var cc=JSON.parse(localStorage.getItem("balkoun_countries")||"null"); if(cc){ cc.chooser=v; localStorage.setItem("balkoun_countries",JSON.stringify(cc)) } }catch(e){} if(m) m.textContent=GX("saved") }) };
  $$("[data-copen]").forEach(function(h){ h.onclick=function(e){ if(e.target.closest("label,input")) return; ADM.cOpen=ADM.cOpen===h.dataset.copen?null:h.dataset.copen; render() } });
  $$("[data-ctoggle]").forEach(function(b){ b.onclick=function(e){ e.stopPropagation();
    var c=byCode(b.dataset.ctoggle), on=b.dataset.on==="1";
    if(!on && c && c.is_default) return msg(GX("cCantDisableDefault"),true);
    if(!on && !confirm(GX("cDisableWarn"))) return;
    b.disabled=true;
    set(b.dataset.ctoggle,{enabled:on}).then(function(){ COUNTRIES=null; return refreshCountries() }).then(function(){ render() }) } });
  $$("[data-cdefault]").forEach(function(b){ b.onclick=function(){ if(!confirm(GX("cMakeDefaultConfirm"))) return; set(b.dataset.cdefault,{is_default:true,enabled:true}) } });
  $$("[data-csave]").forEach(function(b){ b.onclick=function(){
    var code=b.dataset.csave, p={}, list=function(v){ return String(v||"").split(/[,،\s]+/).map(function(x){ return x.trim() }).filter(Boolean) };
    $$('[data-cf$=":'+code+'"]').forEach(function(i){ var k=i.dataset.cf.split(":")[0]; p[k]= k==="currencies"?list(i.value).map(function(x){ return x.toUpperCase() }) : k==="tz"?list(i.value) : k==="sort_order"?parseInt(i.value,10)||100 : i.value });
    p.languages=$$('[data-clang$=":'+code+'"]').filter(function(i){ return i.checked }).map(function(i){ return i.dataset.clang.split(":")[0] });
    var rates={}; $$('[data-crate$=":'+code+'"]').forEach(function(i){ var v=parseFloat(i.value); if(v>0) rates[i.dataset.crate.split(":")[0]]=v }); p.rates=rates;
    if(code!=="SY"){ p.types=Object.keys(D_TYPES_SY).filter(function(k){ var on=$('[data-cty="on:'+code+':'+k+'"]'); return on&&on.checked }).map(function(k){ var g=function(f){ var el=$('[data-cty="'+f+':'+code+':'+k+'"]'); return el?el.value.trim():"" }; return {code:k, ar:g("ar")||D_TYPES_SY[k][0], en:g("en")||D_TYPES_SY[k][1], fr:g("fr")||""} }) }
    set(code,p);
    // verify-channel overrides live in site_content.extras (a different table than `countries` above), so
    // they go through bk_admin_set_content scoped to this one country, not bk_admin_country_set
    var vpatch={}; $$('[data-vf$=":'+code+'"]').forEach(function(i){ vpatch[i.dataset.vf.split(":")[0]]=i.checked });
    if(Object.keys(vpatch).length) rpc("bk_admin_set_content",{p_token:ADM.token,p_patch:{extras:vpatch},p_country:code}).catch(function(){}) } });
  var deedPatch=function(code,dcode){ var p={}; $$('[data-cd$=":'+code+':'+dcode+'"]').forEach(function(i){ var k=i.dataset.cd.split(":")[0]; p[k]= i.type==="checkbox"?i.checked : k==="sort_order"?parseInt(i.value,10)||100 : i.value }); return p };
  $$("[data-cdsave]").forEach(function(b){ b.onclick=function(){ var a=b.dataset.cdsave.split(":");
    DB.rpc("bk_admin_deed_save",{p_token:ADM.token,p_country:a[0],p_code:a[1],p_patch:deedPatch(a[0],a[1])}).then(function(r){ if(r.error) return msg(r.error.message,true); msg(GX("saved")); reload() }) } });
  $$("[data-cdadd]").forEach(function(b){ b.onclick=function(){ var code=b.dataset.cdadd, p={};
    $$('[data-cdnew$=":'+code+'"]').forEach(function(i){ var k=i.dataset.cdnew.split(":")[0]; p[k]= i.type==="checkbox"?i.checked : k==="sort_order"?parseInt(i.value,10)||100 : i.value.trim() });
    var dc=String(p.code||"").toLowerCase().replace(/[^a-z0-9_]+/g,"_"); if(!dc||!p.ar) return; delete p.code;
    DB.rpc("bk_admin_deed_save",{p_token:ADM.token,p_country:code,p_code:dc,p_patch:p}).then(function(r){ if(r.error) return msg(r.error.message,true); msg(GX("saved")); reload() }) } });
}

/* ── Contacts notebook + marketing/notification campaigns (WhatsApp, Telegram, Email). ──
   Sub-pages inside one tab (ADM.cpgView): contacts | campaigns | automation. Country-scoped like every
   other PER_COUNTRY_TABS page (admScope()/rpcScoped()); geography picker only offers a structured
   governorate/area when the row's country matches the site's currently-loaded D.GEO (COUNTRY) — other
   countries fall back to the free-text city field, a deliberate v1 limit (see the plan file). */
var CPG_T={
  title:{ar:"جهات الاتصال والحملات",en:"Contacts & Campaigns"},
  tabContacts:{ar:"جهات الاتصال",en:"Contacts"}, tabCampaigns:{ar:"الحملات",en:"Campaigns"}, tabAuto:{ar:"التنبيه التلقائي",en:"Automation"},
  add:{ar:"+ إضافة جهة اتصال",en:"+ Add contact"}, importBtn:{ar:"استيراد CSV",en:"Import CSV"},
  name:{ar:"الاسم",en:"Name"}, phone:{ar:"الهاتف",en:"Phone"}, email:{ar:"الإيميل",en:"Email"}, city:{ar:"المدينة",en:"City"},
  source:{ar:"المصدر",en:"Source"}, src_member:{ar:"عضو مسجّل",en:"Member"}, src_manual:{ar:"يدوي",en:"Manual"}, src_import:{ar:"مستورد",en:"Imported"},
  tags:{ar:"الوسوم",en:"Tags"}, notes:{ar:"ملاحظات",en:"Notes"}, country:{ar:"الدولة",en:"Country"},
  gov:{ar:"المحافظة",en:"Governorate"}, area:{ar:"المنطقة",en:"Area"}, cityFreeText:{ar:"اسم المدينة (نص حر)",en:"City (free text)"}, wholeCountry:{ar:"— كل الدولة —",en:"— Whole country —"},
  consent:{ar:"الاشتراك",en:"Consent"}, pending:{ar:"لم يُحدَّد",en:"Pending"}, subscribed:{ar:"مشترك",en:"Subscribed"}, unsubscribed:{ar:"ملغى",en:"Unsubscribed"},
  wa:{ar:"واتساب",en:"WhatsApp"}, tg:{ar:"تيليغرام",en:"Telegram"}, chEmail:{ar:"إيميل",en:"Email"},
  tgLink:{ar:"رابط ربط تيليغرام",en:"Telegram link"}, tgLinked:{ar:"تيليغرام مربوط ✓",en:"Telegram linked ✓"}, tgCopy:{ar:"نسخ رابط تيليغرام",en:"Copy Telegram link"}, tgCopied:{ar:"تم النسخ ✓",en:"Copied ✓"},
  noContacts:{ar:"لا توجد جهات اتصال بعد.",en:"No contacts yet."}, searchPH:{ar:"ابحث بالاسم أو الهاتف أو الإيميل",en:"Search name, phone or email"},
  allConsent:{ar:"كل حالات الاشتراك",en:"All consent"}, allSource:{ar:"كل المصادر",en:"All sources"},
  save:{ar:"حفظ",en:"Save"}, cancel:{ar:"إلغاء",en:"Cancel"}, del:{ar:"حذف",en:"Delete"}, edit:{ar:"تعديل",en:"Edit"},
  delConfirm:{ar:"حذف جهة الاتصال هذه؟",en:"Delete this contact?"}, needPhoneOrEmail:{ar:"أدخل هاتفاً أو إيميلاً على الأقل",en:"Enter a phone or email"},
  importTitle:{ar:"استيراد جهات اتصال",en:"Import contacts"}, importHint:{ar:"الصق بيانات CSV بالأعمدة: phone,email,name,city_text (سطر أول اختياري بعناوين الأعمدة)",en:"Paste CSV with columns: phone,email,name,city_text (header row optional)"},
  importAssume:{ar:"لدي موافقة مسبقة على مراسلة هذه القائمة",en:"I already have consent to message this list"},
  importGo:{ar:"استيراد",en:"Import"}, importDone:{ar:"تم: {n} مُضافة، {s} متجاهَلة",en:"Done: {n} added, {s} skipped"},
  campNew:{ar:"+ حملة جديدة",en:"+ New campaign"}, campTitle:{ar:"عنوان الحملة",en:"Campaign title"}, campChannels:{ar:"القنوات",en:"Channels"},
  campSubject:{ar:"عنوان الإيميل",en:"Email subject"}, campBodyAr:{ar:"النص (عربي)",en:"Body (Arabic)"}, campBodyEn:{ar:"النص (إنكليزي)",en:"Body (English)"},
  campConsentReq:{ar:"إرسال للمشتركين فقط (موصى به)",en:"Send only to consented contacts (recommended)"},
  campAudience:{ar:"عدد المستلمين المتوقَّع",en:"Expected recipients"}, campTest:{ar:"إرسال تجريبي لي",en:"Send test to me"},
  campSend:{ar:"إرسال الآن",en:"Send now"}, campSendConfirm:{ar:"سيتم الإرسال فعلياً الآن لكل المستلمين المطابقين. متابعة؟",en:"This sends for real to every matching recipient now. Continue?"},
  campStatus:{ar:"الحالة",en:"Status"}, st_draft:{ar:"مسودة",en:"Draft"}, st_sending:{ar:"جارٍ الإرسال",en:"Sending"}, st_sent:{ar:"أُرسلت",en:"Sent"}, st_failed:{ar:"فشل جزئي",en:"Partial failure"}, st_scheduled:{ar:"مجدولة",en:"Scheduled"},
  campStats:{ar:"الإحصاءات",en:"Stats"}, noCampaigns:{ar:"لا توجد حملات بعد.",en:"No campaigns yet."}, notEditable:{ar:"لا يمكن تعديل حملة أُرسلت",en:"A sent campaign can't be edited"},
  autoTitle:{ar:"تنبيه تلقائي عند نشر إعلان جديد",en:"Automatic alert when a new listing goes live"},
  autoHint:{ar:"عند التفعيل، يصل تنبيه تلقائي لكل جهة اتصال مشتركة تغطي منطقة الإعلان الجديد (دولة كاملة، محافظة، أو مدينة محددة حسب ما اختاره كل جهة اتصال).",en:"When on, every subscribed contact whose own coverage includes the new listing's location gets an automatic alert (whole country, a governorate, or a specific city, per contact)."},
  autoOn:{ar:"تفعيل التنبيه التلقائي",en:"Enable automatic alert"},
  waSyriaHint:{ar:"تنبيه: واتساب في سوريا يشارك نفس الرقم المستخدم لإرسال رموز التحقق (WAHA). إرسال حملات كثيرة قد يعرّض ذلك الرقم للحظر ويعطّل رموز التحقق أيضاً.",en:"Note: WhatsApp in Syria shares the same number used for OTP codes (WAHA). Heavy campaign volume risks that number being banned, which would break OTP delivery too."},
  audLoading:{ar:"جارٍ الحساب…",en:"Calculating…"},
};
function cpgT(k){ var o=CPG_T[k]||{}; return o[L]||o.en||o.ar||k }
function cpgConsentChip(v){ var m={subscribed:["st-live","subscribed"],unsubscribed:["st-removed","unsubscribed"],pending:["st-pending","pending"]}[v]||["st-pending","pending"]; return '<span class="st '+m[0]+'">'+cpgT(m[1])+'</span>' }
function cpgGeoSelects(countryCode, govId, areaId, cityText, hideFreeText){
  var sameCountry = countryCode===COUNTRY && D.GEO;
  if(!sameCountry) return hideFreeText ? '' : '<div class="fl"><label>'+cpgT("cityFreeText")+'</label><input data-cpgf="city_text" value="'+escOnce(cityText||"")+'" data-allow-autofill></div>';
  var govName=null; Object.keys(GEO_META.govId||{}).forEach(function(n){ if(GEO_META.govId[n]===govId) govName=n });
  var govOpts='<option value="">'+cpgT("wholeCountry")+'</option>'+Object.keys(D.GEO).map(function(n){ return '<option value="'+GEO_META.govId[n]+'"'+(GEO_META.govId[n]===govId?' selected':'')+'>'+esc(n)+'</option>' }).join("");
  var areaOpts='<option value="">—</option>'+(govName?(D.GEO[govName]||[]).map(function(a){ var aid=GEO_META.areaId[govName+"/"+a]; return '<option value="'+aid+'"'+(aid===areaId?' selected':'')+'>'+esc(a)+'</option>' }).join(""):"");
  return '<div class="fl"><label>'+cpgT("gov")+'</label><select data-cpgf="governorate_id">'+govOpts+'</select></div>'+
         '<div class="fl"><label>'+cpgT("area")+'</label><select data-cpgf="area_id"'+(govName?'':' disabled')+'>'+areaOpts+'</select></div>';
}
function cpgContactRow(c, editing){
  var chips=[c.phone?'<span class="chip ltr">'+esc(c.phone)+'</span>':'', c.email?'<span class="chip">'+esc(c.email)+'</span>':''].filter(Boolean).join("");
  var place=[c.governorate_id?(function(){ var n=null; Object.keys(GEO_META.govId||{}).forEach(function(k){ if(GEO_META.govId[k]===c.governorate_id) n=k }); return n })():null, c.city_text].filter(Boolean).join(" · ");
  var card='<div class="agcard2"><div class="agc-id"><b>'+esc(c.name||"—")+'</b><small>'+chips+(place?' · '+esc(place):'')+' · '+cpgT("src_"+c.source)+'</small></div>'+
    '<div class="agc-meta">'+cpgT("wa")+' '+cpgConsentChip(c.wa_consent)+' '+cpgT("tg")+' '+cpgConsentChip(c.tg_consent)+' '+cpgT("chEmail")+' '+cpgConsentChip(c.email_consent)+'</div>'+
    '<div class="agc-acts"><button type="button" class="ab" data-cpgedit="'+c.id+'">'+(editing?cpgT("cancel"):cpgT("edit"))+'</button><button type="button" class="ab bad" data-cpgdel="'+c.id+'">'+cpgT("del")+'</button></div></div>';
  if(!editing) return card;
  var tgLink=SX("intake_bot","")?("https://t.me/"+encodeURIComponent(SX("intake_bot",""))+"?start=n"+String(c.id).replace(/-/g,"")):"";
  return card+'<div class="tmedit"><div class="row3x"><div class="fl"><label>'+cpgT("name")+'</label><input data-cpgf="name" value="'+escOnce(c.name||"")+'" data-allow-autofill></div>'+
    '<div class="fl"><label>'+cpgT("phone")+'</label><input data-cpgf="phone" class="ltr" value="'+escOnce(c.phone||"")+'" data-allow-autofill></div>'+
    '<div class="fl"><label>'+cpgT("email")+'</label><input data-cpgf="email" class="ltr" value="'+escOnce(c.email||"")+'" data-allow-autofill></div></div>'+
    '<div class="row3x">'+cpgGeoSelects(c.country_code, c.governorate_id, c.area_id, c.city_text)+'</div>'+
    '<div class="fl"><label>'+cpgT("tags")+'</label><input data-cpgf="tags" value="'+escOnce((c.tags||[]).join(", "))+'" placeholder="vip, newspaper" data-allow-autofill></div>'+
    '<div class="row3x">'+["wa_consent","tg_consent","email_consent"].map(function(k,i){ var lbl=[cpgT("wa"),cpgT("tg"),cpgT("chEmail")][i];
      return '<div class="fl"><label>'+lbl+' · '+cpgT("consent")+'</label><select data-cpgf="'+k+'">'+["pending","subscribed","unsubscribed"].map(function(v){ return '<option value="'+v+'"'+(c[k]===v?' selected':'')+'>'+cpgT(v)+'</option>' }).join("")+'</select></div>' }).join("")+'</div>'+
    '<div class="fl"><label>'+cpgT("notes")+'</label><input data-cpgf="notes" value="'+escOnce(c.notes||"")+'" data-allow-autofill></div>'+
    (tgLink?'<div class="hintx" style="margin:6px 0"><b class="ltr" id="cpgTgLink" data-link="'+esc(tgLink)+'" style="user-select:all">'+esc(tgLink)+'</b> <button type="button" class="ab" id="cpgTgCopy">'+cpgT("tgCopy")+'</button></div>':'')+
    '<div class="xactions"><button class="ab ok" data-cpgsave="'+c.id+'">'+cpgT("save")+'</button><span class="xmsg" id="cpgMsg-'+c.id+'"></span></div></div>';
}
function cpgContactsBody(){
  var list=ADM.cpgContacts;
  if(list===null) return '<div class="done2"><b>'+t("loading")+'</b></div>';
  var f=ADM.cpgFilters||{};
  var toolbar='<div class="rtop" style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">'+
    '<input id="cpgQ" placeholder="'+cpgT("searchPH")+'" class="asearch" value="'+escOnce(f.q||"")+'" style="flex:1;min-width:200px;width:auto">'+
    '<select id="cpgConsentPick" class="lvlpick"><option value="">'+cpgT("allConsent")+'</option>'+["subscribed","pending","unsubscribed"].map(function(v){ return '<option value="'+v+'"'+(f.consent===v?' selected':'')+'>'+cpgT(v)+'</option>' }).join("")+'</select>'+
    '<select id="cpgSourcePick" class="lvlpick"><option value="">'+cpgT("allSource")+'</option>'+["member","manual","import"].map(function(v){ return '<option value="'+v+'"'+(f.source===v?' selected':'')+'>'+cpgT("src_"+v)+'</option>' }).join("")+'</select>'+
    '<span class="n" style="font-size:13px;color:var(--grey)"><span class="ltr">'+list.length+'</span></span>'+
    '<button type="button" class="ab ok" id="cpgAddBtn">'+cpgT("add")+'</button><button type="button" class="ab" id="cpgImportBtn">'+cpgT("importBtn")+'</button></div>';
  var addForm = ADM.cpgEditContact==="new" ? cpgContactRow({id:"new",source:"manual",country_code:COUNTRY,wa_consent:"pending",tg_consent:"pending",email_consent:"pending",tags:[]}, true) : "";
  var importModal = ADM.cpgImportOpen ? '<div class="blk" style="margin:14px 0"><h3>'+cpgT("importTitle")+'</h3><div class="in">'+
    '<div class="hintx" style="margin-bottom:8px">'+cpgT("importHint")+'</div><textarea id="cpgImportText" rows="6" style="width:100%;font-family:monospace" placeholder="phone,email,name,city_text"></textarea>'+
    '<label class="xcheck" style="margin-top:8px"><input type="checkbox" id="cpgImportAssume"><span>'+cpgT("importAssume")+'</span></label>'+
    '<div class="xactions"><button class="ab ok" id="cpgImportGo">'+cpgT("importGo")+'</button><button class="ab" id="cpgImportCancel">'+cpgT("cancel")+'</button><span class="xmsg" id="cpgImportMsg"></span></div></div></div>' : "";
  var rows = !list.length ? '<div class="adashempty">'+cpgT("noContacts")+'</div>' : '<div class="elist">'+list.map(function(c){ return cpgContactRow(c, ADM.cpgEditContact===c.id) }).join("")+'</div>';
  return toolbar+addForm+importModal+rows;
}
function cpgCampaignRow(c, editing){
  var stMap={draft:"st-pending",scheduled:"st-pending",sending:"st-pending",sent:"st-live",failed:"st-expired"};
  var card='<div class="agcard2"><div class="agc-id"><b>'+esc(c.title)+'</b><small>'+(c.channels||[]).map(function(ch){ return cpgT(ch==="whatsapp"?"wa":ch==="telegram"?"tg":"chEmail") }).join("، ")+' · '+when(c.created_at)+'</small></div>'+
    '<div class="agc-meta"><span class="st '+(stMap[c.status]||"st-pending")+'">'+cpgT("st_"+c.status)+'</span>'+(c.sent_count||c.failed_count?' <small class="ltrnum">✓'+(c.sent_count||0)+' · ✗'+(c.failed_count||0)+'</small>':'')+'</div>'+
    '<div class="agc-acts">'+(c.status==="draft"||c.status==="scheduled"?'<button type="button" class="ab" data-cpgcedit="'+c.id+'">'+(editing?cpgT("cancel"):cpgT("edit"))+'</button><button type="button" class="ab bad" data-cpgcdel="'+c.id+'">'+cpgT("del")+'</button>':'<button type="button" class="ab" data-cpgcstats="'+c.id+'">'+cpgT("campStats")+'</button>')+'</div></div>'+
    (ADM.cpgStats&&ADM.cpgStats[c.id]?'<div class="hintx" style="margin:4px 0 8px">'+Object.keys(ADM.cpgStats[c.id]).map(function(k){ return k+': '+ADM.cpgStats[c.id][k] }).join(" · ")+'</div>':"");
  if(!editing) return card;
  var aud=ADM.cpgAudience&&ADM.cpgAudience[c.id];
  return card+'<div class="tmedit"><div class="fl"><label>'+cpgT("campTitle")+'</label><input data-cpgcf="title" value="'+escOnce(c.title||"")+'" data-allow-autofill></div>'+
    '<div class="fl"><label>'+cpgT("campChannels")+'</label><div class="chkgrid">'+[["whatsapp","wa"],["telegram","tg"],["email","chEmail"]].map(function(p){ return '<label class="xcheck"><input type="checkbox" data-cpgch="'+p[0]+'"'+((c.channels||[]).indexOf(p[0])>-1?' checked':'')+'><span>'+cpgT(p[1])+'</span></label>' }).join("")+'</div></div>'+
    '<div class="fl"><label>'+cpgT("campSubject")+'</label><input data-cpgcf="subject" value="'+escOnce(c.subject||"")+'" data-allow-autofill></div>'+
    '<div class="row"><div class="fl"><label>'+cpgT("campBodyAr")+'</label><textarea data-cpgcf="body_ar" rows="3">'+escOnce(c.body_ar||"")+'</textarea></div><div class="fl"><label>'+cpgT("campBodyEn")+'</label><textarea data-cpgcf="body_en" rows="3">'+escOnce(c.body_en||"")+'</textarea></div></div>'+
    '<div class="row3x">'+cpgGeoSelects(c.country_code||COUNTRY, c.governorate_id, c.area_id, null, true)+'</div>'+
    '<label class="xcheck"><input type="checkbox" id="cpgConsentReq"'+(c.consent_required!==false?' checked':'')+'><span>'+cpgT("campConsentReq")+'</span></label>'+
    (String(c.country_code||"SY")==="SY"&&(c.channels||[]).indexOf("whatsapp")>-1?'<div class="hintx" style="margin-top:6px;color:var(--danger)">'+cpgT("waSyriaHint")+'</div>':'')+
    '<div class="xactions"><button class="ab ok" data-cpgcsave="'+c.id+'">'+cpgT("save")+'</button>'+
    '<button type="button" class="ab" data-cpgcaudience="'+c.id+'">'+cpgT("campAudience")+(aud?": "+Object.keys(aud).map(function(k){return k+" "+aud[k]}).join(" · "):"")+'</button>'+
    '<button type="button" class="ab" data-cpgctest="'+c.id+'">'+cpgT("campTest")+'</button>'+
    '<button type="button" class="ab bad" data-cpgcsend="'+c.id+'">'+cpgT("campSend")+'</button>'+
    '<span class="xmsg" id="cpgcMsg-'+c.id+'"></span></div></div>';
}
function cpgCampaignsBody(){
  var list=ADM.cpgCampaigns;
  if(list===null) return '<div class="done2"><b>'+t("loading")+'</b></div>';
  var addForm = ADM.cpgEditCampaign==="new" ? cpgCampaignRow({id:"new",title:"",channels:[],country_code:COUNTRY,consent_required:true,status:"draft"}, true) : "";
  var rows = !list.length ? '<div class="adashempty">'+cpgT("noCampaigns")+'</div>' : '<div class="elist">'+list.map(function(c){ return cpgCampaignRow(c, ADM.cpgEditCampaign===c.id) }).join("")+'</div>';
  return '<div class="rtop" style="margin-bottom:10px"><button type="button" class="ab ok" id="cpgAddCampBtn">'+cpgT("campNew")+'</button></div>'+addForm+rows;
}
function cpgAutomationBody(){
  var cur=(ADM.countries||[]).filter(function(c){ return c.code===COUNTRY })[0]||{}; var cfg=cur.campaign_cfg||{};
  return '<div class="blk"><h3>'+cpgT("autoTitle")+'</h3><div class="in"><div class="hintx" style="margin-bottom:10px">'+cpgT("autoHint")+'</div>'+
    '<label class="xcheck"><input type="checkbox" id="cpgAutoOn"'+(cfg.auto_notify_new_listing_on==="true"||cfg.auto_notify_new_listing_on===true?' checked':'')+'><span>'+cpgT("autoOn")+'</span></label>'+
    '<div class="chkgrid" style="margin-top:8px">'+[["auto_notify_ch_telegram","tg"],["auto_notify_ch_whatsapp","wa"],["auto_notify_ch_email","chEmail"]].map(function(p){ var on=cfg[p[0]]!=="false"&&cfg[p[0]]!==false; return '<label class="xcheck"><input type="checkbox" data-cpgautoch="'+p[0]+'"'+(on?' checked':'')+'><span>'+cpgT(p[1])+'</span></label>' }).join("")+'</div>'+
    (COUNTRY==="SY"?'<div class="hintx" style="margin-top:10px;color:var(--danger)">'+cpgT("waSyriaHint")+'</div>':'')+
    '<div class="xactions"><button class="ab ok" id="cpgAutoSave">'+cpgT("save")+'</button><span class="xmsg" id="cpgAutoMsg"></span></div></div></div>';
}
function adminCampaignsBody(){
  var view=ADM.cpgView||"contacts";
  var segs=[["contacts","tabContacts"],["campaigns","tabCampaigns"],["automation","tabAuto"]].map(function(s){ return '<button type="button" class="ab'+(view===s[0]?' ok':'')+'" data-cpgview="'+s[0]+'">'+cpgT(s[1])+'</button>' }).join(" ");
  var body = view==="contacts" ? cpgContactsBody() : view==="campaigns" ? cpgCampaignsBody() : cpgAutomationBody();
  return '<div class="rtop" style="margin-bottom:14px">'+segs+'</div>'+body;
}
function cpgParseCsv(text){
  var lines=text.split(/\r?\n/).map(function(l){ return l.trim() }).filter(Boolean);
  if(!lines.length) return [];
  var head=lines[0].toLowerCase().split(",").map(function(h){ return h.trim() });
  var known=["phone","email","name","city_text","tags"];
  var startAt = known.indexOf(head[0])>-1 ? 1 : 0;
  var cols = startAt===1 ? head : known.slice(0, lines[0].split(",").length);
  return lines.slice(startAt).map(function(line){ var vals=line.split(","); var row={}; cols.forEach(function(c,i){ if(c==="tags") row.tags=(vals[i]||"").split(/[;|]/).map(function(x){return x.trim()}).filter(Boolean); else row[c]=(vals[i]||"").trim() }); return row });
}
function wireAdminCampaigns(){
  if(ADM.tab!=="campaigns") return;
  if(!ADM.countries){ DB.rpc("bk_admin_countries",{p_token:ADM.token}).then(function(r){ if(r&&r.data) ADM.countries=r.data; render() }); return }
  var view=ADM.cpgView||"contacts";
  if(view==="contacts" && ADM.cpgContacts===null){ var f=ADM.cpgFilters||{};
    rpcScoped("bk_admin_contacts",{p_token:ADM.token,p_country:admScope(),p_q:f.q||null,p_consent:f.consent||null,p_source:f.source||null}).then(function(r){ ADM.cpgContacts=r||[]; render() }); return }
  if(view==="campaigns" && ADM.cpgCampaigns===null){ rpcScoped("bk_admin_campaigns",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM.cpgCampaigns=r||[]; render() }); return }
  $$("[data-cpgview]").forEach(function(b){ b.onclick=function(){ ADM.cpgView=b.dataset.cpgview; render() } });
  // contacts
  if($("#cpgQ")){ var cpgQEl=$("#cpgQ");
    if(ADM._cpgQFocused){ cpgQEl.focus(); cpgQEl.setSelectionRange(cpgQEl.value.length,cpgQEl.value.length) }
    cpgQEl.onfocus=function(){ ADM._cpgQFocused=true }; cpgQEl.onblur=function(){ ADM._cpgQFocused=false };
    cpgQEl.oninput=function(){ clearTimeout(ADM._cpgQT); var v=this.value; ADM._cpgQT=setTimeout(function(){ ADM.cpgFilters=Object.assign({},ADM.cpgFilters,{q:v}); ADM.cpgContacts=null; render() },400) } }
  if($("#cpgConsentPick")) $("#cpgConsentPick").onchange=function(){ ADM.cpgFilters=Object.assign({},ADM.cpgFilters,{consent:this.value}); ADM.cpgContacts=null; render() };
  if($("#cpgSourcePick")) $("#cpgSourcePick").onchange=function(){ ADM.cpgFilters=Object.assign({},ADM.cpgFilters,{source:this.value}); ADM.cpgContacts=null; render() };
  if($("#cpgAddBtn")) $("#cpgAddBtn").onclick=function(){ ADM.cpgEditContact="new"; render() };
  if($("#cpgImportBtn")) $("#cpgImportBtn").onclick=function(){ ADM.cpgImportOpen=!ADM.cpgImportOpen; render() };
  if($("#cpgImportCancel")) $("#cpgImportCancel").onclick=function(){ ADM.cpgImportOpen=false; render() };
  if($("#cpgImportGo")) $("#cpgImportGo").onclick=function(){
    var rows=cpgParseCsv($("#cpgImportText").value||""); if(!rows.length) return;
    DB.rpc("bk_admin_contacts_import",{p_token:ADM.token,p_country:admScope()||COUNTRY,p_rows:rows,p_assume_consent:!!$("#cpgImportAssume").checked}).then(function(raw){
      var r=(raw&&raw.data)||{}; var m=$("#cpgImportMsg"); if(raw&&raw.error){ m.textContent=raw.error.message||String(raw.error); m.style.color="var(--danger)"; return } if(r.error){ m.textContent=r.error; m.style.color="var(--danger)"; return }
      m.textContent=cpgT("importDone").replace("{n}",r.inserted).replace("{s}",r.skipped); m.style.color="var(--ok)"; ADM.cpgContacts=null; setTimeout(function(){ ADM.cpgImportOpen=false; render() },1200) }) };
  $$("[data-cpgedit]").forEach(function(b){ b.onclick=function(){ var id=b.dataset.cpgedit; ADM.cpgEditContact=ADM.cpgEditContact===id?null:id; render() } });
  $$("[data-cpgdel]").forEach(function(b){ b.onclick=function(){ if(!confirm(cpgT("delConfirm"))) return; DB.rpc("bk_admin_contact_delete",{p_token:ADM.token,p_id:b.dataset.cpgdel}).then(function(){ ADM.cpgContacts=null; ADM.cpgEditContact=null; render() }) } });
  $$("[data-cpgsave]").forEach(function(b){ b.onclick=function(){
    var id=b.dataset.cpgsave, root=b.closest(".tmedit"), p={};
    $$("[data-cpgf]", root).forEach(function(i){ var k=i.dataset.cpgf; p[k]= k==="tags" ? i.value.split(",").map(function(x){return x.trim()}).filter(Boolean) : (k==="governorate_id"||k==="area_id") ? (i.value?parseInt(i.value,10):null) : i.value });
    DB.rpc("bk_admin_contact_save",{p_token:ADM.token,p_id:id==="new"?null:id,p_patch:p}).then(function(raw){
      var r=(raw&&raw.data)||{}; var m=$("#cpgMsg-"+id); if((raw&&raw.error)||r.error){ if(m){ m.textContent=cpgT("needPhoneOrEmail"); m.style.color="var(--danger)" } return }
      ADM.cpgContacts=null; ADM.cpgEditContact=null; render() }) } });
  if($("#cpgTgCopy")) $("#cpgTgCopy").onclick=function(){ var el=$("#cpgTgLink"); if(!el) return; navigator.clipboard&&navigator.clipboard.writeText(el.dataset.link).then(function(){ this.textContent=cpgT("tgCopied") }.bind(this)) };
  // campaigns
  if($("#cpgAddCampBtn")) $("#cpgAddCampBtn").onclick=function(){ ADM.cpgEditCampaign="new"; render() };
  $$("[data-cpgcedit]").forEach(function(b){ b.onclick=function(){ var id=b.dataset.cpgcedit; ADM.cpgEditCampaign=ADM.cpgEditCampaign===id?null:id; render() } });
  $$("[data-cpgcdel]").forEach(function(b){ b.onclick=function(){ if(!confirm(cpgT("delConfirm"))) return; DB.rpc("bk_admin_campaign_delete",{p_token:ADM.token,p_id:b.dataset.cpgcdel}).then(function(){ ADM.cpgCampaigns=null; render() }) } });
  $$("[data-cpgcstats]").forEach(function(b){ b.onclick=function(){ DB.rpc("bk_admin_campaign_stats",{p_token:ADM.token,p_id:b.dataset.cpgcstats}).then(function(raw){ ADM.cpgStats=Object.assign({},ADM.cpgStats); ADM.cpgStats[b.dataset.cpgcstats]=(raw&&raw.data)||{}; render() }) } });
  $$("[data-cpgcsave]").forEach(function(b){ b.onclick=function(){
    var id=b.dataset.cpgcsave, root=b.closest(".tmedit"), p={};
    $$("[data-cpgcf]", root).forEach(function(i){ p[i.dataset.cpgcf]=i.value });
    p.channels=$$("[data-cpgch]", root).filter(function(i){ return i.checked }).map(function(i){ return i.dataset.cpgch });
    p.governorate_id=(function(){ var s=$('[data-cpgf="governorate_id"]',root); return s&&s.value?parseInt(s.value,10):null })();
    p.area_id=(function(){ var s=$('[data-cpgf="area_id"]',root); return s&&s.value?parseInt(s.value,10):null })();
    p.consent_required=!!$("#cpgConsentReq",root).checked; p.country_code=admScope()||COUNTRY;
    DB.rpc("bk_admin_campaign_save",{p_token:ADM.token,p_id:id==="new"?null:id,p_patch:p}).then(function(raw){
      var r=(raw&&raw.data)||{}; var m=$("#cpgcMsg-"+id); if((raw&&raw.error)||r.error){ if(m){ m.textContent=(raw&&raw.error&&raw.error.message)||r.error||"error"; m.style.color="var(--danger)" } return }
      ADM.cpgCampaigns=null; ADM.cpgEditCampaign=null; render() }) } });
  $$("[data-cpgcaudience]").forEach(function(b){ b.onclick=function(){ var id=b.dataset.cpgcaudience; b.textContent=cpgT("audLoading");
    DB.rpc("bk_admin_campaign_audience_count",{p_token:ADM.token,p_id:id}).then(function(raw){ ADM.cpgAudience=Object.assign({},ADM.cpgAudience); ADM.cpgAudience[id]=(raw&&raw.data)||{}; render() }) } });
  $$("[data-cpgctest]").forEach(function(b){ b.onclick=function(){ var id=b.dataset.cpgctest;
    DB.rpc("bk_admin_campaign_send",{p_token:ADM.token,p_id:id,p_test:true}).then(function(raw){ var r=(raw&&raw.data)||{}; var m=$("#cpgcMsg-"+id); if(!m) return; if((raw&&raw.error)||r.error){ m.textContent=(raw&&raw.error&&raw.error.message)||r.error||"error"; m.style.color="var(--danger)" } else { m.textContent="✓ "+(r.queued||0); m.style.color="var(--ok)"; intakeAdmin("tick").catch(function(){}) } }) } });
  $$("[data-cpgcsend]").forEach(function(b){ b.onclick=function(){ if(!confirm(cpgT("campSendConfirm"))) return; var id=b.dataset.cpgcsend;
    DB.rpc("bk_admin_campaign_send",{p_token:ADM.token,p_id:id,p_test:false}).then(function(raw){ var r=(raw&&raw.data)||{}; if((raw&&raw.error)||r.error){ admToast((raw&&raw.error&&raw.error.message)||r.error||"error","bad"); return } admToast("✓ "+(r.queued||0)); ADM.cpgCampaigns=null; render(); intakeAdmin("tick").catch(function(){}) }) } });
  // automation
  if($("#cpgAutoSave")) $("#cpgAutoSave").onclick=function(){
    var patch={auto_notify_new_listing_on:!!$("#cpgAutoOn").checked};
    $$("[data-cpgautoch]").forEach(function(i){ patch[i.dataset.cpgautoch]=!!i.checked });
    DB.rpc("bk_admin_set_content",{p_token:ADM.token,p_patch:{extras:patch},p_country:admScope()||COUNTRY}).then(function(r){
      var m=$("#cpgAutoMsg"); if(r.error){ m.textContent=r.error.message||r.error; m.style.color="var(--danger)"; return }
      m.textContent=t("saved"); m.style.color="var(--ok)"; ADM.countries=null; DB.rpc("bk_admin_countries",{p_token:ADM.token}).then(function(rr){ if(rr&&rr.data) ADM.countries=rr.data; render() }) }) };
}

/* ── Message intake page: connections, settings, drafts, log. Data: bk_admin_intake; actions through the bk-intake Edge Function. ── */
var IK_STATUS={collecting:"ik_collecting",reading:"ik_reading",ready:"ik_ready",needs_info:"ik_needs_info",review:"ik_review",published:"ik_published",cancelled:"ik_cancelled",failed:"ik_failed"};
var IK_PILL={collecting:"pending",reading:"pending",ready:"live",needs_info:"pending",review:"expired",published:"live",cancelled:"expired",failed:"expired"};
function ikPill(st){ return '<span class="st st-'+(IK_PILL[st]||"pending")+'">'+GX(IK_STATUS[st]||st)+'</span>' }
function ikSrc(x){ return x.source==="telegram"?"Telegram":x.source==="whatsapp"?"WhatsApp":GX("ik_web") }
async function intakeAdmin(action, extra){
  var r=await fetch(CONFIG.supabaseUrl+"/functions/v1/bk-intake/admin",{method:"POST",headers:{"Content-Type":"application/json","apikey":CONFIG.supabaseKey,"Authorization":"Bearer "+CONFIG.supabaseKey},
    body:JSON.stringify(Object.assign({token:ADM.token,action:action},extra||{}))});
  var j=null; try{ j=await r.json() }catch(e){ j={} }
  if(!r.ok||(j&&j.error)) throw new Error((j&&(j.detail&&j.detail.error||j.error))||("intake "+r.status));
  return j }
function ikFieldsForm(x){
  var f=x.fields||{}; var v=function(k){ return f[k]==null?"":escOnce(String(f[k])) };
  var inp=function(k,lbl,type,wide){ return '<div class="fl'+(wide?' wide':'')+'"><label>'+lbl+'</label><input data-ikf="'+k+'" type="'+(type||"text")+'" value="'+v(k)+'" data-allow-autofill></div>' };
  var sel=function(k,lbl,opts){ return '<div class="fl"><label>'+lbl+'</label><select data-ikf="'+k+'"><option value=""></option>'+opts.map(function(o){ return '<option value="'+o[0]+'"'+(String(f[k])===o[0]?' selected':'')+'>'+o[1]+'</option>' }).join("")+'</select></div>' };
  var chk=function(k,lbl){ return '<label class="xcheck" style="align-self:end"><input type="checkbox" data-ikf="'+k+'" data-ikbool="1"'+(f[k]===true||f[k]==="true"?' checked':'')+'><span>'+lbl+'</span></label>' };
  return '<div class="ikfields">'+
    sel("deal",GX("ik_f_deal"),[["sale",t("forsale")],["rent",t("forrent")]])+sel("property_type",GX("ik_f_type"),Object.keys(D.TYPES).map(function(k){ return [k,D.TYPES[k][li()]] }))+
    inp("governorate",GX("ik_f_gov"))+inp("area",GX("ik_f_area"))+inp("landmark",GX("ik_f_landmark"))+
    inp("price",GX("ik_f_price"),"number")+inp("currency",GX("ik_f_cur"))+inp("area_m2",GX("ik_f_m2"),"number")+
    inp("rooms",GX("ik_f_rooms"),"number")+inp("baths",GX("ik_f_baths"),"number")+inp("living_rooms",GX("ik_f_living"),"number")+inp("floor",GX("ik_f_floor"),"number")+inp("year_built",GX("ik_f_year"),"number")+
    inp("tabu",GX("ik_f_tabu"))+inp("condition",GX("ik_f_cond"))+sel("rental_period",GX("ik_f_period"),[["yearly",t("periodYearly")],["monthly",t("periodMonthly")],["weekly",t("periodWeekly")],["daily",t("periodDaily")]])+
    inp("contact_phone",GX("ik_f_phone"),"tel")+chk("furnished",GX("ik_f_furn"))+chk("negotiable",GX("ik_f_negot"))+
    '<div class="fl wide"><label>'+GX("ik_f_desc")+'</label><textarea data-ikf="description">'+v("description")+'</textarea></div>'+
  '</div>' }
function ikRow(x){
  var open=String(ADM.ikOpen)===String(x.id), photos=Array.isArray(x.photos)?x.photos:[], d=ADM.ik||{};
  var head=esc(x.agency_name||x.sender_name||x.chat_id||""), sub=ikSrc(x)+(x.by_admin?' · '+GX("ik_byOwner"):'')+(x.sender_name&&x.agency_name?' · '+esc(x.sender_name):'');
  var line=(x.summary||"").split("\n").filter(function(l){ return l && !/^📋/.test(l) }).slice(0,2).join(" · ") || (x.raw_text||"").slice(0,90);
  return '<div class="erow ikrow'+(open?' open':'')+'">'+
    '<div class="ecode"><b>#'+x.id+'</b><div><b>'+scopeFlag(x.country_code)+head+'</b><small class="usub">'+sub+'</small></div></div>'+
    '<div class="ewho">'+esc(line)+'<small>'+photos.length+' '+GX("ik_photos")+' · '+(x.messages||0)+' '+GX("ik_msgs")+(x.country_code&&x.country_code!=="SY"?' · '+flagOf(x.country_code):'')+'</small></div>'+
    '<div class="eclient">'+ikPill(x.status)+(x.listing_ref?' <a class="elink" data-open="'+x.listing_id+'">'+esc(x.listing_ref)+'</a>':'')+(x.error&&!open?'<small style="color:var(--danger)">'+esc(String(x.error)).slice(0,60)+'</small>':'')+'</div>'+
    '<div class="eperiod"><span class="ltr">'+when(x.created_at)+'</span><small>$'+(+x.cost_usd||0).toFixed(4)+'</small></div>'+
    '<div class="eacts"><button type="button" class="ab" data-ikopen="'+x.id+'">'+(open?GX("ik_close"):GX("ik_open"))+'</button></div>'+
    (open ? '<div class="eedit ikdetail" data-ikid="'+x.id+'"><div class="ikcols">'+
      '<div><b>'+GX("ik_rawH")+'</b><pre class="ikpre">'+esc(x.raw_text||"—")+'</pre>'+(x.error?'<div class="hintx" style="color:var(--danger)">'+esc(String(x.error))+'</div>':'')+(x.summary?'<pre class="ikpre">'+esc(x.summary)+'</pre>':'')+
        (photos.length?'<div class="ikphotos">'+photos.map(function(p){ return '<a href="'+esc(p.url)+'" target="_blank" rel="noopener"><img src="'+esc(p.thumb_url||p.url)+'" alt="" loading="lazy"></a>' }).join("")+'</div>':'')+'</div>'+
      '<div><b>'+GX("ik_fieldsH")+'</b>'+ikFieldsForm(x)+'</div></div>'+
      '<div class="xactions">'+
        '<select data-ikag="'+x.id+'"><option value="">'+GX("ik_pickAgency")+'</option>'+(d.agencies||[]).map(function(g){ return '<option value="'+g.id+'"'+(String(g.id)===String(x.agency_id)?' selected':'')+'>'+esc(g.name)+(g.country_code&&g.country_code!=="SY"?' '+flagOf(g.country_code):'')+'</option>' }).join("")+'</select>'+
        '<button type="button" class="ab ok" data-iksave="'+x.id+'">'+t("save")+'</button>'+
        (x.status!=="published" ? '<button type="button" class="ab" data-ikread="'+x.id+'">'+GX("ik_readAgain")+'</button><button type="button" class="ab ok" data-ikpub="'+x.id+':pending">'+GX("ik_pubPending")+'</button><button type="button" class="ab ok" data-ikpub="'+x.id+':live">'+GX("ik_pubLive")+'</button>'+(x.status!=="cancelled"?'<button type="button" class="ab" data-ikcancel="'+x.id+'">'+t("cancel")+'</button>':'') : '')+
        '<button type="button" class="ab bad" data-ikdel="'+x.id+'">'+t("del")+'</button><span class="xmsg" id="ikMsg'+x.id+'"></span>'+
      '</div></div>' : '')+
  '</div>' }
function adminIntakeBody(){
  var d=ADM.ik; if(!d) return '<div class="blk"><div class="in adashempty">'+(ADM.ikErr?'<span style="color:var(--danger)">'+esc(ADM.ikErr)+'</span>':t("loading"))+'</div></div>';
  var cfg=d.cfg||{}, c=d.counts||{}, st=ADM.ikStatus, f=ADM.ikFilter||"all", fnUrl=CONFIG.supabaseUrl+"/functions/v1/bk-intake";
  var list=(d.drafts||[]).filter(function(x){ return f==="all" ? x.status!=="cancelled" : f==="attention" ? (x.status==="review"||x.status==="failed") : f==="open" ? ["collecting","reading","ready","needs_info"].indexOf(x.status)>-1 : x.status===f });
  var stats='<div class="ikstats">'+[[GX("ik_st_open"),(+c.collecting||0)+(+c.ready||0)],[GX("ik_st_attention"),(+c.review||0)+(+c.failed||0)],[GX("ik_st_published"),+c.published||0],[GX("ik_st_today"),+c.today||0],[GX("ik_st_cost"),"$"+(+c.cost_month||0).toFixed(2)]].map(function(s){ return '<div class="astat"><b class="ltr">'+s[1]+'</b><span>'+s[0]+'</span></div>' }).join("")+'</div>';
  var row=function(name,state,acts){ return '<div class="ikc"><b>'+name+'</b><div>'+state+'</div><div class="eacts">'+(acts||'')+'</div></div>' };
  var ok=function(s){ return '<span class="ikok">✓ '+s+'</span>' }, warn=function(s){ return '<span class="ikwarn">! '+s+'</span>' }, off=function(s){ return '<span class="ikoff">○ '+s+'</span>' };
  var chats=cfg.intake_admin_chats||{}; var nChats=(chats.telegram||[]).length+(chats.whatsapp||[]).length;
  var conn='<div class="blk"><h3>'+GX("ik_connH")+'</h3><div class="in">'+
    (!st ? '<div class="hintx">'+t("loading")+'</div>' : st.error ? '<div class="hintx" style="color:var(--danger)">'+esc(st.error)+'</div>' :
     '<div class="ikconn">'+
      row("Telegram", st.telegram.configured ? (st.telegram.ok ? ok(GX("ik_tgOk").replace("{b}","@"+esc((st.telegram.me&&st.telegram.me.username)||cfg.intake_bot||"")))+(st.telegram.webhook&&st.telegram.webhook.last_error_message?'<small style="color:var(--danger)">'+esc(st.telegram.webhook.last_error_message)+'</small>':'') : warn(GX("ik_tgNoHook"))) : off(GX("ik_tgOff")), st.telegram.configured ? '<button type="button" class="ab ok" id="ikSetupTg">'+GX("ik_tgSetup")+'</button>' : '')+
      row("WhatsApp", (st.whatsapp.configured ? (st.whatsapp.ok ? ok(GX("ik_waOk").replace("{n}",esc((st.whatsapp.phone&&st.whatsapp.phone.display_phone_number)||""))) : warn(GX("ik_waErr"))) : off(GX("ik_waOff")))+'<small>'+GX("ik_waHook")+' <b class="ltr" style="user-select:all">'+fnUrl+'/whatsapp</b></small>', '<button type="button" class="ab" data-ecopy="'+fnUrl+'/whatsapp">'+GX("engCopy")+'</button>')+
      row("Claude", st.anthropic.configured ? ok(GX("ik_clOk")) : off(GX("ik_clOff")), '')+
     '</div><div class="hintx" style="margin-top:10px">'+GX("ik_secretsHint")+'</div>')+
    '<div class="ikown"><b>'+GX("ik_ownerH")+'</b><div class="hintx">'+GX("ik_ownerHint")+'</div>'+
      (cfg.intake_bot&&cfg.intake_admin_code ? '<div class="ecodebox"><a class="ab" href="https://t.me/'+esc(cfg.intake_bot)+'?start=adm-'+esc(cfg.intake_admin_code)+'" target="_blank" rel="noopener">'+GX("ik_ownerOpen")+'</a><b>'+esc(cfg.intake_admin_code)+'</b><button type="button" class="ab" data-ecopy="'+esc(cfg.intake_admin_code)+'">'+GX("engCopy")+'</button></div>' : '<button type="button" class="ab" id="ikAdminCode" style="margin-top:8px"'+(cfg.intake_bot?'':' disabled title="Telegram"')+'>'+GX("ik_ownerMake")+'</button>')+
      (nChats?'<div class="hintx" style="margin-top:6px">'+GX("ik_ownerLinked").replace("{n}",nChats)+'</div>':'')+'</div>'+
    '<div class="iktest"><b>'+GX("ik_testH")+'</b><textarea id="ikTestText" data-allow-autofill placeholder="'+esc(GX("ik_testPH"))+'">'+escOnce(ADM.ikTestText||"")+'</textarea><div class="xactions"><button type="button" class="ab" id="ikTestBtn">'+GX("ik_testBtn")+'</button><span class="xmsg" id="ikTestMsg"></span></div>'+(ADM.ikTest?'<pre class="ikpre">'+esc(ADM.ikTest)+'</pre>':'')+'</div>'+
  '</div></div>';
  var num=function(k,lbl,def,min,max,step){ return '<div class="fl"><label>'+lbl+'</label><input type="number" data-ikc="'+k+'" data-ikt="num" value="'+(cfg[k]!=null?cfg[k]:"")+'" placeholder="'+def+'"'+(min!=null?' min="'+min+'"':'')+(max!=null?' max="'+max+'"':'')+(step?' step="'+step+'"':'')+' data-allow-autofill></div>' };
  var sel=function(k,lbl,opts){ return '<div class="fl"><label>'+lbl+'</label><select data-ikc="'+k+'" data-ikt="str">'+opts.map(function(o){ return '<option value="'+o[0]+'"'+(String(cfg[k]||"")===o[0]?' selected':'')+'>'+o[1]+'</option>' }).join("")+'</select></div>' };
  var txt=function(k,lbl){ return '<div class="fl"><label>'+lbl+'</label><input data-ikc="'+k+'" data-ikt="str" class="ltr" value="'+escOnce(cfg[k]||"")+'" data-allow-autofill></div>' };
  var chk=function(k,lbl){ return '<label class="xcheck"><input type="checkbox" data-ikc="'+k+'" data-ikt="bool"'+(cfg[k]!==false&&cfg[k]!=="false"?' checked':'')+'><span>'+lbl+'</span></label>' };
  var settings='<div class="blk"><h3>'+GX("ik_setH")+'</h3><div class="in" id="ikCfg">'+
    '<div class="chkgrid">'+chk("intake_enabled",GX("ik_on"))+chk("intake_telegram_on","Telegram")+chk("intake_whatsapp_on","WhatsApp")+'</div>'+
    '<div class="row3">'+num("intake_wait_s",GX("ik_wait"),90,20,900)+num("intake_max_photos",GX("ik_maxPhotos"),12,1,30)+num("intake_daily_limit",GX("ik_daily"),30,1,500)+'</div>'+
    '<div class="row3">'+sel("intake_model",GX("ik_model"),[["claude-haiku-4-5-20251001","Claude Haiku 4.5"],["claude-sonnet-5","Claude Sonnet 5"],["claude-opus-5","Claude Opus 5"]])+num("intake_price_in",GX("ik_priceIn"),1,0,100,0.01)+num("intake_price_out",GX("ik_priceOut"),5,0,500,0.01)+'</div>'+
    '<div class="row">'+sel("intake_reply_lang",GX("ik_lang"),[["ar","العربية"],["en","English"]])+txt("intake_wa_display",GX("ik_waDisplay"))+'</div>'+
    '<div class="xactions"><button type="button" class="ab ok" id="ikCfgSave">'+t("save")+'</button><span class="xmsg" id="ikCfgMsg"></span></div>'+
  '</div></div>';
  var nchk=function(k,lbl){ return '<label class="xcheck"><input type="checkbox" data-ikc="'+k+'" data-ikt="bool"'+(GSX(k,true)!==false?' checked':'')+'><span>'+lbl+'</span></label>' };
  var nnum=function(k,lbl,ph){ return '<div class="fl"><label>'+lbl+'</label><input type="number" min="0" max="23" data-ikc="'+k+'" data-ikt="num" value="'+(GSX(k,"")===""?"":GSX(k,""))+'" placeholder="'+ph+'" data-allow-autofill></div>' };
  var tzs=[["America/Toronto","كندا (تورونتو)"],["Asia/Damascus","سوريا (دمشق)"],["Asia/Beirut","لبنان"],["Asia/Amman","الأردن"],["Asia/Dubai","الإمارات"],["Europe/Berlin","ألمانيا"]];
  var notify='<div class="blk"><h3>'+GX("ik_ntfH")+'</h3><div class="in" id="ikNtf">'+
    '<div class="hintx" style="margin-bottom:10px">'+(nChats?GX("ik_ntfHint").replace("{n}",nChats):GX("ik_ntfNoChat"))+'</div>'+
    '<div class="chkgrid">'+nchk("notify_tg_on",GX("ik_ntfOn"))+'</div>'+
    '<div class="acs-sub" style="margin-top:8px">'+GX("ik_ntfEvents")+'</div><div class="chkgrid">'+[["listing",GX("bellListings")],["agency",GX("bellAgencies")],["wanted",GX("bellWanted")],["verify",GX("bellVerify")],["intake",GX("bellIntake")],["report",GX("bellReports")],["feedback",GX("bellFeedback")]].map(function(e){ return nchk("notify_ev_"+e[0],e[1]) }).join("")+'</div>'+
    '<div class="row3" style="margin-top:8px">'+nnum("notify_quiet_from",GX("ik_ntfQuietFrom"),"22")+nnum("notify_quiet_to",GX("ik_ntfQuietTo"),"8")+'<div class="fl"><label>'+GX("ik_ntfTz")+'</label><select data-ikc="notify_tz" data-ikt="str">'+tzs.map(function(z){ return '<option value="'+z[0]+'"'+(GSX("notify_tz","America/Toronto")===z[0]?' selected':'')+'>'+z[1]+'</option>' }).join("")+'</select></div></div>'+
    '<div class="hintx">'+GX("ik_ntfQuietHint")+'</div>'+
    '<div class="xactions"><button type="button" class="ab ok" id="ikNtfSave">'+t("save")+'</button><button type="button" class="ab" id="ikNtfTest">'+GX("ik_ntfTest")+'</button><span class="xmsg" id="ikNtfMsg"></span></div>'+
  '</div></div>';
  var filters=[["all",GX("ik_fAll")],["attention",GX("ik_fAttention")],["open",GX("ik_fOpen")],["published",GX("ik_published")],["cancelled",GX("ik_cancelled")]];
  var drafts='<div class="blk"><h3>'+GX("ik_draftsH")+' <span class="n">'+list.length+'</span></h3><div class="in eng-in">'+
    '<div class="ikfilters">'+filters.map(function(x){ return '<button type="button" class="ab'+(x[0]===f?' on':'')+'" data-ikf-filter="'+x[0]+'">'+x[1]+'</button>' }).join("")+'<button type="button" class="ab" id="ikReload" style="margin-inline-start:auto">'+AICO.refresh+'</button></div>'+
    (list.length ? '<div class="elist">'+list.map(ikRow).join("")+'</div>' : '<div class="adashempty">'+GX("ik_none")+'</div>')+'</div></div>';
  var logs='<div class="blk"><h3>'+GX("ik_logH")+'</h3><div class="in eng-in"><div class="iklog">'+(d.log||[]).slice(0,40).map(function(l){ return '<div class="iklog-r lvl-'+esc(l.level||"info")+'"><span class="ltr">'+when(l.created_at)+'</span><b>'+esc(l.event)+'</b><i>'+(l.draft_id?'#'+l.draft_id:'')+'</i><span>'+esc(JSON.stringify(l.detail||{})).slice(0,160)+'</span></div>' }).join("")+'</div></div></div>';
  return stats+conn+notify+settings+drafts+logs }
function wireAdminIntake(){
  if(!ADM._ikLoaded){ ADM._ikLoaded=true; ADM.ikErr=null;
    rpcScoped("bk_admin_intake",{p_token:ADM.token,p_country:admScope()}).then(function(r){ ADM.ik=r||{}; render() }).catch(function(e){ ADM.ik=null; ADM.ikErr=e.message||"error"; render() });
    if(!ADM.ikStatus) intakeAdmin("status").then(function(r){ ADM.ikStatus=r; render() }).catch(function(e){ ADM.ikStatus={error:e.message||"error"}; render() }) }
  var reload=function(){ ADM._ikLoaded=false; render() };
  var busy=function(btn,on){ if(btn){ btn.disabled=on; btn.classList.toggle("busy",on) } };
  if($("#ikReload")) $("#ikReload").onclick=function(){ ADM.ikStatus=null; reload() };
  $$("[data-ikf-filter]").forEach(function(b){ b.onclick=function(){ ADM.ikFilter=this.dataset.ikfFilter; render() } });
  $$("[data-ikopen]").forEach(function(b){ b.onclick=function(){ ADM.ikOpen = String(ADM.ikOpen)===this.dataset.ikopen ? null : this.dataset.ikopen; render() } });
  if($("#ikSetupTg")) $("#ikSetupTg").onclick=async function(){ busy(this,true); try{ var r=await intakeAdmin("setup_telegram"); admToast("@"+(r.bot||"")+" ✓"); ADM.ikStatus=null; reload() }catch(e){ admToast(e.message||"error","bad"); busy(this,false) } };
  if($("#ikAdminCode")) $("#ikAdminCode").onclick=async function(){ busy(this,true); try{ await intakeAdmin("admin_code"); reload() }catch(e){ admToast(e.message||"error","bad"); busy(this,false) } };
  var tt=$("#ikTestText"); if(tt) tt.oninput=function(){ ADM.ikTestText=this.value };
  if($("#ikTestBtn")) $("#ikTestBtn").onclick=async function(){ var m=$("#ikTestMsg"), text=(ADM.ikTestText||"").trim(); if(text.length<10) return; busy(this,true); if(m) m.textContent=GX("qfBusy");
    try{ var r=await intakeAdmin("test_claude",{text:text,country:COUNTRY}); ADM.ikTest=(r.summary||"")+"\n\n"+JSON.stringify(r.fields,null,1)+(r.missing&&r.missing.length?"\nmissing: "+r.missing.join(", "):"")+"\ntokens in/out: "+(r.usage&&r.usage.in)+"/"+(r.usage&&r.usage.out); render() }
    catch(e){ if(m){ m.style.color="var(--danger)"; m.textContent=e.message||"error" } busy(this,false) } };
  if($("#ikNtfSave")) $("#ikNtfSave").onclick=async function(){ var m=$("#ikNtfMsg"), patch={}; busy(this,true);
    $$("#ikNtf [data-ikc]").forEach(function(i){ var k=i.dataset.ikc, ty=i.dataset.ikt; patch[k] = ty==="bool" ? !!i.checked : ty==="num" ? (i.value===""?null:+i.value) : (String(i.value).trim()===""?null:String(i.value).trim()) });
    try{ await saveGlobalExtras(patch); admToast(GX("ik_saved")); busy(this,false) }catch(e){ if(m){ m.style.color="var(--danger)"; m.textContent=e.message||"error" } busy(this,false) } };
  if($("#ikNtfTest")) $("#ikNtfTest").onclick=async function(){ var m=$("#ikNtfMsg"); busy(this,true); try{ var r=await intakeAdmin("notify_test"); if(m){ m.style.color=r.sent?"var(--ok)":"var(--danger)"; m.textContent=r.sent?GX("ik_ntfTestOk"):GX("ik_ntfNoChat") } }catch(e){ if(m){ m.style.color="var(--danger)"; m.textContent=e.message||"error" } } busy(this,false) };
  if($("#ikCfgSave")) $("#ikCfgSave").onclick=async function(){ var m=$("#ikCfgMsg"), patch={}; busy(this,true);
    $$("#ikCfg [data-ikc]").forEach(function(i){ var k=i.dataset.ikc, ty=i.dataset.ikt; patch[k] = ty==="bool" ? !!i.checked : ty==="num" ? (i.value===""?null:+i.value) : (String(i.value).trim()===""?null:String(i.value).trim()) });
    try{ await rpc("bk_admin_set_content",{p_token:ADM.token,p_patch:{extras:patch},p_country:"SY"}); admToast(GX("ik_saved")); reload() }catch(e){ if(m){ m.style.color="var(--danger)"; m.textContent=e.message||"error" } busy(this,false) } };
  var collect=function(id){ var box=$('.ikdetail[data-ikid="'+id+'"]'); if(!box) return null; var fields={};
    box.querySelectorAll("[data-ikf]").forEach(function(i){ var k=i.dataset.ikf; if(i.dataset.ikbool) fields[k]=!!i.checked; else { var v=String(i.value).trim(); fields[k]= v===""?null:(i.type==="number"?+v:v) } });
    var x=((ADM.ik||{}).drafts||[]).filter(function(y){ return String(y.id)===String(id) })[0]||{}; var f0=x.fields||{};
    if(fields.governorate!==(f0.governorate==null?null:String(f0.governorate))){ fields.governorate_id=null; fields.area_id=null } else if(fields.area!==(f0.area==null?null:String(f0.area))) fields.area_id=null;
    var ag=box.querySelector("[data-ikag]"); return {fields:fields, agency_id: ag ? (ag.value||"") : undefined} };
  var saveDraft=async function(id){ var c=collect(id); if(!c) return; var patch={fields:c.fields}; if(c.agency_id!==undefined) patch.agency_id=c.agency_id||null; await rpc("bk_admin_intake_set",{p_token:ADM.token,p_id:+id,p_patch:patch}) };
  $$("[data-iksave]").forEach(function(b){ b.onclick=async function(){ var id=this.dataset.iksave, m=$("#ikMsg"+id); busy(this,true); try{ await saveDraft(id); admToast(GX("ik_saved")); reload() }catch(e){ if(m){ m.style.color="var(--danger)"; m.textContent=e.message||"error" } busy(this,false) } } });
  $$("[data-ikread]").forEach(function(b){ b.onclick=async function(){ var id=this.dataset.ikread, m=$("#ikMsg"+id); busy(this,true); if(m){ m.style.color="var(--grey)"; m.textContent=GX("qfBusy") } try{ await saveDraft(id); await intakeAdmin("read",{draft_id:+id,quiet:true}); reload() }catch(e){ if(m){ m.style.color="var(--danger)"; m.textContent=e.message||"error" } busy(this,false) } } });
  $$("[data-ikpub]").forEach(function(b){ b.onclick=async function(){ var p=this.dataset.ikpub.split(":"), m=$("#ikMsg"+p[0]); busy(this,true); if(m){ m.style.color="var(--grey)"; m.textContent=GX("qfBusy") }
    try{ await saveDraft(p[0]); var r=await intakeAdmin("publish",{draft_id:+p[0],status:p[1]}); admToast(GX("ik_pubDone").replace("{r}",r.ref||"")); syncAdminTodo(); reload() }catch(e){ if(m){ m.style.color="var(--danger)"; m.textContent=e.message||"error" } busy(this,false) } } });
  $$("[data-ikcancel]").forEach(function(b){ b.onclick=async function(){ var id=this.dataset.ikcancel; busy(this,true); try{ await rpc("bk_admin_intake_set",{p_token:ADM.token,p_id:+id,p_patch:{status:"cancelled"}}); reload() }catch(e){ admToast(e.message||"error","bad"); busy(this,false) } } });
  $$("[data-ikdel]").forEach(function(b){ b.onclick=async function(){ var id=this.dataset.ikdel; if(!confirm(GX("ik_delConfirm"))) return; busy(this,true); try{ await rpc("bk_admin_intake_delete",{p_token:ADM.token,p_id:+id}); ADM.ikOpen=null; syncAdminTodo(); reload() }catch(e){ admToast(e.message||"error","bad"); busy(this,false) } } });
}
