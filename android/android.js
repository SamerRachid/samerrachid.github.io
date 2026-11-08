// balkoun.com/android — the link the owner posts on the page, in comments and in messages (2026-11-08): on an Android phone
// the app file starts downloading by itself; Facebook/Messenger/Instagram's own browser often refuses a download, so it
// also gets the "open in browser" hint; an iPhone or a computer is told what to do instead. ES5, like the site's head scripts.
(function(){
  var ua=navigator.userAgent||"", $=function(id){ return document.getElementById(id) };
  var android=/Android/i.test(ua), ios=/iPhone|iPad|iPod/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints>1);
  var inApp=/FBAN|FBAV|FB_IAB|FBIOS|Messenger|Instagram|Line\/|; wv\)/i.test(ua), insideApp=/BalkounApp\//.test(ua);
  var bot=navigator.webdriver===true || /bot|crawl|spider|facebookexternalhit|embedly|preview|headless|lighthouse|python|curl|wget|playwright|puppeteer/i.test(ua);
  if(ios) $("ios").hidden=false;
  else if(!android) $("desk").hidden=false;
  if(android && inApp) $("inapp").hidden=false;
  // once per visit, never inside the Balkoun app itself and never for link-preview robots
  if(android && !insideApp && !bot && !/[?&]preview=1/.test(location.search)){
    var done=false; try{ done=sessionStorage.getItem("bk_apk_auto")==="1"; sessionStorage.setItem("bk_apk_auto","1") }catch(e){}
    if(!done) setTimeout(function(){ $("started").hidden=false; location.href="/downloads/balkoun.apk" }, 900);
  }
  // the visit counts like any other page of the site (same visitor id); a tap on the button is counted as its own page
  if(bot || /[?&]preview=1/.test(location.search)) return;
  var U="https://coajrqynjrptujmzjjdh.supabase.co/rest/v1/rpc/", K="sb_publishable_RmwJTwdLt5P7eh4NtXhw3w_17WPpQ1t";
  var get=function(k){ try{ return localStorage.getItem(k) }catch(e){ return null } }, put=function(k,v){ try{ localStorage.setItem(k,v) }catch(e){} };
  var vid=get("balkoun_vid"); if(!vid){ vid=Math.random().toString(36).slice(2,10)+new Date().getTime().toString(36); put("balkoun_vid",vid) }
  var me=null; try{ me=JSON.parse(get("balkoun_user")||"null") }catch(e){}
  var dev=(window.innerWidth<=700 || /Mobi|Android|iPhone/i.test(ua)) ? "mobile" : "desktop";
  var ref=(document.referrer||"").replace(/^https?:\/\//,"").split("/")[0]; if(ref===location.host) ref="";
  var src=(location.search.match(/[?&]src=([\w-]{1,40})/)||[])[1]; if(src){ ref="src:"+src; put("balkoun_src",src) }
  var log=function(path,view){
    var b=JSON.stringify({p_path:path,p_view:view,p_user:(me&&me.id)||null,p_country:null,p_token:(me&&me.token)||null,p_visitor:vid,p_device:dev,p_referrer:ref,p_site_country:"SY"});
    var send=function(body,again){ try{ fetch(U+"bk_log_view2",{method:"POST",keepalive:true,headers:{"Content-Type":"application/json",apikey:K,Authorization:"Bearer "+K},body:body})
      .then(function(r){ if(!r.ok && again) again() },function(){}) }catch(e){} };
    // a saved session that is no longer valid: still a visit, sent without the member
    send(b, me ? function(){ var o=JSON.parse(b); o.p_user=null; o.p_token=null; send(JSON.stringify(o)) } : null) };
  log((location.pathname+location.search).slice(0,300),"android");
  $("dl").addEventListener("click",function(){ log("/downloads/balkoun.apk","apk") });
})();
