import SwiftUI
import AVFoundation
import Speech

struct VoiceView: View {
    let language: String
    @StateObject private var speech = SpeechSession()

    var body: some View {
        Form {
            Section {
                TextEditor(text: $speech.transcript)
                    .frame(minHeight: 150)
                    .accessibilityLabel(L("Transcript", "Расшифровка"))
                Button(speech.recording ? L("Stop recording", "Остановить запись") : L("Record", "Записать")) {
                    if speech.recording { speech.stop() } else { Task { await speech.start(language) } }
                }
                Button(L("Save to keyboard", "Сохранить для клавиатуры")) {
                    do {
                        try SharedStore.write(speech.transcript, "dictation.json")
                        speech.message = L("Open Dictation on the keyboard to insert the transcript.",
                                           "Откройте Диктовку на клавиатуре, чтобы вставить расшифровку.")
                    } catch { speech.message = error.localizedDescription }
                }
                .disabled(speech.transcript.isEmpty || speech.recording)
                if !speech.message.isEmpty { Text(speech.message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(L("Dictation", "Диктовка"))
        .onDisappear { speech.stop() }
    }
}

@MainActor
final class SpeechSession: ObservableObject {
    @Published var transcript = ""
    @Published var recording = false
    @Published var message = ""
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var hasTap = false
    private var run = UUID()

    func start(_ locale: String) async {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard speech == .authorized, microphone else { message = L("Allow Speech Recognition and Microphone in Settings.",
                                                                       "Разрешите распознавание речи и микрофон в Настройках."); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            message = L("Speech recognition is unavailable for this language.", "Распознавание этого языка недоступно.")
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            stop()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let buffer = SFSpeechAudioBufferRecognitionRequest()
            buffer.shouldReportPartialResults = true
            buffer.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request = buffer
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 && format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { data, _ in buffer.append(data) }
            hasTap = true
            engine.prepare()
            try engine.start()
            transcript = ""
            message = ""
            recording = true
            let current = run
            task = recognizer.recognitionTask(with: buffer) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self, self.run == current else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if result?.isFinal == true || error != nil {
                        self.stop()
                        if let error { self.message = error.localizedDescription }
                    }
                }
            }
        } catch {
            stop()
            message = error.localizedDescription
        }
    }

    func stop() {
        run = UUID()
        if engine.isRunning { engine.stop() }
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
