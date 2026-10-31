import SwiftUI
import DivKit

private let accent = Color(red: 0.851, green: 0.467, blue: 0.341)   // оранжевый суфлёра
private let paper = Color(red: 0.98, green: 0.976, blue: 0.961)     // фон суфлёра

// Корень: вход → экран из JSON (DivKit). Что на экране, решает сервер; приложение даёт родную рамку (навигация, меню, вход, вибрация) и выполняет действия rasengan://…
struct Root: View {
    @State private var phase: Phase = .start
    @State private var screen: Data?
    @State private var web = false
    @State private var train = false
    @StateObject private var tr = Train()
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
        .fullScreenCover(isPresented: $train, onDismiss: { tr.stop() }) { Training(tr: tr, close: { train = false }) }
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
                            case "train": train = true; Task { await tr.start() }
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
            self.run(h == "act" ? "act:" + url.lastPathComponent : h)
        }
    }
}

// Тренировка: экран приходит с сервера, у нас — рамка, выбор источника собеседующего и кнопка-рация.
struct Training: View {
    @ObservedObject var tr: Train
    let close: () -> Void
    @State private var held = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let d = tr.card {
                    DivHostingView(
                        divkitComponents: DivKitComponents(urlHandler: Actions { act in
                            if act.hasPrefix("act:") { tr.act(String(act.dropFirst(4))) }
                        }),
                        source: DivViewSource(kind: .data(d), cardId: "train\(tr.rev)")
                    )
                } else {
                    ProgressView().frame(maxHeight: .infinity)
                }
                if !tr.error.isEmpty { Text(tr.error).font(.footnote).foregroundColor(.red).padding(.horizontal) }
                if tr.iv == "mic" {
                    Text("Вопрос")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(held ? accent : Color.clear)
                        .foregroundColor(held ? .white : .primary)
                        .overlay(Capsule().stroke(held ? accent : Color.primary, lineWidth: 1))
                        .clipShape(Capsule())
                        .padding(.horizontal, 16).padding(.bottom, 12)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !held { held = true; tr.talk(true); UIImpactFeedbackGenerator(style: .light).impactOccurred() } }
                            .onEnded { _ in held = false; tr.talk(false) })
                }
            }
            .background(paper)
            .navigationTitle("Тренировка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Закрыть") { close() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Собеседующий", selection: Binding(get: { tr.iv }, set: { tr.iv = $0; Task { await tr.start() } })) {
                            Text("Вопросы").tag("cache")
                            Text("Микрофон").tag("mic")
                            Text("Телефон").tag("phone")
                        }
                    } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
        }
        .tint(accent)
    }
}
