import SwiftUI

/// App shell: wires the two tabs (Inspection, Audit Log) together, owns the manager singletons
/// and the shared `ChatLogStore`, and hosts the two modals shared across tabs (disconnect
/// confirmation, model settings sheet).
///
/// Each tab's actual UI lives in its own file: `InspectionView.swift`, `AuditLogView.swift`.
/// Shared visuals (colors, header) live in `Theme.swift` and `Shared.swift`; the phase catalog
/// lives in `PhaseCatalog.swift`; the model list lives in `GeminiModelCatalog.swift`.
struct ContentView: View {
    @StateObject private var wearableManager = WearableManager.shared
    @StateObject private var geminiManager = GeminiManager.shared
    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var telemetryManager = TelemetryManager.shared
    @StateObject private var voiceTriggerManager = VoiceTriggerManager.shared
    @StateObject private var chatLog = ChatLogStore()

    @State private var showDisconnectAlert = false
    @State private var showSettingsSheet = false
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            InspectionView(
                wearableManager: wearableManager,
                geminiManager: geminiManager,
                telemetryManager: telemetryManager,
                voiceTriggerManager: voiceTriggerManager,
                chatLog: chatLog,
                showDisconnectAlert: $showDisconnectAlert,
                showSettingsSheet: $showSettingsSheet,
                selectedTab: $selectedTab
            )
            .tabItem {
                Label("Inspection", systemImage: "sparkles.tv")
            }
            .tag(0)

            AuditLogView(
                wearableManager: wearableManager,
                geminiManager: geminiManager,
                speechManager: speechManager,
                telemetryManager: telemetryManager,
                chatLog: chatLog,
                showDisconnectAlert: $showDisconnectAlert,
                showSettingsSheet: $showSettingsSheet
            )
            .tabItem {
                Label("Audit Log", systemImage: "doc.text.magnifyingglass")
            }
            .tag(1)
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
