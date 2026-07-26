import SwiftUI

/// Audit Log tab: the running chat/audit transcript built up by Inspection's trigger actions,
/// voice/simulation toggles, and telemetry export/purge.
struct AuditLogView: View {
    @Environment(\.colorScheme) var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    @ObservedObject var wearableManager: WearableManager
    @ObservedObject var geminiManager: GeminiManager
    @ObservedObject var speechManager: SpeechManager
    @ObservedObject var telemetryManager: TelemetryManager
    @ObservedObject var chatLog: ChatLogStore

    @Binding var showDisconnectAlert: Bool
    @Binding var showSettingsSheet: Bool

    @State private var autoScrollProxy: ScrollViewProxy? = nil

    var body: some View {
        ZStack {
            theme.mainBgColor
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HeaderView(
                    wearableManager: wearableManager,
                    geminiManager: geminiManager,
                    theme: theme,
                    showSettingsGear: true,
                    showDisconnectAlert: $showDisconnectAlert,
                    showSettingsSheet: $showSettingsSheet
                )
                chatLogPanel
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var chatLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AUDIT LOG")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.secondaryTextColor)

                Spacer()

                // Voice Speech Toggle
                Button(action: {
                    speechManager.isVoiceEnabled.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: speechManager.isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        Text(speechManager.isVoiceEnabled ? "VOICE ON" : "VOICE OFF")
                    }
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(speechManager.isVoiceEnabled ? .green : theme.secondaryTextColor)
                }
                .padding(.trailing, 10)

                // Simulation toggle
                Button(action: {
                    wearableManager.toggleMockMode()
                }) {
                    Text(wearableManager.isMockMode ? "Switch to Live Device" : "Switch to Simulation")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 4)

            // Telemetry Export Buttons Row
            HStack(spacing: 12) {
                Text("Session Records: \(telemetryManager.records.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.secondaryTextColor)

                Spacer()

                if !telemetryManager.records.isEmpty {
                    Button(action: purgeTelemetry) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                            Text("Purge Logs")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12))
                        .cornerRadius(4)
                    }
                }

                Button(action: exportCSV) {
                    HStack(spacing: 4) {
                        Image(systemName: "tablecells.fill")
                        Text("Export Telemetry (CSV)")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4)
                }
                .disabled(telemetryManager.records.isEmpty)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            // Chat history ScrollView
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(chatLog.chatHistory) { item in
                            chatBubble(item)
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    autoScrollProxy = proxy
                }
                .onChange(of: chatLog.chatHistory.count) { _ in
                    scrollToBottom()
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func chatBubble(_ message: MessageItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if let thumbnail = message.imageThumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 160)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }

                    Text(message.text)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(12, corners: [.topLeft, .bottomLeft, .bottomRight])

                    Text(formattedTime(message.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(theme.secondaryTextColor)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if let badge = complianceBadge(for: message.text) {
                        badge
                    }

                    Text(message.text)
                        .font(.system(size: 14))
                        .foregroundColor(message.text.contains("Error") ? .red : theme.primaryTextColor)
                        .padding(12)
                        .background(theme.secondaryPanelBgColor)
                        .cornerRadius(12, corners: [.topRight, .bottomLeft, .bottomRight])
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(message.text.contains("Error") ? Color.red.opacity(0.3) : theme.panelBorderColor.opacity(0.5), lineWidth: 1)
                        )

                    HStack(spacing: 6) {
                        if let trialId = message.trialId,
                           let record = telemetryManager.records.first(where: { $0.id == trialId }) {
                            Text(record.formattedModelName)
                                .fontWeight(.bold)
                            Text("•")
                            Text(formattedTime(message.timestamp))
                            Text("•")
                            Text(String(format: "Latency: %.2fs", record.latencySeconds))
                             if let inTok = record.inputTokens, let outTok = record.outputTokens {
                                 Text("•")
                                 if let thinkTok = record.thinkingTokens, thinkTok > 0 {
                                     Text("Tokens: \(inTok) in / \(outTok) out (\(thinkTok) think)")
                                 } else {
                                     Text("Tokens: \(inTok) in / \(outTok) out")
                                 }
                             }
                        } else {
                            Text("Gemini Flash")
                                .fontWeight(.bold)
                            Text("•")
                            Text(formattedTime(message.timestamp))
                            if geminiManager.lastResponseTime > 0 && !message.text.contains("Welcome") {
                                Text("•")
                                Text(String(format: "Latency: %.2fs", geminiManager.lastResponseTime))
                            }
                        }
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(theme.secondaryTextColor)

                    if let trialId = message.trialId {
                        feedbackRow(for: trialId)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Actions & Logic

    private func scrollToBottom() {
        guard let proxy = autoScrollProxy, let last = chatLog.chatHistory.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    /// Parses the compliance level out of simulated or live Gemini responses
    private func complianceBadge(for text: String) -> AnyView? {
        let lower = text.lowercased()
        if lower.contains("critical") {
            return AnyView(badgeView(text: "CRITICAL HAZARD", color: .red))
        } else if lower.contains("warning") {
            return AnyView(badgeView(text: "SAFETY WARNING", color: .orange))
        } else if lower.contains("nominal") || lower.contains("satisfactory") {
            return AnyView(badgeView(text: "NOMINAL", color: .green))
        }
        return nil
    }

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
    }

    private func feedbackRow(for trialId: UUID) -> some View {
        guard let record = telemetryManager.records.first(where: { $0.id == trialId }) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("Accuracy:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(theme.secondaryTextColor)

                    Button(action: {
                        TelemetryManager.shared.submitFeedback(recordId: trialId, isCorrect: true, rating: record.rating1To5)
                    }) {
                        Image(systemName: record.isCorrect == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .foregroundColor(record.isCorrect == true ? .green : theme.secondaryTextColor)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: {
                        TelemetryManager.shared.submitFeedback(recordId: trialId, isCorrect: false, rating: record.rating1To5)
                    }) {
                        Image(systemName: record.isCorrect == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .foregroundColor(record.isCorrect == false ? .red : theme.secondaryTextColor)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Divider()
                    .frame(height: 12)
                    .background(Color.white.opacity(0.12))

                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Button(action: {
                            TelemetryManager.shared.submitFeedback(recordId: trialId, isCorrect: record.isCorrect, rating: star)
                        }) {
                            Image(systemName: (record.rating1To5 ?? 0) >= star ? "star.fill" : "star")
                                .foregroundColor((record.rating1To5 ?? 0) >= star ? .yellow : theme.secondaryTextColor)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding(.top, 4)
        )
    }

    private func purgeTelemetry() {
        telemetryManager.purgeRecords()
        chatLog.reset()
    }

    private func exportCSV() {
        guard let url = TelemetryManager.shared.exportAsCSV() else { return }
        shareFile(url: url)
    }

    private func exportJSON() {
        guard let url = TelemetryManager.shared.exportAsJSON() else { return }
        shareFile(url: url)
    }

    private func shareFile(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let popoverController = activityVC.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                popoverController.sourceView = rootVC.view
                popoverController.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popoverController.permittedArrowDirections = []
            }
        }

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true, completion: nil)
        }
    }
}
