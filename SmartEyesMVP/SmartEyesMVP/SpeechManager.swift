import Foundation
import AVFoundation
import Combine

@MainActor
public class SpeechManager: ObservableObject {
    public static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published public var isVoiceEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isVoiceEnabled, forKey: "isVoiceEnabled")
            if !isVoiceEnabled {
                stop()
            }
        }
    }
    
    private init() {
        // Default to false but load user's previous preference
        self.isVoiceEnabled = UserDefaults.standard.bool(forKey: "isVoiceEnabled")
    }
    
    /// Cleans formatting and speaks the provided text content
    public func speak(_ text: String) {
        guard isVoiceEnabled else { return }
        
        // Strip out common markdown symbols like asterisks, bullet points, headers, or code blocks for cleaner narration
        var cleanText = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: " - ", with: ", ")
            .replacingOccurrences(of: "\n", with: ". ")
        
        // Remove duplicate dots
        while cleanText.contains("..") {
            cleanText = cleanText.replacingOccurrences(of: "..", with: ".")
        }
        
        let trimmed = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        // Configure AVAudioSession to allow playback even if phone is on silent switch (within reason)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .voicePrompt, options: [.allowBluetoothA2DP, .duckOthers])
        try? audioSession.setActive(true)
        
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.52 // Slightly slower pace for clarity in noisy settings
        utterance.pitchMultiplier = 1.0
        
        synthesizer.speak(utterance)
    }
    
    public func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
