#!/usr/bin/env node
/**
 * Чёрный ящик-аудит публичного сайта: сеть, заголовки, производительность,
 * SEO, доступность, мобильная вёрстка, юр. обязательные страницы.
 *
 * Запуск:
 *   npm i playwright && npx playwright install chromium
 *   node audit.mjs https://puffinpizza.ru/ --paths /,/catalog/picca,/promo
 *
 * Результат: ./audit-report/report.md, report.json, screenshots/*.png
 *
 * Скрипт только читает страницы обычными GET-запросами (как поисковый робот).
 * Никакого сканирования уязвимостей, перебора путей и нагрузочного тестирования.
 */

import { chromium } from 'playwright';
import tls from 'node:tls';
import fs from 'node:fs/promises';
import fss from 'node:fs';
import path from 'node:path';

// Обычно достаточно `npx playwright install chromium`. Но если в окружении уже
// лежит несовместимый по версии бинарь (напр. предустановленный в облаке),
// даём Playwright путь к нему через PW_EXECUTABLE_PATH или известный симлинк.
async function launchBrowser() {
  const explicit = process.env.PW_EXECUTABLE_PATH;
  if (explicit && fss.existsSync(explicit)) return chromium.launch({ executablePath: explicit });
  try {
    return await chromium.launch();
  } catch (e) {
    const fallback = '/opt/pw-browsers/chromium';
    if (fss.existsSync(fallback)) return chromium.launch({ executablePath: fallback });
    throw e;
  }
}

// ---------------------------------------------------------------- аргументы

