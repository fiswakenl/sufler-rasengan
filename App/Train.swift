import AVFoundation
import ReplayKit
import SwiftUI

// Клиент тренировки: сокет /ws/app + микрофон. Экран рисует сервер (приходит {"screen": карточка DivKit}), приложение шлёт звук и действия.
// Кадр звука: первый байт — чей голос (0 — вы, 1 — собеседующий), дальше PCM 16 кГц моно Int16, по 100 мс.
@MainActor
final class Train: ObservableObject {
    @Published var card: Data?
    @Published var rev = 0
    @Published var iv = "cache"          // источник собеседующего: cache (озвученные вопросы) | mic (рация) | phone (звук звонка)
    @Published var live = false
    @Published var error = ""

    private var task: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    private var conv: AVAudioConverter?
    private var pcm = Data()
    private var talking = false          // держат рацию: микрофон считается голосом собеседующего
    private let group = "group.dev.sufler.rasengan"
    private let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))

    func start() async {
        stop()
        error = ""
        guard await withCheckedContinuation({ c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } }) else { error = "Нет доступа к микрофону"; return }
        if iv == "phone", let t = try? await Net.phoneToken() { prepareBroadcast(t) }
        var c = URLComponents(url: Net.base.appendingPathComponent("ws/app"), resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        c.queryItems = [URLQueryItem(name: "iv", value: iv)]
        task = URLSession.shared.webSocketTask(with: c.url!)
        task?.resume()
        live = true
        listen()
        do { try startMic() } catch { self.error = error.localizedDescription }
    }

    func stop() {
        if engine.isRunning { engine.inputNode.removeTap(onBus: 0); engine.stop() }
        task?.send(.string("\"close\"")) { _ in }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil; live = false; talking = false; pcm = Data()
    }

    func act(_ name: String) { json(["act": name]) }
    func talk(_ on: Bool) { talking = on }

    private func json(_ o: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func listen() {
        task?.receive { [weak self] r in
            Task { @MainActor in
                guard let self, self.task != nil else { return }
                switch r {
                case .success(let m):
                    if case .string(let s) = m, let o = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
                        if let c = o["screen"], let d = try? JSONSerialization.data(withJSONObject: c) { self.card = d; self.rev += 1 }
                        if let e = o["error"] as? String { self.error = e }
                    }
                    self.listen()
                case .failure(let e):
                    self.error = e.localizedDescription; self.live = false
                }
            }
        }
    }

    // Микрофон → 16 кГц моно Int16 → кадры по 100 мс.
    private func startMic() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
        try s.setActive(true)
        let inp = engine.inputNode
        let src = inp.outputFormat(forBus: 0)
        let dst = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        conv = AVAudioConverter(from: src, to: dst)
        inp.installTap(onBus: 0, bufferSize: 4096, format: src) { [weak self] buf, _ in
            guard let self, let conv = self.conv else { return }
            let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000 / src.sampleRate) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: cap) else { return }
            var fed = false
            conv.convert(to: out, error: nil) { _, st in
                if fed { st.pointee = .noDataNow; return nil }
                fed = true; st.pointee = .haveData; return buf
            }
            guard let p = out.int16ChannelData?[0] else { return }
            let bytes = Data(bytes: p, count: Int(out.frameLength) * 2)
            Task { @MainActor in self.push(bytes) }
        }
        engine.prepare()
        try engine.start()
    }

    private func push(_ d: Data) {
        pcm.append(d)
        let flag: UInt8 = (iv == "mic" && talking) ? 1 : 0
        while pcm.count >= 3200 {
            task?.send(.data(Data([flag]) + pcm.prefix(3200))) { _ in }
            pcm.removeFirst(3200)
        }
    }

    // Источник «Телефон»: адрес и ключ — расширению, потом системное окно трансляции.
    private func prepareBroadcast(_ token: String) {
        var c = URLComponents(url: Net.base.appendingPathComponent("ws/phone"), resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        let ud = UserDefaults(suiteName: group)
        ud?.set(c.url?.absoluteString, forKey: "url")
        ud?.set(token, forKey: "token")
        picker.preferredExtension = (Bundle.main.bundleIdentifier ?? "") + ".Broadcast"
        picker.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .allTouchEvents)
    }
}
