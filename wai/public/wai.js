const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
const clamp=(v,a=0,b=1)=>Math.min(b,Math.max(a,v)),ease=t=>t<.5?4*t*t*t:1-Math.pow(-2*t+2,3)/2;
const RM=matchMedia('(prefers-reduced-motion:reduce)').matches;
const fmt=n=>Math.round(n).toLocaleString('ru-RU');

// loader (home only)
if($('#loader'))addEventListener('load',()=>setTimeout(()=>{$('#loader').classList.add('done');document.body.classList.remove('locked');document.body.classList.add('ready')},RM?0:1300));
else document.body.classList.add('ready');

// Background video: pause outside the hero and honor reduced-motion.
if($('.hero-video')){const video=$('.hero-video');new IntersectionObserver(([e])=>{document.body.classList.toggle('hero-visible',e.isIntersecting);if(RM)return;if(e.isIntersecting)video.play().catch(()=>{});else video.pause()},{threshold:.08}).observe($('#hero'));if(RM)video.pause()}

// hero background: holographic terrain + orbital rings
if($('#heroFx'))(()=>{const cv=$('#heroFx'),ctx=cv.getContext('2d'),hero=$('#hero');let W,H,dpr,vis=true,mx=.5,my=.5,tx=.5,ty=.5;
const ORB=[...Array(140)].map((_,i)=>({r:i<90?1:.72,a:Math.random()*6.283,s:(i<90?.12:-.18)*(.8+Math.random()*.4),j:(Math.random()-.5)*.06,z:Math.random()}));
const PK=[...Array(5)].map(()=>({a:Math.random()*6.283,s:.5+Math.random()*.6,r:Math.random()<.5?1:.72}));
function size(){dpr=Math.min(devicePixelRatio||1,1.5);W=cv.clientWidth;H=cv.clientHeight;cv.width=W*dpr;cv.height=H*dpr;ctx.setTransform(dpr,0,0,dpr,0,0)}
const hgt=(x,z,t)=>Math.sin(x*1.3+t*.5)*.18+Math.sin(z*.55-t*.9+x*.4)*.28+Math.sin((x-z)*.8+t*.3)*.12+Math.exp(-x*x*1.4)*Math.sin(z*.9-t*1.6)*.22;
function frame(ts){if(vis){const t=ts*.001;mx+=(tx-mx)*.04;my+=(ty-my)*.04;ctx.clearRect(0,0,W,H);ctx.globalCompositeOperation='lighter';
// terrain
const hz=H*(.6+(my-.5)*.03),f=Math.min(W,H)*.9,camX=(mx-.5)*1.2,camH=1.15,ROWS=34,COLS=W<700?26:44,span=7,zN=1.2,zF=14,scroll=(t*1.1)%((zF-zN)/ROWS);
const proj=(x,y,z)=>[W/2+(x-camX)*f/z,hz+(camH-y)*f/z*.55];
ctx.lineWidth=.7;
for(let r=0;r<ROWS;r++){const z=zF-r*(zF-zN)/ROWS+scroll;if(z<zN)continue;const fade=Math.pow(1-(z-zN)/(zF-zN),1.4);ctx.beginPath();for(let c=0;c<=COLS;c++){const x=-span+c*2*span/COLS,[sx,sy]=proj(x,hgt(x,z,t),z);c?ctx.lineTo(sx,sy):ctx.moveTo(sx,sy)}
const pr=Math.sin(z*1.4-t*2.2)>.93;ctx.strokeStyle=pr?`rgba(156,128,242,${.55*fade})`:`rgba(205,205,220,${.16*fade})`;ctx.stroke()}
for(let c=0;c<=COLS;c+=2){const x=-span+c*2*span/COLS;ctx.beginPath();let first=true;for(let k=0;k<=24;k++){const z=zN+k*(zF-zN)/24,[sx,sy]=proj(x,hgt(x,z,t),z);first?ctx.moveTo(sx,sy):ctx.lineTo(sx,sy);first=false}const g=ctx.createLinearGradient(0,H,0,hz);g.addColorStop(0,'rgba(205,205,220,.12)');g.addColorStop(1,'rgba(205,205,220,0)');ctx.strokeStyle=g;ctx.stroke()}
// horizon glow line
const hg=ctx.createLinearGradient(0,0,W,0);hg.addColorStop(0,'rgba(156,128,242,0)');hg.addColorStop(.5,'rgba(220,210,255,.35)');hg.addColorStop(1,'rgba(156,128,242,0)');ctx.fillStyle=hg;ctx.fillRect(0,hz+(camH-.2)*f/zF*.55-1,W,1);
// orbital rings around W
const cx=W/2+(mx-.5)*-20,cy=H*.36+(my-.5)*-10,R=Math.min(W*.42,560),tilt=.22+(my-.5)*.05;
for(const ring of [1,.72]){ctx.beginPath();ctx.ellipse(cx,cy,R*ring,R*ring*tilt,-.06,0,6.283);ctx.strokeStyle='rgba(200,200,215,.07)';ctx.lineWidth=1;ctx.stroke()}
for(const p of ORB){const a=p.a+t*p.s,x=Math.cos(a),y=Math.sin(a),d=(y+1)/2,sx=cx+x*R*p.r,sy=cy+(y*tilt+p.j)*R*p.r;const front=y>0;ctx.fillStyle=`rgba(${front?'235,235,245':'156,128,242'},${(.15+.6*d)*(.6+.4*Math.sin(t*2+p.z*9))})`;const s=.6+d*1.6;ctx.fillRect(sx-s/2,sy-s/2,s,s)}
for(const p of PK){const a=p.a+t*p.s,x=Math.cos(a),y=Math.sin(a),sx=cx+x*R*p.r,sy=cy+y*tilt*R*p.r;const g=ctx.createRadialGradient(sx,sy,0,sx,sy,14);g.addColorStop(0,'rgba(255,255,255,.9)');g.addColorStop(.3,'rgba(156,128,242,.5)');g.addColorStop(1,'rgba(156,128,242,0)');ctx.fillStyle=g;ctx.fillRect(sx-14,sy-14,28,28);
for(let k=1;k<10;k++){const aa=a-k*.025*Math.sign(p.s),tx2=cx+Math.cos(aa)*R*p.r,ty2=cy+Math.sin(aa)*tilt*R*p.r;ctx.fillStyle=`rgba(200,185,255,${.35*(1-k/10)})`;ctx.fillRect(tx2-1,ty2-1,2,2)}}
}if(!RM)requestAnimationFrame(frame)}
size();addEventListener('resize',size);new IntersectionObserver(([e])=>vis=e.isIntersecting).observe(hero);requestAnimationFrame(frame)})();

