import ReplayKit
import CoreMedia

// Расширение трансляции: получает звук других приложений (.audioApp), приводит к PCM 16 кГц моно и шлёт на сервер.
final class SampleHandler: RPBroadcastSampleHandler {
    private var task: URLSessionWebSocketTask?
    private var pos = 0.0          // дробная позиция ресемплера между буферами

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let ud = UserDefaults(suiteName: "group.dev.sufler.rasengan")
        guard let s = ud?.string(forKey: "url"), let t = ud?.string(forKey: "token"),
              var c = URLComponents(string: s) else {
            finishBroadcastWithError(NSError(domain: "rasengan", code: 1, userInfo: [NSLocalizedDescriptionKey: "Откройте приложение и нажмите запуск из страницы"]))
            return
        }
        c.queryItems = [URLQueryItem(name: "token", value: t)]
        guard let u = c.url else { return }
        task = URLSession.shared.webSocketTask(with: u)
        task?.resume()
    }

    override func broadcastFinished() { task?.cancel(with: .goingAway, reason: nil) }

    override func processSampleBuffer(_ sb: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .audioApp, let pcm = to16k(sb), !pcm.isEmpty else { return }
        task?.send(.data(pcm)) { _ in }
    }

    // Любой входной PCM (Int16 BE/LE или Float32, любое число каналов) → Int16 LE, 16 кГц, моно.
    private func to16k(_ sb: CMSampleBuffer) -> Data? {
        guard let fd = CMSampleBufferGetFormatDescription(sb),
              let a = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee,
              let bb = CMSampleBufferGetDataBuffer(sb) else { return nil }
        var len = 0
        var p: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &p) == noErr, let base = p else { return nil }
        let ch = Int(a.mChannelsPerFrame), bytes = Int(a.mBitsPerChannel) / 8
        guard ch > 0, bytes == 2 || bytes == 4, !(a.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0) else { return nil }
        let frames = len / (ch * bytes)
        let isFloat = a.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let big = a.mFormatFlags & kAudioFormatFlagIsBigEndian != 0
        let raw = UnsafeRawPointer(base)
        var mono = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            var sum: Float = 0
            for c in 0..<ch {
                let o = (i * ch + c) * bytes
                if isFloat {
                    var u = raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)
                    if big { u = u.byteSwapped }
                    sum += Float(bitPattern: u)
                } else {
                    var u = raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)
                    if big { u = u.byteSwapped }
                    sum += Float(Int16(bitPattern: u)) / 32768
                }
            }
            mono[i] = sum / Float(ch)
        }
        let step = a.mSampleRate / 16000
        var out = Data()
        while pos < Double(frames) {
            let i = Int(pos), f = Float(pos - Double(i))
            let v = i + 1 < frames ? mono[i] * (1 - f) + mono[i + 1] * f : mono[min(i, frames - 1)]
            var s = Int16(max(-1, min(1, v)) * 32767).littleEndian
            withUnsafeBytes(of: &s) { out.append(contentsOf: $0) }
            pos += step
        }
        pos -= Double(frames)
        return out
    }
}
