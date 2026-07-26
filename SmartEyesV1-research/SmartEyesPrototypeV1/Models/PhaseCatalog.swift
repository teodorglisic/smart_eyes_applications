import Foundation

/// One inspection phase in the Phase 1-3 empirical evaluation framework: a name, its system
/// prompt, its default (no-custom-prompt) question, and the canned responses used in simulator
/// mode when Firebase isn't configured.
///
/// To add Phase 4 (or retire an existing phase), edit `.all` below — that's the only place that
/// needs to change. Previously this same information was spread across three separate `switch
/// mode` statements in `GeminiManager.swift` (system instruction, default prompt, mock
/// responses) plus a 4th ad-hoc copy of the default-prompt logic in `ContentView.swift` — easy
/// to update one and forget another. Now `GeminiManager` and the views just read fields off
/// whichever `Phase` is selected.
public struct Phase: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let systemInstruction: String
    public let defaultPrompt: String
    public let mockResponses: [String]

    public init(
        id: String,
        name: String,
        systemInstruction: String,
        defaultPrompt: String,
        mockResponses: [String]
    ) {
        self.id = id
        self.name = name
        self.systemInstruction = systemInstruction
        self.defaultPrompt = defaultPrompt
        self.mockResponses = mockResponses
    }

    public static func == (lhs: Phase, rhs: Phase) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public extension Phase {
    static let phase1 = Phase(
        id: "phase1",
        name: "Phase 1: Baseline",
        systemInstruction: """
        You are a fast, objective visual assistant for smart glasses baseline testing. Your goal is to identify common objects, basic safety features, flat reference materials, and baseline industrial components under various lighting conditions.
        Guidelines:
        1. **Extreme Brevity**: Keep your response under 1–2 sentences. State what you see immediately without introductory filler (e.g., avoid "I can see..." or "In this image...").
        2. **Identification Scope**: Accurately recognize everyday items (e.g., apples), basic room safety elements (e.g., exit doors), printed 2D schematics/manuals, and generic industrial elements (e.g., pipes, pressure gauges) without assuming deep context.
        3. **Lighting Adaptability**: If the image has extreme lighting (bright sunlight glare or dark shadows), attempt to identify the object but briefly note if the visual quality is degraded (e.g., "A pressure gauge, slightly obscured by direct sunlight glare").
        """,
        defaultPrompt: "Identify the baseline objects and features in this image.",
        mockResponses: [
            "Red apple on the table, clean and positioned in the center.",
            "A pressure gauge, slightly obscured by direct sunlight glare.",
            "Standard industrial exit door, clearly marked with a green exit sign under normal office lighting."
        ]
    )

    static let phase2 = Phase(
        id: "phase2",
        name: "Phase 2: Industrial",
        systemInstruction: """
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
        """,
        defaultPrompt: "Perform high-precision technical inspection of this view.",
        mockResponses: [
            """
            **Smart Eyes Inspection Report**

            - **OBJECT DETECTED**: Flange Coupling Bolts
            - **STATE/VALUE**: 7 out of 8 bolts present
            - **DETECTED ANOMALY**: One mounting bolt is missing from the lower flange segment.
            - **SEVERITY**: Warning
            - **SUGGESTED ACTION**: Install a replacement M16 grade 8.8 steel bolt and torque to spec.
            """,
            """
            **Smart Eyes Inspection Report**

            - **OBJECT DETECTED**: Primary Gas Line Valve
            - **STATE/VALUE**: Closed (valve handle is perpendicular to the pipe orientation)
            - **DETECTED ANOMALY**: Minor surface pitting observed near the joint threads.
            - **SEVERITY**: Nominal
            - **SUGGESTED ACTION**: Monitor pitting at next routine check. No immediate repair required.
            """,
            """
            **Smart Eyes Inspection Report**

            - **OBJECT DETECTED**: Boiler Control Panel LEDs
            - **STATE/VALUE**: Red LED is ON, Green LED is OFF
            - **DETECTED ANOMALY**: Over-temperature indicator is active.
            - **SEVERITY**: Critical
            - **SUGGESTED ACTION**: Immediately shut down the main feed and verify boiler temperature sensor functionality.
            """
        ]
    )

    static let phase3 = Phase(
        id: "phase3",
        name: "Phase 3: Stress Test",
        systemInstruction: """
        You are a robust visual stress-test analyst for smart glasses. Your goal is to extract technical details and evaluate surface defects from highly degraded, distorted, or obstructed visual inputs.
        Guidelines:
        1. **Perspective Correction**: De-warp and interpret text, labels, or component features viewed from awkward angles or tight perspectives (e.g., sharp 45-degree views).
        2. **Low Contrast & Glare Filtering**: Separate low-contrast monochromatic components from matching backgrounds (e.g., a dark pipe against a concrete wall). Ignore bright glare spots or reflections on metallic surfaces to identify underlying defects (cracks, dents, rust).
        3. **Contextual Inference**: When a component is partially obstructed (30-50% blocked by cables or pipes), use surrounding visual context to infer the hidden component's identity and state.
        4. **Surface Degradation Analysis**: Identify, locate, and classify material anomalies such as rust, corrosion, or pitting, and estimate the severity (e.g., superficial rust vs. structural corrosion).
        5. **Uncertainty & Quality Reporting**: When processing motion blur or extreme noise, provide your best technical hypothesis, but explicitly report the limitation and your confidence level (e.g., "High motion blur detected. Likely a valve handle, but confidence is low due to pixel smear").
        """,
        defaultPrompt: "Analyze visual stress factors, anomalies, or degradation in this view.",
        mockResponses: [
            "High motion blur detected. Likely a primary valve handle, but confidence is low due to pixel smear.",
            "Low-contrast dark pipe against a matching concrete wall. Obstructed (approx. 40%) by overhead wiring bundles. Contextual inference suggests the line is closed. Structural integrity is intact, but minor surface corrosion is starting to form at the joint.",
            "Perspective view (approx. 45-degree angle). De-warped label reading: 'MAINTENANCE DUE 06/2026'. No major structural deformation visible, but superficial rust is present along the pipe threading."
        ]
    )

    static let all: [Phase] = [.phase1, .phase2, .phase3]
}