// reveal
const io=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}}),{threshold:.12,rootMargin:'0px 0px -40px 0px'});
$$('.rv').forEach((el,i)=>{el.style.transitionDelay=(i%4)*70+'ms';io.observe(el)});

// scroll scenes (each guarded)
const hdr=$('#hdr'),pars=$$('[data-par]'),wd=$('#wdepth'),web=$('#web'),mega=$$('#webMega span'),hs=$('#hs'),track=$('#track'),panels=$$('#track .panel'),hsBar=$('#hsBar'),inv=$('#invert'),invIn=$('#invIn'),invT=$('#invTitle'),ps=$('#psteps'),psLi=$$('#psteps li'),ag=$$('#agentList li');
const hsOn=()=>!RM&&innerWidth>760&&hs;
function layout(){if(hs)hs.style.height=hsOn()?(track.scrollWidth-innerWidth+innerHeight)+'px':'';tick()}
const pin=el=>{const r=el.getBoundingClientRect();return clamp(-r.top/(r.height-innerHeight))};
const grey=t=>{const v=Math.round(10+240*t);return `rgb(${v},${v},${v})`};
let ticking=false;
function tick(){ticking=false;const vh=innerHeight,y=scrollY;hdr.classList.toggle('scrolled',y>10);let light=false;
if(!RM){
if(wd){const hp=clamp(y/vh);wd.style.transform=`translate3d(0,${-hp*90}px,0) scale(${1+hp*.2})`;wd.style.opacity=1-hp*1.1}
pars.forEach(el=>{const r=el.parentElement.getBoundingClientRect();if(r.bottom>-200&&r.top<vh+200){const d=(r.top+r.height/2-vh/2)*-parseFloat(el.dataset.par);el.style.transform=el.classList.contains('dragon')?`translate3d(-50%,calc(-50% + ${d}px),0)`:`translate3d(0,${d}px,0)`}});
}
$$('.light').forEach(el=>{const r=el.getBoundingClientRect();if(r.top<=40&&r.bottom>40)light=true});
if(web){const br=web.getBoundingClientRect();if(!RM&&br.top<vh&&br.bottom>0){const hp2=clamp((vh*.25-br.top)/vh,-.3,.8);mega.forEach(s=>s.style.transform=`translate3d(${parseFloat(s.dataset.x)*hp2*6}vw,0,0)`)}}
if(hsOn()){const r=hs.getBoundingClientRect();if(r.top<vh&&r.bottom>0){const p=pin(hs),max=track.scrollWidth-innerWidth;track.style.transform=`translate3d(${-p*max}px,0,0)`;hsBar.style.setProperty('--hp',p);const cx=innerWidth/2;panels.forEach(pn=>{const b=pn.getBoundingClientRect(),d=Math.abs(b.left+b.width/2-cx)/innerWidth;pn.style.transform=`scale(${1-Math.min(1,d)*.07})`})}}
if(inv){const ir=inv.getBoundingClientRect();if(ir.top<vh&&ir.bottom>0){const p=pin(inv),t=RM?1:ease(clamp((p-.1)/.55));invIn.style.setProperty('--ibg',grey(1-t));invIn.style.setProperty('--ifg',grey(t));if(!RM)invT.style.transform=`scale(${1.14-.14*clamp(p/.8)})`;if(ir.top<=40&&ir.bottom>40&&t<.5)light=true}}
hdr.classList.toggle('onlight',light);
if(ps){const pr=ps.getBoundingClientRect();ps.style.setProperty('--pp',clamp((vh*.6-pr.top)/pr.height));psLi.forEach(li=>li.classList.toggle('on',li.getBoundingClientRect().top<vh*.6))}
ag.forEach(li=>{const b=li.getBoundingClientRect();li.classList.toggle('lit',b.top<vh*.62&&b.bottom>vh*.25)});
}
addEventListener('scroll',()=>{if(!ticking){ticking=true;requestAnimationFrame(tick)}},{passive:true});
addEventListener('resize',layout);addEventListener('load',layout);layout();

