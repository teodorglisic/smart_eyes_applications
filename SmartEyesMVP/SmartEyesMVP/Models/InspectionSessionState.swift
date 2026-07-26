import SwiftUI
import Combine

/// Holds the state that flows *between* the Inspection and Chat Log tabs: which use case is
/// selected, the photo captured in Inspection, whether a question has already been asked about
/// it, and the chat history built up across both tabs. Setup doesn't touch any of this —
/// it only reads/writes state owned by `WearableManager`/`SpeechManager`/`GeminiManager`
/// directly — so it doesn't need a reference to this class.
@MainActor
final class InspectionSessionState: ObservableObject {
    static let welcomeMessage = MessageItem(
        timestamp: Date().addingTimeInterval(-60),
        isUser: false,
        text: "Welcome to Smart Eyes. In the Inspection tab: connect your Meta Glasses, choose a use case, and take a photo. Then come back here to ask your question.",
        imageThumbnail: nil
    )

    @Published var selectedUseCase: UseCase = .pipeAnalysis
    @Published var capturedPhoto: UIImage? = nil
    @Published var hasAskedAboutCurrentPhoto = false
    @Published var isCapturingPhoto = false
    @Published var chatHistory: [MessageItem] = [InspectionSessionState.welcomeMessage]

    /// Discards the captured photo and ends its conversation, but leaves the chat history alone.
    /// Used by the Chat Log's "Cancel" button — the transcript stays, only the active photo
    /// session goes away, and the view also jumps back to the Inspection tab afterwards so a
    /// fresh photo can be captured right away.
    func retakePhoto() {
        capturedPhoto = nil
        hasAskedAboutCurrentPhoto = false
    }

    /// Wipes the chat log back down to just the welcome message and discards any in-progress
    /// photo conversation alongside it. Called when the user purges telemetry records, since a
    /// transcript referencing purged trial IDs is no longer meaningful.
    func resetForPurge() {
        chatHistory = [InspectionSessionState.welcomeMessage]
        capturedPhoto = nil
        hasAskedAboutCurrentPhoto = false
    }
}
