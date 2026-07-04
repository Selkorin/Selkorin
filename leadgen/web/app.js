/* ─────────────────────────────────────────────────────────────────────────
   Selkorin Lead Engine — фронтенд (SPA без сборки)
   ───────────────────────────────────────────────────────────────────────── */
"use strict";

// ── Утилиты ────────────────────────────────────────────────────────────────
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
  ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

async function api(path, opts = {}) {
  const res = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...opts,
    body: opts.body ? JSON.stringify(opts.body) : undefined,
  });
  if (!res.ok) {
    let msg = res.statusText;
    try { const j = await res.json(); msg = j.detail || JSON.stringify(j); } catch (_) {}
    throw new Error(msg);
  }
  const ct = res.headers.get("content-type") || "";
  return ct.includes("json") ? res.json() : res.text();
}

function toast(msg, type = "") {
  const t = document.createElement("div");
  t.className = "toast " + type;
  t.innerHTML = `<span>${type === "ok" ? "✓" : type === "err" ? "✕" : "•"}</span><span>${esc(msg)}</span>`;
  $("#toasts").appendChild(t);
  setTimeout(() => { t.style.opacity = "0"; t.style.transform = "translateY(8px)"; setTimeout(() => t.remove(), 250); }, 3200);
}

function openModal(title, bodyHtml, footHtml = "") {
  const root = $("#modal-root");
  root.innerHTML = `
    <div class="overlay" data-close>
      <div class="modal">
        <div class="modal-head"><h3>${esc(title)}</h3><button class="x-close" data-close>×</button></div>
        <div class="modal-body">${bodyHtml}</div>
        ${footHtml ? `<div class="modal-foot">${footHtml}</div>` : ""}
      </div>
    </div>`;
  $$("[data-close]", root).forEach((b) => b.addEventListener("click", (e) => {
    if (e.target === b) closeModal();
  }));
  return root;
}
function closeModal() { $("#modal-root").innerHTML = ""; }