// menu
const menu=$('#menu');function setMenu(o){menu.classList.toggle('open',o);menu.setAttribute('aria-hidden',!o);$('#menuBtn').setAttribute('aria-expanded',o);$('#menuBtn').setAttribute('aria-label',o?'Закрыть меню':'Открыть меню');document.body.classList.toggle('locked',o);$$('#menu nav a').forEach((a,i)=>a.style.transitionDelay=o?(100+i*35)+'ms':'0ms');if(o)setTimeout(()=>$('#menu [data-close]').focus(),120)}
$('#menuBtn').onclick=()=>setMenu(!menu.classList.contains('open'));$$('[data-close]').forEach(b=>b.onclick=()=>{setMenu(false);$('#menuBtn').focus()});$$('#menu nav a').forEach(a=>a.addEventListener('click',()=>setMenu(false)));
const pg=document.body.dataset.page;$$('#menu nav a').forEach(a=>a.classList.toggle('active',a.dataset.key===pg));
addEventListener('keydown',e=>{if(e.key==='Escape'){setMenu(false);closeCase&&closeCase()}});

// calculator
if($('#cEmp'))(()=>{const E=$('#cEmp'),S=$('#cSal'),P=$('#cPct'),pot=$$('#cPot button');let K=.6,anim,shown=null;
const plural=(n,f)=>{const a=n%10,b=n%100;return f[a===1&&b!==11?0:a>=2&&a<=4&&(b<10||b>=20)?1:2]};
const nice=(v,st)=>Math.round(v/st)*st,rub=v=>v>=1e6?nice(v,10000):v>=1e5?nice(v,1000):nice(v,500),hr=v=>v>=1000?nice(v,10):Math.round(v);
function fill(el){el.style.setProperty('--p',((el.value-el.min)/(el.max-el.min)*100)+'%')}
pot.forEach(b=>b.onclick=()=>{pot.forEach(x=>x.setAttribute('aria-checked',x===b));K=+b.dataset.v;calc()});
function calc(){[E,S,P].forEach(fill);const e=+E.value,s=+S.value,p=+P.value/100;
const routine=e*160*p,auto=routine*K,left=routine-auto,eq=auto*(s/160),year=auto*12,fte=year/1920,per=Math.round(160*p);
$('#oEmp').textContent=`${fmt(e)} ${plural(e,['сотрудник','сотрудника','сотрудников'])}`;$('#oSal').textContent=fmt(s)+' ₽';$('#oPct').textContent=Math.round(p*100)+'%';
$('#oPerEmp').textContent=`≈ ${per} ${plural(per,['час','часа','часов'])} рутины на одного сотрудника в месяц`;
const R=Math.round(routine),A=Math.round(auto),Lf=R-A;
$('#rRoutine').textContent=fmt(R);$('#fRoutine').textContent=fmt(R)+' ч';$('#fAi').textContent=fmt(A)+' ч';$('#fLeft').textContent=fmt(Lf)+' ч';$('#sbAi').style.width=(K*100)+'%';
const fr=fte<10?Math.round(fte*100)/100:Math.round(fte),fteTxt=fr.toLocaleString('ru-RU',{maximumFractionDigits:2});
$('#rFte').textContent=`≈ ${fteTxt} ${Number.isInteger(fr)?plural(fr,['рабочий год','рабочих года','рабочих лет']):'рабочего года'} одного сотрудника`;
const to={a:A,r:rub(eq),y:hr(year)};cancelAnimationFrame(anim);const from=shown||{a:0,r:0,y:0},t0=performance.now();
const step=t=>{const k=RM||shown&&Math.abs(to.a-from.a)<1?1:ease(clamp((t-t0)/(shown?260:700)));const c={a:from.a+(to.a-from.a)*k,r:from.r+(to.r-from.r)*k,y:from.y+(to.y-from.y)*k};shown=c;$('#rAuto').textContent=fmt(c.a);$('#rRub').textContent=fmt(k<1?nice(c.r,100):to.r);$('#rYear').textContent=fmt(k<1?c.y:to.y);if(k<1)anim=requestAnimationFrame(step)};anim=requestAnimationFrame(step);
window.__calc={e,p:Math.round(p*100),k:Math.round(K*100),h:A}}
[E,S,P].forEach(i=>i.addEventListener('input',calc));calc();
$('#calcCta').onclick=()=>{const c=window.__calc;openForm('AI-агенты');$('#task').value=`Разбор процессов: ${c.e} ${plural(c.e,['сотрудник','сотрудника','сотрудников'])}, ${c.p}% времени на рутину, потенциал ${c.k}% — ≈ ${fmt(c.h)} ч/мес.`;scrollTo({top:$('#contact').getBoundingClientRect().top+scrollY,behavior:'smooth'})};
})();

