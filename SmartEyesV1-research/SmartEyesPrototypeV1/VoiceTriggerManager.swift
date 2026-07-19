import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
public class VoiceTriggerManager: ObservableObject {
    public static let shared = VoiceTriggerManager()
    
    @Published public var isListening: Bool = false
    @Published public var isAuthorized: Bool = false
    @Published public var errorText: String? = nil
    @Published public var lastSpokenText: String = ""
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var onTrigger: (() -> Void)?
    private var lastTriggerTime = Date.distantPast
    private let cooldownDuration: TimeInterval = 4.0
    private var lastTriggeredTranscriptLength = 0
    
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
        if !authorized {
            errorText = "Microphone and Speech Recognition permissions are required for Voice Trigger."
        } else {
            errorText = nil
        }
        return authorized
    }
    
    /// Starts the voice trigger listener
    public func startListening(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        
        guard isAuthorized else {
            Task {
                let granted = await requestPermissions()
                if granted {
                    self.startAudioEngine()
                }
            }
            return
        }
        
        startAudioEngine()
    }
    
    /// Stops the voice trigger listener
    public func stopListening() {
        stopAudioEngine()
        isListening = false
    }
    
    // MARK: - Internal Audio Engine Setup
    
    private func startAudioEngine() {
        guard !audioEngine.isRunning else { return }
        
        // Reset state
        errorText = nil
        lastSpokenText = ""
        lastTriggeredTranscriptLength = 0
        
        // Configure the audio session for recording
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
        
        // We want partial results so we can match wake words in real-time
        recognitionRequest.shouldReportPartialResults = true
        
        // Setup input node tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Remove tap if already installed to avoid crashes
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, when in
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
                    let transcript = result.bestTranscription.formattedString
                    self.lastSpokenText = transcript
                    self.checkForWakeWords(in: transcript)
                }
                
                if let error = error {
                    print("Speech recognition update error: \(error.localizedDescription)")
                    let nsError = error as NSError
                    if self.isListening && (nsError.domain == "kAFAssistantErrorDomain" || nsError.code != 4) {
                        // Reconnect with a 1-second delay to let speechd clean up resources
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            self?.restartSession()
                        }
                    }
                }
            }
        }
    }
    
    private func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        lastTriggeredTranscriptLength = 0
        
        // Re-configure audio session category back to playback (so SpeechManager can speak)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .voicePrompt, options: [.allowBluetoothA2DP, .duckOthers])
        try? audioSession.setActive(true)
    }
    
    /// Restarts the speech recognition request session without stopping the whole audio engine (prevents stutter)
    private func restartSession() {
        guard isListening else { return }
        
        // Stop current task and clear request
        recognitionTask?.cancel()
        recognitionTask = nil
        lastSpokenText = ""
        lastTriggeredTranscriptLength = 0
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        guard let recognitionRequest = recognitionRequest,
              let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else { return }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            Task { @MainActor in
                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    self.lastSpokenText = transcript
                    self.checkForWakeWords(in: transcript)
                }
                if let error = error {
                    let nsError = error as NSError
                    if self.isListening && nsError.code != 4 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                            self?.restartSession()
                        }
                    }
                }
            }
        }
    }
    
    /// Analyzes the recognized transcript for wake words using character offset slicing
    private func checkForWakeWords(in text: String) {
        let lower = text.lowercased()
        
        // If the speech recognition session reset naturally or got restarted,
        // sync the tracking offset index back to 0.
        if lower.count < lastTriggeredTranscriptLength {
            lastTriggeredTranscriptLength = 0
        }
        
        guard lower.count > lastTriggeredTranscriptLength else { return }
        
        // Get the substring of newly spoken text since the last successfully triggered phrase
        let startIndex = lower.index(lower.startIndex, offsetBy: lastTriggeredTranscriptLength)
        let substring = String(lower[startIndex...])
        
        let wakeWords = ["inspect"]
        
        for word in wakeWords {
            if substring.contains(word) {
                let now = Date()
                if now.timeIntervalSince(lastTriggerTime) > cooldownDuration {
                    lastTriggerTime = now
                    lastTriggeredTranscriptLength = lower.count // Update tracking offset to block duplicate fires
                    print("VoiceTriggerManager: Wake word detected! (\(word)) in substring: '\(substring)'")
                    
                    self.onTrigger?()
                }
                break
            }
        }
    }
}
