'use strict';

// ── Elements ──
const webview       = document.getElementById('browser-webview');
const urlBar        = document.getElementById('url-bar');
const backBtn       = document.getElementById('back-btn');
const forwardBtn    = document.getElementById('forward-btn');
const reloadBtn     = document.getElementById('reload-btn');
const statusDot     = document.getElementById('status-dot');
const zoomInBtn     = document.getElementById('zoom-in');
const zoomOutBtn    = document.getElementById('zoom-out');
const zoomReset     = document.getElementById('zoom-reset');
const zoomLevel     = document.getElementById('zoom-level');
const assistantPanel = document.getElementById('assistant-panel');
const widgetBtn     = document.getElementById('widget-btn');
const pulseRing     = document.getElementById('pulse-ring');
const closeAssistant = document.getElementById('close-assistant');
const voiceToggleBtn = document.getElementById('voice-toggle-btn');
const voiceText     = document.getElementById('voice-text');
const voiceWaves    = document.getElementById('voice-waves');
const chatMessages  = document.getElementById('chat-messages');
const topbarAssBtn  = document.getElementById('topbar-assistant-btn');
const micBtn        = document.getElementById('mic-btn');

// ── State ──
let currentZoom = 1.0;
let isListening = false;
let recognition = null;
let assistantVisible = false;

// ── Browser: webview events ──
webview.addEventListener('did-start-loading', () => {
  statusDot.style.background = '#f0a030';
  reloadBtn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
    <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
  </svg>`;
});

webview.addEventListener('did-finish-load', () => {
  statusDot.style.background = '#4caf50';
  reloadBtn.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
    <polyline points="23 4 23 10 17 10"/>
    <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
  </svg>`;
  urlBar.value = webview.getURL();
  updateNavButtons();
});

webview.addEventListener('did-fail-load', () => {
  statusDot.style.background = '#f44336';
});

webview.addEventListener('page-title-updated', (e) => {
  document.title = `Алакея — ${e.title}`;
});

webview.addEventListener('new-window', (e) => {
  webview.loadURL(e.url);
});

// ── Browser: navigation ──
function navigate(url) {
  let target = url.trim();
  if (!target) return;
  if (!target.startsWith('http://') && !target.startsWith('https://')) {
    // If it looks like a domain, add https, otherwise search
    if (target.includes('.') && !target.includes(' ')) {
      target = 'https://' + target;
    } else {
      target = 'https://www.google.com/search?q=' + encodeURIComponent(target);
    }
  }
  webview.loadURL(target);
}

urlBar.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') navigate(urlBar.value);
});

urlBar.addEventListener('focus', () => {
  urlBar.select();
});

backBtn.addEventListener('click', () => { if (webview.canGoBack()) webview.goBack(); });
forwardBtn.addEventListener('click', () => { if (webview.canGoForward()) webview.goForward(); });
reloadBtn.addEventListener('click', () => { webview.reload(); });

function updateNavButtons() {
  backBtn.disabled = !webview.canGoBack();
  forwardBtn.disabled = !webview.canGoForward();
}

// ── Zoom ──
function applyZoom() {
  webview.setZoomFactor(currentZoom);
  zoomLevel.textContent = Math.round(currentZoom * 100) + '%';
}

zoomInBtn.addEventListener('click', () => {
  currentZoom = Math.min(currentZoom + 0.1, 3.0);
  applyZoom();
});

zoomOutBtn.addEventListener('click', () => {
  currentZoom = Math.max(currentZoom - 0.1, 0.3);
  applyZoom();
});

zoomReset.addEventListener('click', () => {
  currentZoom = 1.0;
  applyZoom();
});

// Keyboard zoom shortcuts
document.addEventListener('keydown', (e) => {
  if (e.ctrlKey || e.metaKey) {
    if (e.key === '=' || e.key === '+') { e.preventDefault(); currentZoom = Math.min(currentZoom + 0.1, 3.0); applyZoom(); }
    if (e.key === '-') { e.preventDefault(); currentZoom = Math.max(currentZoom - 0.1, 0.3); applyZoom(); }
    if (e.key === '0') { e.preventDefault(); currentZoom = 1.0; applyZoom(); }
  }
});

// ── Assistant panel ──
function showAssistant() {
  assistantVisible = true;
  assistantPanel.classList.add('visible');
}

function hideAssistant() {
  assistantVisible = false;
  assistantPanel.classList.remove('visible');
  if (isListening) stopListening();
}

