import AVFoundation
import FluidAudio
import Observation

// ═══════════ DictationEngine — распознавание речи на устройстве ═══════════
//
// Просьба владельца 03.09.2026: «подключи уже искусственный интеллект, то
// есть распознавание речи». До этого коммита `micKeyboardBar` в
// `NoteEditorScreen`/`TaskFormScreen` был чистой декорацией (`Button {}` —
// см. их комментарии) — «в проекте нигде нет живого ASR-провода на native»
// (было честно задокументировано, не мой недосмотр).
//
// Движок — NVIDIA Parakeet TDT v3 (0.6B, мультиязычный, 25 языков + русский)
// через `FluidAudio` (SPM, `argmaxinc`-соседний проект `FluidInference`,
// CoreML-порт, инференс на ANE). Владелец сам назвал эту модель — «маленькая,
// все хвалят, мультиязычная» — и явно попросил НЕ городить пикер из
// нескольких движков/размеров («не надо прям все это туда пикать это лишняя
// информация мне»): один хороший движок вместо трёх помельче нарезанных.
// WhisperKit не взят — Parakeet TDT v3 уже на голову быстрее (ANE, ~150-190x
// realtime) при сравнимом или лучшем качестве, и не тащит отдельной загрузки
// на 200МБ-1.5ГБ под каждый размер.
//
// Батч, не стриминг: жмём микрофон — пишем в буфер, отпускаем — одним
// вызовом `transcribe()` получаем готовый текст. Живых частичных результатов
// по ходу диктовки нет (FluidAudio даёт `SlidingWindowAsrManager` для этого,
// но для диктовки задачи/абзаца в заметке ждать 1-3 секунды после короткой
// фразы — не проблема, а стриминг — отдельный кусок сложности не по цели
// этой правки).
@MainActor
@Observable
public final class DictationEngine {
    public static let shared = DictationEngine()

    public enum ModelState: Equatable {
        case unknown
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    public enum RecordingState: Equatable {
        case idle
        case recording
        case transcribing
        case failed(String)
    }

    /// Какую версию Parakeet держим на телефоне. Владелец 20.09.2026:
    /// «пусть будет лёгкая и тяжёлая — двух моделей достаточно». Английскую
    /// v2 не показываем вовсе: русский она не понимает.
    public enum ModelChoice: String, CaseIterable, Identifiable, Sendable {
        case tdtCtc110m
        case v3

        public var id: String { rawValue }

        var version: AsrModelVersion {
            switch self {
            case .v3: .v3
            case .tdtCtc110m: .tdtCtc110m
            }
        }

        public var displayName: String {
            switch self {
            case .v3: "Parakeet TDT v3"
            case .tdtCtc110m: "Parakeet 110M"
            }
        }

        public var note: String {
            switch self {
            case .v3: "тяжёлая, понимает русский"
            case .tdtCtc110m: "лёгкая и быстрая"
            }
        }
    }

    private static let selectedModelKey = "dictation.selectedModel"
    private static let enabledKey = "dictation.isEnabled"

    /// Выбранная модель переживает перезапуск: выбор владельца не должен
    /// сбрасываться к v3 при каждом входе в настройки.
    public private(set) var selectedModel: ModelChoice
    /// Диктовка на устройстве вкл/выкл. Выключена — микрофон не пишет вовсе,
    /// приложение не трогает модель (и не докачивает её втихую).
    public private(set) var isEnabled: Bool

    public private(set) var modelState: ModelState = .unknown
    public private(set) var recordingState: RecordingState = .idle
    /// Живой уровень громкости записи (0…1) — для анимации амплитуды у
    /// микрофона (LOCK-254, владелец 30.09.2026: «посмотри, как в чате
    /// работает голосовое, вырежи оттуда кусок, вставь сюда»). Тот же
    /// `VoiceWaveform.recordingLevel` с тем же асимметричным сглаживанием,
    /// что и запись голосового сообщения в чате — просто источник децибел
    /// другой (сырые PCM-сэмплы tap-колбэка вместо `AVAudioRecorder.meters`,
    /// у `DictationEngine` иной способ захвата микрофона).
    public private(set) var currentLevel: Double = 0

    /// Короткое сообщение о результате действия («Модель актуальна»,
    /// «Модель удалена»). Нужно потому, что кнопка без отклика выглядит
    /// мёртвой (замечание владельца 20.09.2026: «нажимаю, ничего не
    /// происходит, и мне непонятно, работает кнопка или нет»). Гаснет само.
    public private(set) var feedback: String?
    private var feedbackTask: Task<Void, Never>?

