import AppKit
import SwiftUI
import WebKit

@MainActor
final class BrowserStore: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var address = "https://www.google.com"
    @Published var title = "Браузер"
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var zoom: CGFloat = 1.0
    @Published var isShowingFind = false
    @Published var findQuery = ""
    @Published var lastScreenshot: NSImage? = nil
    @Published var lastAnnotatedScreenshot: NSImage? = nil

    let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        // Mobile Safari UA — renders mobile layout to match 390px browser width
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        // Dark appearance via native WebKit — signals prefers-color-scheme: dark
        // without overriding sites' own dark mode implementations
        webView.appearance = NSAppearance(named: .darkAqua)
        webView.underPageBackgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1)
    }

    func navigate(_ value: String) {
        let target = Self.normalizedURL(value)
        address = target.absoluteString
        webView.load(URLRequest(url: target))
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    func reload() {
        webView.reload()
    }

    func hardReload() {
        webView.reloadFromOrigin()
    }

    func setZoom(_ factor: CGFloat) {
        let clamped = max(0.25, min(5.0, factor))
        zoom = clamped
        webView.magnification = clamped
    }

    func toggleFind() {
        isShowingFind.toggle()
        if !isShowingFind { findQuery = "" }
    }

    func findNext() {
        guard !findQuery.isEmpty else { return }
        let q = (try? Self.javascriptLiteral(findQuery)) ?? "\"\")"
        Task { _ = try? await evaluate("window.find(\(q),false,false,true)") }
    }

    func findPrevious() {
        guard !findQuery.isEmpty else { return }
        let q = (try? Self.javascriptLiteral(findQuery)) ?? "\"\")"
        Task { _ = try? await evaluate("window.find(\(q),false,true,true)") }
    }

    func clearCookies(completion: @escaping () -> Void = {}) {
        let ds = webView.configuration.websiteDataStore
        ds.fetchDataRecords(ofTypes: [WKWebsiteDataTypeCookies]) { records in
            ds.removeData(ofTypes: [WKWebsiteDataTypeCookies], for: records,
                          completionHandler: completion)
        }
    }

    func clearCache(completion: @escaping () -> Void = {}) {
        let ds = webView.configuration.websiteDataStore
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache
        ]
        ds.removeData(ofTypes: types, modifiedSince: .distantPast,
                      completionHandler: completion)
    }

    func takeScreenshotAndCopy() async throws -> String {
        let result = try await takeScreenshot()
        guard let data = result.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = dict["path"] as? String,
              let image = NSImage(contentsOf: URL(fileURLWithPath: path))
        else { throw BrowserError.invalidPageResult }

        lastScreenshot = image
        lastAnnotatedScreenshot = nil
        guard BrowserClipboard.copy(image) else {
            throw BrowserError.clipboardFailed
        }
        return result
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        updateState()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        updateState()
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func readPage() async throws -> String {
        let script = """
        (() => {
          const clean = value => String(value || '').replace(/\\s+/g, ' ').trim();
          const visible = element => {
            const style = getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.visibility !== 'hidden' && style.display !== 'none' &&
                   rect.width > 0 && rect.height > 0;
          };
          const candidates = Array.from(document.querySelectorAll(
            'a[href],button,input,textarea,select,[role="button"],h1,h2,h3,p,li'
          )).filter(visible).slice(0, 160);
          window.__alakeyaElementCounter = window.__alakeyaElementCounter || 0;
          return JSON.stringify({
            url: location.href,
            title: document.title,
            scrollY: Math.round(scrollY),
            viewportHeight: innerHeight,
            documentHeight: document.documentElement.scrollHeight,
            text: clean(document.body?.innerText).slice(0, 8000),
            elements: candidates.map(element => {
              const interactive = element.matches(
                'a[href],button,input,textarea,select,[role="button"]'
              );
              let id = element.dataset.alakeyaId || '';
              if (interactive && !id) {
                id = `ak-${++window.__alakeyaElementCounter}`;
                element.dataset.alakeyaId = id;
              }
              return {
                id,
                tag: element.tagName.toLowerCase(),
                role: element.getAttribute('role') || '',
                type: element.getAttribute('type') || '',
                text: clean(
                element.innerText || element.value ||
                element.getAttribute('aria-label') || element.title
              ).slice(0, 160),
                href: element.href || '',
                placeholder: element.getAttribute('placeholder') || '',
                disabled: Boolean(element.disabled)
              };
            }).filter(item => item.text || item.href || item.placeholder)
          });
        })()
        """
        guard let json = try await evaluate(script) as? String else {
            throw BrowserError.invalidPageResult
        }
        return json
    }

    func click(elementID: String, text: String) async throws -> String {
        let id = try Self.javascriptLiteral(elementID)
        let needle = try Self.javascriptLiteral(text)
        let script = """
        (() => {
          const id = \(id).trim();
          const needle = \(needle).trim().toLocaleLowerCase();
          const visible = element => {
            const style = getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.visibility !== 'hidden' && style.display !== 'none' &&
                   rect.width > 0 && rect.height > 0;
          };
          let element = id
            ? document.querySelector(`[data-alakeya-id="${CSS.escape(id)}"]`)
            : null;
          if (!element) element = Array.from(document.querySelectorAll(
            'a,button,[role="button"],input,textarea,select,label'
          )).find(candidate => {
            const value = String(
              candidate.innerText || candidate.value ||
              candidate.getAttribute('aria-label') || candidate.title || ''
            ).trim().toLocaleLowerCase();
            return visible(candidate) && (value === needle || value.includes(needle));
          });
          if (!element) return JSON.stringify({ok:false,error:'Элемент не найден'});
          if (element.disabled) return JSON.stringify({ok:false,error:'Элемент отключён'});
          element.scrollIntoView({block:'center',inline:'center'});
          element.click();
          return JSON.stringify({
            ok:true,
            tag:element.tagName.toLowerCase(),
            text:String(element.innerText || element.value || '').trim().slice(0,160)
          });
        })()
        """
        return (try await evaluate(script) as? String) ?? #"{"ok":false}"#
    }

    func type(text: String, elementID: String, field: String) async throws -> String {
        let textLiteral = try Self.javascriptLiteral(text)
        let idLiteral = try Self.javascriptLiteral(elementID)
        let fieldLiteral = try Self.javascriptLiteral(field)
        let script = """
        (() => {
          const value = \(textLiteral);
          const id = \(idLiteral).trim();
          const needle = \(fieldLiteral).trim().toLocaleLowerCase();
          let element = id
            ? document.querySelector(`[data-alakeya-id="${CSS.escape(id)}"]`)
            : null;
          if (!element) element = Array.from(document.querySelectorAll(
            'input,textarea,[contenteditable="true"]'
          )).find(candidate => {
            const label = [
              candidate.getAttribute('aria-label'),
              candidate.getAttribute('placeholder'),
              candidate.name,
              candidate.id
            ].filter(Boolean).join(' ').toLocaleLowerCase();
            return label.includes(needle);
          });
          if (!element) return JSON.stringify({ok:false,error:'Поле не найдено'});
          element.focus();
          if (element.isContentEditable) {
            element.textContent = value;
            element.dispatchEvent(new InputEvent('input', {
              bubbles:true,inputType:'insertText',data:value
            }));
          } else {
            const setter = Object.getOwnPropertyDescriptor(
              Object.getPrototypeOf(element), 'value'
            )?.set;
            if (setter) setter.call(element, value); else element.value = value;
            element.dispatchEvent(new Event('input', {bubbles:true}));
            element.dispatchEvent(new Event('change', {bubbles:true}));
          }
          return JSON.stringify({ok:true});
        })()
        """
        return (try await evaluate(script) as? String) ?? #"{"ok":false}"#
    }

    func scroll(direction: String, amount: Int) async throws -> String {
        let normalized = direction.lowercased()
        let sign = ["up", "вверх"].contains(normalized) ? -1 : 1
        let distance = max(120, min(1600, amount))
        let script = """
        (() => {
          window.scrollBy({top:\(sign * distance),left:0,behavior:'smooth'});
          return JSON.stringify({ok:true,scrollY:Math.round(window.scrollY)});
        })()
        """
        return (try await evaluate(script) as? String) ?? #"{"ok":false}"#
    }

    func scrollResultsContainer() async throws -> String {
        let script = """
        (() => {
          const candidates = Array.from(document.querySelectorAll(
            '[role="feed"],[role="list"],[class*="scroll"],[class*="results"],[class*="search-list"],main,section,div'
          )).filter(el => {
            const style = getComputedStyle(el);
            const canScroll = el.scrollHeight > el.clientHeight + 120;
            const visible = style.display !== 'none' && style.visibility !== 'hidden' &&
              el.clientWidth > 180 && el.clientHeight > 180;
            const content = el.querySelectorAll('a[href],article,[role="listitem"]').length;
            return canScroll && visible && content >= 3;
          }).sort((a,b) => {
            const score = el => el.querySelectorAll('a[href],article,[role="listitem"]').length +
              Math.min(50, Math.round(el.scrollHeight / Math.max(1, el.clientHeight)));
            return score(b) - score(a);
          });
          const target = candidates[0] || document.scrollingElement || document.documentElement;
          const before = target === document.scrollingElement
            ? window.scrollY : target.scrollTop;
          const distance = Math.max(700, Math.round((target.clientHeight || window.innerHeight) * 0.85));
          if(target === document.scrollingElement || target === document.documentElement) {
            window.scrollBy({top:distance,left:0,behavior:'smooth'});
          } else {
            target.scrollBy({top:distance,left:0,behavior:'smooth'});
          }
          const after = target === document.scrollingElement
            ? window.scrollY : target.scrollTop;
          return JSON.stringify({
            ok:true,
            usedContainer:target !== document.scrollingElement && target !== document.documentElement,
            before:Math.round(before),
            after:Math.round(after),
            candidates:candidates.length
          });
        })()
        """
        return (try await evaluate(script) as? String) ?? #"{"ok":false}"#
    }

    func submit(elementID: String, text: String) async throws -> String {
        let id = try Self.javascriptLiteral(elementID)
        let needle = try Self.javascriptLiteral(text)
        let script = """
        (() => {
          const id = \(id).trim();
          const needle = \(needle).trim().toLocaleLowerCase();
          let element = id
            ? document.querySelector(`[data-alakeya-id="${CSS.escape(id)}"]`)
            : null;
          if (!element && needle) {
            element = Array.from(document.querySelectorAll(
              'button,input[type="submit"],[role="button"]'
            )).find(candidate => String(
              candidate.innerText || candidate.value ||
              candidate.getAttribute('aria-label') || ''
            ).trim().toLocaleLowerCase().includes(needle));
          }
          if (!element) return JSON.stringify({ok:false,error:'Кнопка отправки не найдена'});
          const form = element.closest('form');
          if (form?.requestSubmit) form.requestSubmit(element.matches('[type="submit"]') ? element : undefined);
          else element.click();
          return JSON.stringify({ok:true,submitted:true});
        })()
        """
        return (try await evaluate(script) as? String) ?? #"{"ok":false}"#
    }

    func select(elementID: String, value: String) async throws -> String {
        let id = try Self.javascriptLiteral(elementID)
        let valueLiteral = try Self.javascriptLiteral(value)
        let script = """
        (() => {
          const element = document.querySelector(
            `[data-alakeya-id="${CSS.escape(\(id))}"]`
          );
          if (!(element instanceof HTMLSelectElement)) {
            return JSON.stringify({ok:false,error:'Список не найден'});
          }
          const wanted = \(valueLiteral).toLocaleLowerCase();
          const option = Array.from(element.options).find(item =>
            item.value.toLocaleLowerCase() === wanted ||
            item.text.toLocaleLowerCase().includes(wanted)
          );
          if (!option) return JSON.stringify({ok:false,error:'Значение не найдено'});
          element.value = option.value;
          element.dispatchEvent(new Event('input',{bubbles:true}));
          element.dispatchEvent(new Event('change',{bubbles:true}));
          return JSON.stringify({ok:true,value:option.value,text:option.text});
        })()
        """
        return (try await evaluate(script) as? String) ?? #"{"ok":false}"#
    }

    func waitForPage(milliseconds: Int) async throws -> String {
        let timeout = max(200, min(10_000, milliseconds))
        try await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000)
        var remaining = 20
        while webView.isLoading && remaining > 0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            remaining -= 1
        }
        return #"{"ok":true,"waited":\#(timeout),"loading":\#(webView.isLoading)}"#
    }

    func highlightElement(elementID: String, textSearch: String, color: String, durationMs: Int, label: String) async throws -> String {
        let idLit    = try Self.javascriptLiteral(elementID)
        let textLit  = try Self.javascriptLiteral(textSearch)
        let colorLit = try Self.javascriptLiteral(color.isEmpty ? "rgba(89,196,250,0.9)" : color)
        let labelLit = try Self.javascriptLiteral(label)
        let dur = max(0, min(30_000, durationMs))
        let script = """
        (() => {
          const idVal = \(idLit);
          const needle = \(textLit).trim().toLowerCase();
          const colorVal = \(colorLit);
          const labelVal = \(labelLit);
          const duration = \(dur);
          let el = idVal ? document.querySelector('[data-alakeya-id="' + CSS.escape(idVal) + '"]') : null;
          if (!el && needle) {
            el = Array.from(document.querySelectorAll('a,button,[role="button"],h1,h2,h3,p,span,div,input,label'))
              .find(e => {
                const t = String(e.innerText || e.value || e.getAttribute('aria-label') || '').trim().toLowerCase();
                return t === needle || t.includes(needle);
              });
          }
          if (!el) return JSON.stringify({ok:false,error:'Элемент не найден'});
          el.scrollIntoView({block:'center',behavior:'smooth'});
          const rect = el.getBoundingClientRect();
          const prev = document.getElementById('__alakeya_highlight__');
          if (prev) prev.remove();
          if (!document.getElementById('__alakeya_kf__')) {
            const style = document.createElement('style');
            style.id = '__alakeya_kf__';
            style.textContent = '@keyframes __ak_pulse {from{opacity:.7}to{opacity:1}}';
            document.head.appendChild(style);
          }
          const overlay = document.createElement('div');
          overlay.id = '__alakeya_highlight__';
          overlay.style.cssText = [
            'position:fixed',
            'left:' + (rect.left - 4) + 'px',
            'top:' + (rect.top - 4) + 'px',
            'width:' + (rect.width + 8) + 'px',
            'height:' + (rect.height + 8) + 'px',
            'border:3px solid ' + colorVal,
            'border-radius:4px',
            'background:rgba(89,196,250,.12)',
            'z-index:2147483647',
            'pointer-events:none',
            'box-shadow:0 0 12px rgba(89,196,250,.5)',
            'animation:__ak_pulse 1s ease-in-out infinite alternate'
          ].join(';');
          if (labelVal) {
            const lbl = document.createElement('div');
            lbl.style.cssText = 'position:absolute;top:-26px;left:0;background:rgba(89,196,250,.9);color:#000;padding:2px 8px;border-radius:4px;font-size:11px;font-weight:600;white-space:nowrap;font-family:system-ui';
            lbl.textContent = labelVal;
            overlay.appendChild(lbl);
          }
          document.body.appendChild(overlay);
          if (duration > 0) setTimeout(() => overlay.remove(), duration);
          return JSON.stringify({ok:true,tag:el.tagName.toLowerCase(),text:String(el.innerText||'').trim().slice(0,120)});
        })()
        """
        return (try await evaluate(script) as? String) ?? #"{"ok":false}"#
    }

    func extractPageData() async throws -> String {
        let script = """
        (() => {
          const clean = s => String(s||'').replace(/\\s+/g,' ').trim();
          const lim = (s,n) => clean(s).slice(0,n);
          const meta = {};
          document.querySelectorAll('meta').forEach(m => {
            const k = (m.getAttribute('name')||m.getAttribute('property')||'').toLowerCase();
            const v = m.getAttribute('content')||'';
            if(k && v) meta[k]=v;
          });
          const headings = {h1:[],h2:[],h3:[]};
          ['h1','h2','h3'].forEach(tag => {
            document.querySelectorAll(tag).forEach(el => {
              const t = lim(el.innerText,200);
              if(t && !headings[tag].includes(t)) headings[tag].push(t);
            });
            headings[tag] = headings[tag].slice(0,8);
          });
          const bodyText = document.body?.innerText||'';
          const emails = [...new Set((bodyText.match(/[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}/g)||[]))].slice(0,5);
          const phones = [...new Set((bodyText.match(/(?:\\+7|8)[\\s\\-]?\\(?\\d{3}\\)?[\\s\\-]?\\d{3}[\\s\\-]?\\d{2}[\\s\\-]?\\d{2}/g)||[]).map(p=>clean(p)))].slice(0,5);
          const socialPatterns = {telegram:/t\\.me\\/|telegram\\.me\\//i,whatsapp:/whatsapp\\.com\\/|wa\\.me\\//i,vk:/vk\\.com\\/(?!photo|video|doc|wall)/i,instagram:/instagram\\.com\\//i,youtube:/youtube\\.com\\/|youtu\\.be\\//i,avito:/avito\\.ru\\//i,twogis:/2gis\\.ru\\//i,yandexmaps:/yandex\\.ru\\/maps/i};
          const socialLinks = [];
          document.querySelectorAll('a[href]').forEach(a => {
            const href = a.href;
            for(const [p,rx] of Object.entries(socialPatterns)){
              if(rx.test(href) && !socialLinks.find(l=>l.url===href)){
                socialLinks.push({platform:p,url:href,text:lim(a.innerText,60)});
              }
            }
          });
          const kwImportant = ['контакт','услуг','цен','о компани','запис','доставк','оплат','отзыв','портфол','галере','прайс','прейскур'];
          const importantLinks = [];
          document.querySelectorAll('a[href]').forEach(a => {
            const t = clean(a.innerText).toLowerCase();
            if(kwImportant.some(kw=>t.includes(kw)) && !importantLinks.find(l=>l.url===a.href)){
              importantLinks.push({text:lim(a.innerText,80),url:a.href});
            }
          });
          const structuredData = [];
          document.querySelectorAll('script[type="application/ld+json"]').forEach(s => {
            try{structuredData.push(JSON.parse(s.textContent));}catch(e){}
          });
          let nextData = null;
          const nd = document.getElementById('__NEXT_DATA__');
          if(nd){try{const p=JSON.parse(nd.textContent);nextData={page:p.page,query:p.query};}catch(e){}}
          const og = {};
          document.querySelectorAll('meta[property^="og:"]').forEach(m=>{
            og[m.getAttribute('property').replace('og:','')]=m.getAttribute('content')||'';
          });
          const techSignals = [];
          if(window.React||document.querySelector('[data-reactroot]')) techSignals.push('React');
          if(window.next||nextData) techSignals.push('Next.js');
          if(window.nuxt||window.__NUXT__) techSignals.push('Nuxt.js');
          if(document.querySelector('[data-tilda-page]')||window.t_onReady) techSignals.push('Tilda');
          if(window.wp||document.querySelector('.wp-block,.wp-content')) techSignals.push('WordPress');
          const forms = [];
          document.querySelectorAll('form').forEach(form => {
            const inputs = Array.from(form.querySelectorAll('input:not([type="hidden"]),textarea')).map(i=>({type:i.type||'text',name:i.name||i.placeholder||''})).slice(0,6);
            const sub = form.querySelector('button[type="submit"],input[type="submit"],button:not([type])');
            forms.push({action:form.action||'',submitText:lim(sub?.innerText||sub?.value||'Отправить',60),fields:inputs});
          });
          const pricePattern = /(?:от\\s+)?[\\d\\s]+[.,]?\\d*\\s*(?:₽|руб|р\\b|рублей|USD|EUR|\\$|€)/gi;
          const prices = [...new Set((bodyText.match(pricePattern)||[]).map(p=>clean(p)))].slice(0,10);
          const result = {
            url:location.href,
            title:lim(document.title,200),
            metaDescription:lim(meta['description']||og.description||'',300),
            headings,
            contacts:{emails,phones},
            socialLinks:socialLinks.slice(0,10),
            businessInfo:{prices},
            importantLinks:importantLinks.slice(0,15),
            forms:forms.slice(0,5),
            structuredData:structuredData.slice(0,3),
            openGraph:og,
            techSignals,
            nextData,
          };
          let json = JSON.stringify(result);
          if(json.length > 20000){
            result.structuredData = result.structuredData.slice(0,1);
            result.importantLinks = result.importantLinks.slice(0,8);
            result.truncated = true;
            json = JSON.stringify(result);
          }
          return json;
        })()
        """
        guard let json = try await evaluate(script) as? String else {
            throw BrowserError.invalidPageResult
        }
        return json
    }

    func seoAudit() async throws -> String {
        let script = """
        (() => {
          const clean = s => String(s||'').replace(/\\s+/g,' ').trim();
          const lim = (s,n) => clean(s).slice(0,n);
          const meta = {};
          document.querySelectorAll('meta').forEach(m => {
            const k = (m.getAttribute('name')||m.getAttribute('property')||'').toLowerCase();
            const v = m.getAttribute('content')||'';
            if(k&&v) meta[k]=v;
          });
          const title = document.title;
          const desc = meta['description']||'';
          const h1s = Array.from(document.querySelectorAll('h1')).map(h=>lim(h.innerText,200));
          const h2s = Array.from(document.querySelectorAll('h2')).map(h=>lim(h.innerText,200)).slice(0,10);
          const h3s = Array.from(document.querySelectorAll('h3')).map(h=>lim(h.innerText,120)).slice(0,8);
          const images = Array.from(document.querySelectorAll('img'));
          const noAlt = images.filter(i=>!i.alt||!i.alt.trim()).length;
          const sampleAlts = images.filter(i=>i.alt&&i.alt.trim()).map(i=>({src:i.src.split('/').pop().slice(0,40),alt:i.alt})).slice(0,5);
          const links = Array.from(document.querySelectorAll('a[href]'));
          const internalLinks = links.filter(a=>a.href.startsWith(location.origin)).length;
          const externalLinks = links.filter(a=>!a.href.startsWith(location.origin)&&/^https?:/.test(a.href)).length;
          const canonical = document.querySelector('link[rel="canonical"]')?.href||'';
          const robotsMeta = meta['robots']||'';
          const hasViewport = !!document.querySelector('meta[name="viewport"]');
          const bodyText = clean(document.body?.innerText||'');
          const ldJson = Array.from(document.querySelectorAll('script[type="application/ld+json"]')).map(s=>{try{return JSON.parse(s.textContent);}catch(e){return null;}}).filter(Boolean);
          const og = {};
          document.querySelectorAll('meta[property^="og:"]').forEach(m=>{og[m.getAttribute('property').replace('og:','')]=m.getAttribute('content')||'';});
          const problems = [];
          if(!title) problems.push('Нет title');
          else if(title.length < 30) problems.push('Title слишком короткий ('+title.length+' симв.)');
          else if(title.length > 70) problems.push('Title слишком длинный ('+title.length+' симв.)');
          if(!desc) problems.push('Нет meta description');
          else if(desc.length < 70) problems.push('Meta description короткий ('+desc.length+' симв.)');
          else if(desc.length > 160) problems.push('Meta description длинный ('+desc.length+' симв.)');
          if(h1s.length === 0) problems.push('Нет тега H1');
          if(h1s.length > 1) problems.push('Несколько H1 (' + h1s.length + ')');
          if(noAlt > 0) problems.push('Изображения без alt: ' + noAlt);
          if(!hasViewport) problems.push('Нет meta viewport');
          if(!canonical) problems.push('Нет canonical');
          if(bodyText.length < 300) problems.push('Мало текста (' + bodyText.length + ' симв.)');
          const quickWins = [];
          if(noAlt > 0) quickWins.push('Добавить alt ко всем изображениям');
          if(!canonical) quickWins.push('Добавить canonical ссылку');
          if(h1s.length === 0) quickWins.push('Добавить уникальный H1 с ключевой фразой');
          if(ldJson.length === 0) quickWins.push('Добавить JSON-LD разметку (Organization, LocalBusiness или WebPage)');
          return JSON.stringify({
            url:location.href,
            title:lim(title,200),titleLength:title.length,
            metaDescription:lim(desc,300),metaDescriptionLength:desc.length,
            h1:h1s.slice(0,3),h2:h2s,h3:h3s,
            canonical,robotsMeta,hasViewport,
            imagesTotal:images.length,imagesWithoutAlt:noAlt,sampleAlts,
            internalLinks,externalLinks,
            textLength:bodyText.length,
            structuredData:ldJson.slice(0,2),
            openGraph:og,
            problems,quickWins
          });
        })()
        """
        guard let json = try await evaluate(script) as? String else {
            throw BrowserError.invalidPageResult
        }
        return json
    }

    func takeScreenshot() async throws -> String {
        let image = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<NSImage, Error>) in
            webView.takeSnapshot(with: nil) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: BrowserError.invalidPageResult)
                }
            }
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { throw BrowserError.invalidPageResult }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alakeya-browser-\(UUID().uuidString).png")
        try png.write(to: url)
        return #"{"ok":true,"path":"\#(url.path)"}"#
    }

    // MARK: - Research extraction methods
    func extractSearchResults() async throws -> String {
        let script = """
        (() => {
          const clean = s => String(s||'').replace(/\\s+/g,' ').trim();
          const lim = (s,n) => clean(s).slice(0,n);
          const results = [];
          // Yandex SERP
          document.querySelectorAll('.serp-item,.organic,.Organic').forEach(el => {
            const titleEl = el.querySelector('h2,h3,.organic__title,.OrganicTitle');
            const linkEl  = el.querySelector('a[href]');
            const snipEl  = el.querySelector('.text-container,.organic__text,.OrganicTextContentSpan');
            const urlEl   = el.querySelector('.organic__path,.Path,.path');
            if(titleEl && linkEl) {
              results.push({
                title: lim(titleEl.innerText, 200),
                url: linkEl.href,
                displayUrl: lim(urlEl?.innerText||linkEl.hostname,120),
                snippet: lim(snipEl?.innerText||'', 400)
              });
            }
          });
          // Google SERP fallback
          if(results.length < 3) {
            const links = Array.from(document.querySelectorAll('main a[href]'))
              .filter(link => link.querySelector('h3'));
            links.forEach(linkEl => {
              const titleEl = linkEl.querySelector('h3');
              const el = linkEl.parentElement?.parentElement || linkEl.parentElement || linkEl;
              const snipEl  = el.querySelector('[data-sncf="1"],[data-snf="nke7rc"],.VwiC3b,[data-content-feature="1"]');
              if(titleEl && linkEl) {
                results.push({
                  title: lim(titleEl.innerText, 200),
                  url: linkEl.href,
                  displayUrl: lim(linkEl.hostname, 120),
                  snippet: lim(snipEl?.innerText||'', 400)
                });
              }
            });
          }
          return JSON.stringify({url: location.href, count: results.length, results: results.slice(0,20)});
        })()
        """
        guard let json = try await evaluate(script) as? String else {
            throw BrowserError.invalidPageResult
        }
        return json
    }

    func extractBusinessCards(maxCards: Int = 20) async throws -> String {
        let limit = max(1, min(100, maxCards))
        let script = """
        (() => {
          const clean = s => String(s||'').replace(/\\s+/g,' ').trim();
          const lim = (s,n) => clean(s).slice(0,n);
          const bodyText = document.body?.innerText||'';
          const phoneRx = /(?:\\+7|8)[\\s\\-]?\\(?\\d{3}\\)?[\\s\\-]?\\d{3}[\\s\\-]?\\d{2}[\\s\\-]?\\d{2}/g;
          const emailRx = /[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}/g;
          const ratingRx = /([4-5][.,]\\d)\\s*(?:\\/\\s*5|из\\s*5|★|из\\s*10)/gi;

          const cards = [];
          const isGoogleSERP = /(^|\\.)google\\./.test(location.hostname) && /\\/search/.test(location.pathname);
          const isYandexSERP = /(^|\\.)yandex\\./.test(location.hostname) && /\\/search/.test(location.pathname);
          if(isGoogleSERP) {
            Array.from(document.querySelectorAll('main a[href]'))
              .filter(link => link.querySelector('h3'))
              .slice(0,\(limit))
              .forEach(link => {
                const name = lim(link.querySelector('h3')?.innerText||'',150);
                if(name) cards.push({
                  name,phones:[],emails:[],ratings:[],address:'',
                  website:link.href,source:location.hostname
                });
              });
          } else if(isYandexSERP) {
            Array.from(document.querySelectorAll('.serp-item,.organic,.Organic'))
              .slice(0,\(limit))
              .forEach(el => {
                const link = el.querySelector('a[href]');
                const name = lim(el.querySelector('h2,h3,.organic__title,.OrganicTitle')?.innerText||'',150);
                if(name && link) cards.push({
                  name,
                  phones:[...new Set(((el.innerText||'').match(phoneRx)||[]).map(p=>clean(p)))].slice(0,3),
                  emails:[],ratings:[],address:'',website:link.href,source:location.hostname
                });
              });
          }
          const selectors = [
            '.business-card','[class*="company"]','[class*="organization"]',
            '.card','[class*="item"]','[class*="listing"]','article',
            '[itemprop="LocalBusiness"],[itemprop="Organization"]'
          ];
          let containers = [];
          if(cards.length === 0) {
            for(const sel of selectors) {
              const found = Array.from(document.querySelectorAll(sel)).filter(el => {
                const text = clean(el.innerText);
                return text.length >= 12 && text.length <= 1600;
              });
              if(found.length >= 2) { containers = found.slice(0,\(limit)); break; }
            }
          }
          if(cards.length === 0 && containers.length === 0) {
            const phones = [...new Set((bodyText.match(phoneRx)||[]).map(p=>clean(p)))].slice(0,5);
            const emails = [...new Set((bodyText.match(emailRx)||[]))].slice(0,5);
            const ratings = [...new Set((bodyText.match(ratingRx)||[]).map(r=>clean(r)))].slice(0,5);
            const nameEl = document.querySelector('h1');
            const name = lim(nameEl?.innerText||document.title,200);
            if(name) cards.push({name,phones,emails,ratings,address:'',website:location.href,source:location.hostname});
          } else if(cards.length === 0) {
            for(const el of containers) {
              const t = el.innerText;
              const nameEl = el.querySelector('h2,h3,h4,[class*="name"],[class*="title"],[itemprop="name"]');
              const name = lim(nameEl?.innerText||'', 150);
              if(!name) continue;
              const phones = [...new Set((t.match(phoneRx)||[]).map(p=>clean(p)))].slice(0,3);
              const emails = [...new Set((t.match(emailRx)||[]))].slice(0,2);
              const ratings = [...new Set((t.match(ratingRx)||[]).map(r=>clean(r)))].slice(0,2);
              const addrEl = el.querySelector('[itemprop="streetAddress"],[class*="address"],[class*="addr"]');
              const link   = el.querySelector('a[href]');
              cards.push({name, phones, emails, ratings, address:lim(addrEl?.innerText||'',200), website:link?.href||'', source:location.hostname});
            }
          }
          const unique = [];
          const seen = new Set();
          for(const card of cards) {
            const key = clean(card.name).toLocaleLowerCase() + '|' + clean(card.website);
            if(!seen.has(key)) { seen.add(key); unique.push(card); }
          }
          return JSON.stringify({url:location.href, count:unique.length, cards:unique.slice(0,\(limit))});
        })()
        """
        guard let json = try await evaluate(script) as? String else {
            throw BrowserError.invalidPageResult
        }
        return json
    }

    func extractHotelCards(maxCards: Int = 20) async throws -> String {
        let script = """
        (() => {
          const clean = s => String(s||'').replace(/\\s+/g,' ').trim();
          const lim = (s,n) => clean(s).slice(0,n);
          const bodyText = document.body?.innerText||'';
          const priceRx = /[\\d\\s]+[.,]?\\d*\\s*(?:₽|руб|р\\b)/gi;
          const ratingRx = /([0-9][.,][0-9])(?:\\s*\\/\\s*(?:5|10)|\\s*из\\s*(?:5|10))/gi;
          const starsRx  = /([1-5])\\s*(?:звезд|★)/gi;

          const selectors = [
            '[class*="hotel"],[class*="Hotel"]',
            '[class*="property"],[class*="accommodation"]',
            '[data-id],[data-hotel-id]',
            '.card, [class*="listing"]'
          ];
          let containers = [];
          for(const sel of selectors) {
            const found = Array.from(document.querySelectorAll(sel)).filter(el => {
              const t = el.innerText||'';
              return t.length > 80 && (priceRx.test(t) || ratingRx.test(t));
            });
            if(found.length >= 2) { containers = found.slice(0,\(maxCards)); break; }
          }
          const hotels = [];
          if(containers.length === 0) {
            const prices  = [...new Set((bodyText.match(priceRx)||[]).map(p=>clean(p)))].slice(0,10);
            const ratings = [...new Set((bodyText.match(ratingRx)||[]).map(r=>clean(r)))].slice(0,10);
            const stars   = [...new Set((bodyText.match(starsRx)||[]).map(s=>clean(s)))].slice(0,10);
            const nameEl  = document.querySelector('h1');
            const name    = lim(nameEl?.innerText||document.title, 200);
            if(name) hotels.push({name, stars:stars[0]||'', rating:ratings[0]||'', priceFrom:prices[0]||'', reviewCount:'', url:location.href});
          } else {
            for(const el of containers) {
              const t = el.innerText;
              const nameEl = el.querySelector('h2,h3,h4,[class*="name"],[class*="title"]');
              const name   = lim(nameEl?.innerText||'',200);
              if(!name) continue;
              const prices  = (t.match(priceRx)||[]).map(p=>clean(p));
              const ratings = (t.match(ratingRx)||[]).map(r=>clean(r));
              const stars   = (t.match(starsRx)||[]).map(s=>clean(s));
              const reviewMatch = t.match(/(\\d+)\\s*(?:отзыв|оценок|review)/i);
              const link   = el.querySelector('a[href]');
              hotels.push({name, stars:stars[0]||'', rating:ratings[0]||'', priceFrom:prices[0]||'', reviewCount:reviewMatch?.[1]||'', url:link?.href||location.href});
            }
          }
          return JSON.stringify({url:location.href, count:hotels.length, hotels});
        })()
        """
        guard let json = try await evaluate(script) as? String else {
            throw BrowserError.invalidPageResult
        }
        return json
    }

    func extractContactCards() async throws -> String {
        let script = """
        (() => {
          const clean = s => String(s||'').replace(/\\s+/g,' ').trim();
          const lim = (s,n) => clean(s).slice(0,n);
          const bodyText = document.body?.innerText||'';
          const allText  = document.documentElement.innerHTML;

          const phoneRx   = /(?:\\+7|8)[\\s\\-]?\\(?\\d{3}\\)?[\\s\\-]?\\d{3}[\\s\\-]?\\d{2}[\\s\\-]?\\d{2}/g;
          const emailRx   = /[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}/g;
          const waRx      = /(?:wa\\.me|whatsapp\\.com\\/send)\\S*/gi;
          const tgRx      = /(?:t\\.me|telegram\\.me)\\/\\S+/gi;
          const vkRx      = /vk\\.com\\/\\S+/gi;

          const phones   = [...new Set((bodyText.match(phoneRx)||[]).map(p=>clean(p)))];
          const emails   = [...new Set((bodyText.match(emailRx)||[]))];
          const whatsapp = [...new Set((allText.match(waRx)||[]).map(u=>clean(u)))];
          const telegram = [...new Set((allText.match(tgRx)||[]).map(u=>clean(u)))];
          const vk       = [...new Set((allText.match(vkRx)||[]).map(u=>clean(u))).values()].filter(u=>!u.includes('share'));

          const addrEl  = document.querySelector('[itemprop="streetAddress"],[class*="address"],[class*="addr"]');
          const address = lim(addrEl?.innerText||'', 300);

          const nameEl  = document.querySelector('h1,[itemprop="name"],[class*="company-name"]');
          const name    = lim(nameEl?.innerText||document.title, 200);

          return JSON.stringify({url:location.href, name, address, phones:phones.slice(0,10), emails:emails.slice(0,10), whatsapp:whatsapp.slice(0,5), telegram:telegram.slice(0,5), vk:vk.slice(0,5)});
        })()
        """
        guard let json = try await evaluate(script) as? String else {
            throw BrowserError.invalidPageResult
        }
        return json
    }

    func extractArticle(maxChars: Int = 6000) async throws -> String {
        let script = """
        (() => {
          const clean = s => String(s||'').replace(/\\s+/g,' ').trim();
          const lim = (s,n) => clean(s).slice(0,n);

          // Try article / main content selectors in priority order
          const selectors = [
            'article','[role="main"] article','main article',
            '[class*="article-body"],[class*="article__body"]',
            '[class*="post-content"],[class*="post__content"]',
            '[class*="entry-content"],[itemprop="articleBody"]',
            'main','[role="main"]','.content','#content'
          ];
          let bestEl = null;
          let bestLen = 0;
          for(const sel of selectors) {
            const el = document.querySelector(sel);
            if(el) {
              const t = (el.innerText||'').trim();
              if(t.length > bestLen) { bestLen = t.length; bestEl = el; }
            }
          }
          const bodyFallback = document.body?.innerText||'';
          const rawText = bestEl ? (bestEl.innerText||'') : bodyFallback;
          const titleEl = document.querySelector('h1');
          const title   = lim(titleEl?.innerText||document.title, 200);
          const dateEl  = document.querySelector('time,[class*="date"],[class*="publish"]');
          const pubDate = lim(dateEl?.getAttribute('datetime')||dateEl?.innerText||'', 80);
          const authorEl= document.querySelector('[class*="author"],[rel="author"],[itemprop="author"]');
          const author  = lim(authorEl?.innerText||'', 100);
          const text    = rawText.slice(0, \(maxChars));
          return JSON.stringify({url:location.href, title, author, pubDate, charCount:rawText.length, text, truncated: rawText.length > \(maxChars)});
        })()
        """
        guard let json = try await evaluate(script) as? String else {
            throw BrowserError.invalidPageResult
        }
        return json
    }

    func evaluate(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func updateState() {
        address = webView.url?.absoluteString ?? address
        title = webView.title ?? "Браузер"
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private static let siteAliases: [String: String] = [
        "яндекс": "https://yandex.ru",
        "yandex": "https://yandex.ru",
        "гугл":   "https://www.google.com",
        "google": "https://www.google.com",
        "вконтакте": "https://vk.com",
        "вк":     "https://vk.com",
        "vk":     "https://vk.com",
        "ютуб":   "https://www.youtube.com",
        "youtube": "https://www.youtube.com",
        "твиттер": "https://x.com",
        "twitter": "https://x.com",
        "x":      "https://x.com",
        "github":  "https://github.com",
        "гитхаб": "https://github.com",
        "вики":    "https://ru.wikipedia.org",
        "wikipedia": "https://en.wikipedia.org",
        "реддит":  "https://www.reddit.com",
        "reddit":  "https://www.reddit.com",
        "фейсбук": "https://www.facebook.com",
        "facebook": "https://www.facebook.com",
        "telegram": "https://web.telegram.org",
        "тг":      "https://web.telegram.org",
        "авито":   "https://www.avito.ru",
        "avito":   "https://www.avito.ru",
        "озон":    "https://www.ozon.ru",
        "ozon":    "https://www.ozon.ru",
        "mail":    "https://mail.ru",
        "дзен":    "https://dzen.ru",
        "bing":    "https://www.bing.com",
    ]

    private static func normalizedURL(_ value: String) -> URL {
        let input = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let alias = siteAliases[input.lowercased()], let url = URL(string: alias) {
            return url
        }
        if let url = URL(string: input),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return url
        }
        if input.contains("."), !input.contains(" ") {
            return URL(string: "https://\(input)")!
        }
        let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        return URL(string: "https://www.google.com/search?q=\(encoded)")!
    }

    private static func javascriptLiteral(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value])
        guard let json = String(data: data, encoding: .utf8) else {
            throw BrowserError.invalidText
        }
        return String(json.dropFirst().dropLast())
    }
}

