import SwiftUI
import DivKit

// Корень: вход → экран из JSON (DivKit). Что на экране, решает сервер; приложение лишь рисует его и выполняет действия rasengan://…
struct Root: View {
    @State private var phase: Phase = .start
    @State private var screen: Data?
    @State private var web = false
    @State private var user = Keys.load("user") ?? ""
    @State private var pass = Keys.load("pass") ?? ""
    @State private var error = ""

    enum Phase { case start, login, screen }

    var body: some View {
        Group {
            switch phase {
            case .start: ProgressView().task { await enter() }
            case .login: form
            case .screen:
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
        }
        .fullScreenCover(isPresented: $web) {
            ZStack(alignment: .topLeading) {
                Web().ignoresSafeArea()
                Button("Закрыть") { web = false }.padding(12).background(.thinMaterial, in: Capsule()).padding(.leading, 12)
            }
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            Text("Вход").font(.title2.bold())
            TextField("Логин", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            SecureField("Пароль", text: $pass).textFieldStyle(.roundedBorder)
            if !error.isEmpty { Text(error).foregroundColor(.red).font(.footnote) }
            Button("Войти") { Task { await enter() } }.buttonStyle(.borderedProminent)
        }
        .padding(28)
    }

    private func enter() async {
        guard !user.isEmpty, !pass.isEmpty else { phase = .login; return }
        do {
            try await Net.login(user, pass)
            Keys.save(user, "user"); Keys.save(pass, "pass")
            screen = try await Net.screen()
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
        DispatchQueue.main.async { self.run(h) }
    }
}
