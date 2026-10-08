(()=>{
const W='<svg viewBox="0 0 200 56"><path d="M0 0L60 20L78.5 44L100 13.5L121.5 44L140 20L200 0L141 25L121.5 56L100 26L78.5 56L59 25Z"></path></svg>';
document.body.insertAdjacentHTML('beforeend',`<button class="chat-fab" id="chatFab" aria-label="Открыть чат WAI AI">${W}<span class="t"><b>WAI AI</b><small>ONLINE</small></span></button>
<div class="chat" id="chat" role="dialog" aria-label="WAI AI" aria-hidden="true"><div><div class="chat-h"><span class="av">${W}</span><span class="nm"><b>WAI AI</b><span class="chat-st">ONLINE</span></span><button class="chat-x" id="chatX" aria-label="Закрыть чат">×</button></div><div class="chat-prog"><i id="chatProg"></i></div></div><div class="chat-log" id="chatLog" aria-live="polite"></div><form class="chat-f" id="chatF"><input id="chatI" placeholder="Напишите сообщение…" autocomplete="off" aria-label="Сообщение"><button aria-label="Отправить">→</button></form></div>`);
const fab=document.getElementById('chatFab'),box=document.getElementById('chat'),log=document.getElementById('chatLog'),inp=document.getElementById('chatI'),prog=document.getElementById('chatProg');
const DIR={'Хочу AI-агента':'AI-агенты','Нужно приложение':'Приложения','Нужен сайт':'Сайты','Хочу автоматизировать бизнес':'Автоматизация','Нужна реклама':'Performance-маркетинг','Нужен AI-креатив':'AI-креатив'};
const Q=[
{k:'company',l:'Компания',q:'Какая у вас компания? Название и чем занимаетесь.'},
{k:'task',l:'Задача',q:'Какую задачу хотите решить?'},
{k:'now',l:'Сейчас',q:'Как сейчас решается эта задача?',opts:['Вручную сотрудниками','Частично автоматизировано','Пока никак']},
{k:'sys',l:'Системы',q:'Какие системы уже используются? CRM, 1С, сайт, мессенджеры, таблицы.',opts:['amoCRM','Битрикс24','1С','Таблицы','Пока ничего']},
{k:'scale',l:'Масштаб',q:'Какой ориентировочный масштаб? Например: число сотрудников, обращений в день или пользователей.',opts:['До 10 сотрудников','10–50','50–200','200+']},
{k:'contact',l:'Контакт',q:'Оставьте контакт для связи — email, Telegram или телефон.',v:s=>/^\S+@\S+\.\S+$/.test(s)||/^@?[a-zA-Z0-9_]{4,}$/.test(s)||/^[+\d][\d\s()-]{8,}$/.test(s)}
];
let st=-1,data={},dir=null,started=false,busy=false;
const scroll=()=>log.scrollTop=log.scrollHeight;
function add(html,who='ai',step){const d=document.createElement('div');d.className='cmsg '+who;d.innerHTML=(step?`<span class="step">${step}</span>`:'')+html;log.appendChild(d);scroll();return d}
const esc=s=>s.replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function quick(opts,cb){const q=document.createElement('div');q.className='quick';opts.forEach(o=>{const b=document.createElement('button');b.type='button';b.textContent=o;b.onclick=()=>{q.remove();cb(o)};q.appendChild(b)});log.appendChild(q);scroll()}
function say(text,step,then){busy=true;const t=document.createElement('div');t.className='typing';t.innerHTML='<i></i><i></i><i></i>';log.appendChild(t);scroll();setTimeout(()=>{t.remove();add(text,'ai',step);busy=false;then&&then()},matchMedia('(prefers-reduced-motion:reduce)').matches?100:650+Math.min(900,text.length*8))}
function ask(){st++;prog.style.width=(st/Q.length*100)+'%';if(st>=Q.length)return done();const q=Q[st];say(q.q,`Шаг ${st+1} / ${Q.length}`,()=>{if(q.opts)quick(q.opts,answer);inp.focus()})}
function answer(v){v=v.trim();if(!v||busy)return;$$('.quick',log).forEach(n=>n.remove());add(esc(v),'me');
if(st<0){dir=DIR[v]||null;if(!dir)data.task=v;say(dir?`Отлично, направление — ${dir}. Задам несколько вопросов, чтобы подобрать решение и предварительно оценить проект.`:'Понял. Задам несколько вопросов, чтобы подобрать решение и предварительно оценить проект.',null,ask);return}
const q=Q[st];if(q.v&&!q.v(v)){say('Похоже, это не контакт. Укажите email, @username в Telegram или телефон.');return}
data[q.k]=v;if(q.k==='company'&&data.task&&!dir){st++;}ask()}
function $$(s,r){return[...(r||document).querySelectorAll(s)]}
function done(){prog.style.width='100%';say('Спасибо. Я передал информацию команде — специалист свяжется с вами в течение рабочего дня с предварительной оценкой.',null,()=>{const s=document.createElement('div');s.className='summary';s.innerHTML=`<span class="cap" style="margin-bottom:8px;color:var(--accent2)">Заявка сформирована</span>`+(dir?`<div class="row"><span>Направление</span><span>${dir}</span></div>`:'')+Q.map(q=>data[q.k]?`<div class="row"><span>${q.l}</span><span>${esc(data[q.k])}</span></div>`:'').join('');log.appendChild(s);scroll();quick(['Начать заново'],reset)})}
function reset(){log.innerHTML='';st=-1;data={};dir=null;prog.style.width=0;start()}
function start(){started=true;say('Привет. Я AI-агент ВАЙ.\nРасскажите, какую задачу хотите решить — я помогу подобрать подходящее решение и предварительно оценить проект.',null,()=>quick(Object.keys(DIR),answer))}
function open(o){box.classList.toggle('open',o);box.setAttribute('aria-hidden',!o);fab.classList.toggle('hide',o);if(o){if(!started)start();setTimeout(()=>inp.focus(),300)}else fab.focus()}
fab.onclick=()=>open(true);document.getElementById('chatX').onclick=()=>open(false);
addEventListener('keydown',e=>{if(e.key==='Escape'&&box.classList.contains('open'))open(false)});
document.getElementById('chatF').onsubmit=e=>{e.preventDefault();const v=inp.value;if(!v.trim()||busy)return;inp.value='';answer(v)};
})();
