import Foundation

/// A selectable Gemini/Gemma model, shown in the "AI model" settings screen and passed straight
/// through to Firebase AI Logic's `generativeModel(modelName:)`. Add, remove, or rename models
/// by editing `.all` below — nothing else in the app needs to change.
///
/// NOTE: this list previously drifted out of sync with the MVP project's copy (this file used to
/// be a separate hardcoded `Picker` list with 3 fewer entries). Keeping the catalog in its own
/// file like this makes it easy to eyeball whether the two projects' model lists still match.
public struct GeminiModel: Identifiable, Hashable {
    /// The exact model name Firebase AI Logic expects, e.g. "gemini-3.5-flash". This is what
    /// gets persisted to `UserDefaults` and sent to the API — keep it exact.
    public let id: String
    /// Human-readable label shown in the picker.
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public extension GeminiModel {
    static let all: [GeminiModel] = [
        GeminiModel(id: "gemini-3.5-flash", displayName: "Gemini 3.5 Flash"),
        GeminiModel(id: "gemini-3.1-flash-lite", displayName: "Gemini 3.1 Flash Lite"),
        GeminiModel(id: "gemini-3.1-flash-lite-preview", displayName: "Gemini 3.1 Flash Lite Preview"),
        GeminiModel(id: "gemini-3-flash-preview", displayName: "Gemini 3 Flash Preview"),
        GeminiModel(id: "gemini-flash-lite-latest", displayName: "Gemini Flash Lite Latest"),
        GeminiModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
        GeminiModel(id: "gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite"),
        GeminiModel(id: "gemini-robotics-er-1.6-preview", displayName: "Gemini Robotics-ER 1.6 Preview"),
        GeminiModel(id: "gemma-4-26b-a4b-it", displayName: "Gemma 4 26B (MoE)"),
        GeminiModel(id: "gemma-4-31b-it", displayName: "Gemma 4 31B (Dense)")
    ]

    /// Used whenever no model has been configured yet (fresh install / empty UserDefaults).
    static let `default` = GeminiModel.all[0]

    /// Looks up a model by its raw id, e.g. for validating a value read back from UserDefaults.
    static func find(id: String) -> GeminiModel? {
        all.first { $0.id == id }
    }
}
