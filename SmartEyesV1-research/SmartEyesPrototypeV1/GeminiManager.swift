import Foundation
import UIKit
import Combine
import FirebaseAILogic
import FirebaseCore

public enum InspectionMode: String, CaseIterable, Identifiable {
    case phase1 = "Phase 1: Baseline"
    case phase2 = "Phase 2: Industrial"
    case phase3 = "Phase 3: Stress Test"

    public var id: String { self.rawValue }
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

    private init() {
        self.selectedModel = UserDefaults.standard.string(forKey: "GEMINI_MODEL_NAME") ?? "gemini-3.5-flash"
    }

    public func updateModel(_ modelName: String) {
        self.selectedModel = modelName
    }

    /// Analyzes the captured frame using the Firebase AI Logic SDK (Gemini Developer API).
    /// Falls back to a simulated response if Firebase is not configured.
    public func analyzeFrame(image: UIImage, mode: InspectionMode, customPrompt: String? = nil) async -> String {
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
            var mockRes = generateMockResponse(for: mode)
            if let custom = customPrompt {
                mockRes = "(SIMULATION - Command: \"\(custom)\")\n\n\(mockRes)"
            }
            self.lastResponseTime = Date().timeIntervalSince(startTime)
            self.analysisResult = mockRes
            self.isAnalyzing = false
            return mockRes
        }

        let modelName = self.selectedModel

        // Setup system instructions based on the selected thesis phase
        let systemInstruction: String
        switch mode {
        case .phase1:
            systemInstruction = """
            You are a fast, objective visual assistant for smart glasses baseline testing. Your goal is to identify common objects, basic safety features, flat reference materials, and baseline industrial components under various lighting conditions.
            Guidelines:
            1. **Extreme Brevity**: Keep your response under 1–2 sentences. State what you see immediately without introductory filler (e.g., avoid "I can see..." or "In this image...").
            2. **Identification Scope**: Accurately recognize everyday items (e.g., apples), basic room safety elements (e.g., exit doors), printed 2D schematics/manuals, and generic industrial elements (e.g., pipes, pressure gauges) without assuming deep context.
            3. **Lighting Adaptability**: If the image has extreme lighting (bright sunlight glare or dark shadows), attempt to identify the object but briefly note if the visual quality is degraded (e.g., "A pressure gauge, slightly obscured by direct sunlight glare").
            """
        case .phase2:
            systemInstruction = """
            You are "Smart Eyes", a specialized industrial inspection assistant. Your goal is to perform high-precision inspection of machinery, piping, gauges, valves, and structural integrity.
            Guidelines:
            1. **Precise Readings**: Estimate numerical readings from analog dials (e.g., manometers) based on needle positions and markings, stating the value clearly.
            2. **State & Orientation Detection**: Distinguish between valve states (e.g., "Open" if the handle is parallel to the pipe, "Closed" if perpendicular) and electrical status indicators (e.g., reporting which color LEDs are ON or OFF).
            3. **Meticulous Counting**: Audit completeness by counting repeating components (e.g., checking if all bolts on a flange coupling are present, or flagging a missing bolt).
            4. **Structured Inspection Reporting**: For any identified anomaly or maintenance issue, structure your response as:
               - **OBJECT DETECTED**: [Name of the component/area]
               - **STATE/VALUE**: [Operational state, configuration, or numerical reading]
               - **DETECTED ANOMALY**: [Describe the physical damage, missing part, or safety hazard]
               - **SEVERITY**: [Critical / Warning / Nominal]
               - **SUGGESTED ACTION**: [Actionable maintenance step for the field technician]
            5. **Tone**: Keep responses technical, clear, and highly professional.
            """
        case .phase3:
            systemInstruction = """
            You are a robust visual stress-test analyst for smart glasses. Your goal is to extract technical details and evaluate surface defects from highly degraded, distorted, or obstructed visual inputs.
            Guidelines:
            1. **Perspective Correction**: De-warp and interpret text, labels, or component features viewed from awkward angles or tight perspectives (e.g., sharp 45-degree views).
            2. **Low Contrast & Glare Filtering**: Separate low-contrast monochromatic components from matching backgrounds (e.g., a dark pipe against a concrete wall). Ignore bright glare spots or reflections on metallic surfaces to identify underlying defects (cracks, dents, rust).
            3. **Contextual Inference**: When a component is partially obstructed (30-50% blocked by cables or pipes), use surrounding visual context to infer the hidden component's identity and state.
            4. **Surface Degradation Analysis**: Identify, locate, and classify material anomalies such as rust, corrosion, or pitting, and estimate the severity (e.g., superficial rust vs. structural corrosion).
            5. **Uncertainty & Quality Reporting**: When processing motion blur or extreme noise, provide your best technical hypothesis, but explicitly report the limitation and your confidence level (e.g., "High motion blur detected. Likely a valve handle, but confidence is low due to pixel smear").
            """
        }

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
                switch mode {
                case .phase1:
                    prompt = "Identify the baseline objects and features in this image."
                case .phase2:
                    prompt = "Perform high-precision technical inspection of this view."
                case .phase3:
                    prompt = "Analyze visual stress factors, anomalies, or degradation in this view."
                }
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