    private var asrManager: AsrManager?
    private var decoderState: TdtDecoderState?
    private let recorder = MicRecorder()

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.selectedModelKey) ?? ""
        selectedModel = ModelChoice(rawValue: raw) ?? .v3
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        refreshModelState()
    }

    private func showFeedback(_ text: String) {
        feedback = text
        feedbackTask?.cancel()
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { feedback = nil }
        }
    }

    // MARK: - Настройки модели

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled { cancelRecording() }
    }

    /// Замена модели: сохраняем выбор, снимаем старые веса из памяти (они не
    /// подходят новому движку) и сразу качаем, если выбранной версии нет.
    public func selectModel(_ choice: ModelChoice) async {
        guard choice != selectedModel else { return }
        selectedModel = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.selectedModelKey)
        asrManager = nil
        decoderState = nil
        refreshModelState()
        if case .notDownloaded = modelState {
            await downloadModelIfNeeded()
        }
        if case .ready = modelState {
            showFeedback("Выбрана \(choice.displayName)")
        }
    }

    /// «Проверить и обновить». FluidAudio обновления сам не сверяет, поэтому
    /// честно сообщаем по факту: весов нет — качаем; веса на месте — значит
    /// актуальны. Без сообщения кнопка выглядит нерабочей.
    public func checkModel() async {
        let hadFiles = AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: selectedModel.version),
            version: selectedModel.version
        )
        await downloadModelIfNeeded()
        switch modelState {
        case .ready: showFeedback(hadFiles ? "Модель актуальна" : "Модель скачана")
        case .failed(let message): showFeedback(message)
        default: break
        }
    }

    /// Удаление весов выбранной версии с диска. Статус пересчитывается по
    /// факту (папка), а не по флагу: прерванная загрузка флаг разъедет.
    public func deleteModel() {
        cancelRecording()
        asrManager = nil
        decoderState = nil
        let dir = AsrModels.defaultCacheDirectory(for: selectedModel.version)
        try? FileManager.default.removeItem(at: dir)
        refreshModelState()
        showFeedback("Модель удалена")
    }

    // MARK: - Модель

    /// Дешёвая проверка на диске, без сети — вызывать при открытии
    /// «Модели и голоса» и при старте приложения, чтобы честно показать
    /// «скачана»/«не скачана», не имитируя.
    public func refreshModelState() {
        guard case .downloading = modelState else {
            let dir = AsrModels.defaultCacheDirectory(for: selectedModel.version)
            modelState = AsrModels.modelsExist(at: dir, version: selectedModel.version) ? .ready : .notDownloaded
            return
        }
    }

    public func downloadModelIfNeeded() async {
        if case .ready = modelState, asrManager != nil { return }
        let version = selectedModel.version
        modelState = .downloading(0)
        do {
            let models = try await AsrModels.downloadAndLoad(
                version: version,
                progressHandler: { progress in
                    Task { @MainActor in
                        if case .downloading = DictationEngine.shared.modelState {
                            DictationEngine.shared.modelState = .downloading(progress.fractionCompleted)
                        }
                    }
                }
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            asrManager = manager
            decoderState = try TdtDecoderState()
            modelState = .ready
        } catch {
            modelState = .failed(Self.message(error))
        }
    }

    // MARK: - Запись + распознавание

    /// Пуш-ту-токовый режим: жмём — пишем, ещё раз жмём (или зовём
    /// `stopRecordingAndTranscribe`) — получаем текст. Дозагружает модель
    /// сама, если она ещё не скачана (первая диктовка в жизни установки).
    public func startRecording() async {
        guard recordingState == .idle else { return }
        // Выключено в настройках — не пишем и не докачиваем модель втихую.
        guard isEnabled else {
            recordingState = .failed("Диктовка на устройстве выключена в настройках")
            return
        }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            recordingState = .failed("Нет доступа к микрофону — разрешите в Настройках iOS")
            return
        }
        if asrManager == nil {
            await downloadModelIfNeeded()
            guard asrManager != nil else { return }
        }
        do {
            currentLevel = 0
            recorder.onLevel = { [weak self] averageDecibels, peakDecibels in
                Task { @MainActor in
                    guard let self, self.recordingState == .recording else { return }
                    self.currentLevel = VoiceWaveform.recordingLevel(
                        previous: self.currentLevel,
                        averageDecibels: averageDecibels,
                        peakDecibels: peakDecibels
                    )
                }
            }
            try recorder.start()
            recordingState = .recording
        } catch {
            recordingState = .failed(Self.message(error))
        }
    }

    /// Возвращает распознанный текст (без начальных/конечных пробелов) или
    /// `nil`, если запись была пустой/слишком короткой/распознавание упало —
    /// вызывающий код просто ничего не вставляет, без модалок с ошибкой:
    /// микрофон — необязательный ускоритель ввода, а не критичный путь.
    @discardableResult
    public func stopRecordingAndTranscribe() async -> String? {
        guard recordingState == .recording else { return nil }
        let buffer = recorder.stop()
        currentLevel = 0
        guard let buffer, buffer.frameLength > 0, let asrManager, decoderState != nil else {
            recordingState = .idle
            return nil
        }
        recordingState = .transcribing
        defer { recordingState = .idle }
        do {
            var state = decoderState!
            let result = try await asrManager.transcribe(buffer, decoderState: &state, language: .russian)
            decoderState = state
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            recordingState = .failed(Self.message(error))
            return nil
        }
    }

    public func cancelRecording() {
        guard recordingState == .recording else { return }
        _ = recorder.stop()
        currentLevel = 0
        recordingState = .idle
    }

    private static func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Захват микрофона в один накопительный буфер

