import Foundation
import Speech
import AVFoundation
import Combine

/// Captures a single spoken question from the user (no wake word — explicit start/stop),
/// used in the MVP flow after a photo has been taken: the user taps the mic, asks their
/// question, taps stop, reviews/edits the transcript, then sends it for analysis.
@MainActor
public class VoiceQuestionManager: ObservableObject {
    public static let shared = VoiceQuestionManager()

    @Published public var isListening: Bool = false
    @Published public var isAuthorized: Bool = false
    @Published public var liveTranscript: String = ""
    @Published public var errorText: String? = nil

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private init() {
        checkAuthorizationStatus()
    }

    /// Checks the current authorization status of speech recognition and microphone
    public func checkAuthorizationStatus() {
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        let micAuth = AVAudioSession.sharedInstance().recordPermission
        self.isAuthorized = (speechAuth == .authorized && micAuth == .granted)
    }

    /// Requests speech recognition and microphone permissions from the user
    public func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        let micStatus = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let authorized = (speechStatus == .authorized && micStatus)
        isAuthorized = authorized
        errorText = authorized ? nil : "Microphone and Speech Recognition permissions are required to ask a question."
        return authorized
    }

    /// Starts capturing a spoken question. Call `stopAndFinish()` to end and get the transcript,
    /// or `cancel()` to discard it.
    public func startListening() {
        liveTranscript = ""
        errorText = nil

        guard isAuthorized else {
            Task {
                let granted = await requestPermissions()
                if granted {
                    self.beginAudioSession()
                }
            }
            return
        }

        beginAudioSession()
    }

    /// Stops recording and returns the finalized (trimmed) transcript text.
    @discardableResult
    public func stopAndFinish() -> String {
        let finalText = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        teardownAudio()
        return finalText
    }

    /// Cancels the current recording session, discarding whatever was transcribed so far.
    public func cancel() {
        teardownAudio()
        liveTranscript = ""
    }

    // MARK: - Internal Audio Engine Setup

    private func beginAudioSession() {
        guard !audioEngine.isRunning else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.errorText = "Audio Session Error: \(error.localizedDescription)"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            self.errorText = "Unable to create speech recognition request."
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            self.errorText = "Audio Engine failed to start: \(error.localizedDescription)"
            return
        }

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            self.errorText = "Speech recognizer is not available or offline."
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            Task { @MainActor in
                if let result = result {
                    self.liveTranscript = result.bestTranscription.formattedString
                }

                if let error = error {
                    // Code 4 / 216 are benign "no speech"/cancellation errors triggered by
                    // intentionally stopping the session — don't surface those to the UI.
                    let nsError = error as NSError
                    if self.isListening && nsError.code != 4 && nsError.code != 216 {
                        print("VoiceQuestionManager recognition error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func teardownAudio() {
        guard isListening || audioEngine.isRunning else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        // Re-configure audio session category back to playback (so SpeechManager can speak the answer)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .voicePrompt, options: [.allowBluetoothA2DP, .duckOthers])
        try? audioSession.setActive(true)
    }
}
