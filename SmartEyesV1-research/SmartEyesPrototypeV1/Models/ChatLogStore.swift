import Foundation
import Combine

/// Holds the chat/audit transcript shared between the Inspection tab (which appends to it on
/// every trigger) and the Audit Log tab (which displays it and can purge it). V1's flow doesn't
/// hand a photo across tabs the way MVP's does — `triggerInspection` captures, analyzes, and
/// logs in one go — so this is a much thinner shared object than MVP's `InspectionSessionState`.
@MainActor
final class ChatLogStore: ObservableObject {
    static let welcomeMessage = MessageItem(
        timestamp: Date().addingTimeInterval(-60),
        isUser: false,
        text: "Welcome to Smart Eyes. Connect your Meta Glasses and select an inspection mode to begin your compliance audit.",
        imageThumbnail: nil
    )

    @Published var chatHistory: [MessageItem] = [ChatLogStore.welcomeMessage]

    /// Wipes the log back down to just the welcome message. Called when telemetry is purged.
    func reset() {
        chatHistory = [ChatLogStore.welcomeMessage]
    }
}
