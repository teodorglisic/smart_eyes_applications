import SwiftUI

/// App shell: wires the three tabs (Setup, Inspection, Chat Log) together, owns the manager
/// singletons and the cross-tab `InspectionSessionState`, and hosts the two modals shared across
/// tabs (disconnect confirmation, model settings sheet).
///
/// Each tab's actual UI lives in its own file: `SetupView.swift`, `InspectionView.swift`,
/// `ChatLogView.swift`. Shared visuals (colors, header, step label) live in `Theme.swift` and
/// `Shared.swift`; the use-case and model catalogs live in `UseCaseCatalog.swift` and
/// `GeminiModelCatalog.swift`.
struct ContentView: View {
    @StateObject private var wearableManager = WearableManager.shared
    @StateObject private var geminiManager = GeminiManager.shared
    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var telemetryManager = TelemetryManager.shared
    @StateObject private var voiceQuestionManager = VoiceQuestionManager.shared
    @StateObject private var session = InspectionSessionState()

    @State private var showDisconnectAlert = false
    @State private var showSettingsSheet = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SetupView(
                wearableManager: wearableManager,
                geminiManager: geminiManager,
                speechManager: speechManager,
                showDisconnectAlert: $showDisconnectAlert,
                showSettingsSheet: $showSettingsSheet
            )
            .tabItem {
                Label("Setup", systemImage: "gearshape.fill")
            }
            .tag(0)

            InspectionView(
                wearableManager: wearableManager,
                geminiManager: geminiManager,
                session: session,
                showDisconnectAlert: $showDisconnectAlert,
                selectedTab: $selectedTab
            )
            .tabItem {
                Label("Inspection", systemImage: "sparkles.tv")
            }
            .tag(1)

            ChatLogView(
                wearableManager: wearableManager,
                geminiManager: geminiManager,
                speechManager: speechManager,
                telemetryManager: telemetryManager,
                voiceQuestionManager: voiceQuestionManager,
                session: session,
                showDisconnectAlert: $showDisconnectAlert,
                selectedTab: $selectedTab
            )
            .tabItem {
                Label("Chat Log", systemImage: "doc.text.magnifyingglass")
            }
            .tag(2)
        }
        .accentColor(.blue)
        .alert(isPresented: $showDisconnectAlert) {
            Alert(
                title: Text("Disconnect Glasses"),
                message: Text("Are you sure you want to unregister and disconnect your Meta Smart Glasses?"),
                primaryButton: .destructive(Text("Disconnect")) {
                    wearableManager.unregisterDevice()
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showSettingsSheet) {
            ApiKeySettingsView()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .preferredColorScheme(.dark)
            ContentView()
                .preferredColorScheme(.light)
        }
    }
}
