import SwiftUI

struct ProfileSettingsView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject private var profiles = ProfileStore.shared
    @State private var name = ""
    @State private var showsAvatarEditor = false
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Профиль")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WAI.text)

            HStack(spacing: 18) {
                Button { showsAvatarEditor = true } label: {
                    ZStack(alignment: .bottomTrailing) {
                        profileAvatar.frame(width: 96, height: 96)
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
                        .padding(11)
                        .background(RoundedRectangle(cornerRadius: 10).fill(WAI.control))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WAI.lineStrong))
                        .frame(maxWidth: 360)
                    Text("Имя и аватар будут показаны рядом с вашими сообщениями.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(WAI.textMuted)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(WAI.surfaceInset))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(WAI.line))

            HStack {
                Text(status ?? "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(status == "Сохранено" ? WAI.success : WAI.danger)
                Spacer()
                Button("Сохранить профиль") {
                    do {
                        try profiles.updateUser(name: name, avatarData: nil)
                        status = "Сохранено"
                    } catch {
                        status = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(WAI.accent)
            }
        }
        .onAppear { name = profiles.user.name }
        .sheet(isPresented: $showsAvatarEditor) {
            AvatarEditorView(
                store: store,
                title: "Создать аватар профиля",
                initialImage: profiles.userAvatar()
            ) { data in
                try profiles.updateUser(name: name, avatarData: data)
            }
        }
    }

    @ViewBuilder private var profileAvatar: some View {
        if let image = profiles.userAvatar() {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
                .overlay(Circle().stroke(WAI.lineAccent, lineWidth: 1.5))
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(WAI.textMuted)
        }
    }
}