// case detail
var closeCase=null;
if($('#caseFeat'))(()=>{const CASE={title:"AI-консультант для сервиса",tag:"AI-агенты · Пример структуры",task:"Снизить нагрузку на менеджеров.",sol:"AI-агент на базе внутренней базы знаний с интеграцией в Telegram и CRM.",built:"AI-агент, база знаний",integ:"Telegram · CRM",res:[["73%","типовых обращений закрываются автоматически"],["24/7","поддержка"],["< 10 с","среднее время ответа"]]};
const det=$('#detail');
function openCase(){const c=CASE;$('#dBody').innerHTML=`<div class="dhero"><image-slot id="case-ai-consultant-hero" shape="rect" placeholder="Главный визуал кейса"></image-slot></div><div class="wrap" style="padding-bottom:96px"><div style="display:grid;gap:20px;padding-top:64px"><span class="tag" style="justify-self:start">${c.tag}</span><h2 class="disp h2">${c.title}</h2></div><div class="dres">${c.res.map(x=>`<div><span class="v">${x[0]}</span><span class="cap">${x[1]}</span></div>`).join('')}</div><dl class="cfields" style="max-width:860px"><div><dt>Задача</dt><dd>${c.task}</dd></div><div><dt>Решение</dt><dd>${c.sol}</dd></div><div><dt>Разработано</dt><dd>${c.built}</dd></div><div><dt>Интеграции</dt><dd>${c.integ}</dd></div></dl><div style="margin-top:56px;display:flex;gap:16px;flex-wrap:wrap"><button class="btn" data-dcta>Обсудить похожий проект <span class="ar">→</span></button><button class="btn ghost" data-dclose2>← Все кейсы</button></div></div>`;
det.scrollTop=0;det.classList.add('open');det.setAttribute('aria-hidden','false');document.body.classList.add('locked');
$('[data-dclose2]').onclick=closeCase;$('[data-dcta]').onclick=()=>{closeCase();openForm('AI-агенты');scrollTo({top:$('#contact').getBoundingClientRect().top+scrollY,behavior:'smooth'})}}
closeCase=()=>{det.classList.remove('open');det.setAttribute('aria-hidden','true');document.body.classList.remove('locked')};
const feat=$('#caseFeat');feat.addEventListener('click',e=>{if(e.target.closest('image-slot'))return;openCase()});feat.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();openCase()}});
$('[data-dclose]').onclick=closeCase})();

