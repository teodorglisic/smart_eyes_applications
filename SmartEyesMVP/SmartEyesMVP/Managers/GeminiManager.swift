import Foundation
import UIKit
import Combine
import FirebaseAILogic
import FirebaseCore

// `UseCase` (the pipe/gauge/anomaly/SUVA prompt catalog) now lives in UseCaseCatalog.swift, and
// the selectable model list lives in GeminiModelCatalog.swift — both are just data this class
// reads from, so they don't need to sit in the same file as the networking logic below.

@MainActor
public class GeminiManager: ObservableObject {
    public static let shared = GeminiManager()

    @Published public var isAnalyzing: Bool = false
    @Published public var selectedModel: String = GeminiModel.default.id

    // Firebase AI Logic manages the API key server-side via GoogleService-Info.plist.
    // This property now reflects whether Firebase is configured rather than whether
    // a raw API key is present in the app. The Settings UI for manual key entry
    // can be removed or repurposed once Firebase is fully set up.
    public var hasAPIKey: Bool {
        return FirebaseApp.app() != nil
    }

    @Published public var analysisResult: String = ""
    @Published public var lastResponseTime: Double = 0.0
    @Published public var lastInputTokens: Int? = nil
    @Published public var lastTextInputTokens: Int? = nil
    @Published public var lastImageInputTokens: Int? = nil
    @Published public var lastOutputTokens: Int? = nil
    @Published public var lastTotalTokens: Int? = nil
    @Published public var lastThinkingTokens: Int? = nil

    // Keeps the multi-turn conversation alive so follow-up questions about the same
    // captured photo have context from earlier turns, without needing to resend the image.
    private var activeChat: Chat? = nil
    private var activeChatUseCaseId: String? = nil

    private init() {
        self.selectedModel = UserDefaults.standard.string(forKey: "GEMINI_MODEL_NAME") ?? GeminiModel.default.id
    }

    public func updateModel(_ modelName: String) {
        self.selectedModel = modelName
    }

    /// Ends the current photo's conversation. Call this whenever the user retakes a photo
    /// or switches use case, so the next `analyzeFrame` call starts a fresh chat rather than
    /// dragging stale context (or a mismatched photo) into a new conversation.
    public func startNewConversation() {
        activeChat = nil
        activeChatUseCaseId = nil
    }

