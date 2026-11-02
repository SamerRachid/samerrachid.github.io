// preview-only: block writes, then a layout audit for the admin panel
(function(){
  if(!window.__guard){
    window.__guard=true;
    var READ=/^(bk_admin_(uid|stats|search|list|get|todo|overview)|.*_(list|get|stats|count|rows|search|row|load|status|preview)$)/i;
    var WR=/(save|set_|update|delete|del_|send|publish|approve|reject|create|add|edit|apply|notify|flush|upsert|insert|remove|mark|toggle|import|run|claim|ping|reset|purge|ban|verify|merge)/i;
    var _rpc=window.rpc;
    window.__blocked=[];
    window.rpc=function(fn,args){ if(WR.test(fn)&&!READ.test(fn)){ window.__blocked.push(fn); return Promise.resolve({error:{message:"preview: write blocked"}}) } return _rpc.apply(this,arguments) };
    var _f=window.fetch;
    window.fetch=function(u,o){ var m=(o&&o.method||"GET").toUpperCase(), s=String(u&&u.url||u);
      if(m!=="GET"&&m!=="HEAD"&&/supabase/.test(s)){ var fn=(s.match(/\/rpc\/([\w]+)/)||[])[1]||"";
        if(!fn||(WR.test(fn)&&!READ.test(fn))){ window.__blocked.push(m+" "+(fn||s.slice(0,90))); return Promise.resolve(new Response('{"message":"preview: write blocked"}',{status:403,headers:{"content-type":"application/json"}})) } }
      return _f.apply(this,arguments) };
  }
  function vis(el){ var r=el.getBoundingClientRect(); if(r.width<2||r.height<2) return null; var cs=getComputedStyle(el); if(cs.visibility==="hidden"||+cs.opacity===0) return null; return r }
  function inScroller(el){ for(var p=el.parentElement;p&&p!==document.body;p=p.parentElement){ var cs=getComputedStyle(p),o=cs.overflowX+" "+cs.overflowY; if(/auto|scroll|hidden/.test(o)) return p } return null }
  function name(el){ var t=(el.innerText||el.value||el.getAttribute("aria-label")||el.placeholder||"").trim().replace(/\s+/g," ").slice(0,28); return el.tagName.toLowerCase()+(el.id?"#"+el.id:"")+(el.className&&typeof el.className==="string"?"."+el.className.trim().split(/\s+/).slice(0,2).join("."):"")+(t?" «"+t+"»":"") }
  window.__run=async function(keys,ms){ window.__res=null; var res={}; for(const k of keys){ __go(k); await new Promise(function(r){ setTimeout(r,ms||1500) }); window.scrollTo(0,0); var a=__audit(); if(a.pageScroll||a.offscreen.length+a.overlap.length+a.clipped.length+a.crooked.length) res[k]=a } window.__res=res; return res };
  function realHit(p,q){ var A=[].slice.call(p.getClientRects()), B=[].slice.call(q.getClientRects()); return A.some(function(a){ return B.some(function(b){ return Math.min(a.right,b.right)-Math.max(a.left,b.left)>3 && Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top)>3 }) }) }
  window.__audit=function(root){
    root=root||document.querySelector(".adm")||document.body;
    var W=document.documentElement.clientWidth, out={offscreen:[],overlap:[],clipped:[],crooked:[],pageScroll:document.documentElement.scrollWidth>W+1};
    var els=[].slice.call(root.querySelectorAll("button,a,input,select,textarea,label,h1,h2,h3,h4,b,strong,p,span,small,td,th,.pill,.chip,.ab"));
    // ignore things inside the closed «المزيد» sheet and hidden pop-ups
    els=els.filter(function(e){ return !e.closest("[hidden],.abot,.adm-top,.amore") && vis(e) });
    var leaf=els.filter(function(e){ return !els.some(function(o){ return o!==e && e.contains(o) && /^(BUTTON|A|INPUT|SELECT|TEXTAREA)$/.test(o.tagName) }) });
    // 1) off the screen (outside any scrolling strip)
    leaf.forEach(function(e){ var r=e.getBoundingClientRect(); if((r.right>W+1||r.left<-1)&&!inScroller(e)) out.offscreen.push(name(e)+" ["+Math.round(r.left)+"→"+Math.round(r.right)+" of "+W+"]") });
    // 2) controls / text sitting on top of each other (not parent-child, not a badge on purpose)
    var ctl=leaf.filter(function(e){ return /^(BUTTON|A|INPUT|SELECT|TEXTAREA|LABEL|H1|H2|H3|H4|P|TD|TH)$/.test(e.tagName) || (e.children.length===0 && (e.innerText||"").trim()) });
    // a caption laid over its own photo on purpose doesn't count
    ctl=ctl.filter(function(e){ var cs=getComputedStyle(e); if(cs.position==="absolute"&&e.parentElement&&e.parentElement.querySelector("img,video")) return false; if(e.querySelector("img,video")&&e.parentElement.querySelector(":scope>[style*=absolute],:scope>.aused")) return false; return !(cs.position==="absolute"&&e.getBoundingClientRect().width<40) && !e.closest(".abadge2,.abot i") });
    for(var i=0;i<ctl.length;i++){ var a=ctl[i].getBoundingClientRect();
      for(var j=i+1;j<ctl.length;j++){ var x=ctl[j]; if(ctl[i].contains(x)||x.contains(ctl[i])) continue; var b=x.getBoundingClientRect();
        var w=Math.min(a.right,b.right)-Math.max(a.left,b.left), h=Math.min(a.bottom,b.bottom)-Math.max(a.top,b.top);
        if(w>3&&h>4&&!realHit(ctl[i],x)) continue;
        if(w>3&&h>4){ var sa=inScroller(ctl[i]), sb=inScroller(x); var ca=sa&&sa.getBoundingClientRect(), cb=sb&&sb.getBoundingClientRect();
          // pieces scrolled out of view of their strip don't count
          if(ca&&(a.right<ca.left+2||a.left>ca.right-2||a.bottom<ca.top+2||a.top>ca.bottom-2)) continue; if(cb&&(b.right<cb.left+2||b.left>cb.right-2||b.bottom<cb.top+2||b.top>cb.bottom-2)) continue;
          if(getComputedStyle(x).position==="fixed"||getComputedStyle(ctl[i]).position==="fixed") continue;
          out.overlap.push(name(ctl[i])+"  ✕  "+name(x)+" ["+Math.round(w)+"×"+Math.round(h)+"]") } } }
    // 3) text cut off inside its box (no "…" on purpose)
    leaf.forEach(function(e){ var cs=getComputedStyle(e); if(e.children.length>2) return;
      if((cs.overflow==="hidden"||cs.overflowX==="hidden")&&cs.textOverflow!=="ellipsis"&&e.scrollWidth>e.clientWidth+2&&(e.innerText||"").trim()) out.clipped.push(name(e)+" ["+e.scrollWidth+">"+e.clientWidth+"]") });
    // 4) crooked rows: buttons that share a row but don't share a centre line
    var rows={}; [].slice.call(root.querySelectorAll("button.ab,a.ab,.ab")).filter(function(e){ return !e.closest("[hidden]")&&vis(e) }).forEach(function(e){ var p=e.parentElement; (rows[p.__k||(p.__k=Math.random())]=rows[p.__k]||{p:p,l:[]}).l.push(e) });
    Object.keys(rows).forEach(function(k){ var l=rows[k].l; if(l.length<2) return; var cs=getComputedStyle(rows[k].p); if(cs.display.indexOf("flex")<0) return;
      var lines={}; l.forEach(function(e){ var r=e.getBoundingClientRect(); var key=Math.round(r.top/8); (lines[key]=lines[key]||[]).push(r) });
      Object.keys(lines).forEach(function(q){ var g=lines[q]; if(g.length<2) return; var c=g.map(function(r){ return r.top+r.height/2 }); var hs=g.map(function(r){ return r.height });
        if(Math.max.apply(0,c)-Math.min.apply(0,c)>3||Math.max.apply(0,hs)-Math.min.apply(0,hs)>6) out.crooked.push(name(rows[k].p)+" heights "+hs.map(Math.round).join("/")) }) });
    ["offscreen","overlap","clipped","crooked"].forEach(function(k){ out[k]=out[k].filter(function(v,i,a){ return a.indexOf(v)===i }).slice(0,15) });
    return out };
  window.__go=function(k){ var el=document.querySelector('[data-atab="'+k+'"]'); if(!el){ var g=(window.ADM_GROUPS?Object.keys(ADM_GROUPS).filter(function(x){ return ADM_GROUPS[x].indexOf(k)>-1 })[0]:null); if(g){ var ge=document.querySelector('[data-atab="'+g+'"]'); ge&&ge.click(); el=document.querySelector('[data-atab="'+k+'"]') } } if(el){ el.click(); return true } ADM.tab=k; render(); return "forced" };
})();
window.__shot=async function(k){ __go(k); await new Promise(function(r){ setTimeout(r,1800) }); window.scrollTo(0,0); return k };