/// Не стриминговый — копит всю диктовку в предвыделенный `AVAudioPCMBuffer`
/// на родном формате входа (без ручного ресемплинга: `AsrManager.transcribe
/// (_ audioBuffer: AVAudioPCMBuffer, ...)` сам ресемплит в 16кГц внутри —
/// свой конвертер тут был бы дублированием чужой работы).
private final class MicRecorder {
    private let engine = AVAudioEngine()
    private var buffer: AVAudioPCMBuffer?
    private var writeOffset: AVAudioFrameCount = 0
    /// (averageDecibels, peakDecibels) по последнему tap-колбэку — вызывается
    /// на аудио-потоке, не на MainActor (см. `append` ниже).
    var onLevel: ((Float, Float) -> Void)?

    /// 90с с запасом — диктовка задачи или абзаца заметки короче на порядок;
    /// хвост, который не влез, тихо не пишется (не роняем запись целиком).
    private static let maxDuration: Double = 90

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "DictationEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Микрофон недоступен"])
        }

        let capacity = AVAudioFrameCount(format.sampleRate * Self.maxDuration)
        guard let preallocated = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw NSError(domain: "DictationEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось выделить буфер записи"])
        }
        buffer = preallocated
        writeOffset = 0

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] tapBuffer, _ in
            self?.append(tapBuffer)
        }

        engine.prepare()
        try engine.start()
    }

    /// Вызывается на аудио-потоке движка (не главном) — обычный `NSLock`
    /// вместо изоляции актором, чтобы не гонять копирование через хоп на
    /// MainActor на каждый tap-колбэк (несколько раз в секунду).
    private let lock = NSLock()

    private func append(_ tapBuffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer, let src = tapBuffer.floatChannelData, let dst = buffer.floatChannelData else { return }
        let remaining = buffer.frameCapacity - writeOffset
        let toCopy = min(remaining, tapBuffer.frameLength)
        guard toCopy > 0 else { return }
        for channel in 0..<Int(min(buffer.format.channelCount, tapBuffer.format.channelCount)) {
            (dst[channel] + Int(writeOffset)).update(from: src[channel], count: Int(toCopy))
        }
        writeOffset += toCopy
        reportLevel(src[0], frameCount: Int(tapBuffer.frameLength))
    }

    /// Децибелы из сырых сэмплов — тот же смысл, что `AVAudioRecorder`
    /// отдаёт готовым через `averagePower`/`peakPower`, но у `AVAudioEngine`
    /// tap такого нет, считаем сами: RMS → средняя громкость, максимум
    /// модуля сэмпла → пиковая.
    private func reportLevel(_ samples: UnsafeMutablePointer<Float>, frameCount: Int) {
        guard frameCount > 0, let onLevel else { return }
        var sumSquares: Float = 0
        var peakAmplitude: Float = 0
        for i in 0..<frameCount {
            let sample = samples[i]
            sumSquares += sample * sample
            peakAmplitude = max(peakAmplitude, abs(sample))
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        let averageDecibels = 20 * log10(max(rms, 1e-7))
        let peakDecibels = 20 * log10(max(peakAmplitude, 1e-7))
        onLevel(averageDecibels, peakDecibels)
    }

    func stop() -> AVAudioPCMBuffer? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        lock.lock()
        defer { lock.unlock() }
        buffer?.frameLength = writeOffset
        let result = buffer
        buffer = nil
        writeOffset = 0
        return result
    }
}