const fmtTime = (t) => {
  if (!t) return "—";
  const d = new Date(t * 1000), now = Date.now();
  const diff = (now - d.getTime()) / 1000;
  if (diff < 60) return "только что";
  if (diff < 3600) return Math.floor(diff / 60) + " мин назад";
  if (diff < 86400) return Math.floor(diff / 3600) + " ч назад";
  return d.toLocaleDateString("ru-RU", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
};

const intentLabel = { hot: "Горячий", warm: "Тёплый", cold: "Холодный" };
const sourceLabel = { telegram: "Telegram", yandex_search: "Яндекс-поиск", yandex_maps: "Яндекс.Карты", manual: "Вручную" };
const sourceIcon = { telegram: "✈️", yandex_search: "🔎", yandex_maps: "🗺️", manual: "✍️" };
const statusLabel = { new: "Новый", contacted: "Связались", replied: "Ответил", won: "Клиент", lost: "Отказ", skip: "Пропуск" };

// ── Навигация ───────────────────────────────────────────────────────────────
const NAV = [
  { group: "Лидогенерация" },
  { id: "dashboard", icon: "▧", label: "Обзор", title: "Обзор", sub: "Панель лидогенерации" },
  { id: "search", icon: "🔍", label: "Найти лидов", title: "Поиск лидов", sub: "Опиши, кого искать — движок соберёт заявки" },
  { id: "leads", icon: "🎯", label: "Лиды", title: "Лиды", sub: "Найденные заявки и клиенты", count: "leads_new" },
  { id: "monitors", icon: "📡", label: "Мониторы", title: "Мониторы", sub: "Автопоиск по расписанию" },
  { group: "Telegram" },
  { id: "telegram", icon: "✈️", label: "Аккаунты", title: "Telegram-аккаунты", sub: "Сессии для парсинга и рассылок" },
  { id: "campaigns", icon: "📣", label: "Рассылки", title: "Рассылки и активность", sub: "Массовые сообщения, реакции, кружки" },
  { group: "Система" },
  { id: "brain", icon: "🧠", label: "Мозг (промты)", title: "Мозг движка", sub: "Промты, которые управляют поиском" },
  { id: "settings", icon: "⚙️", label: "Настройки", title: "Настройки", sub: "Ключи API, режим, лимиты" },
];

let STATE = { stats: {}, settings: {} };

function renderNav() {
  const nav = $("#nav");
  nav.innerHTML = NAV.map((n) => {
    if (n.group) return `<div class="nav-label">${esc(n.group)}</div>`;
    const count = n.count && STATE.stats[n.count] ? `<span class="badge-count">${STATE.stats[n.count]}</span>` : "";
    return `<a class="nav-item" href="#/${n.id}" data-nav="${n.id}"><span class="ic">${n.icon}</span> ${esc(n.label)} ${count}</a>`;
  }).join("");
}

function setActive(id) {
  $$(".nav-item").forEach((a) => a.classList.toggle("active", a.dataset.nav === id));
  const meta = NAV.find((n) => n.id === id) || {};
  $("#page-title").textContent = meta.title || "";
  $("#page-sub").textContent = meta.sub || "";
}

function renderTopbar() {
  const s = STATE.settings;
  const ai = s.anthropic_api_key_set;
  $("#topbar-right").innerHTML = `
    <span class="chip ${ai ? "ok" : "warn"}">${ai ? "🤖 AI: Claude" : "🤖 AI: эвристика"}</span>
    <span class="chip ${STATE.stats.mode === "live" ? "ok" : "warn"}">${STATE.stats.mode === "live" ? "🟢 LIVE" : "🟡 DEMO"}</span>
    <a class="btn primary sm" href="#/search">＋ Найти лидов</a>`;
  const pill = $("#mode-pill");
  if (pill) pill.innerHTML = `<span class="dot ${STATE.stats.mode === "live" ? "" : "demo"}"></span> ${STATE.stats.mode === "live" ? "live-режим" : "демо-режим"}`;
}

// ── Роутер ───────────────────────────────────────────────────────────────────
const VIEWS = {};
async function route() {
  const hash = location.hash.replace(/^#\//, "") || "dashboard";
  const [id] = hash.split("/");
  closeModal(); // закрываем модалку при навигации
  setActive(id);
  const app = $("#app");
  app.innerHTML = `<div class="loading"><span class="spinner dark"></span> Загрузка…</div>`;
  try {
    STATE.stats = await api("/api/stats");
    renderNav();
    renderTopbar();
    await (VIEWS[id] || VIEWS.dashboard)(app);
  } catch (e) {
    app.innerHTML = `<div class="empty"><div class="big">⚠️</div>${esc(e.message)}</div>`;
  }
}

// ═════════════════════════════════════ ОБЗОР ════════════════════════════════
VIEWS.dashboard = async (app) => {
  const s = STATE.stats;
  const [events, hotLeads] = await Promise.all([
    api("/api/events?limit=8"),
    api("/api/leads?intent=hot&limit=4"),
  ]);
  const stat = (lbl, val, sub, ic) => `
    <div class="stat"><div class="ic-badge">${ic}</div>
      <div class="lbl">${lbl}</div><div class="val">${val}</div><div class="sub">${sub}</div></div>`;

  const srcRows = Object.entries(s.by_source || {}).map(([k, v]) => {
    const pct = s.leads_total ? Math.round((v / s.leads_total) * 100) : 0;
    return `<div style="margin-bottom:12px">
      <div style="display:flex;justify-content:space-between;font-size:13px;margin-bottom:5px">
        <span>${sourceIcon[k] || "•"} ${esc(sourceLabel[k] || k)}</span><b>${v}</b></div>
      <div class="progress"><span style="width:${pct}%"></span></div></div>`;
  }).join("") || `<div class="faint">Пока нет данных</div>`;

  app.innerHTML = `
    <div class="hero" style="margin-bottom:20px">
      <h1>Найди клиентов, пока их не забрали конкуренты</h1>
      <p>Опиши задачу обычными словами — движок разложит её на план и соберёт свежие заявки из Telegram-чатов, Яндекс-поиска и Яндекс.Карт (бизнесы без сайта).</p>
      <div class="search-box">
        <input class="search-input" id="dash-q" placeholder="Например: найди мне клиентов, кому нужен сайт" value="Найди мне клиентов, кому нужен сайт" />
        <input class="city-input" id="dash-city" placeholder="Город (необязательно)" />
        <button class="btn primary" id="dash-go">Искать →</button>
      </div>
    </div>

    <div class="grid stats" style="margin-bottom:20px">
      ${stat("Всего лидов", s.leads_total || 0, "в базе", "🎯")}
      ${stat("Горячие", s.leads_hot || 0, "готовы к контакту", "🔥")}
      ${stat("Новые", s.leads_new || 0, "ещё не в работе", "🆕")}
      ${stat("Клиенты", s.leads_won || 0, "закрыто в продажу", "🏆")}
      ${stat("Мониторы", `${s.monitors_active || 0}/${s.monitors || 0}`, "активны / всего", "📡")}
      ${stat("Аккаунты TG", `${s.accounts_connected || 0}/${s.accounts || 0}`, "подключены", "✈️")}
    </div>

    <div class="grid two">
      <div class="card pad">
        <div class="section-head"><div class="section-title">🔥 Горячие лиды</div><a class="btn ghost sm" href="#/leads">Все лиды →</a></div>
        <div id="hot-list">${hotLeads.length ? hotLeads.map(leadCard).join("") : `<div class="empty"><div class="big">🌱</div>Запусти поиск, чтобы собрать первых лидов</div>`}</div>
      </div>
      <div style="display:flex;flex-direction:column;gap:16px">
        <div class="card pad">
          <div class="section-title" style="margin-bottom:14px">Источники</div>
          ${srcRows}
        </div>
        <div class="card pad">
          <div class="section-title" style="margin-bottom:10px">Активность</div>
          ${events.map((e) => `<div style="display:flex;gap:9px;padding:7px 0;font-size:13px;border-bottom:1px solid var(--border)">
            <span>${{ success: "✅", warn: "⚠️", error: "⛔", info: "•" }[e.level] || "•"}</span>
            <div style="flex:1"><div>${esc(e.message)}</div><div class="faint">${fmtTime(e.created_at)}</div></div></div>`).join("") || `<div class="faint">Тихо</div>`}
        </div>
      </div>
    </div>`;

  wireLeadActions(app);
  $("#dash-go").addEventListener("click", () => {
    const q = $("#dash-q").value, c = $("#dash-city").value;
    location.hash = `#/search`;
    sessionStorage.setItem("pendingSearch", JSON.stringify({ q, c }));
  });
};

// ═════════════════════════════════════ ПОИСК ════════════════════════════════
VIEWS.search = async (app) => {
  const prompts = await api("/api/prompts");
  const suggestions = [
    "Найди мне клиентов, кому нужен сайт",
    "Кому нужен лендинг под запуск курса",
    "Бизнесы без сайта в моём городе",
    "Ищут разработчика интернет-магазина",
  ];
  app.innerHTML = `
    <div class="hero" style="margin-bottom:22px">
      <h1>Опиши, кого искать</h1>
      <p>${esc(prompts.default_brief)}</p>
      <div class="search-box">
        <input class="search-input" id="q" placeholder="Найди мне клиентов, кому нужен сайт" />
        <input class="city-input" id="city" placeholder="Город" />
        <button class="btn primary" id="go">Искать →</button>
      </div>
      <div class="suggest-row">${suggestions.map((s) => `<button class="suggest" data-s="${esc(s)}">${esc(s)}</button>`).join("")}</div>
    </div>
    <div id="search-result"></div>`;

  $$(".suggest", app).forEach((b) => b.addEventListener("click", () => { $("#q").value = b.dataset.s; }));
  $("#go").addEventListener("click", runSearch);
  $("#q").addEventListener("keydown", (e) => { if (e.key === "Enter") runSearch(); });

  const pending = sessionStorage.getItem("pendingSearch");
  if (pending) {
    sessionStorage.removeItem("pendingSearch");
    const { q, c } = JSON.parse(pending);
    $("#q").value = q; $("#city").value = c || "";
    runSearch();
  }

  async function runSearch() {
    const query = $("#q").value.trim();
    if (!query) return toast("Введите запрос", "err");
    const city = $("#city").value.trim();
    const box = $("#search-result");
    box.innerHTML = `<div class="loading"><span class="spinner dark"></span> Строю план и собираю заявки…</div>`;
    try {
      const r = await api("/api/search", { method: "POST", body: { query, city } });
      renderSearchResult(box, r, query, city);
    } catch (e) { box.innerHTML = `<div class="empty"><div class="big">⚠️</div>${esc(e.message)}</div>`; }
  }

  function renderSearchResult(box, r, query, city) {
    const p = r.plan || {};
    box.innerHTML = `
      <div class="grid two">
        <div>
          <div class="section-head">
            <div class="section-title">Найдено: ${r.leads.length} <span class="faint">· новых ${r.saved} · проверено ${r.checked} · ${r.engine === "claude" ? "Claude" : "эвристика"}</span></div>
            <button class="btn sm" id="save-monitor">💾 Сохранить как монитор</button>
          </div>
          <div>${r.leads.length ? r.leads.map(leadCard).join("") : `<div class="empty"><div class="big">🔍</div>Свежих заявок не нашлось. Попробуй другой запрос или включи live-режим с ключами.</div>`}</div>
        </div>
        <div class="card pad">
          <div class="section-title" style="margin-bottom:12px">🧭 План поиска</div>
          <div class="kv"><span class="k">Ниша</span><b>${esc(p.niche || "—")}</b></div>
          <div class="kv"><span class="k">Идеальный клиент</span><span>${esc(p.ideal_lead || "—")}</span></div>
          <div class="divider"></div>
          ${planBlock("Ключевые фразы", p.keywords)}
          ${planBlock("Сигналы намерения", p.intent_signals)}
          ${planBlock("Минус-слова", p.negative_keywords)}
          ${planBlock("Чаты Telegram", p.telegram_chats)}
          ${planBlock("Категории на Картах", p.maps_categories)}
          ${planBlock("Города", p.cities)}
        </div>
      </div>`;
    wireLeadActions(box);
    $("#save-monitor").addEventListener("click", async () => {
      try {
        await api("/api/monitors", { method: "POST", body: { name: query.slice(0, 40), query, city, plan: p, schedule_minutes: 0 } });
        toast("Монитор сохранён", "ok");
      } catch (e) { toast(e.message, "err"); }
    });
  }
  function planBlock(title, arr) {
    if (!arr || !arr.length) return "";
    return `<div style="margin-bottom:10px"><div class="faint" style="margin-bottom:5px">${esc(title)}</div>
      <div style="display:flex;gap:6px;flex-wrap:wrap">${arr.slice(0, 12).map((x) => `<span class="badge tag">${esc(x)}</span>`).join("")}</div></div>`;
  }
};

// ═════════════════════════════════════ ЛИДЫ ═════════════════════════════════
let LEAD_FILTER = { status: "", source: "", intent: "", q: "" };
VIEWS.leads = async (app) => {
  app.innerHTML = `
    <div class="filters" id="lead-filters">
      <div class="pill-toggle" id="status-toggle">
        ${["", "new", "contacted", "replied", "won"].map((s) => `<button data-st="${s}" class="${LEAD_FILTER.status === s ? "on" : ""}">${s ? statusLabel[s] : "Все"}</button>`).join("")}
      </div>
      <select class="select" id="f-source" style="width:auto"><option value="">Все источники</option>
        ${Object.entries(sourceLabel).map(([k, v]) => `<option value="${k}" ${LEAD_FILTER.source === k ? "selected" : ""}>${v}</option>`).join("")}</select>
      <select class="select" id="f-intent" style="width:auto"><option value="">Любой интерес</option>
        <option value="hot">🔥 Горячие</option><option value="warm">Тёплые</option><option value="cold">Холодные</option></select>
      <input class="input" id="f-q" placeholder="Поиск по тексту…" style="width:auto;flex:1;min-width:180px" value="${esc(LEAD_FILTER.q)}" />
    </div>
    <div id="leads-list"></div>`;

  const reload = async () => {
    const params = new URLSearchParams();
    Object.entries(LEAD_FILTER).forEach(([k, v]) => v && params.set(k, v));
    const list = $("#leads-list");
    list.innerHTML = `<div class="loading"><span class="spinner dark"></span> Загрузка…</div>`;
    const leads = await api("/api/leads?" + params.toString());
    list.innerHTML = leads.length
      ? `<div class="faint" style="margin-bottom:12px">Показано: ${leads.length}</div>` + leads.map(leadCard).join("")
      : `<div class="empty"><div class="big">🎯</div>Лиды не найдены. Запусти поиск на вкладке «Найти лидов».</div>`;
    wireLeadActions(list);
  };

  $$("#status-toggle button").forEach((b) => b.addEventListener("click", () => {
    LEAD_FILTER.status = b.dataset.st;
    $$("#status-toggle button").forEach((x) => x.classList.toggle("on", x === b));
    reload();
  }));
  $("#f-source").addEventListener("change", (e) => { LEAD_FILTER.source = e.target.value; reload(); });
  $("#f-intent").addEventListener("change", (e) => { LEAD_FILTER.intent = e.target.value; reload(); });
  let deb; $("#f-q").addEventListener("input", (e) => { clearTimeout(deb); LEAD_FILTER.q = e.target.value; deb = setTimeout(reload, 300); });
  $("#f-intent").value = LEAD_FILTER.intent;
  await reload();
};

function leadCard(l) {
  const ring = l.intent === "hot" ? "var(--hot)" : l.intent === "warm" ? "var(--warm)" : "var(--cold)";
  const tags = (l.tags || []).slice(0, 3).map((t) => `<span class="badge tag">${esc(t)}</span>`).join("");
  const link = l.url ? `<a class="btn sm" href="${esc(l.url)}" target="_blank" rel="noopener">↗ Открыть</a>` : "";
  return `
    <div class="lead" data-lead="${l.id}">
      <div class="score-ring" style="--pct:${l.score};--ring-color:${ring}"><span>${l.score}</span></div>
      <div class="lead-body">
        <div class="lead-head">
          <span class="lead-title">${esc(l.title || l.name || "Лид")}</span>
          <span class="badge ${l.intent}">${intentLabel[l.intent] || l.intent}</span>
          <span class="badge src">${sourceIcon[l.source] || "•"} ${esc(sourceLabel[l.source] || l.source)}</span>
          <span class="badge status-${l.status}">${statusLabel[l.status] || l.status}</span>
        </div>
        <div class="lead-snippet">${esc((l.snippet || "").slice(0, 240))}</div>
        <div class="lead-meta">
          ${l.name ? `<span><b>Имя:</b> ${esc(l.name)}</span>` : ""}
          ${l.contact ? `<span><b>Контакт:</b> ${esc(l.contact)}</span>` : ""}
          ${l.location ? `<span><b>📍</b> ${esc(l.location)}</span>` : ""}
          ${tags ? `<span>${tags}</span>` : ""}
        </div>
        ${l.reason ? `<div class="faint" style="margin-top:7px">💡 ${esc(l.reason)}</div>` : ""}
        <div class="lead-actions">
          <button class="btn primary sm" data-act="message" data-id="${l.id}">✍️ Сообщение</button>
          <select class="select" data-act="status" data-id="${l.id}" style="width:auto;padding:6px 10px;font-size:12.5px">
            ${["new", "contacted", "replied", "won", "lost", "skip"].map((s) => `<option value="${s}" ${l.status === s ? "selected" : ""}>${statusLabel[s]}</option>`).join("")}
          </select>
          ${link}
          <button class="btn ghost sm" data-act="delete" data-id="${l.id}">Удалить</button>
        </div>
      </div>
    </div>`;
}

function wireLeadActions(root) {
  $$('[data-act="status"]', root).forEach((sel) => sel.addEventListener("change", async (e) => {
    try { await api(`/api/leads/${sel.dataset.id}/status`, { method: "PATCH", body: { status: e.target.value } }); toast("Статус обновлён", "ok"); }
    catch (err) { toast(err.message, "err"); }
  }));
  $$('[data-act="delete"]', root).forEach((b) => b.addEventListener("click", async () => {
    if (!confirm("Удалить лид?")) return;
    await api(`/api/leads/${b.dataset.id}`, { method: "DELETE" });
    $(`[data-lead="${b.dataset.id}"]`, root)?.remove();
    toast("Удалено", "ok");
  }));
  $$('[data-act="message"]', root).forEach((b) => b.addEventListener("click", () => openMessageModal(b.dataset.id)));
}

async function openMessageModal(leadId) {
  openModal("✍️ Первое сообщение",
    `<div class="row2">
       <div class="field"><label>Кто пишет (о вас)</label><input class="input" id="m-bio" placeholder="Веб-студия, делаю сайты под ключ" value="Веб-студия — делаю сайты и лендинги под ключ"></div>
       <div class="field"><label>Тон</label><select class="select" id="m-tone"><option>дружелюбный</option><option>деловой</option><option>прямой</option></select></div>
     </div>
     <div class="field"><label>Что предлагаем</label><input class="input" id="m-offer" placeholder="Быстро сделаю современный сайт" value="Быстро сделаю современный сайт с онлайн-записью"></div>
     <button class="btn primary" id="m-gen" style="width:100%">✨ Сгенерировать сообщение</button>
     <div id="m-result" style="margin-top:16px"></div>`);
  $("#m-gen").addEventListener("click", async () => {
    const btn = $("#m-gen"); btn.disabled = true; btn.innerHTML = `<span class="spinner"></span> Пишу…`;
    try {
      const r = await api(`/api/leads/${leadId}/message`, { method: "POST", body: {
        sender_bio: $("#m-bio").value, offer: $("#m-offer").value, tone: $("#m-tone").value } });
      $("#m-result").innerHTML = `
        <div class="field"><label>Первое сообщение (${r._engine === "claude" ? "Claude" : "шаблон"})</label>
          <textarea class="textarea" id="m-msg" style="min-height:110px">${esc(r.message)}</textarea></div>
        ${r.followup ? `<div class="field"><label>Фоллоу-ап</label><textarea class="textarea" style="min-height:60px">${esc(r.followup)}</textarea></div>` : ""}
        <button class="btn sm" id="m-copy">📋 Скопировать</button>`;
      $("#m-copy").addEventListener("click", () => { navigator.clipboard.writeText($("#m-msg").value); toast("Скопировано", "ok"); });
    } catch (e) { toast(e.message, "err"); }
    finally { btn.disabled = false; btn.innerHTML = "✨ Сгенерировать сообщение"; }
  });
}

// ═════════════════════════════════════ МОНИТОРЫ ═════════════════════════════
VIEWS.monitors = async (app) => {
  const monitors = await api("/api/monitors");
  app.innerHTML = `
    <div class="section-head">
      <div class="faint">Мониторы ищут лидов автоматически по расписанию.</div>
      <button class="btn primary" id="new-monitor">＋ Новый монитор</button>
    </div>
    <div class="grid" style="grid-template-columns:repeat(auto-fill,minmax(340px,1fr))">
      ${monitors.length ? monitors.map(monitorCard).join("") : `<div class="empty" style="grid-column:1/-1"><div class="big">📡</div>Пока нет мониторов</div>`}
    </div>`;
  $("#new-monitor").addEventListener("click", openMonitorModal);
  wireMonitors(app);
};

function monitorCard(m) {
  const st = m.stats || {};
  const sched = m.schedule_minutes ? `каждые ${m.schedule_minutes} мин` : "вручную";
  return `<div class="card pad" data-mon="${m.id}">
    <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px">
      <div class="section-title">${esc(m.name)}</div>
      <span class="badge ${m.enabled ? "status-won" : "cold"}">${m.enabled ? "вкл" : "выкл"}</span>
    </div>
    <div class="faint" style="margin:4px 0 12px">${esc(m.query)}</div>
    <div class="kv"><span class="k">Расписание</span><b>${sched}</b></div>
    <div class="kv"><span class="k">Запусков</span><b>${st.runs || 0}</b></div>
    <div class="kv"><span class="k">Собрано лидов</span><b>${st.total_leads || 0}</b></div>
    <div class="kv"><span class="k">Последний запуск</span><span>${fmtTime(m.last_run_at)}</span></div>
    <div class="btn-row" style="margin-top:14px">
      <button class="btn primary sm" data-mact="run" data-id="${m.id}">▶ Запустить</button>
      <button class="btn sm" data-mact="toggle" data-id="${m.id}">${m.enabled ? "Выключить" : "Включить"}</button>
      <button class="btn ghost sm" data-mact="delete" data-id="${m.id}">Удалить</button>
    </div>
  </div>`;
}

function wireMonitors(root) {
  $$('[data-mact="run"]', root).forEach((b) => b.addEventListener("click", async () => {
    b.disabled = true; b.innerHTML = `<span class="spinner"></span> Ищу…`;
    try { const r = await api(`/api/monitors/${b.dataset.id}/run`, { method: "POST" }); toast(`Готово: новых лидов ${r.saved}`, "ok"); route(); }
    catch (e) { toast(e.message, "err"); b.disabled = false; b.textContent = "▶ Запустить"; }
  }));
  $$('[data-mact="toggle"]', root).forEach((b) => b.addEventListener("click", async () => {
    await api(`/api/monitors/${b.dataset.id}/toggle`, { method: "PATCH" }); route();
  }));
  $$('[data-mact="delete"]', root).forEach((b) => b.addEventListener("click", async () => {
    if (!confirm("Удалить монитор?")) return;
    await api(`/api/monitors/${b.dataset.id}`, { method: "DELETE" }); route();
  }));
}

function openMonitorModal() {
  openModal("Новый монитор",
    `<div class="field"><label>Название</label><input class="input" id="mo-name" placeholder="Клиенты на сайт — Москва"></div>
     <div class="field"><label>Запрос (что искать)</label><textarea class="textarea" id="mo-query">Найди мне клиентов, кому нужен сайт</textarea></div>
     <div class="row2">
       <div class="field"><label>Город</label><input class="input" id="mo-city" placeholder="Москва, Казань"></div>
       <div class="field"><label>Автозапуск</label>
         <select class="select" id="mo-sched">
           <option value="0">Вручную</option><option value="30">Каждые 30 мин</option>
           <option value="60">Каждый час</option><option value="180">Каждые 3 часа</option><option value="1440">Раз в день</option>
         </select></div>
     </div>
     <div class="field"><label>Источники</label>
       <div style="display:flex;gap:14px;flex-wrap:wrap">
         <label class="faint"><input type="checkbox" class="mo-src" value="telegram" checked> Telegram</label>
         <label class="faint"><input type="checkbox" class="mo-src" value="yandex_search" checked> Яндекс-поиск</label>
         <label class="faint"><input type="checkbox" class="mo-src" value="yandex_maps" checked> Яндекс.Карты</label>
       </div></div>`,
    `<button class="btn ghost" data-close onclick="document.getElementById('modal-root').innerHTML=''">Отмена</button>
     <button class="btn primary" id="mo-save">Создать</button>`);
  $("#mo-save").addEventListener("click", async () => {
    const sources = $$(".mo-src").filter((c) => c.checked).map((c) => c.value);
    try {
      await api("/api/monitors", { method: "POST", body: {
        name: $("#mo-name").value || "Монитор",
        query: $("#mo-query").value,
        city: $("#mo-city").value,
        schedule_minutes: parseInt($("#mo-sched").value, 10),
        sources,
      } });
      closeModal(); toast("Монитор создан", "ok"); route();
    } catch (e) { toast(e.message, "err"); }
  });
}

// ═════════════════════════════════════ TELEGRAM ═════════════════════════════
VIEWS.telegram = async (app) => {
  const accounts = await api("/api/telegram/accounts");
  app.innerHTML = `
    <div class="warn-banner">⚠️ <div>Автоматизация пользовательских аккаунтов нарушает правила Telegram и может привести к блокировке номера. Используйте прогретые аккаунты, начинайте с малых объёмов, соблюдайте паузы. Ответственность за использование — на вас.</div></div>
    <div class="section-head">
      <div class="faint">Telegram-сессии нужны для парсинга чатов и рассылок. API-ключи возьмите на <b>my.telegram.org</b>.</div>
      <button class="btn primary" id="new-acc">＋ Добавить аккаунт</button>
    </div>
    <div class="grid" style="grid-template-columns:repeat(auto-fill,minmax(320px,1fr))">
      ${accounts.length ? accounts.map(accountCard).join("") : `<div class="empty" style="grid-column:1/-1"><div class="big">✈️</div>Нет аккаунтов</div>`}
    </div>`;
  $("#new-acc").addEventListener("click", openAccountModal);
  wireAccounts(app);
};

function accountCard(a) {
  const st = { connected: ["status-won", "🟢 подключён"], disconnected: ["cold", "⚪ не подключён"],
    awaiting_code: ["status-contacted", "✉️ ждёт код"], awaiting_password: ["status-contacted", "🔐 ждёт пароль"],
    error: ["hot", "⛔ ошибка"] }[a.status] || ["cold", a.status];
  return `<div class="card pad" data-acc="${a.id}">
    <div style="display:flex;justify-content:space-between;align-items:flex-start">
      <div class="section-title">${esc(a.label || a.phone)}</div>
      <span class="badge ${st[0]}">${st[1]}</span>
    </div>
    <div class="kv"><span class="k">Телефон</span><b>${esc(a.phone)}</b></div>
    ${a.me_username ? `<div class="kv"><span class="k">Аккаунт</span><b>@${esc(a.me_username)}</b></div>` : ""}
    ${a.note ? `<div class="faint" style="margin-top:6px">${esc(a.note)}</div>` : ""}
    <div class="btn-row" style="margin-top:14px">
      ${a.status === "connected"
        ? `<span class="badge status-won">Готов к работе</span>`
        : `<button class="btn primary sm" data-aact="login" data-id="${a.id}">🔑 Войти</button>`}
      <button class="btn ghost sm" data-aact="delete" data-id="${a.id}">Удалить</button>
    </div>
  </div>`;
}

function wireAccounts(root) {
  $$('[data-aact="login"]', root).forEach((b) => b.addEventListener("click", () => loginFlow(b.dataset.id)));
  $$('[data-aact="delete"]', root).forEach((b) => b.addEventListener("click", async () => {
    if (!confirm("Удалить аккаунт?")) return;
    await api(`/api/telegram/accounts/${b.dataset.id}`, { method: "DELETE" }); route();
  }));
}

function openAccountModal() {
  openModal("Добавить Telegram-аккаунт",
    `<div class="hint" style="margin-bottom:14px">Зайдите на <b>my.telegram.org</b> → API development tools → создайте приложение, получите <b>api_id</b> и <b>api_hash</b>.</div>
     <div class="field"><label>Название</label><input class="input" id="a-label" placeholder="Мой рабочий аккаунт"></div>
     <div class="field"><label>Телефон (в международном формате)</label><input class="input" id="a-phone" placeholder="+79001234567"></div>
     <div class="row2">
       <div class="field"><label>api_id</label><input class="input" id="a-apiid" placeholder="1234567"></div>
       <div class="field"><label>api_hash</label><input class="input" id="a-apihash" placeholder="abcd1234…"></div>
     </div>`,
    `<button class="btn ghost" onclick="document.getElementById('modal-root').innerHTML=''">Отмена</button>
     <button class="btn primary" id="a-save">Добавить</button>`);
  $("#a-save").addEventListener("click", async () => {
    try {
      await api("/api/telegram/accounts", { method: "POST", body: {
        label: $("#a-label").value, phone: $("#a-phone").value,
        api_id: $("#a-apiid").value, api_hash: $("#a-apihash").value } });
      closeModal(); toast("Аккаунт добавлен", "ok"); route();
    } catch (e) { toast(e.message, "err"); }
  });
}

async function loginFlow(id) {
  openModal("Вход в Telegram", `<div class="loading"><span class="spinner dark"></span> Запрашиваю код…</div>`);
  try {
    const r = await api(`/api/telegram/accounts/${id}/login`, { method: "POST" });
    if (r.status === "connected") { closeModal(); toast("Аккаунт подключён!", "ok"); return route(); }
    renderCodeStep(id);
  } catch (e) { $(".modal-body").innerHTML = `<div class="empty"><div class="big">⚠️</div>${esc(e.message)}</div>`; }
}
function renderCodeStep(id) {
  $(".modal-body").innerHTML = `
    <div class="hint" style="margin-bottom:12px">Telegram отправил код в приложение. Введите его:</div>
    <div class="field"><label>Код подтверждения</label><input class="input" id="tg-code" placeholder="12345" autofocus></div>
    <button class="btn primary" id="tg-code-btn" style="width:100%">Подтвердить</button>`;
  $("#tg-code-btn").addEventListener("click", async () => {
    const btn = $("#tg-code-btn"); btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
    try {
      const r = await api(`/api/telegram/accounts/${id}/code`, { method: "POST", body: { code: $("#tg-code").value } });
      if (r.status === "awaiting_password") return renderPasswordStep(id);
      closeModal(); toast("Аккаунт подключён!", "ok"); route();
    } catch (e) { toast(e.message, "err"); btn.disabled = false; btn.textContent = "Подтвердить"; }
  });
}
function renderPasswordStep(id) {
  $(".modal-body").innerHTML = `
    <div class="hint" style="margin-bottom:12px">Включена двухфакторная защита. Введите облачный пароль Telegram:</div>
    <div class="field"><label>Пароль (2FA)</label><input class="input" type="password" id="tg-pass" autofocus></div>
    <button class="btn primary" id="tg-pass-btn" style="width:100%">Войти</button>`;
  $("#tg-pass-btn").addEventListener("click", async () => {
    const btn = $("#tg-pass-btn"); btn.disabled = true; btn.innerHTML = `<span class="spinner"></span>`;
    try {
      await api(`/api/telegram/accounts/${id}/password`, { method: "POST", body: { password: $("#tg-pass").value } });
      closeModal(); toast("Аккаунт подключён!", "ok"); route();
    } catch (e) { toast(e.message, "err"); btn.disabled = false; btn.textContent = "Войти"; }
  });
}

// ═════════════════════════════════════ КАМПАНИИ ═════════════════════════════
VIEWS.campaigns = async (app) => {
  const [campaigns, accounts] = await Promise.all([api("/api/campaigns"), api("/api/telegram/accounts")]);
  app.innerHTML = `
    <div class="warn-banner">⚠️ <div>Массовые рассылки, реакции и кружки нарушают правила Telegram. Соблюдайте паузы и суточные лимиты (настраиваются). Шлите только тем, кому это уместно — иначе аккаунт улетит в бан.</div></div>
    <div class="section-head">
      <div class="faint">Массовые сообщения, реакции ❤️👍, кружки и просмотры — с человекоподобными паузами.</div>
      <button class="btn primary" id="new-camp">＋ Новая кампания</button>
    </div>
    <div id="camp-list">
      ${campaigns.length ? campaigns.map(campaignCard).join("") : `<div class="empty"><div class="big">📣</div>Нет кампаний</div>`}
    </div>`;
  $("#new-camp").addEventListener("click", () => openCampaignModal(accounts));
  wireCampaigns(app);
};

const KIND_LABEL = { broadcast: "📨 Рассылка", reaction: "👍 Реакции", like: "❤️ Лайки", circle: "⭕ Кружки", views: "👁 Просмотры", forward: "↪️ Репост" };
function campaignCard(c) {
  const pr = c.progress || {}; const total = pr.total || (c.targets || []).length || 0;
  const done = pr.done || 0; const pct = total ? Math.round((done / total) * 100) : 0;
  const stColor = { running: "status-contacted", done: "status-won", paused: "cold", draft: "src", error: "hot" }[c.status] || "cold";
  return `<div class="card pad" data-camp="${c.id}" style="margin-bottom:14px">
    <div style="display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px">
      <div><span class="section-title">${esc(c.name)}</span> <span class="badge src">${KIND_LABEL[c.kind] || c.kind}</span> <span class="badge ${stColor}">${esc(c.status)}</span></div>
      <div class="btn-row">
        ${c.status === "running"
          ? `<button class="btn sm" data-cact="pause" data-id="${c.id}">⏸ Пауза</button><button class="btn danger sm" data-cact="stop" data-id="${c.id}">⏹ Стоп</button>`
          : `<button class="btn primary sm" data-cact="start" data-id="${c.id}">▶ Запустить</button>`}
        <button class="btn ghost sm" data-cact="logs" data-id="${c.id}">Логи</button>
        <button class="btn ghost sm" data-cact="delete" data-id="${c.id}">✕</button>
      </div>
    </div>
    <div style="display:flex;gap:20px;margin:12px 0 8px;font-size:13px" class="muted">
      <span>Целей: <b>${total}</b></span><span>✅ ${pr.sent || 0}</span><span>❌ ${pr.failed || 0}</span>
    </div>
    <div class="progress"><span style="width:${pct}%"></span></div>
  </div>`;
}

function wireCampaigns(root) {
  const act = async (id, action, method = "POST") => { await api(`/api/campaigns/${id}/${action}`, { method }); route(); };
  $$('[data-cact="start"]', root).forEach((b) => b.addEventListener("click", () => act(b.dataset.id, "start").catch((e) => toast(e.message, "err"))));
  $$('[data-cact="pause"]', root).forEach((b) => b.addEventListener("click", () => act(b.dataset.id, "pause")));
  $$('[data-cact="stop"]', root).forEach((b) => b.addEventListener("click", () => act(b.dataset.id, "stop")));
  $$('[data-cact="delete"]', root).forEach((b) => b.addEventListener("click", async () => {
    if (!confirm("Удалить кампанию?")) return; await api(`/api/campaigns/${b.dataset.id}`, { method: "DELETE" }); route();
  }));
  $$('[data-cact="logs"]', root).forEach((b) => b.addEventListener("click", () => openLogs(b.dataset.id)));
}

async function openLogs(id) {
  openModal("Логи кампании", `<div class="loading"><span class="spinner dark"></span></div>`);
  const logs = await api(`/api/campaigns/${id}/logs`);
  $(".modal-body").innerHTML = logs.length ? `<div class="tablewrap"><table>
    <tr><th>Цель</th><th>Действие</th><th>Статус</th><th>Детали</th></tr>
    ${logs.map((l) => `<tr><td>${esc(l.target)}</td><td>${esc(l.action)}</td>
      <td><span class="badge ${l.status === "ok" ? "status-won" : l.status === "skip" ? "cold" : "hot"}">${esc(l.status)}</span></td>
      <td class="faint">${esc(l.detail || "")}</td></tr>`).join("")}</table></div>`
    : `<div class="empty">Пока пусто</div>`;
}

function openCampaignModal(accounts) {
  const connected = accounts.filter((a) => a.status === "connected");
  const accOptions = accounts.map((a) => `<option value="${a.id}">${esc(a.label || a.phone)}${a.status !== "connected" ? " (не подключён)" : ""}</option>`).join("");
  openModal("Новая кампания",
    `${!connected.length ? `<div class="warn-banner">Нет подключённых аккаунтов. Кампанию можно создать, но для запуска подключите аккаунт во вкладке «Аккаунты».</div>` : ""}
     <div class="field"><label>Название</label><input class="input" id="c-name" placeholder="Рассылка по тёплым лидам"></div>
     <div class="row2">
       <div class="field"><label>Тип</label>
         <select class="select" id="c-kind">
           <option value="broadcast">📨 Массовая рассылка</option>
           <option value="reaction">👍 Массовые реакции</option>
           <option value="like">❤️ Массовые лайки</option>
           <option value="circle">⭕ Рассылка кружков (видео)</option>
           <option value="views">👁 Накрутка просмотров</option>
         </select></div>
       <div class="field"><label>Аккаунт</label><select class="select" id="c-acc">${accOptions}</select></div>
     </div>
     <div id="c-dynamic"></div>
     <div class="field"><label>Цели (по одной в строке)</label>
       <textarea class="textarea" id="c-targets" placeholder="@username&#10;https://t.me/chat/123&#10;+79001234567"></textarea>
       <div class="hint" id="c-targets-hint">Юзернеймы/телефоны для рассылки. Для реакций/просмотров — ссылки на посты вида t.me/канал/123.</div>
       <button class="btn sm" id="c-fill-leads" style="margin-top:8px">🎯 Подставить контакты из лидов</button>
     </div>`,
    `<button class="btn ghost" onclick="document.getElementById('modal-root').innerHTML=''">Отмена</button>
     <button class="btn primary" id="c-save">Создать кампанию</button>`);

  const dyn = $("#c-dynamic");
  const renderDyn = () => {
    const k = $("#c-kind").value;
    if (k === "broadcast") {
      dyn.innerHTML = `
        <div class="field"><label>Текст сообщения <span class="faint">(можно spintax: {Привет|Здравствуйте})</span></label>
          <textarea class="textarea" id="c-msg" placeholder="{Привет|Здравствуйте}! Увидел, что вам может быть нужен сайт…"></textarea></div>
        <label class="faint" style="display:flex;gap:8px;align-items:center"><input type="checkbox" id="c-personalize"> ✨ Персонализировать каждое сообщение через AI (по данным лида)</label>
        <div class="hint">AI-персонализация работает, если цели — лиды с контактом. Иначе шлётся общий текст.</div>`;
    } else if (k === "reaction") {
      dyn.innerHTML = `<div class="field"><label>Эмодзи реакции</label>
        <select class="select" id="c-emoji"><option>👍</option><option>🔥</option><option>❤️</option><option>👏</option><option>🎉</option><option>😁</option></select></div>`;
    } else if (k === "like") {
      dyn.innerHTML = `<div class="hint">Будет поставлена реакция ❤️ на каждый указанный пост.</div>`;
    } else if (k === "circle") {
      dyn.innerHTML = `<div class="field"><label>Видео для кружка (mp4, квадратное)</label>
        <input type="file" id="c-media" accept="video/mp4"><div class="hint" id="c-media-status"></div></div>`;
      $("#c-media").addEventListener("change", uploadMedia);
    } else if (k === "views") {
      dyn.innerHTML = `<div class="hint">Накрутка просмотров у постов канала. Цели — ссылки на посты t.me/канал/123.</div>`;
    }
  };
  $("#c-kind").addEventListener("change", renderDyn); renderDyn();

  let mediaPath = "";
  async function uploadMedia(e) {
    const f = e.target.files[0]; if (!f) return;
    const fd = new FormData(); fd.append("file", f);
    $("#c-media-status").textContent = "Загрузка…";
    const res = await fetch("/api/campaigns/media/upload", { method: "POST", body: fd }).then((r) => r.json());
    mediaPath = res.path; $("#c-media-status").textContent = "✓ " + res.filename;
  }

  $("#c-fill-leads").addEventListener("click", async () => {
    const leads = await api("/api/leads?limit=100");
    const contacts = leads.map((l) => l.contact).filter((c) => c && c.startsWith("@"));
    $("#c-targets").value = contacts.join("\n");
    toast(`Подставлено контактов: ${contacts.length}`, "ok");
  });

  $("#c-save").addEventListener("click", async () => {
    const kind = $("#c-kind").value;
    const targets = $("#c-targets").value.split("\n").map((s) => s.trim()).filter(Boolean);
    const settings = {};
    if (kind === "reaction") settings.emoji = $("#c-emoji").value;
    if (kind === "broadcast") settings.personalize = $("#c-personalize")?.checked || false;
    try {
      await api("/api/campaigns", { method: "POST", body: {
        name: $("#c-name").value || "Кампания", kind, account_id: $("#c-acc").value,
        message_template: $("#c-msg")?.value || "", media_path: mediaPath, targets, settings } });
      closeModal(); toast("Кампания создана", "ok"); route();
    } catch (e) { toast(e.message, "err"); }
  });
}

// ═════════════════════════════════════ МОЗГ ═════════════════════════════════
VIEWS.brain = async (app) => {
  const p = await api("/api/prompts");
  const block = (title, desc, text) => `
    <div class="card pad" style="margin-bottom:16px">
      <div class="section-title">${title}</div>
      <div class="faint" style="margin:4px 0 12px">${desc}</div>
      <div class="code">${esc(text)}</div>
    </div>`;
  app.innerHTML = `
    <div class="warn-banner" style="background:var(--accent-soft);border-color:transparent;color:var(--accent)">
      🧠 <div>Это «мозг» движка — три промта, которые превращают вашу фразу в реальный поиск. Их можно править под свою нишу прямо в коде (<b>app/prompts.py</b>). Пока ключ Claude не задан, работает встроенная эвристика.</div>
    </div>
    ${block("1. План поиска", "Разбирает запрос вроде «найди клиентов, кому нужен сайт» на ключевые слова, сигналы намерения, чаты, категории и города.", p.search_plan)}
    ${block("2. Классификатор лида", "Оценивает каждого кандидата: лид или мусор, насколько горячий (0–100), почему — и как выйти на связь.", p.lead_classifier)}
    ${block("3. Первое сообщение", "Пишет персональное первое сообщение под конкретный лид — живо, по-человечески, с зацепкой.", p.outreach)}`;
};

// ═════════════════════════════════════ НАСТРОЙКИ ════════════════════════════
VIEWS.settings = async (app) => {
  const s = await api("/api/settings");
  STATE.settings = s;
  app.innerHTML = `
    <div class="grid two">
      <div class="card pad">
        <div class="section-title" style="margin-bottom:16px">Режим и ключи</div>
        <div class="field"><label>Режим работы</label>
          <select class="select" id="s-mode">
            <option value="demo" ${s.mode === "demo" ? "selected" : ""}>DEMO — демо-данные, без внешних сервисов</option>
            <option value="live" ${s.mode === "live" ? "selected" : ""}>LIVE — реальные источники и Telegram</option>
          </select>
          <div class="hint">В live-режиме используются реальные API. Нужны ключи ниже и подключённый Telegram-аккаунт.</div>
        </div>
        <div class="field"><label>Anthropic API Key (Claude) ${s.anthropic_api_key_set ? `<span class="badge status-won">задан</span>` : ""}</label>
          <input class="input" id="s-anthropic" placeholder="${s.anthropic_api_key_masked || "sk-ant-…"}"></div>
        <div class="field"><label>Модель Claude</label>
          <select class="select" id="s-model">
            ${["claude-sonnet-5", "claude-opus-4-8", "claude-haiku-4-5-20251001"].map((m) => `<option ${s.anthropic_model === m ? "selected" : ""}>${m}</option>`).join("")}
          </select></div>
        <div class="field"><label>Yandex Search API (user:key) ${s.yandex_search_api_key_set ? `<span class="badge status-won">задан</span>` : ""}</label>
          <input class="input" id="s-ysearch" placeholder="user:ключ"></div>
        <div class="field"><label>Yandex Maps / Geosearch API ${s.yandex_maps_api_key_set ? `<span class="badge status-won">задан</span>` : ""}</label>
          <input class="input" id="s-ymaps" placeholder="ключ Geosearch"></div>
        <button class="btn primary" id="s-save" style="width:100%;margin-top:8px">Сохранить</button>
      </div>
      <div>
        <div class="card pad" style="margin-bottom:16px">
          <div class="section-title" style="margin-bottom:12px">Лимиты безопасности Telegram</div>
          <div class="kv"><span class="k">Пауза между действиями</span><b>${s.tg_min_delay_sec}–${s.tg_max_delay_sec} сек</b></div>
          <div class="kv"><span class="k">Сообщений в сутки</span><b>${s.tg_daily_message_limit}</b></div>
          <div class="kv"><span class="k">Реакций в сутки</span><b>${s.tg_daily_reaction_limit}</b></div>
          <div class="hint" style="margin-top:10px">Меняются через переменные окружения (.env). Консервативные значения защищают аккаунт от блокировки.</div>
        </div>
        <div class="card pad">
          <div class="section-title" style="margin-bottom:10px">Как получить ключи</div>
          <ul class="list-plain">
            <li><b>Claude</b> — console.anthropic.com → API Keys</li>
            <li><b>Telegram api_id/api_hash</b> — my.telegram.org</li>
            <li><b>Yandex Search API</b> — yandex.ru/dev/xml</li>
            <li><b>Yandex Geosearch</b> — yandex.ru/dev/maps (Places API)</li>
          </ul>
        </div>
      </div>
    </div>`;
  $("#s-save").addEventListener("click", async () => {
    const body = { mode: $("#s-mode").value, anthropic_model: $("#s-model").value };
    if ($("#s-anthropic").value) body.anthropic_api_key = $("#s-anthropic").value;
    if ($("#s-ysearch").value) body.yandex_search_api_key = $("#s-ysearch").value;
    if ($("#s-ymaps").value) body.yandex_maps_api_key = $("#s-ymaps").value;
    try { await api("/api/settings", { method: "POST", body }); toast("Настройки сохранены", "ok"); route(); }
    catch (e) { toast(e.message, "err"); }
  });
};

// ── Старт ────────────────────────────────────────────────────────────────────
window.addEventListener("hashchange", route);
(async () => {
  try { STATE.settings = await api("/api/settings"); } catch (_) {}
  renderNav();
  await route();
})();
