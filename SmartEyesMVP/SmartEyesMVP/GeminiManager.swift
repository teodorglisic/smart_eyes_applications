import Foundation
import UIKit
import Combine
import FirebaseAILogic
import FirebaseCore

/// A selectable use case: a named lens (with its own system prompt/context) that the user
/// applies to a captured photo before asking their question. New use cases can be added by
/// simply appending to `UseCase.all` — no enum/switch changes required elsewhere.
public struct UseCase: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let icon: String
    public let systemInstruction: String
    public let defaultPrompt: String
    /// When true, `GeminiManager` attaches the Google Search grounding tool so this use case
    /// can look up live, real-world information (e.g. published safety guidelines) instead of
    /// relying only on the model's trained knowledge.
    public let usesGoogleSearch: Bool

    // Explicit initializer (rather than relying on the compiler-synthesized memberwise init)
    // so `usesGoogleSearch` can have a default of `false` while still being overridable per
    // use case — existing use cases below don't need to mention it at all.
    public init(
        id: String,
        name: String,
        icon: String,
        systemInstruction: String,
        defaultPrompt: String,
        usesGoogleSearch: Bool = false
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.systemInstruction = systemInstruction
        self.defaultPrompt = defaultPrompt
        self.usesGoogleSearch = usesGoogleSearch
    }

    public static func == (lhs: UseCase, rhs: UseCase) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public extension UseCase {
    /// Shared "safe failure" instruction appended to every use case's system prompt: tells the
    /// model to say *why* it can't answer (out of frame, too dark, obstructed, etc.) instead of
    /// guessing. Kept as a single shared string so every use case — including future ones —
    /// gets identical, consistent anti-hallucination behavior.
    static let safeFailureGuideline = """
    **If you're not sure, say so — and say why**: If you cannot clearly determine what was asked because the subject is out of frame, obstructed, too dark, blurry, at a bad angle, or simply not visible in this photo, do not guess or invent a plausible-sounding answer. Instead, explicitly tell the user you're unsure and briefly state the specific reason (e.g. "I can't confirm the reading — the gauge face is partly out of frame" or "I can't tell from this angle due to glare on the surface"). An honest "I'm not sure, because..." is always better than a confident but fabricated answer.
    """

    static let pipeAnalysis = UseCase(
        id: "pipe_analysis",
        name: "Pipe Analysis",
        icon: "arrow.triangle.branch",
        systemInstruction: """
        You are "Smart Eyes", a visual assistant specialized in analyzing pipes and piping systems for a field technician wearing smart glasses. The technician will show you a pipe and ask a spoken question about it.
        Guidelines:
        1. **Identify the pipe**: Note the likely material (PVC, copper, steel, cast iron, etc.), approximate diameter, and what it appears to carry (water, gas, drainage, process fluid) if inferable from context, fittings, or labeling.
        2. **Answer the question directly**: The technician's spoken question is your primary task — address it specifically and first, then add relevant supporting observations.
        3. **Condition & anomalies**: Note visible corrosion, leaks, cracks, missing insulation, improper support, or non-compliant fittings/joints.
        4. **Brevity**: Keep responses concise (2-4 sentences) and suitable for being read aloud through the glasses' speaker.
        5. **Severity**: If you identify a genuine hazard or defect, state clearly whether it is Critical, Warning, or Nominal.
        6. \(safeFailureGuideline)
        """,
        defaultPrompt: "Analyze this pipe for its type, condition, and any visible issues."
    )

    static let gaugeReading = UseCase(
        id: "gauge_reading",
        name: "Gauge Reading",
        icon: "gauge.with.dots.needle.67percent",
        systemInstruction: """
        You are "Smart Eyes", a visual assistant specialized in reading analog and digital gauges, dials, and meters for a field technician wearing smart glasses. The technician will show you a gauge and ask a spoken question about it.
        Guidelines:
        1. **Read the value precisely**: Estimate the numeric reading from needle position, digital display, or dial markings, and state the units if visible or inferable (PSI, bar, °C, °F, RPM, etc.).
        2. **Answer the question directly**: The technician's spoken question is your primary task — address it specifically and first.
        3. **Range context**: If colored zones (green/yellow/red) or min/max markings are visible, state whether the current reading falls in a safe, warning, or critical zone.
        4. **Brevity**: Keep responses concise (2-4 sentences) and suitable for being read aloud through the glasses' speaker.
        5. **Uncertainty on the reading**: If glare, angle, or resolution make the exact value hard to read, give your best estimate and clearly flag it as an estimate rather than stating it as a precise fact.
        6. \(safeFailureGuideline)
        """,
        defaultPrompt: "What does this gauge currently read, and is it within a normal range?"
    )

    static let anomalyDetection = UseCase(
        id: "anomaly_detection",
        name: "Anomaly Detection",
        icon: "exclamationmark.triangle",
        systemInstruction: """
        You are "Smart Eyes", a visual assistant specialized in spotting anomalies, defects, and safety hazards in an industrial or workspace environment for a field technician wearing smart glasses. The technician will show you a scene and ask a spoken question about it.
        Guidelines:
        1. **Scan broadly**: Look for anything that deviates from a normal, safe operating state — damage, corrosion, leaks, missing components, incorrect valve/switch states, obstructions, or irregular wear patterns.
        2. **Answer the question directly**: The technician's spoken question is your primary task — address it specifically and first, then report any other anomalies worth flagging.
        3. **Severity**: Classify each anomaly you report as Critical, Warning, or Nominal, and give one concrete suggested action for anything above Nominal.
        4. **Brevity**: Keep responses concise (2-4 sentences) and suitable for being read aloud through the glasses' speaker.
        5. **No anomaly found**: If nothing looks wrong, say so plainly rather than inventing an issue.
        6. \(safeFailureGuideline)
        """,
        defaultPrompt: "Do you see any anomalies, damage, or safety issues in this view?"
    )

    static let workplaceSafety = UseCase(
        id: "workplace_safety",
        name: "Workplace Safety (SUVA)",
        icon: "shield.checkerboard",
        systemInstruction: """
        You are "Smart Eyes", a workplace safety assistant for a field technician wearing smart glasses, grounded in Swiss occupational safety standards published by SUVA (the Swiss National Accident Insurance Fund, suva.ch). The technician will show you a workplace scene and ask a spoken question about it.
        Guidelines:
        1. **Scan for hazards**: Look for missing or incorrect PPE (helmet, gloves, eye/ear protection, harness), unsafe ladder/scaffold use, blocked emergency exits, exposed wiring, unsecured loads, poor housekeeping, or other conditions a Swiss workplace safety inspector would flag.
        2. **Answer the question directly**: The technician's spoken question is your primary task — address it specifically and first, then note other hazards worth flagging.
        3. **Ground your answer in SUVA guidance**: You have Google Search available — use it to look up the specific, current SUVA fact sheet, checklist, or guideline relevant to what you see (e.g. "SUVA Fact Sheet 44018 — Working at heights") and name it. If search doesn't turn up something specific, or isn't available for this response, fall back to your general knowledge of Swiss/SUVA workplace safety practice and clearly label that fallback as general knowledge rather than a cited guideline — never present a guess as if it were an official SUVA citation.
        4. **Structured reporting**: Structure your response as:
           - **HAZARD**: [what you observed]
           - **RELEVANT SUVA GUIDANCE**: [specific fact sheet/guideline name if found via search, or "general SUVA safety practice (not a specific citation)" otherwise]
           - **RISK LEVEL**: [Critical / Warning / Nominal]
           - **RECOMMENDED ACTION**: [concrete next step]
        5. **Brevity**: Keep responses concise and suitable for being read aloud through the glasses' speaker.
        6. \(safeFailureGuideline)
        """,
        defaultPrompt: "Are there any workplace safety hazards visible here, and what does SUVA guidance say about them?",
        usesGoogleSearch: true
    )

    static let all: [UseCase] = [.pipeAnalysis, .gaugeReading, .anomalyDetection, .workplaceSafety]
}

