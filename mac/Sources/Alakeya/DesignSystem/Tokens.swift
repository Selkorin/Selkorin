import SwiftUI

// ============================================================
// Tokens.swift — design tokens ported from the ALAKEYA design
// system (handoff/src/tokens.css). Single source of truth for
// colors, radii, durations and the orb gradients.
// ============================================================

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum WAI {
    // ── Color · base — soft dark + Twitter blue ──────────
    static let bg            = Color(hex: 0x0F1117)
    static let sidebar       = Color(hex: 0x0B0D12)
    static let surface       = Color(hex: 0x13161E, alpha: 0.72)
    static let surfaceStrong = Color(hex: 0x13161E, alpha: 0.92)
    static let surfaceInset  = Color.white.opacity(0.04)
    static let canvas        = Color(hex: 0x0F1117)
    static let control       = Color(hex: 0x13161E)
    static let controlHover  = Color(hex: 0x181C26)

    // ── Borders — clean white + blue accent ───────────────
    static let line          = Color.white.opacity(0.07)
    static let lineStrong    = Color.white.opacity(0.11)
    static let lineAccent    = Color(hex: 0x1D9BF0, alpha: 0.35)

    // ── Text ──────────────────────────────────────────────
    static let text      = Color.white.opacity(0.94)
    static let textDim   = Color.white.opacity(0.68)
    static let textMuted = Color.white.opacity(0.42)
    static let textFaint = Color.white.opacity(0.26)

    // ── Accent — Twitter blue ─────────────────────────────
    static var accent       = Color(hex: 0x1D9BF0) // overridable from settings
    static let accentBright = Color(hex: 0x4DB8FF)
    static let accentPale   = Color(hex: 0xA0D9FF)
    static let accentDeep   = Color(hex: 0x1A6FC2)
    static let accentSoft   = Color(hex: 0x1D9BF0, alpha: 0.12)
    static let accentGlow   = Color(hex: 0x4DB8FF, alpha: 0.35)
    static let coral        = Color(hex: 0xE0876A)

    // ── Semantic ──────────────────────────────────────────
    static let success     = Color(hex: 0x1D9BF0)
    static let warning      = Color(hex: 0xFBBF24)
    static let warningSoft = Color(hex: 0xF59E0B)
    static let danger      = Color(hex: 0xF87171)

    // ── Radii ─────────────────────────────────────────────
    static let rSm: CGFloat = 6
    static let rMd: CGFloat = 10
    static let rLg: CGFloat = 14
    static let rXl: CGFloat = 22
    static let r2xl: CGFloat = 28
    static let rPill: CGFloat = 999

    // ── Durations (seconds) ───────────────────────────────
    static let durInstant = 0.12
    static let durFast    = 0.20
    static let durMorph   = 0.24
    static let durMedium  = 0.40
    static let durBreath  = 4.0

    static let easeOut = Animation.timingCurve(0.16, 1, 0.3, 1)

    // ── Typography ────────────────────────────────────────
    static let mono = Font.system(.body, design: .monospaced)

    // ── Orb gradients ─────────────────────────────────────
    // OrbView uses size-relative endRadius directly; these are kept for reference only.
    static let orbCore = RadialGradient(
        stops: [
            .init(color: Color(hex: 0xC8EEFF), location: 0.00),
            .init(color: Color(hex: 0x1D9BF0), location: 0.35),
            .init(color: Color(hex: 0x1A2A5E), location: 0.75),
            .init(color: Color(hex: 0x050216), location: 1.00),
        ],
        center: UnitPoint(x: 0.35, y: 0.30), startRadius: 0, endRadius: 200
    )
    static let orbCoreError = RadialGradient(
        stops: [
            .init(color: Color(hex: 0xFEE6B0), location: 0.00),
            .init(color: Color(hex: 0xF59E0B), location: 0.30),
            .init(color: Color(hex: 0x4B1C03), location: 0.75),
            .init(color: Color(hex: 0x1A0700), location: 1.00),
        ],
        center: UnitPoint(x: 0.35, y: 0.30), startRadius: 0, endRadius: 200
    )
}
