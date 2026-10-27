import AVFoundation
import SwiftUI

/// Голосовой ввод (Рома, 27.10): кнопка с микрофоном в поле ввода — говоришь, текст появляется в поле.
/// Распознаёт FlowLocal (GigaAM для русского, Parakeet для английского) на этом Маке: Lumen берёт его Python и модели,
/// см. VoiceBackend. Запись идёт, пока говоришь; каждые ~1,3 с она разбирается заново, поэтому слова появляются по ходу речи,
/// а при остановке разбирается вся запись целиком — с запятыми и заглавными
@MainActor @Observable
final class VoiceInput {
    enum State: Equatable {
        case idle
        /// Ждём разрешения и включаем микрофон
        case starting
        case listening
        /// Микрофон выключен, ждём разбор всей записи
        case finishing
        case problem(VoiceBackend.Problem)
    }

    private(set) var state: State = .idle
    /// Громкость 0…1 — кольцо вокруг кнопки дышит вместе с голосом
    private(set) var level: Double = 0

    var listening: Bool { state == .listening }
    var busy: Bool { state == .starting || state == .listening }

    private let recorder = VoiceRecorder()
    private var base = ""
    private var lang = "ru"
    private var onText: (String) -> Void = { _ in }
    /// Номер попытки: ответы от прошлых попыток (остановили, начали заново) игнорируются
    private var generation = 0
    private var partialTask: Task<Void, Never>?

    /// К тому, что уже было в поле, дописать сказанное — через пробел, если надо
    nonisolated static func merged(base: String, transcript: String) -> String {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return base }
        if base.isEmpty || base.hasSuffix(" ") || base.hasSuffix("\n") { return base + t }
        return base + " " + t
    }

    /// «ru-RU» → «ru»: язык модели
    nonisolated static func modelLanguage(_ locale: String) -> String { locale.hasPrefix("en") ? "en" : "ru" }

    /// Нажали на микрофон: идёт запись — закончить, иначе начать. `base` — что уже в поле, `onText` получает поле целиком
    func toggle(base: String, language: String, onText: @escaping (String) -> Void) {
        if busy { stop(); return }
        start(base: base, language: language, onText: onText)
    }

    func start(base: String, language: String, onText: @escaping (String) -> Void) {
        guard state == .idle || { if case .problem = state { true } else { false } }() else { return }
        let lang = Self.modelLanguage(language)
        if let problem = VoiceBackend.problem(for: lang) { state = .problem(problem); return }
        generation += 1
        let gen = generation
        self.base = base
        self.lang = lang
        self.onText = onText
        state = .starting
        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard gen == generation, state == .starting else { return }
            guard granted else {
                state = .problem(.init(text: "Нет доступа к микрофону. Разреши Lumen в «Системные настройки → Конфиденциальность → Микрофон»",
                                       buttonTitle: "Открыть настройки",
                                       url: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")))
                return
            }
            do {
                try recorder.start { [weak self] v in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.hear(v, gen: gen) } }
                }
            } catch {
                state = .problem(.init(text: "Не нашёл микрофон", buttonTitle: nil, url: nil))
                return
            }
            state = .listening
            // модель грузится при первой диктовке — пока говоришь, она уже поднимается
            let lang = self.lang
            Task.detached { _ = await VoiceBackend.shared.transcribe([Float](repeating: 0, count: 8000), lang: lang) }
            partialTask = Task { await self.partials(gen: gen) }
        }
    }

    /// Пока идёт запись: каждые ~1,3 с разобрать то, что уже сказано, и показать в поле
    private func partials(gen: Int) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1300))
            guard gen == generation, state == .listening else { return }
            let samples = recorder.snapshot()
            // короткое — рано, длинное — дольше разбирать, чем говорить: его разберут целиком при остановке
            guard samples.count > 12_000, samples.count < 16_000 * 40 else { continue }
            let text = await VoiceBackend.shared.transcribe(samples, lang: lang)
            guard gen == generation, state == .listening, let text, !text.isEmpty else { continue }
            onText(Self.merged(base: base, transcript: text))
        }
    }

    /// Закончить: микрофон выключается, вся запись разбирается ещё раз — уже целиком
    func stop() {
        switch state {
        case .listening:
            state = .finishing
            level = 0
            partialTask?.cancel()
            let samples = recorder.stop()
            let gen = generation
            let lang = lang
            Task {
                let text = await VoiceBackend.shared.transcribe(samples, lang: lang)
                guard gen == generation, state == .finishing else { return }
                if let text {
                    if !text.isEmpty { onText(Self.merged(base: base, transcript: text)) }
                    state = .idle
                } else {
                    state = .problem(.init(text: "Не вышло разобрать речь — FlowLocal не ответил", buttonTitle: nil, url: nil))
                }
            }
        case .starting:
            cancel()
        default:
            break
        }
    }

    /// Бросить: ничего больше в поле не попадёт (сообщение отправили, поле закрылось)
    func cancel() {
        generation += 1
        partialTask?.cancel()
        _ = recorder.stop()
        level = 0
        if state != .idle { state = .idle }
    }

    func dismissProblem() {
        if case .problem = state { state = .idle }
    }

    private func hear(_ v: Double, gen: Int) {
        guard gen == generation, state == .listening else { return }
        // плавно: резкие скачки кольца глаз не любит
        level = level * 0.6 + v * 0.4
    }
}

/// Запись с микрофона в 16 кГц моно float32 — как ждёт распознавание
final class VoiceRecorder: @unchecked Sendable {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []

    static let sampleRate = 16000.0

    func start(onLevel: @escaping @Sendable (Double) -> Void) throws {
        _ = stop()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else { throw NSError(domain: "lumen.voice", code: 1) }
        converter.downmix = true
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let cap = AVAudioFrameCount(Double(buffer.frameLength) * Self.sampleRate / inFormat.sampleRate + 64)
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
            var fed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let ch = out.floatChannelData else { return }
            let chunk = Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
            self.lock.withLock { self.samples.append(contentsOf: chunk) }
            if !chunk.isEmpty {
                let rms = (chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count)).squareRoot()
                onLevel(Double(min(1, rms * 9)))
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    /// Что записано на сию минуту (запись идёт дальше)
    func snapshot() -> [Float] { lock.withLock { samples } }

    /// Останавливает запись и отдаёт всё записанное
    func stop() -> [Float] {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        return lock.withLock { samples }
    }
}

/// Лазерная полоса по нижней кромке поля, пока идёт диктовка (Рома, 27.10): видно, что Lumen слушает. Тонкая светящаяся
/// черта плывёт туда-сюда; чем громче голос, тем она ярче и длиннее. Пока разбирается запись — бегает быстро и тише
struct LaserLine: View {
    var level: Double
    var processing = false

    @Environment(\.palette) private var p

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let period = processing ? 0.8 : 2.4
            let phase = t.truncatingRemainder(dividingBy: period) / period
            // 0 → 1 → 0 мягко, без рывка на краях
            let pos = 0.5 - 0.5 * cos(phase * 2 * .pi)
            GeometryReader { g in
                let len = max(64, g.size.width * (0.18 + 0.2 * level))
                ZStack(alignment: .bottomLeading) {
                    Capsule()
                        .fill(LinearGradient(colors: [p.glow.opacity(0), p.glow, p.glow.opacity(0)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: len, height: 2)
                        .shadow(color: p.glow.opacity(0.9), radius: 4)
                        .shadow(color: p.glow.opacity(0.45), radius: 12)
                        .opacity(processing ? 0.55 : 0.65 + 0.35 * level)
                        .offset(x: (g.size.width - len) * pos)
                        .padding(.bottom, 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}
