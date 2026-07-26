import Foundation
import UIKit
import Combine
import FirebaseAILogic
import FirebaseCore

// `Phase` (the Phase 1-3 prompt catalog) now lives in PhaseCatalog.swift, and the selectable
// model list lives in GeminiModelCatalog.swift — both are just data this class reads from, so
// they don't need to sit in the same file as the networking logic below. Adding a new phase no
// longer touches this file at all: just append to `Phase.all`.

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

    private init() {
        self.selectedModel = UserDefaults.standard.string(forKey: "GEMINI_MODEL_NAME") ?? GeminiModel.default.id
    }

    public func updateModel(_ modelName: String) {
        self.selectedModel = modelName
    }

    /// Analyzes the captured frame using the Firebase AI Logic SDK (Gemini Developer API).
    /// Falls back to a simulated response if Firebase is not configured.
    public func analyzeFrame(image: UIImage, phase: Phase, customPrompt: String? = nil) async -> String {
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
        // fall back to simulated inspection responses for development/simulator testing.
        guard hasAPIKey else {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            var mockRes = generateMockResponse(for: phase)
            if let custom = customPrompt {
                mockRes = "(SIMULATION - Command: \"\(custom)\")\n\n\(mockRes)"
            }
            self.lastResponseTime = Date().timeIntervalSince(startTime)
            self.analysisResult = mockRes
            self.isAnalyzing = false
            return mockRes
        }

        let modelName = self.selectedModel

        // System instruction comes straight from the selected phase's catalog entry.
        let systemInstruction = phase.systemInstruction

        // Initialize Firebase AI Logic with the Gemini Developer API backend.
        // The API key is managed by Firebase — never hardcoded here.
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())
        let model = ai.generativeModel(
            modelName: modelName,
            systemInstruction: ModelContent(parts: [TextPart(systemInstruction)])
        )

        // Pre-process image: Downsize to reduce upload payload and improve latency
        guard let imageData = compressImageForAPI(image: image) else {
            self.isAnalyzing = false
            self.analysisResult = "Error: Failed to process image payload."
            return self.analysisResult
        }

        do {
            let prompt: String
            if let custom = customPrompt, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prompt = custom
            } else {
                prompt = phase.defaultPrompt
            }

            // Send image as inline data + text prompt.
            // NOTE: The old SDK accepted UIImage directly; Firebase AI Logic uses InlineDataPart.
            let response = try await model.generateContent([
                InlineDataPart(data: imageData, mimeType: "image/jpeg"),
                TextPart(prompt)
            ])
            let responseText = response.text ?? "Error: Empty response received."

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

    /// Generates a local mock reply (for simulator testing without Firebase configured) by
    /// picking randomly from the selected phase's `mockResponses`.
    private func generateMockResponse(for phase: Phase) -> String {
        "(SIMULATION) " + (phase.mockResponses.randomElement() ?? "")
    }
}