    /// Retries `operation` only for the genuinely transient "high demand" case (HTTP 500/503 —
    /// the model is momentarily overloaded and a retry can plausibly succeed).
    ///
    /// NOTE: Firebase AI Logic wraps *every* backend HTTP error (404 model retired, 429 quota
    /// exhausted, 500/503 overloaded, etc.) into the same `GenerateContentError.internalError`
    /// case — there's no dedicated case per HTTP status. So matching on the case alone would
    /// also retry 404s (pointless — the model is permanently gone) and 429s (counterproductive —
    /// hammering an already-exhausted quota). `BackendError` (the underlying type that actually
    /// carries the HTTP status) is an internal SDK type we can't downcast to directly, but it
    /// conforms to `CustomNSError` with `errorCode == httpResponseCode`, so bridging through
    /// `NSError` gets us the real status code without needing SDK-internal access.
    private func withTransientErrorRetry(
        maxAttempts: Int = 3,
        _ operation: () async throws -> GenerateContentResponse
    ) async throws -> GenerateContentResponse {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch let error as GenerateContentError {
                guard case .internalError(let underlying) = error, attempt < maxAttempts else { throw error }
                let httpStatusCode = (underlying as NSError).code
                guard httpStatusCode == 500 || httpStatusCode == 503 else { throw error }
                let delaySeconds = Double(attempt) * 2.0
                self.analysisResult = "Model is under high demand, retrying (\(attempt)/\(maxAttempts - 1))..."
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                attempt += 1
            }
        }
    }

    /// Analyzes the captured frame using the Firebase AI Logic SDK (Gemini Developer API).
    ///
    /// - Parameter isFollowUp: pass `true` to continue the existing conversation about the
    ///   same photo (no need to resend image data — Gemini already has it from turn one).
    ///   Pass `false` (default) to start a brand-new conversation anchored to `image`.
    public func analyzeFrame(image: UIImage, useCase: UseCase, customPrompt: String? = nil, isFollowUp: Bool = false) async -> String {
        self.isAnalyzing = true
        self.analysisResult = "Analyzing frame..."
        self.lastInputTokens = nil
        self.lastTextInputTokens = nil
        self.lastImageInputTokens = nil
        self.lastOutputTokens = nil
        self.lastTotalTokens = nil
        self.lastThinkingTokens = nil

        let startTime = Date()

        // If Firebase isn't configured (no GoogleService-Info.plist / FirebaseApp.configure()),
        // surface that clearly instead of silently faking a result.
        guard hasAPIKey else {
            self.lastResponseTime = Date().timeIntervalSince(startTime)
            self.isAnalyzing = false
            let errorRes = "Error: Firebase is not configured — add GoogleService-Info.plist to this project to enable AI analysis (see SETUP.md)."
            self.analysisResult = errorRes
            return errorRes
        }

        let modelName = self.selectedModel

        // System instruction comes straight from the selected use case's context prompt.
        let systemInstruction = useCase.systemInstruction

        do {
            let prompt: String
            if let custom = customPrompt, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prompt = custom
            } else {
                prompt = useCase.defaultPrompt
            }

            let response: GenerateContentResponse

            if isFollowUp, let chat = activeChat, activeChatUseCaseId == useCase.id {
                // Continue the existing conversation — Gemini already has the photo from turn one.
                response = try await withTransientErrorRetry {
                    try await chat.sendMessage([TextPart(prompt)])
                }
            } else {
                // Starting fresh: pre-process the image, open a new chat session, and send
                // the image + prompt together as the first turn.
                guard let imageData = compressImageForAPI(image: image) else {
                    self.isAnalyzing = false
                    self.analysisResult = "Error: Failed to process image payload."
                    return self.analysisResult
                }

                // Initialize Firebase AI Logic with the Gemini Developer API backend.
                // The API key is managed by Firebase — never hardcoded here.
                let ai = FirebaseAI.firebaseAI(backend: .googleAI())
                let model = ai.generativeModel(
                    modelName: modelName,
                    // Use cases like Workplace Safety (SUVA) need live web results, not just the
                    // model's training data, so attach Google Search grounding when requested.
                    // NOTE: only a subset of Gemini models support grounding (see
                    // https://firebase.google.com/docs/ai-logic/grounding-google-search#supported-models)
                    // — behavior with an unsupported model isn't verified here, so test this
                    // combination before relying on it.
                    tools: useCase.usesGoogleSearch ? [Tool.googleSearch()] : nil,
                    systemInstruction: ModelContent(parts: [TextPart(systemInstruction)])
                )

                let chat = model.startChat()
                self.activeChat = chat
                self.activeChatUseCaseId = useCase.id

                // Send image as inline data + text prompt.
                // NOTE: The old SDK accepted UIImage directly; Firebase AI Logic uses InlineDataPart.
                response = try await withTransientErrorRetry {
                    try await chat.sendMessage([
                        InlineDataPart(data: imageData, mimeType: "image/jpeg"),
                        TextPart(prompt)
                    ])
                }
            }

            var responseText = response.text ?? "Error: Empty response received."

            // If this use case is grounded in Google Search and the model actually used it,
            // surface the sources — Gemini API usage terms require showing where a grounded
            // answer's claims came from. (NOTE: this only lists sources as plain text; full
            // compliance also calls for rendering the "Google Search suggestions" widget from
            // groundingMetadata.searchEntryPoint.renderedContent, which needs a WebView and
            // isn't wired up here yet.)
            if useCase.usesGoogleSearch,
               let candidate = response.candidates.first,
               let groundingMetadata = candidate.groundingMetadata,
               !groundingMetadata.groundingChunks.isEmpty {
                let sourceLines = groundingMetadata.groundingChunks.compactMap { chunk -> String? in
                    guard let web = chunk.web else { return nil }
                    return "- \(web.title): \(web.uri)"
                }
                if !sourceLines.isEmpty {
                    responseText += "\n\nSources:\n" + sourceLines.joined(separator: "\n")
                }
            }

            if let usage = response.usageMetadata {
                self.lastInputTokens = usage.promptTokenCount
                self.lastOutputTokens = usage.candidatesTokenCount
                self.lastTotalTokens = usage.totalTokenCount
                self.lastThinkingTokens = usage.thoughtsTokenCount

                // Break out input tokens by modality directly from the SDK
                for detail in usage.promptTokensDetails ?? [] {
                    switch detail.modality.rawValue {
                    case "TEXT":
                        self.lastTextInputTokens = detail.tokenCount
                    case "IMAGE":
                        self.lastImageInputTokens = detail.tokenCount
                    default:
                        break
                    }
                }
            }

            self.lastResponseTime = Date().timeIntervalSince(startTime)
            self.analysisResult = responseText
            self.isAnalyzing = false
            return responseText

        } catch {
            self.isAnalyzing = false
            var errorDetails = error.localizedDescription
            if let genAIError = error as? GenerateContentError {
                // NOTE: Firebase AI Logic replaced most enums with structs, so a
                // `default:` case is now required to cover unknown/future values.
                switch genAIError {
                case .internalError(let underlying):
                    errorDetails = "Internal Error: \(underlying.localizedDescription) (Underlying: \(underlying))"
                case .promptImageContentError(let underlying):
                    errorDetails = "Prompt/Image Content Error: \(underlying.localizedDescription)"
                case .promptBlocked:
                    errorDetails = "Prompt blocked by safety settings."
                case .responseStoppedEarly(let reason, _):
                    errorDetails = "Response stopped early. Reason: \(reason)"
                default:
                    errorDetails = "Generative AI Error: \(error)"
                }
            }
            self.analysisResult = "API Error: \(errorDetails)"
            print("Firebase AI call failed: \(error)")
            return self.analysisResult
        }
    }

    // MARK: - Helper Utilities

    /// Compresses and resizes the image for low-bandwidth scenarios.
    /// Returns raw JPEG Data (no longer needs to wrap back into UIImage).
    private func compressImageForAPI(image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1920.0
        var targetSize = image.size

        if image.size.width > maxDimension || image.size.height > maxDimension {
            if image.size.width > image.size.height {
                let ratio = maxDimension / image.size.width
                targetSize = CGSize(width: maxDimension, height: image.size.height * ratio)
            } else {
                let ratio = maxDimension / image.size.height
                targetSize = CGSize(width: image.size.width * ratio, height: maxDimension)
            }
        }

        UIGraphicsBeginImageContext(targetSize)
        image.draw(in: CGRect(origin: .zero, size: targetSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage?.jpegData(compressionQuality: 0.95)
    }

}