widgetBtn.addEventListener('click', () => {
  if (assistantVisible) hideAssistant();
  else showAssistant();
});

closeAssistant.addEventListener('click', hideAssistant);
topbarAssBtn.addEventListener('click', () => {
  if (assistantVisible) hideAssistant();
  else showAssistant();
});

// ── Voice recognition ──
function addMessage(text, role) {
  const div = document.createElement('div');
  div.className = `message ${role}`;
  div.textContent = text;
  chatMessages.appendChild(div);
  chatMessages.scrollTop = chatMessages.scrollHeight;
}

function startListening() {
  if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
    addMessage('Голосовой ввод не поддерживается в этом браузере.', 'assistant');
    return;
  }

  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  recognition = new SR();
  recognition.lang = 'ru-RU';
  recognition.interimResults = false;
  recognition.maxAlternatives = 1;

  recognition.onstart = () => {
    isListening = true;
    voiceText.textContent = 'Слушаю...';
    voiceWaves.classList.add('active');
    pulseRing.classList.add('active');
    voiceToggleBtn.style.background = 'rgba(100,140,255,0.3)';
    voiceToggleBtn.style.color = '#90b8ff';
  };

  recognition.onresult = (e) => {
    const transcript = e.results[0][0].transcript;
    addMessage(transcript, 'user');
    processCommand(transcript);
  };

  recognition.onerror = (e) => {
    console.error('Speech error:', e.error);
    voiceText.textContent = 'Ошибка: ' + e.error;
    stopListening();
  };

  recognition.onend = () => {
    stopListening();
  };

  recognition.start();
}

function stopListening() {
  isListening = false;
  if (recognition) { recognition.stop(); recognition = null; }
  voiceText.textContent = 'Нажмите, чтобы говорить';
  voiceWaves.classList.remove('active');
  pulseRing.classList.remove('active');
  voiceToggleBtn.style.background = '';
  voiceToggleBtn.style.color = '';
}

function processCommand(text) {
  const lower = text.toLowerCase();

  // Navigate command
  const gotoMatch = lower.match(/открой|перейди на|зайди на|открыть|открой сайт/);
  if (gotoMatch) {
    const domain = text.replace(/открой|перейди на|зайди на|открыть|открой сайт/gi, '').trim();
    if (domain) {
      navigate(domain);
      addMessage(`Открываю ${domain}...`, 'assistant');
      setTimeout(hideAssistant, 1000);
      return;
    }
  }

  // Idea / creative
  if (lower.includes('придум') || lower.includes('идея')) {
    addMessage('Хорошо, придумаю что-нибудь интересное для вас!', 'assistant');
    return;
  }

  // Write
  if (lower.includes('напиши') || lower.includes('написать')) {
    addMessage('Конечно, сейчас напишу!', 'assistant');
    return;
  }

  // Close/hide
  if (lower.includes('закрой') || lower.includes('скрой') || lower.includes('спасибо')) {
    addMessage('Хорошо, сворачиваюсь!', 'assistant');
    setTimeout(hideAssistant, 800);
    return;
  }

  // Default echo
  addMessage('Понял! Обрабатываю ваш запрос...', 'assistant');
}

voiceToggleBtn.addEventListener('click', () => {
  if (isListening) stopListening();
  else startListening();
});

micBtn.addEventListener('click', () => {
  showAssistant();
  setTimeout(() => {
    if (!isListening) startListening();
  }, 300);
});

// ── Action buttons ──
document.getElementById('idea-action-btn').addEventListener('click', () => {
  addMessage('Придумай мне что-нибудь интересное', 'user');
  setTimeout(() => addMessage('Вот идея: попробуйте создать мини-игру с необычными правилами!', 'assistant'), 600);
});

document.getElementById('write-action-btn').addEventListener('click', () => {
  addMessage('Напиши короткий текст', 'user');
  setTimeout(() => addMessage('Вот текст: "Каждый день — это новая возможность стать лучше."', 'assistant'), 600);
});

document.getElementById('ai-mode-btn').addEventListener('click', () => {
  showAssistant();
});

// ── Sidebar buttons ──
document.getElementById('idea-btn').addEventListener('click', () => {
  showAssistant();
  setTimeout(() => document.getElementById('idea-action-btn').click(), 300);
});

document.getElementById('write-btn').addEventListener('click', () => {
  showAssistant();
  setTimeout(() => document.getElementById('write-action-btn').click(), 300);
});

// ── Init ──
webview.addEventListener('dom-ready', () => {
  applyZoom();
  updateNavButtons();
});
