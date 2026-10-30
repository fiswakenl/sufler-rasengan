import SwiftUI
import DivKit

private let accent = Color(red: 0.851, green: 0.467, blue: 0.341)   // оранжевый суфлёра
private let paper = Color(red: 0.98, green: 0.976, blue: 0.961)     // фон суфлёра

// Корень: вход → экран из JSON (DivKit). Что на экране, решает сервер; приложение даёт родную рамку (навигация, меню, вход, вибрация) и выполняет действия rasengan://…
struct Root: View {
    @State private var phase: Phase = .start
    @State private var screen: Data?
    @State private var web = false
    @State private var user = Keys.load("user") ?? ""
    @State private var pass = Keys.load("pass") ?? ""
    @State private var error = ""
    @State private var busy = false

    enum Phase { case start, login, screen }

    var body: some View {
        Group {
            switch phase {
            case .start: ProgressView().task { await enter() }
            case .login: login
            case .screen: main
            }
        }
        .tint(accent)
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $web) {
            NavigationStack {
                Web()
                    .background(paper)
                    .navigationTitle("Суфлёр")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { web = false } } }
            }
            .tint(accent)
        }
    }

    private var main: some View {
        NavigationStack {
            Group {
                if let d = screen {
                    DivHostingView(
                        divkitComponents: DivKitComponents(urlHandler: Actions { act in
                            switch act {
                            case "web": web = true
                            case "refresh": Task { await enter() }
                            default: break
                            }
                        }),
                        source: DivViewSource(kind: .data(d), cardId: "main")
                    )
                }
            }
            .background(paper)
            .navigationTitle("Расенган")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { Task { await enter() } } label: { Label("Обновить экран", systemImage: "arrow.clockwise") }
                        Button(role: .destructive) { signOut() } label: { Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
    }

    private var login: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Логин", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    SecureField("Пароль", text: $pass).textContentType(.password)
                } header: { Text("Суфлёр") } footer: {
                    if !error.isEmpty { Text(error).foregroundColor(.red) }
                }
                Section {
                    Button { Task { await enter() } } label: {
                        HStack { Spacer(); if busy { ProgressView() } else { Text("Войти").bold() }; Spacer() }
                    }.disabled(busy || user.isEmpty || pass.isEmpty)
                }
            }
            .navigationTitle("Вход")
        }
    }

    private func signOut() {
        Keys.save("", "user"); Keys.save("", "pass")
        HTTPCookieStorage.shared.cookies?.forEach(HTTPCookieStorage.shared.deleteCookie)
        user = ""; pass = ""; screen = nil; phase = .login
    }

    private func enter() async {
        guard !user.isEmpty, !pass.isEmpty else { phase = .login; return }
        busy = true; defer { busy = false }
        do {
            try await Net.login(user, pass)
            Keys.save(user, "user"); Keys.save(pass, "pass")
            screen = try await Net.screen()
            error = ""
            phase = .screen
        } catch {
            self.error = error.localizedDescription
            phase = .login
        }
    }
}

final class Actions: DivUrlHandler {
    let run: (String) -> Void
    init(_ run: @escaping (String) -> Void) { self.run = run }

    func handle(_ url: URL, info _: DivActionInfo, sender _: AnyObject?) {
        guard url.scheme == "rasengan", let h = url.host else { return }
        DispatchQueue.main.async {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.run(h)
        }
    }
}
