/* Balkoun: adds the page's scripts (data-src: "url#integrity url …", run in that order). On a phone's home page they wait
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