    /// Generates local mock replies to facilitate simulator testing without Firebase configured
    private func generateMockResponse(for mode: InspectionMode) -> String {
        switch mode {
        case .phase1:
            let baselinePrompts = [
                "Red apple on the table, clean and positioned in the center.",
                "A pressure gauge, slightly obscured by direct sunlight glare.",
                "Standard industrial exit door, clearly marked with a green exit sign under normal office lighting."
            ]
            return "(SIMULATION) " + (baselinePrompts.randomElement() ?? "")

        case .phase2:
            let industrialReports = [
                """
                (SIMULATION) **Smart Eyes Inspection Report**

                - **OBJECT DETECTED**: Flange Coupling Bolts
                - **STATE/VALUE**: 7 out of 8 bolts present
                - **DETECTED ANOMALY**: One mounting bolt is missing from the lower flange segment.
                - **SEVERITY**: Warning
                - **SUGGESTED ACTION**: Install a replacement M16 grade 8.8 steel bolt and torque to spec.
                """,
                """
                (SIMULATION) **Smart Eyes Inspection Report**

                - **OBJECT DETECTED**: Primary Gas Line Valve
                - **STATE/VALUE**: Closed (valve handle is perpendicular to the pipe orientation)
                - **DETECTED ANOMALY**: Minor surface pitting observed near the joint threads.
                - **SEVERITY**: Nominal
                - **SUGGESTED ACTION**: Monitor pitting at next routine check. No immediate repair required.
                """,
                """
                (SIMULATION) **Smart Eyes Inspection Report**

                - **OBJECT DETECTED**: Boiler Control Panel LEDs
                - **STATE/VALUE**: Red LED is ON, Green LED is OFF
                - **DETECTED ANOMALY**: Over-temperature indicator is active.
                - **SEVERITY**: Critical
                - **SUGGESTED ACTION**: Immediately shut down the main feed and verify boiler temperature sensor functionality.
                """
            ]
            return industrialReports.randomElement() ?? ""

        case .phase3:
            let stressReports = [
                "High motion blur detected. Likely a primary valve handle, but confidence is low due to pixel smear.",
                "Low-contrast dark pipe against a matching concrete wall. Obstructed (approx. 40%) by overhead wiring bundles. Contextual inference suggests the line is closed. Structural integrity is intact, but minor surface corrosion is starting to form at the joint.",
                "Perspective view (approx. 45-degree angle). De-warped label reading: 'MAINTENANCE DUE 06/2026'. No major structural deformation visible, but superficial rust is present along the pipe threading."
            ]
            return "(SIMULATION) " + (stressReports.randomElement() ?? "")
        }
    }
}
