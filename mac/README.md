# Alakeya — native macOS host (Swift + SwiftUI)

Нативная реализация ассистента Alakeya по производственным отчётам
(`.docx`): **Swift + SwiftUI/AppKit** для UI, разрешений и системной
автоматизации, с control-cascade на **AXSwift** (Accessibility),
AppleScript/Apple Events, clipboard+⌘V и CGEvent, экранным грундингом на
**ScreenCaptureKit** и голосом на **Apple Speech** (STT) +
**AVSpeechSynthesizer** (TTS).

Это рекомендованный докой production-путь (в отличие от Electron-референса в
`../desktop`, который реализует тот же дизайн и UI/permission-логику).

---

## Сборка и запуск

Требуется macOS 14+ и Xcode 15+ (Swift 5.9).

```bash
cd mac
swift run                 # быстрый запуск из SwiftPM
# или собрать .app-бандл:
./build/package.sh        # → build/Alakeya.app
open build/Alakeya.app
```

Подпись + нотаризация (Developer ID, вне Mac App Store — DOC1):

```bash
SIGN_ID="Developer ID Application: YOUR TEAM (TEAMID)" \
APPLE_ID="you@example.com" TEAM_ID="TEAMID" APP_PW="app-specific-pw" \
./build/package.sh --notarize
```

> При первом запуске система попросит **Accessibility**, **Screen
> Recording** и **Microphone** — это и есть TCC-периметр из отчётов.
> Приложение работает как accessory (без иконки в Dock, `LSUIElement`).

LLM: при наличии `OPENAI_API_KEY` оркестратор ходит в OpenAI со строгими
tool-schemas; без ключа — встроенный офлайн-планировщик.

---

## Архитектура

```
Sources/Alakeya/
├── AlakeyaApp.swift            @main + AppDelegate, accessory-режим
├── DesignSystem/
│   ├── Tokens.swift            токены из tokens.css (цвета/радиусы/тайминги)
│   └── OrbState.swift          7 состояний + маппинг статусов
├── Overlay/                    SwiftUI-порт ALAKEYA Design System
│   ├── OrbWindow.swift         borderless transparent NSPanel, всегда сверху,
│   │                           авто-размер, snap в угол / центр (HANDOFF §5.2-5.4)
│   ├── RootView.swift          сборка оверлея (≈ App.jsx)
│   ├── OrbView.swift           орб: 7 анимированных состояний (Orb.jsx/css)
│   ├── AssistantPanelView.swift
│   ├── PermissionCardView.swift  ⌘⏎ / ⌘. горячие клавиши
│   ├── ActivityLogView.swift
│   ├── SettingsView.swift       7 вкладок
│   ├── OnboardingView.swift     6 шагов
│   └── ErrorToastView.swift
├── Agent/
│   ├── AgentStore.swift        ObservableObject — состояние UI
│   ├── Action.swift            типизированные действия + класс риска
│   ├── Permissions.swift       classifyRisk + shouldAutoConfirm + правила
│   ├── Orchestrator.swift      задача → план (mock | OpenAI strict tools)
│   ├── ToolRunner.swift        gate → executor → журнал; цикл задачи; 7 статусов
│   ├── Executors.swift         actuator (каскад AX→AppleScript→paste→CGEvent)
│   └── Settings.swift          модель настроек (из SettingsWindow defaults)
├── Automation/
│   ├── AXController.swift       AXSwift: снимок дерева, поиск поля, setValue, press
│   ├── AppleScriptRunner.swift  NSAppleScript / Apple Events
│   ├── InputFallback.swift      CGEvent: paste ⌘V, клавиши, клик
│   └── ScreenReader.swift       ScreenCaptureKit: снимок экрана для грундинга
├── Voice/
│   ├── SpeechRecognizer.swift   Speech framework, push-to-talk, on-device режим
│   ├── SpeechSynthesizer.swift  AVSpeechSynthesizer (TTS)
│   └── VoiceController.swift     мост голос → агент
├── Permissions/
│   └── PermissionsManager.swift TCC: Accessibility/Screen/Mic + deep-links
└── Storage/
    └── Store.swift              правила + журнал действий (JSON в App Support)
```

### Поток одной задачи (HANDOFF §4)
```
текст/голос → Думаю → Orchestrator.plan
            → каждое действие через PolicyEngine:
                 low/auto            → сразу Действую
                 risk≥medium / hard  → Жду подтверждения → PermissionCard
            → Executors.run (AX→AppleScript→paste→CGEvent) → журнал
            → Говорю (AVSpeechSynthesizer) → Готов
исключение  → Ошибка → ErrorToast → Готов
```

### Классы риска и подтверждения (DOC1 §6 / DOC2)
- **low** (read_screen, search, screenshot) — без подтверждения;
- **medium** (open_app, type_text, click, apple_script) — в auto спрашивает;
- **high** (send_message, delete_file, run_shell, make_payment) — всегда;
  `send_email / delete_file / make_payment` — hard-limit (никогда не авто).

### Семантика прежде координат
`Executors.enterText` сперва пытается `AXSetAttributeValue` на focused-поле
(`AXController`), и только при неудаче — clipboard + ⌘V (`InputFallback`).
Координатный CGEvent-клик — последний fallback. Это прямой паттерн из DOC1/DOC2.

---

## Что осознанно оставлено как точки расширения
- `Executors.clickElement` — резолв элемента по тексту через обход AX-дерева;
- `ScreenReader.describeScreen` — здесь точка для VLM-проверки скриншота;
- `SpeechRecognizer` — Apple Speech; для офлайна можно подменить на whisper.cpp;
- тесты: DOC рекомендует Appium mac2-driver (e2e) + macOSWorld (safety-eval).
