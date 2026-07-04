import SwiftUI

struct ActivityLogView: View {
    @ObservedObject private var appLog = AppLog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity log").font(.headline)
                Spacer()
                Button("Clear") { appLog.clear() }
            }
            Text("An audit trail of what the tool did — useful evidence for an authorized engagement.")
                .font(.caption).foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(appLog.entries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.date, style: .time)
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(entry.level.rawValue)
                                    .font(.caption.monospaced().bold())
                                    .foregroundStyle(color(for: entry.level))
                                    .frame(width: 46, alignment: .leading)
                                Text(entry.message)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: appLog.entries.count) { _ in
                    if let last = appLog.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        }
        .padding(16)
        .navigationTitle("Activity Log")
    }

    private func color(for level: AppLog.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }
}
