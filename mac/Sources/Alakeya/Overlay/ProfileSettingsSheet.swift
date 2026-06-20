import SwiftUI

/// Dedicated profile editing sheet — avatar, name, save.
/// Accessible from the sidebar profile button.
struct ProfileSettingsSheet: View {
    @ObservedObject var store: AgentStore
    @ObservedObject private var profiles = ProfileStore.shared
    let onClose: () -> Void

    @State private var name = ""
    @State private var avatarData: Data?
    @State private var showsAvatarEditor = false
    @State private var status: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Мой профиль")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WAI.text)
                    Text("Измените имя и аватар.")
                        .font(.system(size: 12))
                        .foregroundStyle(WAI.textMuted)
                }
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark").foregroundStyle(WAI.textDim)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(Rectangle().fill(WAI.line).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Avatar section
                    HStack(spacing: 18) {
                        Button { showsAvatarEditor = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                profilePreview.frame(width: 100, height: 100)
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WAI.bg)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(WAI.accent))
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ваше имя")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WAI.textDim)
                            TextField("Имя", text: $name)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .padding(11)
                                .background(RoundedRectangle(cornerRadius: 10).fill(WAI.control))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WAI.lineStrong))
                        }
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 14).fill(WAI.surfaceInset))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(WAI.line))

                    // Info
                    Text("Аватар и имя отображаются рядом с вашими сообщениями и в левой панели.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(WAI.textMuted)
                        .padding(.horizontal, 4)
                }
                .padding(24)
            }

            // Footer
            HStack {
                if let status {
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(status == "Сохранено" ? WAI.success : WAI.danger)
                        .transition(.opacity)
                }
                Spacer()
                Button("Отмена") { onClose() }
                    .buttonStyle(.plain)
                    .foregroundStyle(WAI.textDim)
                Button("Сохранить") {
                    do {
                        try profiles.updateUser(name: name, avatarData: avatarData)
                        status = "Сохранено"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            onClose()
                        }
                    } catch {
                        status = error.localizedDescription
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(WAI.bg)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(WAI.accent))
            }
            .padding(20)
            .overlay(Rectangle().fill(WAI.line).frame(height: 1), alignment: .top)
        }
        .frame(width: 560, height: 460)
        .background(WAI.surfaceStrong)
        .onAppear {
            name = profiles.user.name
            if let img = profiles.userAvatar(), let tiff = img.tiffRepresentation {
                avatarData = tiff
            }
        }
        .sheet(isPresented: $showsAvatarEditor) {
            AvatarEditorView(
                store: store,
                title: "Создать аватар профиля",
                initialImage: avatarData.flatMap(NSImage.init(data:))
            ) { data in
                avatarData = data
            }
        }
    }

    @ViewBuilder private var profilePreview: some View {
        if let avatarData, let image = NSImage(data: avatarData) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
                .overlay(Circle().stroke(WAI.lineAccent, lineWidth: 1.5))
        } else if let image = profiles.userAvatar() {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
                .overlay(Circle().stroke(WAI.lineAccent, lineWidth: 1.5))
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(WAI.textMuted)
        }
    }
}