enum BrowserError: Error, LocalizedError {
    case invalidPageResult
    case invalidText
    case unavailable
    case clipboardFailed

    var errorDescription: String? {
        switch self {
        case .invalidPageResult: return "Не удалось прочитать страницу."
        case .invalidText: return "Не удалось подготовить текст для страницы."
        case .unavailable: return "Браузер Алакеи недоступен."
        case .clipboardFailed: return "Не удалось скопировать изображение в буфер обмена."
        }
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// ── Browser Tab model ─────────────────────────────────────────

@MainActor
final class BrowserTab: Identifiable, ObservableObject {
    let id = UUID()
    let store = BrowserStore()
}

// ── Browser Tab Item view ─────────────────────────────────────

struct BrowserTabItem: View {
    @ObservedObject var tab: BrowserTab
    var isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? WAI.accentBright : WAI.textFaint)
                .frame(width: 14)
            Text(tab.store.title.isEmpty ? "Новая вкладка" : tab.store.title)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? WAI.text : WAI.textDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WAI.textFaint)
                    .frame(width: 16, height: 16)
                    .background(isHovered ? WAI.surfaceInset : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .opacity(isActive || isHovered ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .frame(width: 140, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? Color(hex: 0x1A1930) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isActive ? WAI.lineAccent : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { isHovered = $0 }
    }
}

// ── Browser Pane View ─────────────────────────────────────────

struct BrowserPaneView: View {
    @ObservedObject var store: BrowserStore
    var isFullFrame: Bool = false
    var assistantPanelVisible: Bool = false
    var onEnterFullFrame: () -> Void = {}
    var onExitFullFrame: () -> Void = {}
    var onToggleAssistantPanel: () -> Void = {}
    var onCloseBrowser: () -> Void = {}

    // Tab state
    @State private var tabs: [BrowserTab] = []
    @State private var activeTabID: UUID? = nil
    @State private var browserToastText: String? = nil
    @State private var browserToastTask: Task<Void, Never>? = nil

    private var activeTab: BrowserTab? {
        tabs.first(where: { $0.id == activeTabID })
    }

    private var activeStore: BrowserStore {
        activeTab?.store ?? store
    }

    var body: some View {
        VStack(spacing: 0) {
            browserTabStrip
            // Use a child view that observes the active store so toolbar re-renders on navigation
            if let tab = activeTab {
                BrowserPaneContent(
                    activeStore: tab.store,
                    isFullFrame: isFullFrame,
                    assistantPanelVisible: assistantPanelVisible,
                    onEnterFullFrame: onEnterFullFrame,
                    onExitFullFrame: onExitFullFrame,
                    onToggleAssistantPanel: onToggleAssistantPanel,
                    onCloseBrowser: onCloseBrowser
                )
            } else {
                BrowserPaneContent(
                    activeStore: store,
                    isFullFrame: isFullFrame,
                    assistantPanelVisible: assistantPanelVisible,
                    onEnterFullFrame: onEnterFullFrame,
                    onExitFullFrame: onExitFullFrame,
                    onToggleAssistantPanel: onToggleAssistantPanel,
                    onCloseBrowser: onCloseBrowser
                )
            }
        }
        .overlay(alignment: .center) {
            if let text = browserToastText {
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .background(Color(hex: 0x07070D))
        .onAppear {
            if tabs.isEmpty {
                let tab = BrowserTab()
                tabs.append(tab)
                activeTabID = tab.id
                tab.store.navigate(store.address)
            }
        }
    }

    // ── Tab strip ────────────────────────────────────────────────

    private var browserTabStrip: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        BrowserTabItem(
                            tab: tab,
                            isActive: tab.id == activeTabID,
                            onSelect: { activeTabID = tab.id },
                            onClose: { closeTab(tab.id) }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }

            Button(action: addTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WAI.textDim)
                    .frame(width: 28, height: 28)
                    .background(WAI.surfaceInset)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(WAI.line))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help("Новая вкладка")
        }
        .frame(height: 36)
        .background(Color(hex: 0x0C0B18))
        .overlay(alignment: .bottom) {
            Rectangle().fill(WAI.line).frame(height: 1)
        }
    }

    private func addTab() {
        let tab = BrowserTab()
        tabs.append(tab)
        activeTabID = tab.id
        tab.store.navigate("https://www.google.com")
    }

    private func closeTab(_ id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if tabs.isEmpty {
            addTab()
        } else if activeTabID == id {
            let newIdx = min(idx, tabs.count - 1)
            activeTabID = tabs[newIdx].id
        }
    }
}

// ── Browser Pane Content (observes active store) ──────────────

private struct BrowserPaneContent: View {
    @ObservedObject var activeStore: BrowserStore
    var isFullFrame: Bool
    var assistantPanelVisible: Bool
    var onEnterFullFrame: () -> Void
    var onExitFullFrame: () -> Void
    var onToggleAssistantPanel: () -> Void
    var onCloseBrowser: () -> Void
    @State private var screenshotCopied = false
    @State private var showAnnotation = false
    @State private var screenshotToast = ""
    @State private var browserToastText: String? = nil
    @State private var browserToastTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if activeStore.isShowingFind {
                findBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack(alignment: .bottomTrailing) {
                BrowserWebView(webView: activeStore.webView)
                if !screenshotToast.isEmpty {
                    Text(screenshotToast)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WAI.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.82))
                        .clipShape(Capsule())
                        .padding(.bottom, 84)
                        .padding(.trailing, 12)
                }
                if activeStore.lastScreenshot != nil {
                    screenshotPreviewCard
                        .padding(12)
                }
            }
        }
        .overlay(alignment: .center) {
            if let text = browserToastText {
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: activeStore.isShowingFind)
        .sheet(isPresented: $showAnnotation) {
            if let img = activeStore.lastScreenshot ?? activeStore.lastAnnotatedScreenshot {
                BrowserAnnotationView(screenshot: img, store: activeStore) {
                    showAnnotation = false
                }
            }
        }
    }

    // ── Screenshot preview card ──────────────────────────────────

    private var screenshotPreviewCard: some View {
        let thumb = activeStore.lastAnnotatedScreenshot ?? activeStore.lastScreenshot
        return VStack(spacing: 0) {
            if let img = thumb {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 96, height: 54)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    if screenshotCopied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(WAI.success)
                            .background(Color.black.opacity(0.6).clipShape(Circle()))
                            .offset(x: -3, y: 3)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(WAI.line, lineWidth: 1)
                )
                .onTapGesture { copyLastScreenshotToClipboard() }
                .help("Нажмите, чтобы скопировать скриншот")
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WAI.line, lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }

    private func copyLastScreenshotToClipboard() {
        let img = activeStore.lastAnnotatedScreenshot ?? activeStore.lastScreenshot
        guard let image = img else { return }
        screenshotCopied = BrowserClipboard.copy(image)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            screenshotCopied = false
        }
    }

    // ── Screenshot to clipboard + toast ──────────────────────────

    private func captureBrowserScreenshotToClipboard() {
        let config = WKSnapshotConfiguration()
        activeStore.webView.takeSnapshot(with: config) { image, _ in
            DispatchQueue.main.async {
                if let image {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.writeObjects([image])
                    if let tiff = image.tiffRepresentation,
                       let bmp = NSBitmapImageRep(data: tiff),
                       let png = bmp.representation(using: .png, properties: [:]) {
                        pb.setData(png, forType: .png)
                    }
                    activeStore.lastScreenshot = image
                    showBrowserToast("Скриншот скопирован в буфер")
                } else {
                    showBrowserToast("Не удалось сделать скриншот")
                }
            }
        }
    }

    private func showBrowserToast(_ text: String) {
        browserToastTask?.cancel()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            browserToastText = text
        }
        browserToastTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    browserToastText = nil
                }
            }
        }
    }

    // ── Toolbar ──────────────────────────────────────────────────

    private var toolbar: some View {
        HStack(spacing: 7) {
            // Navigation
            navBtn("chevron.left", on: activeStore.canGoBack) { activeStore.goBack() }
            navBtn("chevron.right", on: activeStore.canGoForward) { activeStore.goForward() }
            navBtn(activeStore.isLoading ? "xmark" : "arrow.clockwise", on: true) {
                activeStore.isLoading ? activeStore.webView.stopLoading() : activeStore.reload()
            }

            // Address bar
            TextField("Адрес или поисковый запрос", text: $activeStore.address)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(WAI.text)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(WAI.line, lineWidth: 1)
                        )
                )
                .onSubmit { activeStore.navigate(activeStore.address) }

            // Status pill
            HStack(spacing: 5) {
                Circle()
                    .fill(activeStore.isLoading ? WAI.accentBright : WAI.success)
                    .frame(width: 5, height: 5)
                    .animation(.easeInOut(duration: 0.3), value: activeStore.isLoading)
                Text(activeStore.isLoading ? "Загрузка" : "Готово")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(WAI.textFaint)
            }
            .frame(width: 74, alignment: .trailing)

            // Screenshot → clipboard + toast
            toolBtn(screenshotCopied ? "checkmark" : "camera", accent: screenshotCopied) {
                captureBrowserScreenshotToClipboard()
                screenshotCopied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    screenshotCopied = false
                }
            }
            .help("Скриншот → буфер обмена (⌘V в чат)")

            // Annotate
            toolBtn("pencil.and.outline", accent: showAnnotation) {
                Task {
                    do {
                        _ = try await activeStore.takeScreenshotAndCopy()
                        showAnnotation = true
                    } catch {
                        screenshotToast = error.localizedDescription
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        screenshotToast = ""
                    }
                }
            }
            .help("Аннотировать скриншот")

            // Zoom controls
            HStack(spacing: 3) {
                Button { activeStore.setZoom(activeStore.zoom - 0.1) } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WAI.textDim)
                        .frame(width: 22, height: 28)
                }
                .buttonStyle(.plain)
                .help("Уменьшить")

                Text("\(Int(activeStore.zoom * 100))%")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(WAI.textFaint)
                    .frame(width: 36, alignment: .center)
                    .onTapGesture { activeStore.setZoom(1.0) }
                    .help("Сбросить масштаб (100%)")

                Button { activeStore.setZoom(activeStore.zoom + 0.1) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WAI.textDim)
                        .frame(width: 22, height: 28)
                }
                .buttonStyle(.plain)
                .help("Увеличить")
            }
            .background(WAI.surfaceInset)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WAI.line))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Mode-specific toolbar buttons
            if isFullFrame {
                // AI panel toggle
                toolBtn("sparkles", accent: assistantPanelVisible) {
                    onToggleAssistantPanel()
                }
                .help(assistantPanelVisible ? "Скрыть AI-панель" : "Открыть AI-панель")

                // Return to chat
                toolBtn("arrow.down.right.and.arrow.up.left") {
                    onExitFullFrame()
                }
                .help("Вернуть чат")
            } else {
                // Expand to full frame
                toolBtn("arrow.up.left.and.arrow.down.right") {
                    onEnterFullFrame()
                }
                .help("Развернуть браузер")
            }

            // Close browser — always visible
            toolBtn("xmark.circle") {
                onCloseBrowser()
            }
            .help("Закрыть браузер")

            // Overflow menu
            browserMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x12111E), Color(hex: 0x090910)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(WAI.line).frame(height: 1)
        }
    }

    // ── Find bar ─────────────────────────────────────────────────

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(WAI.textMuted)

            TextField("Найти на странице…", text: $activeStore.findQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(WAI.text)
                .onSubmit { activeStore.findNext() }

            Spacer(minLength: 0)

            HStack(spacing: 3) {
                findNavBtn("chevron.up") { activeStore.findPrevious() }
                findNavBtn("chevron.down") { activeStore.findNext() }
            }

            Button {
                withAnimation { activeStore.toggleFind() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WAI.textMuted)
                    .frame(width: 22, height: 22)
                    .background(WAI.surfaceInset)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(hex: 0x0E0D1C))
        .overlay(alignment: .bottom) {
            Rectangle().fill(WAI.line).frame(height: 1)
        }
    }

    // ── Overflow menu ─────────────────────────────────────────────

    private var browserMenu: some View {
        Menu {
            Button {
                activeStore.hardReload()
            } label: {
                Label("Принудительно перезагрузить", systemImage: "arrow.clockwise.circle")
            }

            Button {
                withAnimation { activeStore.toggleFind() }
            } label: {
                Label("Найти на странице", systemImage: "magnifyingglass")
            }

            Divider()

            Button {
            } label: {
                Label("Настройки сайта", systemImage: "lock.shield")
            }
            .disabled(true)

            Button {
            } label: {
                Label("Панель устройств", systemImage: "iphone.and.arrow.right.inward")
            }
            .disabled(true)

            Divider()

            Menu("Масштаб: \(Int(activeStore.zoom * 100))%") {
                Button("Увеличить (+10%)") { activeStore.setZoom(activeStore.zoom + 0.1) }
                Button("Уменьшить (−10%)") { activeStore.setZoom(activeStore.zoom - 0.1) }
                Divider()
                Button("Сбросить (100%)") { activeStore.setZoom(1.0) }
            }

            Divider()

            Button(role: .destructive) {
                activeStore.clearCookies()
            } label: {
                Label("Очистить файлы cookie", systemImage: "hand.raised.slash")
            }

            Button(role: .destructive) {
                activeStore.clearCache()
            } label: {
                Label("Очистить кеш", systemImage: "internaldrive")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WAI.textDim)
                .frame(width: 30, height: 30)
                .background(WAI.surfaceInset)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(WAI.line))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // ── Button builders ───────────────────────────────────────────

    private func navBtn(_ icon: String, on enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? WAI.textDim : WAI.textFaint)
                .frame(width: 28, height: 28)
                .background(WAI.surfaceInset)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WAI.line))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func toolBtn(_ icon: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent ? WAI.accentBright : WAI.textDim)
                .frame(width: 28, height: 28)
                .background(accent ? WAI.accentSoft : WAI.surfaceInset)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent ? WAI.lineAccent : WAI.line)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func findNavBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WAI.textDim)
                .frame(width: 24, height: 24)
                .background(WAI.surfaceInset)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class AlakeyaBrowser: NSObject, ObservableObject {
    static let shared = AlakeyaBrowser()

    let store = BrowserStore()
    @Published private(set) var isPresented = false

    private override init() {
        super.init()
    }

    func open(_ value: String = "https://www.google.com") {
        isPresented = true
        store.navigate(value)
    }

    func toggle() {
        if isPresented {
            close()
        } else {
            open()
        }
    }

    func close() {
        isPresented = false
    }

    func readPage() async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.readPage()
    }

    func click(text: String) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.click(elementID: "", text: text)
    }

    func click(elementID: String, text: String) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.click(elementID: elementID, text: text)
    }

    func type(text: String, elementID: String, field: String) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.type(text: text, elementID: elementID, field: field)
    }

    func scroll(direction: String, amount: Int) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.scroll(direction: direction, amount: amount)
    }

    func scrollResultsContainer() async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.scrollResultsContainer()
    }

    func submit(elementID: String, text: String) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.submit(elementID: elementID, text: text)
    }

    func select(elementID: String, value: String) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.select(elementID: elementID, value: value)
    }

    func wait(milliseconds: Int) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.waitForPage(milliseconds: milliseconds)
    }

    func screenshot() async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.takeScreenshot()
    }

    func highlightElement(elementID: String = "", textSearch: String = "", color: String = "", durationMs: Int = 4000, label: String = "") async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.highlightElement(elementID: elementID, textSearch: textSearch, color: color, durationMs: durationMs, label: label)
    }

    func extractPageData() async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.extractPageData()
    }

    func seoAudit() async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.seoAudit()
    }

    /// Headless search — uses the web view without opening the browser pane.
    func searchHeadless(query: String, maxResults: Int = 15) async throws -> String {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return "SEARCH_INTERNET_RESULTS:\n[]"
        }
        let searchURL = "https://www.google.com/search?q=\(encoded)&num=\(min(maxResults, 30))"
        
        // Navigate headlessly (webView works when pane is hidden)
        let navJS = "window.location.href = '" + searchURL + "';"
        _ = try await store.evaluate(navJS)
        
        // Wait
        try await Task.sleep(nanoseconds: 3_000_000_000)
        
        // Extract (skip isPresented guard)
        return try await store.extractSearchResults()
    }

    func extractSearchResults() async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.extractSearchResults()
    }

    func extractBusinessCards(maxCards: Int = 20) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.extractBusinessCards(maxCards: maxCards)
    }

    func extractHotelCards(maxCards: Int = 20) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.extractHotelCards(maxCards: maxCards)
    }

    func extractContactCards() async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.extractContactCards()
    }

    func extractArticle(maxChars: Int = 6000) async throws -> String {
        guard isPresented else { throw BrowserError.unavailable }
        return try await store.extractArticle(maxChars: maxChars)
    }

    func back() throws {
        guard isPresented else { throw BrowserError.unavailable }
        store.goBack()
    }

    func reload() throws {
        guard isPresented else { throw BrowserError.unavailable }
        store.reload()
    }

    func hardReload() throws {
        guard isPresented else { throw BrowserError.unavailable }
        store.hardReload()
    }

    func clearCookies() async throws {
        guard isPresented else { throw BrowserError.unavailable }
        await withCheckedContinuation { cont in
            store.clearCookies { cont.resume() }
        }
    }

    func clearCache() async throws {
        guard isPresented else { throw BrowserError.unavailable }
        await withCheckedContinuation { cont in
            store.clearCache { cont.resume() }
        }
    }

    func setZoom(_ factor: CGFloat) throws {
        guard isPresented else { throw BrowserError.unavailable }
        store.setZoom(factor)
    }
}