const argv = process.argv.slice(2);
const positional = argv.filter((a) => !a.startsWith('--'));
const flag = (name, def = null) => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`) || a === `--${name}`);
  if (!hit) return def;
  return hit.includes('=') ? hit.slice(hit.indexOf('=') + 1) : true;
};

const TARGET = positional[0] || 'https://puffinpizza.ru/';
const OUT_DIR = path.resolve(String(flag('out', './audit-report')));
const PATHS = String(flag('paths', '/'))
  .split(',')
  .map((p) => p.trim())
  .filter(Boolean);
const TIMEOUT = Number(flag('timeout', 45000));

const origin = new URL(TARGET).origin;
const host = new URL(TARGET).host;

// ---------------------------------------------------------------- находки

const findings = [];
const SEV = { high: 'высокий', medium: 'средний', low: 'низкий' };
const add = (sev, area, msg, detail) =>
  findings.push({ sev, area, msg, detail: detail ?? null });

const log = (...a) => console.log(...a);

// ---------------------------------------------------------------- сеть/HTTP

async function safeFetch(url, opts = {}) {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    return await fetch(url, {
      redirect: 'manual',
      signal: ctl.signal,
      headers: { 'user-agent': 'site-audit/1.0 (+node)', ...(opts.headers || {}) },
      ...opts,
    });
  } finally {
    clearTimeout(t);
  }
}

async function redirectChain(start) {
  const chain = [];
  let url = start;
  for (let i = 0; i < 6; i++) {
    let res;
    try {
      res = await safeFetch(url, { method: 'GET' });
    } catch (e) {
      chain.push({ url, error: String(e.message || e) });
      break;
    }
    const loc = res.headers.get('location');
    chain.push({ url, status: res.status, location: loc || null });
    if (!loc || res.status < 300 || res.status >= 400) break;
    url = new URL(loc, url).toString();
  }
  return chain;
}

async function tlsInfo() {
  return new Promise((resolve) => {
    const socket = tls.connect(
      { host: new URL(origin).hostname, port: 443, servername: new URL(origin).hostname, timeout: 15000 },
      () => {
        const cert = socket.getPeerCertificate();
        resolve({
          protocol: socket.getProtocol(),
          issuer: cert?.issuer?.O || cert?.issuer?.CN || null,
          validTo: cert?.valid_to || null,
          daysLeft: cert?.valid_to
            ? Math.round((new Date(cert.valid_to) - Date.now()) / 86400000)
            : null,
          authorized: socket.authorized,
          authorizationError: socket.authorizationError ? String(socket.authorizationError) : null,
        });
        socket.end();
      },
    );
    socket.on('error', (e) => resolve({ error: String(e.message || e) }));
    socket.on('timeout', () => {
      socket.destroy();
      resolve({ error: 'timeout' });
    });
  });
}

async function httpChecks() {
  log('· проверяю HTTP/TLS/заголовки…');
  const out = {};

  out.httpToHttps = await redirectChain(`http://${host}/`);
  const lastHttp = out.httpToHttps[out.httpToHttps.length - 1];
  if (!lastHttp?.url?.startsWith('https://')) {
    add('high', 'Безопасность', 'HTTP-версия сайта не переадресуется на HTTPS', out.httpToHttps);
  }

  const wwwHost = host.startsWith('www.') ? host.slice(4) : `www.${host}`;
  out.wwwCanonical = await redirectChain(`https://${wwwHost}/`);
  const lastWww = out.wwwCanonical[out.wwwCanonical.length - 1];
  if (lastWww && !lastWww.error && lastWww.status === 200 && new URL(lastWww.url).host !== host) {
    add('medium', 'SEO', `Версии с www и без www обе отдают 200 — дубли страниц для поисковиков`, {
      canonicalHost: host,
      alsoServes: new URL(lastWww.url).host,
    });
  }

  let res;
  try {
    res = await safeFetch(origin + '/', {
      redirect: 'follow',
      headers: { 'accept-encoding': 'gzip, deflate, br' },
    });
  } catch (e) {
    add('high', 'Доступность', 'Главная страница не открывается', String(e.message || e));
    return out;
  }
  const h = Object.fromEntries(res.headers.entries());
  out.status = res.status;
  out.headers = h;

  if (res.status !== 200) add('high', 'Доступность', `Главная отдаёт HTTP ${res.status}`, null);

  const sec = [
    ['strict-transport-security', 'high', 'HSTS не включён — возможен даунгрейд на HTTP'],
    ['content-security-policy', 'medium', 'Нет Content-Security-Policy — выше риск XSS/подмены скриптов'],
    ['x-content-type-options', 'low', 'Нет X-Content-Type-Options: nosniff'],
    ['referrer-policy', 'low', 'Нет Referrer-Policy'],
  ];
  for (const [name, sev, msg] of sec) if (!h[name]) add(sev, 'Безопасность', msg, null);

  const frameProtected = h['x-frame-options'] || /frame-ancestors/i.test(h['content-security-policy'] || '');
  if (!frameProtected)
    add('medium', 'Безопасность', 'Нет защиты от встраивания в iframe (X-Frame-Options / frame-ancestors) — риск кликджекинга', null);

  if (!h['content-encoding'])
    add('medium', 'Производительность', 'HTML отдаётся без сжатия (нет gzip/brotli)', null);

  for (const leaky of ['server', 'x-powered-by', 'x-aspnet-version']) {
    if (h[leaky] && /\d/.test(h[leaky]))
      add('low', 'Безопасность', `Заголовок ${leaky} раскрывает версию ПО: ${h[leaky]}`, null);
  }

  out.tls = await tlsInfo();
  if (out.tls?.error) add('high', 'Безопасность', 'Не удалось установить TLS-соединение', out.tls.error);
  if (out.tls?.authorized === false)
    add('high', 'Безопасность', 'Сертификат не проходит проверку', out.tls.authorizationError);
  if (typeof out.tls?.daysLeft === 'number' && out.tls.daysLeft < 21)
    add('high', 'Безопасность', `Сертификат истекает через ${out.tls.daysLeft} дн.`, out.tls.validTo);

  // robots / sitemap / 404 — обычные проверки поискового робота
  const probe = async (p) => {
    try {
      const r = await safeFetch(origin + p, { redirect: 'follow' });
      const body = r.status === 200 ? (await r.text()).slice(0, 4000) : '';
      return { status: r.status, type: r.headers.get('content-type'), body };
    } catch (e) {
      return { error: String(e.message || e) };
    }
  };

  out.robots = await probe('/robots.txt');
  if (out.robots.status !== 200) add('medium', 'SEO', 'robots.txt отсутствует или недоступен', out.robots.status);
  else {
    if (!/sitemap:/i.test(out.robots.body))
      add('low', 'SEO', 'В robots.txt не указана директива Sitemap', null);
    if (/^\s*disallow:\s*\/\s*$/im.test(out.robots.body))
      add('high', 'SEO', 'robots.txt запрещает индексацию всего сайта (Disallow: /)', null);
  }

  out.sitemap = await probe('/sitemap.xml');
  if (out.sitemap.status !== 200) add('medium', 'SEO', 'sitemap.xml не найден по стандартному адресу', out.sitemap.status);

  const notFound = await probe(`/audit-check-${Date.now()}`);
  out.notFound = { status: notFound.status };
  if (notFound.status === 200)
    add('medium', 'SEO', 'Несуществующая страница отдаёт HTTP 200 вместо 404 (soft 404)', null);

  out.favicon = await probe('/favicon.ico');
  return out;
}

