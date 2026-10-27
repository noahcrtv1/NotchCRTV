import AVFoundation
import Speech

/// Ditado PT-BR (no dispositivo quando possível).
@MainActor
final class Voice: ObservableObject {
    @Published var listening = false
    @Published var error: String?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    var onText: (String) -> Void = { _ in }

    func toggle() { listening ? stop() : start() }

    func start() {
        error = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { self.error = "Permita Reconhecimento de Fala em Ajustes do Sistema"; return }
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    Task { @MainActor in
                        if ok { self.begin() } else { self.error = "Permita o Microfone em Ajustes do Sistema" }
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else { error = "Reconhecimento indisponível"; return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in req.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { self.error = "Microfone: \(error.localizedDescription)"; return }
        listening = true
        task = recognizer.recognitionTask(with: req) { result, err in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                if let text { self.onText(text) }
                if err != nil || final { self.stop() }
            }
        }
    }

    func stop() {
        guard listening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil; request = nil
        listening = false
    }
}
