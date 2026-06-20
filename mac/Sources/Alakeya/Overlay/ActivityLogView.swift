import SwiftUI

// ============================================================
// ActivityLogView.swift — action journal, ported from ActivityLog.jsx.
// ============================================================

struct ActivityLogView: View {
    let entries: [ActivityEntry]
    var onExport: () -> Void
    var onClose: () -> Void

    @State private var filter = "today"

    private func statusColor(_ s: String) -> Color {
        switch s { case "ok": return WAI.success; case "awaiting": return WAI.warning
        case "blocked": return WAI.danger; case "denied": return Color(hex: 0x999999); default: return WAI.success }
    }

    private var filtered: [ActivityEntry] {
        let now = Date()
        return entries.filter { e in
            switch filter {
            case "today": return Calendar.current.isDateInToday(e.time)
            case "week": return now.timeIntervalSince(e.time) < 7 * 86400
            default: return true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                // Back button
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Назад")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(WAI.accentBright)
                }
                .buttonStyle(.plain)

                Spacer()
                tabs
            }.padding(.bottom, 12)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACTIVITY").font(.system(size: 11, weight: .medium)).tracking(2).foregroundStyle(WAI.textMuted)
                    Text("Журнал действий").font(.system(size: 17, weight: .semibold)).foregroundStyle(WAI.text)
                }
                Spacer()
            }.padding(.bottom, 18)

            if filtered.isEmpty {
                Text("Пока пусто.\nДействия агента появятся здесь.")
                    .multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(WAI.textMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered.reversed()) { e in row(e) }
                    }
                }.frame(maxHeight: 360)
            }

            Button("Экспортировать · CSV", action: onExport)
                .buttonStyle(.plain).foregroundStyle(WAI.textDim).font(.system(size: 13))
                .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.top, 8)
                .overlay(RoundedRectangle(cornerRadius: WAI.rLg).stroke(WAI.lineStrong))
        }
        .padding(24).frame(width: 420)
        .background(WAI.surfaceStrong)
        .overlay(RoundedRectangle(cornerRadius: WAI.r2xl).stroke(WAI.lineStrong))
        .clipShape(RoundedRectangle(cornerRadius: WAI.r2xl))
        .shadow(color: .black.opacity(0.7), radius: 30, y: 24)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach([("today", "Сегодня"), ("week", "Неделя"), ("all", "Всё")], id: \.0) { f in
                Button(f.1) { filter = f.0 }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(filter == f.0 ? WAI.text : WAI.textMuted)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(filter == f.0 ? Color.white.opacity(0.08) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: WAI.rSm))
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: WAI.rSm).stroke(WAI.line))
        .clipShape(RoundedRectangle(cornerRadius: WAI.rSm))
    }

    private func row(_ e: ActivityEntry) -> some View {
        HStack(spacing: 12) {
            Circle().fill(statusColor(e.status)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: 13)).foregroundStyle(WAI.text)
                Text(e.subtitle).font(.system(size: 11)).foregroundStyle(WAI.textMuted).lineLimit(1)
            }
            Spacer()
            Text(timeLabel(e.time)).font(.system(size: 10)).foregroundStyle(WAI.textMuted)
        }.padding(.horizontal, 8).padding(.vertical, 10)
    }

    private func timeLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru")
        if Calendar.current.isDateInToday(d) { f.dateFormat = "HH:mm" } else { f.dateFormat = "d MMM" }
        return f.string(from: d)
    }
}