// model list animation
if($('.models'))(()=>{const ul=$('.models');const items=[...ul.children].filter(li=>!li.classList.contains('sep'));
[...ul.children].forEach((li,i)=>{li.innerHTML=`<span>${li.innerHTML}</span>`;li.firstChild.style.transitionDelay=i*70+'ms';li.style.transitionDelay=i*70+'ms'});
let k=-1,timer,paused=false;const step=()=>{if(paused)return;items.forEach(x=>x.classList.remove('on'));k=(k+1)%items.length;items[k].classList.add('on')};
new IntersectionObserver(([e])=>{if(e.isIntersecting){if(!timer&&!RM){setTimeout(step,900);timer=setInterval(step,1800)}}else{clearInterval(timer);timer=null}},{threshold:.3}).observe(ul);
ul.addEventListener('pointerenter',()=>{paused=true;items.forEach(x=>x.classList.remove('on'))});ul.addEventListener('pointerleave',()=>paused=false)})();

// insights filter
$$('#filters .chip').forEach(c=>c.onclick=()=>{$$('#filters .chip').forEach(x=>x.setAttribute('aria-pressed',x===c));const cat=c.dataset.cat;let n=0;$$('#posts li').forEach(li=>{const show=cat==='all'||li.dataset.cat===cat;li.hidden=!show;if(show)n++});$('#postsEmpty').hidden=n>0});

// form
const chips=$$('#chips .chip'),fw=$('#formWrap');
function openForm(pick){if(!fw)return;fw.classList.add('open');$('#openForm').setAttribute('aria-expanded','true');if(pick)chips.forEach(c=>c.setAttribute('aria-pressed',c.textContent===pick))}
window.openForm=openForm;
if(fw){
$('#openForm').onclick=()=>{const o=!fw.classList.contains('open');if(o)openForm();else{fw.classList.remove('open');$('#openForm').setAttribute('aria-expanded','false')}};
$$('[data-open-form]').forEach(a=>a.addEventListener('click',()=>openForm(a.dataset.pick)));
chips.forEach(c=>c.onclick=()=>c.setAttribute('aria-pressed',c.getAttribute('aria-pressed')!=='true'));
const val={name:v=>v.trim().length>1,contactI:v=>/^\S+@\S+\.\S+$/.test(v.trim())||/^@?[a-zA-Z0-9_]{4,}$/.test(v.trim())};
['name','contactI'].forEach(id=>$('#'+id).addEventListener('input',e=>{const f=e.target.closest('.field');if(f.classList.contains('err')&&val[id](e.target.value))f.classList.remove('err')}));
$('#form').onsubmit=e=>{e.preventDefault();let ok=true;['name','contactI'].forEach(id=>{const good=val[id]($('#'+id).value);$('#'+id).closest('.field').classList.toggle('err',!good);if(!good&&ok){$('#'+id).focus();ok=false}});if(!ok)return;
const b=$('#send');b.disabled=true;b.textContent='Отправляем…';setTimeout(()=>{const s=chips.filter(c=>c.getAttribute('aria-pressed')==='true').map(c=>c.textContent);$('#sentMsg').textContent=`${$('#name').value.trim()}, ответим в течение 24 часов${s.length?' — направление: '+s.join(', '):''}.`;$('#form').style.display='none';$('#sent').classList.add('show');b.disabled=false;b.innerHTML='Отправить <span class="ar">→</span>'},900)};
$('#again').onclick=()=>{$('#form').reset();chips.forEach(c=>c.setAttribute('aria-pressed','false'));$('#sent').classList.remove('show');$('#form').style.display=''};
if(location.hash==='#contact')openForm();
}

// services background video
// The group (services + calculator + insights) shares one sticky background,
// so the video stays put while only the content scrolls over it.
const fxGroup=$('#fxGroup');
if(fxGroup){
  const media=document.createElement('div');
  media.className='directions-video';
  media.setAttribute('aria-hidden','true');
  media.innerHTML='<video autoplay muted loop playsinline preload="metadata"><source src="assets/flower-services-bg.mp4" type="video/mp4"></video>';
  fxGroup.prepend(media);
}