// ---------------------------------------------------------------- в браузере

const IN_PAGE = () => {
  const vis = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none' && Number(s.opacity) > 0.05;
  };
  const sel = (el) => {
    const id = el.id ? `#${el.id}` : '';
    const cls = typeof el.className === 'string' && el.className ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : '';
    return `${el.tagName.toLowerCase()}${id}${cls}`.slice(0, 120);
  };
  const txt = (el) => (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 80);

  // --- SEO / meta
  const meta = (n) => document.querySelector(`meta[name="${n}"]`)?.content || null;
  const og = (p) => document.querySelector(`meta[property="${p}"]`)?.content || null;
  const seo = {
    title: document.title || null,
    description: meta('description'),
    robots: meta('robots'),
    viewport: meta('viewport'),
    lang: document.documentElement.getAttribute('lang'),
    canonical: document.querySelector('link[rel="canonical"]')?.href || null,
    h1: [...document.querySelectorAll('h1')].map(txt),
    ogTitle: og('og:title'),
    ogImage: og('og:image'),
    ogDescription: og('og:description'),
    jsonLd: [...document.querySelectorAll('script[type="application/ld+json"]')]
      .map((s) => {
        try {
          const j = JSON.parse(s.textContent);
          return Array.isArray(j) ? j.map((x) => x['@type']).join(',') : j['@type'] || 'unknown';
        } catch {
          return 'INVALID_JSON';
        }
      }),
    headingOrder: [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].map((h) => Number(h.tagName[1])),
  };

  // --- изображения
  const images = [...document.querySelectorAll('img')].filter(vis).map((img) => ({
    src: (img.currentSrc || img.src || '').slice(0, 200),
    alt: img.hasAttribute('alt') ? img.alt : null,
    hasAltAttr: img.hasAttribute('alt'),
    natural: [img.naturalWidth, img.naturalHeight],
    displayed: [Math.round(img.getBoundingClientRect().width), Math.round(img.getBoundingClientRect().height)],
    loading: img.getAttribute('loading'),
    sizesAttr: !!img.getAttribute('srcset'),
  }));

  // --- ссылки и кнопки без доступного имени
  const namelessControls = [...document.querySelectorAll('a,button,[role="button"],input[type="submit"],input[type="button"]')]
    .filter(vis)
    .filter((el) => {
      const name =
        (el.getAttribute('aria-label') || '') +
        (el.getAttribute('title') || '') +
        (el.value || '') +
        txt(el) +
        [...el.querySelectorAll('img')].map((i) => i.alt || '').join('');
      return !name.trim();
    })
    .map(sel)
    .slice(0, 30);

  // --- формы
  const fields = [...document.querySelectorAll('input,select,textarea')]
    .filter((el) => !['hidden', 'submit', 'button', 'image'].includes(el.type))
    .filter(vis);
  const unlabeled = fields
    .filter((el) => {
      if (el.getAttribute('aria-label') || el.getAttribute('aria-labelledby')) return false;
      if (el.id && document.querySelector(`label[for="${CSS.escape(el.id)}"]`)) return false;
      if (el.closest('label')) return false;
      return true;
    })
    .map((el) => `${sel(el)}[type=${el.type}]${el.placeholder ? ` placeholder="${el.placeholder}"` : ''}`)
    .slice(0, 20);

  const inputTypes = fields.map((el) => ({
    type: el.type,
    name: el.name || null,
    inputmode: el.getAttribute('inputmode'),
    autocomplete: el.getAttribute('autocomplete'),
    placeholder: el.placeholder || null,
  }));

  // --- горизонтальный скролл (мобильная вёрстка)
  const vw = document.documentElement.clientWidth;
  const overflow =
    document.documentElement.scrollWidth > vw + 2
      ? [...document.querySelectorAll('body *')]
          .filter(vis)
          .filter((el) => {
            const r = el.getBoundingClientRect();
            return r.right > vw + 2 || r.left < -2;
          })
          .slice(0, 12)
          .map((el) => ({ el: sel(el), right: Math.round(el.getBoundingClientRect().right) }))
      : [];

  // --- мелкие зоны нажатия
  const smallTargets = [...document.querySelectorAll('a,button,[role="button"],input[type=checkbox],input[type=radio]')]
    .filter(vis)
    .map((el) => ({ el, r: el.getBoundingClientRect() }))
    .filter(({ r }) => r.width < 40 || r.height < 40)
    .slice(0, 25)
    .map(({ el, r }) => ({ el: sel(el), text: txt(el), size: [Math.round(r.width), Math.round(r.height)] }));

  // --- контраст текста
  const lum = (c) => {
    const f = c.map((v) => {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * f[0] + 0.7152 * f[1] + 0.0722 * f[2];
  };
  const parse = (s) => {
    const m = (s || '').match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(',').map((x) => parseFloat(x));
    return { rgb: [p[0], p[1], p[2]], a: p.length > 3 ? p[3] : 1 };
  };
  const bgOf = (el) => {
    let cur = el;
    while (cur && cur !== document.documentElement) {
      const c = parse(getComputedStyle(cur).backgroundColor);
      if (c && c.a > 0.5) return c.rgb;
      cur = cur.parentElement;
    }
    return [255, 255, 255];
  };
  const lowContrast = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const seen = new Set();
  let node;
  while ((node = walker.nextNode())) {
    const t = node.textContent.trim();
    if (t.length < 4) continue;
    const el = node.parentElement;
    if (!el || seen.has(el) || !vis(el)) continue;
    seen.add(el);
    const s = getComputedStyle(el);
    const fg = parse(s.color);
    if (!fg) continue;
    const bg = bgOf(el);
    const l1 = lum(fg.rgb) + 0.05;
    const l2 = lum(bg) + 0.05;
    const ratio = Math.round((Math.max(l1, l2) / Math.min(l1, l2)) * 100) / 100;
    const size = parseFloat(s.fontSize);
    const bold = Number(s.fontWeight) >= 700;
    const large = size >= 24 || (size >= 18.66 && bold);
    const need = large ? 3 : 4.5;
    if (ratio < need)
      lowContrast.push({ el: sel(el), text: t.slice(0, 50), ratio, need, fontSize: Math.round(size), color: s.color, bg: `rgb(${bg.join(',')})` });
    if (lowContrast.length > 25) break;
  }

  // --- мелкий шрифт
  const tinyText = [...document.querySelectorAll('p,span,li,a,div')]
    .filter(vis)
    .filter((el) => el.children.length === 0 && txt(el).length > 10)
    .filter((el) => parseFloat(getComputedStyle(el).fontSize) < 12)
    .slice(0, 10)
    .map((el) => ({ el: sel(el), text: txt(el), fontSize: getComputedStyle(el).fontSize }));

  // --- юридически обязательные ссылки и элементы (РФ)
  const linkText = [...document.querySelectorAll('a')].map((a) => ({ t: txt(a).toLowerCase(), href: a.href }));
  const legal = {
    privacy: linkText.filter((l) => /конфиденциальн|персональн|privacy/i.test(l.t)).map((l) => l.href).slice(0, 3),
    offer: linkText.filter((l) => /оферт|услови|соглашени|правил/i.test(l.t)).map((l) => l.href).slice(0, 3),
    requisites: /ИНН|ОГРН|ОГРНИП|ИП\s|ООО\s/.test(document.body.innerText),
    cookieBanner: !!document.body.innerText.match(/cookie|куки|файлы? cookie/i),
    consentCheckbox: [...document.querySelectorAll('input[type=checkbox]')].some((c) =>
      /соглас|персональн|политик/i.test((c.closest('label')?.innerText || c.parentElement?.innerText || '')),
    ),
  };

  // --- контакты
  const bodyText = document.body.innerText;
  const contacts = {
    phone: (bodyText.match(/\+7[\s\-(]?\d{3}[\s\-)]?\s?\d{3}[\s\-]?\d{2}[\s\-]?\d{2}/) || [null])[0],
    email: (bodyText.match(/[\w.\-]+@[\w.\-]+\.\w{2,}/) || [null])[0],
    telHref: !!document.querySelector('a[href^="tel:"]'),
    mailHref: !!document.querySelector('a[href^="mailto:"]'),
  };

  // --- ресурсы/производительность
  const nav = performance.getEntriesByType('navigation')[0] || {};
  const res = performance.getEntriesByType('resource').map((r) => ({
    name: r.name.slice(0, 160),
    type: r.initiatorType,
    size: r.transferSize || 0,
    dur: Math.round(r.duration),
  }));
  const byType = {};
  for (const r of res) {
    byType[r.type] = byType[r.type] || { count: 0, size: 0 };
    byType[r.type].count++;
    byType[r.type].size += r.size;
  }

  const perf = {
    ttfb: Math.round(nav.responseStart || 0),
    domContentLoaded: Math.round(nav.domContentLoadedEventEnd || 0),
    load: Math.round(nav.loadEventEnd || 0),
    transferSize: nav.transferSize || 0,
    domNodes: document.getElementsByTagName('*').length,
    requests: res.length,
    totalBytes: res.reduce((s, r) => s + r.size, 0),
    byType,
    heaviest: res.sort((a, b) => b.size - a.size).slice(0, 10),
    lcp: window.__lcp || null,
    cls: window.__cls != null ? Math.round(window.__cls * 1000) / 1000 : null,
    longTasks: window.__longTasks || 0,
  };

  const thirdParty = [...new Set(res.map((r) => {
    try { return new URL(r.name).host; } catch { return null; }
  }).filter((hst) => hst && hst !== location.host))];

  return { seo, images, namelessControls, unlabeled, inputTypes, overflow, smallTargets, lowContrast, tinyText, legal, contacts, perf, thirdParty };
};

const OBSERVERS = () => {
  window.__cls = 0;
  window.__longTasks = 0;
  try {
    new PerformanceObserver((l) => {
      const e = l.getEntries();
      window.__lcp = Math.round(e[e.length - 1].startTime);
    }).observe({ type: 'largest-contentful-paint', buffered: true });
  } catch {}
  try {
    new PerformanceObserver((l) => {
      for (const e of l.getEntries()) if (!e.hadRecentInput) window.__cls += e.value;
    }).observe({ type: 'layout-shift', buffered: true });
  } catch {}
  try {
    new PerformanceObserver((l) => { window.__longTasks += l.getEntries().length; }).observe({ type: 'longtask', buffered: true });
  } catch {}
};

const VIEWPORTS = [
  { name: 'mobile', width: 390, height: 844, isMobile: true },
  { name: 'tablet', width: 768, height: 1024, isMobile: false },
  { name: 'desktop', width: 1440, height: 900, isMobile: false },
];

async function auditPages(browser) {
  const pages = {};
  for (const vp of VIEWPORTS) {
    const ctx = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: vp.isMobile ? 2 : 1,
      isMobile: vp.isMobile,
      hasTouch: vp.isMobile,
      locale: 'ru-RU',
    });
    for (const p of PATHS) {
      const url = new URL(p, origin).toString();
      const key = `${vp.name} ${p}`;
      log(`· ${key}`);
      const page = await ctx.newPage();
      const consoleErrors = [];
      const pageErrors = [];
      const failed = [];
      const slow = [];
      page.on('console', (m) => {
        if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 300));
      });
      page.on('pageerror', (e) => pageErrors.push(String(e.message || e).slice(0, 300)));
      page.on('requestfailed', (r) =>
        failed.push({ url: r.url().slice(0, 160), reason: r.failure()?.errorText || 'unknown' }),
      );
      page.on('response', (r) => {
        if (r.status() >= 400) slow.push({ url: r.url().slice(0, 160), status: r.status() });
      });
      await page.addInitScript(OBSERVERS);

      const t0 = Date.now();
      let navOk = true;
      try {
        await page.goto(url, { waitUntil: 'load', timeout: TIMEOUT });
      } catch (e) {
        navOk = false;
        add('high', 'Доступность', `Страница ${p} (${vp.name}) не загрузилась за ${TIMEOUT} мс`, String(e.message || e));
      }
      const wallClock = Date.now() - t0;
      try {
        await page.waitForLoadState('networkidle', { timeout: 12000 });
      } catch {}
      // дать LCP/CLS дособраться
      await page.waitForTimeout(1200);

      let data = null;
      if (navOk) {
        try {
          data = await page.evaluate(IN_PAGE);
        } catch (e) {
          add('low', 'Аудит', `Не удалось собрать метрики со страницы ${p} (${vp.name})`, String(e.message || e));
        }
      }

      const shot = path.join(OUT_DIR, 'screenshots', `${vp.name}${p.replace(/[^\w]+/g, '_') || '_root'}.png`);
      try {
        await page.screenshot({ path: shot, fullPage: true });
      } catch {}

      pages[key] = { url, viewport: vp.name, wallClock, consoleErrors, pageErrors, failed, badResponses: slow, ...(data || {}) };
      await page.close();
    }
    await ctx.close();
  }
  return pages;
}