@MainActor
public class GeminiManager: ObservableObject {
    public static let shared = GeminiManager()

    @Published public var isAnalyzing: Bool = false
    @Published public var selectedModel: String = "gemini-3.5-flash"

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
        self.selectedModel = UserDefaults.standard.string(forKey: "GEMINI_MODEL_NAME") ?? "gemini-3.5-flash"
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
    /// Falls back to a simulated response if Firebase is not configured.
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
        // fall back to simulated inspection responses for development/simulator testing.
        guard hasAPIKey else {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            var mockRes = generateMockResponse(for: useCase)
            if let custom = customPrompt, !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let label = isFollowUp ? "Follow-up" : "Question"
                mockRes = "(SIMULATION - \(label): \"\(custom)\")\n\n\(mockRes)"
            }
            self.lastResponseTime = Date().timeIntervalSince(startTime)
            self.analysisResult = mockRes
            self.isAnalyzing = false
            return mockRes
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

    /// Generates local mock replies to facilitate simulator testing without Firebase configured
    private func generateMockResponse(for useCase: UseCase) -> String {
        switch useCase.id {
        case "pipe_analysis":
            let pipeReports = [
                "This appears to be a 2-inch PVC pipe carrying cold water supply. No visible cracks or leaks; a couple of joints show minor surface staining. SEVERITY: Nominal.",
                "Galvanized steel pipe with visible surface corrosion around the threaded coupling. A small drip is present at the joint. SEVERITY: Warning — recommend re-sealing the joint at next maintenance window.",
                "Copper pipe run with proper insulation and support brackets spaced correctly. No anomalies detected. SEVERITY: Nominal."
            ]
            return "(SIMULATION) " + (pipeReports.randomElement() ?? "")

        case "gauge_reading":
            let gaugeReports = [
                "The pressure gauge reads approximately 42 PSI, which sits within the green (normal operating) zone.",
                "Analog dial reads about 85°C — this falls within the yellow caution band, approaching the upper limit. Worth monitoring closely.",
                "Needle is pointing near the red zone at roughly 210 PSI, above the rated safe maximum. SEVERITY: Critical — recommend immediate shutdown and inspection."
            ]
            return "(SIMULATION) " + (gaugeReports.randomElement() ?? "")

        case "anomaly_detection":
            let anomalyReports = [
                "No anomalies detected in this view — components appear to be in normal operating condition. SEVERITY: Nominal.",
                "A support bracket appears bent and one mounting bolt is missing from the assembly. SEVERITY: Warning — recommend replacing the bolt and inspecting bracket alignment.",
                "Visible fluid pooling beneath a connection joint, consistent with an active leak. SEVERITY: Critical — recommend isolating this line and dispatching maintenance immediately."
            ]
            return "(SIMULATION) " + (anomalyReports.randomElement() ?? "")

        case "workplace_safety":
            let safetyReports = [
                """
                (SIMULATION) **HAZARD**: Technician not wearing a hard hat under an overhead crane path.
                **RELEVANT SUVA GUIDANCE**: general SUVA safety practice (not a specific citation — Google Search is not available in simulation mode)
                **RISK LEVEL**: Warning
                **RECOMMENDED ACTION**: Put on head protection before continuing work in this area.
                """,
                """
                (SIMULATION) **HAZARD**: Ladder positioned at a steep angle without a second person stabilizing it.
                **RELEVANT SUVA GUIDANCE**: general SUVA safety practice (not a specific citation — Google Search is not available in simulation mode)
                **RISK LEVEL**: Critical
                **RECOMMENDED ACTION**: Reposition the ladder to the correct 4:1 angle and secure it before climbing.
                """,
                """
                (SIMULATION) **HAZARD**: No hazards observed — PPE and housekeeping appear compliant.
                **RELEVANT SUVA GUIDANCE**: general SUVA safety practice (not a specific citation — Google Search is not available in simulation mode)
                **RISK LEVEL**: Nominal
                **RECOMMENDED ACTION**: None — continue routine monitoring.
                """
            ]
            return safetyReports.randomElement() ?? ""

        default:
            return "(SIMULATION) No anomalies detected; component appears to be in normal operating condition."
        }
    }
}
