import Foundation
import SwiftUI

// ============================================================
// OrbState.swift — assistant state/emotion + status<->state map.
// ============================================================

enum AssistantState: String {
    case idle
    case hover
    case pressed
    case listening
    case thinking
    case generating
    case processing
    case vectorizing
    case speaking
    case success
    case waitingForConfirmation
    case error
    case offline

    var statusText: String {
        switch self {
        case .idle, .hover, .pressed: return ""
        case .listening: return "Слушаю"
        case .thinking: return "Думаю…"
        case .generating: return "Создаю изображение…"
        case .processing: return "Обрабатываю файл"
        case .vectorizing: return "Векторизую"
        case .speaking: return "Говорю"
        case .success: return "Готово"
        case .waitingForConfirmation: return "Жду подтверждения"
        case .error: return "Ошибка"
        case .offline: return "Не в сети"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle, .hover, .pressed: return "Алакея готова"
        case .listening: return "Алакея слушает вас"
        case .thinking: return "Алакея думает"
        case .generating: return "Алакея создаёт изображение"
        case .processing: return "Алакея обрабатывает файл"
        case .vectorizing: return "Алакея переводит изображение в вектор"
        case .speaking: return "Алакея отвечает голосом"
        case .success: return "Алакея завершила работу"
        case .waitingForConfirmation: return "Алакея ждёт подтверждения"
        case .error: return "Произошла ошибка"
        case .offline: return "Нет соединения"
        }
    }

    var isBusy: Bool {
        switch self {
        case .listening, .thinking, .generating, .processing, .vectorizing,
             .speaking, .waitingForConfirmation:
            return true
        default:
            return false
        }
    }

    var isStill: Bool {
        self == .error || self == .offline
    }

    var accentColor: Color {
        switch self {
        case .error:
            return WAI.coral
        case .waitingForConfirmation:
            return WAI.warning
        case .offline:
            return WAI.textMuted
        default:
            return WAI.accentBright
        }
    }
}

enum OrbEmotion: String {
    case neutral
    case happy
    case curious
    case focused
    case confused
    case error
}

typealias OrbState = AssistantState

// Human-facing agent statuses (HANDOFF §4.2).
enum AgentStatusLabel: String, CaseIterable {
    case ready      = "Готов"
    case listening  = "Слушаю"
    case thinking   = "Думаю"
    case speaking   = "Говорю"
    case acting     = "Действую"
    case awaiting   = "Жду подтверждения"
    case error      = "Ошибка"

    var assistantState: AssistantState {
        switch self {
        case .ready:     return .idle
        case .listening: return .listening
        case .thinking:  return .thinking
        case .speaking:  return .speaking
        case .acting:    return .processing
        case .awaiting:  return .waitingForConfirmation
        case .error:     return .error
        }
    }

    var orbState: OrbState { assistantState }

    var orbEmotion: OrbEmotion {
        switch self {
        case .ready:     return .neutral
        case .listening: return .curious
        case .thinking:  return .focused
        case .speaking:  return .happy
        case .acting:    return .focused
        case .awaiting:  return .curious
        case .error:     return .error
        }
    }
}