// ---------------------------------------------------------------- правила

function analyse(pages) {
  for (const [key, d] of Object.entries(pages)) {
    const p = ` [${key}]`;
    if (!d.seo) continue;

    // ошибки исполнения
    if (d.pageErrors.length)
      add('high', 'Ошибки JS', `Необработанные исключения JavaScript${p}: ${d.pageErrors.length}`, d.pageErrors.slice(0, 5));
    if (d.consoleErrors.length)
      add('medium', 'Ошибки JS', `Ошибки в консоли${p}: ${d.consoleErrors.length}`, d.consoleErrors.slice(0, 5));
    if (d.failed.length)
      add('medium', 'Сеть', `Незагруженные ресурсы${p}: ${d.failed.length}`, d.failed.slice(0, 5));
    if (d.badResponses.length)
      add('medium', 'Сеть', `Ответы 4xx/5xx при загрузке${p}: ${d.badResponses.length}`, d.badResponses.slice(0, 5));

    // производительность
    const perf = d.perf || {};
    if (perf.lcp && perf.lcp > 2500)
      add(perf.lcp > 4000 ? 'high' : 'medium', 'Производительность', `LCP ${(perf.lcp / 1000).toFixed(1)} с${p} (норма ≤ 2,5 с)`, null);
    if (perf.cls != null && perf.cls > 0.1)
      add(perf.cls > 0.25 ? 'high' : 'medium', 'Производительность', `CLS ${perf.cls}${p} — вёрстка «прыгает» при загрузке (норма ≤ 0,1)`, null);
    if (perf.ttfb > 800)
      add('medium', 'Производительность', `TTFB ${perf.ttfb} мс${p} — медленный ответ сервера`, null);
    if (perf.totalBytes > 3_000_000)
      add('medium', 'Производительность', `Вес страницы ${(perf.totalBytes / 1e6).toFixed(1)} МБ${p}`, perf.heaviest?.slice(0, 5));
    if (perf.requests > 100)
      add('low', 'Производительность', `${perf.requests} HTTP-запросов при загрузке${p}`, perf.byType);
    if (perf.domNodes > 3000)
      add('low', 'Производительность', `Тяжёлый DOM: ${perf.domNodes} узлов${p}`, null);
    if (perf.longTasks > 10)
      add('low', 'Производительность', `${perf.longTasks} длинных задач JS (>50 мс)${p} — подвисает интерфейс`, null);

    // изображения
    const noAlt = d.images.filter((i) => !i.hasAltAttr);
    if (noAlt.length)
      add('medium', 'Доступность', `Изображений без атрибута alt${p}: ${noAlt.length}`, noAlt.slice(0, 5).map((i) => i.src));
    const oversized = d.images.filter(
      (i) => i.natural[0] > 0 && i.displayed[0] > 0 && i.natural[0] > i.displayed[0] * 2.2,
    );
    if (oversized.length)
      add('medium', 'Производительность', `Картинки грузятся в разрешении сильно больше отображаемого${p}: ${oversized.length}`,
        oversized.slice(0, 5).map((i) => ({ src: i.src, natural: i.natural, displayed: i.displayed })));
    const legacyFmt = d.images.filter((i) => /\.(jpe?g|png)(\?|$)/i.test(i.src));
    if (legacyFmt.length > 5)
      add('low', 'Производительность', `${legacyFmt.length} изображений в JPEG/PNG без WebP/AVIF${p}`, null);
    const noLazy = d.images.filter((i) => !i.loading);
    if (noLazy.length > 10)
      add('low', 'Производительность', `${noLazy.length} изображений без loading="lazy"${p}`, null);

    // мобильная вёрстка
    if (d.overflow?.length)
      add('high', 'Мобильная вёрстка', `Горизонтальный скролл — контент вылезает за экран${p}`, d.overflow);
    if (d.viewport === 'mobile' && d.smallTargets?.length > 3)
      add('medium', 'Мобильная вёрстка', `Мелкие зоны нажатия (<40px)${p}: ${d.smallTargets.length}`, d.smallTargets.slice(0, 6));
    if (d.tinyText?.length)
      add('low', 'Читаемость', `Текст меньше 12px${p}: ${d.tinyText.length} блоков`, d.tinyText.slice(0, 4));

    // доступность
    if (d.lowContrast?.length)
      add('medium', 'Доступность', `Недостаточный контраст текста${p}: ${d.lowContrast.length} мест`, d.lowContrast.slice(0, 6));
    if (d.namelessControls?.length)
      add('medium', 'Доступность', `Кнопки/ссылки без текста и aria-label${p}: ${d.namelessControls.length}`, d.namelessControls.slice(0, 8));
    if (d.unlabeled?.length)
      add('medium', 'Доступность', `Поля форм без <label>${p}: ${d.unlabeled.length}`, d.unlabeled);
    if (!d.seo.lang) add('medium', 'Доступность', `Не указан <html lang>${p}`, null);

    // мобильные удобства форм
    const phoneField = (d.inputTypes || []).find((f) => /phone|tel|телефон/i.test(`${f.name} ${f.placeholder}`));
    if (phoneField && phoneField.type !== 'tel')
      add('low', 'UX форм', `Поле телефона не type="tel"${p} — на мобильном откроется обычная клавиатура`, phoneField);
    if ((d.inputTypes || []).length && !(d.inputTypes || []).some((f) => f.autocomplete))
      add('low', 'UX форм', `Ни одно поле формы не имеет autocomplete${p} — автозаполнение не работает`, null);

    // SEO
    const s = d.seo;
    if (!s.title) add('high', 'SEO', `Нет <title>${p}`, null);
    else if (s.title.length < 20 || s.title.length > 70)
      add('low', 'SEO', `Длина <title> ${s.title.length} симв.${p} (оптимально 30–65)`, s.title);
    if (!s.description) add('medium', 'SEO', `Нет meta description${p}`, null);
    else if (s.description.length > 180 || s.description.length < 50)
      add('low', 'SEO', `Длина description ${s.description.length} симв.${p} (оптимально 70–160)`, null);
    if (s.h1.length === 0) add('medium', 'SEO', `На странице нет <h1>${p}`, null);
    if (s.h1.length > 1) add('low', 'SEO', `Несколько <h1>${p}: ${s.h1.length}`, s.h1);
    if (!s.canonical) add('low', 'SEO', `Нет rel="canonical"${p}`, null);
    if (!s.ogTitle || !s.ogImage)
      add('low', 'SEO', `Неполная Open Graph-разметка${p} — некрасивые превью в мессенджерах`, { ogTitle: s.ogTitle, ogImage: s.ogImage });
    if (!s.jsonLd.length)
      add('medium', 'SEO', `Нет микроразметки Schema.org (JSON-LD)${p} — нет расширенных сниппетов Restaurant/Menu/Product`, null);
    if (s.jsonLd.includes('INVALID_JSON'))
      add('medium', 'SEO', `Микроразметка JSON-LD с синтаксической ошибкой${p}`, null);
    if (!s.viewport) add('high', 'Мобильная вёрстка', `Нет meta viewport${p} — сайт не адаптируется под мобильные`, null);
    if (/noindex/i.test(s.robots || ''))
      add('high', 'SEO', `Страница закрыта от индексации (meta robots: ${s.robots})${p}`, null);
    const order = s.headingOrder || [];
    for (let i = 1; i < order.length; i++)
      if (order[i] - order[i - 1] > 1) {
        add('low', 'Доступность', `Нарушена иерархия заголовков (h${order[i - 1]} → h${order[i]})${p}`, null);
        break;
      }

    // юридическое / доверие
    if (!d.legal.privacy?.length)
      add('high', 'Юридическое', `Не найдена ссылка на политику обработки персональных данных${p} — нарушение 152-ФЗ`, null);
    if (!d.legal.offer?.length)
      add('medium', 'Юридическое', `Не найдена публичная оферта / условия доставки и оплаты${p}`, null);
    if (!d.legal.requisites)
      add('medium', 'Доверие', `На странице нет реквизитов продавца (ИНН/ОГРН, наименование ИП/ООО)${p}`, null);
    if (!d.legal.consentCheckbox && (d.inputTypes || []).length)
      add('medium', 'Юридическое', `В форме нет чекбокса согласия на обработку персональных данных${p}`, null);

    // контакты
    if (!d.contacts.telHref)
      add('low', 'UX', `Телефон не оформлен ссылкой tel: — с мобильного нельзя позвонить в один тап${p}`, null);

    // третьи стороны
    if (d.thirdParty?.length > 12)
      add('low', 'Производительность', `Много сторонних доменов (${d.thirdParty.length})${p} — счётчики и виджеты тормозят загрузку`, d.thirdParty.slice(0, 15));
  }
}

