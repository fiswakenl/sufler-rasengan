import Foundation
import Security

// Сеть и ключница: приложение входит на сервер само (логин и пароль вводятся один раз), кука живёт в общем хранилище.
enum Net {
    static var base: URL {
        let s = Bundle.main.object(forInfoDictionaryKey: "SuflerURL") as? String ?? ""
        return URL(string: s).flatMap { URL(string: "/", relativeTo: $0)?.absoluteURL } ?? URL(string: "https://invalid")!
    }

    static func login(_ user: String, _ pass: String) async throws {
        var r = URLRequest(url: base.appendingPathComponent("login"))
        r.setValue("Basic " + Data("\(user):\(pass)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        let (_, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw NSError(domain: "rasengan", code: 401, userInfo: [NSLocalizedDescriptionKey: "Неверный логин или пароль"]) }
    }

    static func screen() async throws -> Data {
        let (d, resp) = try await URLSession.shared.data(from: base.appendingPathComponent("api/app/screen"))
        let h = resp as? HTTPURLResponse
        guard h?.statusCode == 200 else {
            throw NSError(domain: "rasengan", code: 1, userInfo: [NSLocalizedDescriptionKey: "Сервер не отдал экран: код \(h?.statusCode ?? 0), \(h?.url?.path ?? "")"])
        }
        return d
    }
}

extension Net {
    // Одноразовый ключ для расширения записи экрана (/ws/phone).
    static func phoneToken() async throws -> String {
        let (d, _) = try await URLSession.shared.data(from: base.appendingPathComponent("api/demo/phone"))
        guard let t = (try JSONSerialization.jsonObject(with: d) as? [String: Any])?["token"] as? String else { throw URLError(.badServerResponse) }
        return t
    }
}

enum Keys {
    static func save(_ v: String, _ k: String) {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: k]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q.merging([kSecValueData: Data(v.utf8)]) { $1 } as CFDictionary, nil)
    }

    static func load(_ k: String) -> String? {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: k, kSecReturnData: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
