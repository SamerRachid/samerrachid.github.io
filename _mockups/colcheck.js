// preview-only: does every column's content start at the same edge as its header? (RTL: right edges)
window.__colcheck=function(){
  var out=[], rtl=document.documentElement.dir!=="ltr";
  var edge=function(el){ if(!el) return null; var r=document.createRange(); r.selectNodeContents(el); var b=r.getBoundingClientRect(); if(!b.width) return null; return rtl?b.right:b.left };
  var nm=function(el){ var b=el.closest(".blk"), h=b&&b.querySelector(":scope>h3,:scope>h4"); return (h?h.textContent.trim().slice(0,30):(el.className||"table")) };
  // real tables
  [].forEach.call(document.querySelectorAll(".adm .acontent table"),function(tb){ if(!tb.offsetParent) return;
    var ths=[].slice.call(tb.querySelectorAll("thead th")); if(!ths.length) return;
    var rows=[].slice.call(tb.querySelectorAll("tbody tr")).filter(function(r){ return r.children.length===ths.length && r.offsetParent }).slice(0,6);
    ths.forEach(function(th,i){ var he=edge(th); if(he==null) return; var bad=[];
      rows.forEach(function(r){ var td=r.children[i], ce=edge(td); if(ce==null) return; var tdPad=parseFloat(getComputedStyle(td)[rtl?"paddingRight":"paddingLeft"]), thPad=parseFloat(getComputedStyle(th)[rtl?"paddingRight":"paddingLeft"]); var d=Math.round((ce-he)+(rtl?(tdPad-thPad):(thPad-tdPad))); if(Math.abs(d)>6) bad.push(d) });
      if(bad.length) out.push(nm(tb)+" › «"+th.textContent.trim().slice(0,18)+"» off by "+bad.slice(0,3).join(",")+"px") }) });
  // grid lists with a header row (ad performance)
  [].forEach.call(document.querySelectorAll(".adm .acontent .adperf"),function(g){ if(!g.offsetParent) return; var h=g.querySelector(".adperf-h"); if(!h||!h.offsetParent) return; var hs=[].slice.call(h.children);
    [].slice.call(g.querySelectorAll(".adperf-r")).slice(0,4).forEach(function(r){ hs.forEach(function(x,i){ var c=r.children[i], he=edge(x), ce=edge(c); if(he==null||ce==null) return; var d=Math.round(ce-he); if(Math.abs(d)>6) out.push(nm(g)+" › «"+x.textContent.trim().slice(0,18)+"» off by "+d+"px") }) }) });
  return out.filter(function(v,i,a){ return a.indexOf(v)===i });
};