// ---------------------------------------------------------------- отчёт

function report(net, pages) {
  const order = { high: 0, medium: 1, low: 2 };
  const uniq = [];
  const seen = new Set();
  for (const f of findings.sort((a, b) => order[a.sev] - order[b.sev])) {
    const k = f.sev + f.area + f.msg;
    if (seen.has(k)) continue;
    seen.add(k);
    uniq.push(f);
  }

  const L = [];
  L.push(`# Аудит ${TARGET}`);
  L.push('');
  L.push(`Дата: ${new Date().toISOString().slice(0, 16).replace('T', ' ')} UTC`);
  L.push(`Проверено страниц: ${PATHS.join(', ')} · вьюпорты: ${VIEWPORTS.map((v) => v.name).join(', ')}`);
  L.push('');
  const counts = { high: 0, medium: 0, low: 0 };
  uniq.forEach((f) => counts[f.sev]++);
  L.push(`**Итого недостатков: ${uniq.length}** — критичных ${counts.high}, средних ${counts.medium}, мелких ${counts.low}`);
  L.push('');

  for (const sev of ['high', 'medium', 'low']) {
    const group = uniq.filter((f) => f.sev === sev);
    if (!group.length) continue;
    L.push(`## Приоритет: ${SEV[sev]} (${group.length})`);
    L.push('');
    group.forEach((f, i) => {
      L.push(`${i + 1}. **[${f.area}]** ${f.msg}`);
      if (f.detail) {
        const d = typeof f.detail === 'string' ? f.detail : JSON.stringify(f.detail, null, 1);
        L.push('');
        L.push('   ```');
        L.push(d.split('\n').slice(0, 14).map((x) => '   ' + x).join('\n'));
        L.push('   ```');
      }
      L.push('');
    });
  }

  L.push('## Сырые метрики');
  L.push('');
  L.push('| Страница | LCP, мс | CLS | TTFB, мс | Запросов | Вес, КБ | DOM | Ошибок JS |');
  L.push('|---|---|---|---|---|---|---|---|');
  for (const [k, d] of Object.entries(pages)) {
    const p = d.perf || {};
    L.push(
      `| ${k} | ${p.lcp ?? '—'} | ${p.cls ?? '—'} | ${p.ttfb ?? '—'} | ${p.requests ?? '—'} | ${p.totalBytes ? Math.round(p.totalBytes / 1024) : '—'} | ${p.domNodes ?? '—'} | ${(d.pageErrors?.length || 0) + (d.consoleErrors?.length || 0)} |`,
    );
  }
  L.push('');
  L.push('### Заголовки ответа');
  L.push('```');
  L.push(JSON.stringify(net.headers || {}, null, 1).split('\n').slice(0, 40).join('\n'));
  L.push('```');
  L.push('');
  L.push('### TLS');
  L.push('```');
  L.push(JSON.stringify(net.tls || {}, null, 1));
  L.push('```');
  L.push('');
  L.push('Скриншоты: `screenshots/`');
  return L.join('\n');
}

// ---------------------------------------------------------------- main

async function main() {
  log(`\nАудит ${TARGET}\n`);
  await fs.mkdir(path.join(OUT_DIR, 'screenshots'), { recursive: true });

  const net = await httpChecks();

  const browser = await launchBrowser();
  let pages = {};
  try {
    pages = await auditPages(browser);
  } finally {
    await browser.close();
  }

  analyse(pages);

  const md = report(net, pages);
  await fs.writeFile(path.join(OUT_DIR, 'report.md'), md);
  await fs.writeFile(
    path.join(OUT_DIR, 'report.json'),
    JSON.stringify({ target: TARGET, generatedAt: new Date().toISOString(), findings, net, pages }, null, 2),
  );

  const counts = findings.reduce((a, f) => ((a[f.sev] = (a[f.sev] || 0) + 1), a), {});
  log(`\nГотово. Найдено: критичных ${counts.high || 0}, средних ${counts.medium || 0}, мелких ${counts.low || 0}`);
  log(`Отчёт: ${path.join(OUT_DIR, 'report.md')}`);
}

main().catch((e) => {
  console.error('Аудит упал:', e);
  process.exit(1);
});
