import SwiftUI
import AudioToolbox

/// Chat Log tab: the running chat transcript, plus the question composer (mic/text) for
/// whatever photo was most recently captured in the Inspection tab, plus telemetry export/purge.
struct ChatLogView: View {
    @Environment(\.colorScheme) var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    @ObservedObject var wearableManager: WearableManager
    @ObservedObject var geminiManager: GeminiManager
    @ObservedObject var speechManager: SpeechManager
    @ObservedObject var telemetryManager: TelemetryManager
    @ObservedObject var voiceQuestionManager: VoiceQuestionManager
    @ObservedObject var session: InspectionSessionState

    @Binding var showDisconnectAlert: Bool
    /// Bound to the app's tab selection so "Cancel" can jump the user back to the Inspection tab.
    @Binding var selectedTab: Int

    @State private var autoScrollProxy: ScrollViewProxy? = nil
    @State private var questionText = ""
    @FocusState private var isQuestionFieldFocused: Bool

    var body: some View {
        ZStack {
            theme.mainBgColor
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HeaderView(wearableManager: wearableManager, theme: theme, showDisconnectAlert: $showDisconnectAlert)
                chatLogPanel
                questionCaptureSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Chat log

    private var chatLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CHAT LOG")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.secondaryTextColor)

                Spacer()
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
                        ForEach(session.chatHistory) { item in
                            chatBubble(item)
                                .id(item.id)
                        }

                        if geminiManager.isAnalyzing {
                            HStack(alignment: .top, spacing: 8) {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: theme.secondaryTextColor))
                                        .scaleEffect(0.7)
                                    Text(geminiManager.analysisResult)
                                        .font(.system(size: 13))
                                        .foregroundColor(theme.secondaryTextColor)
                                }
                                .padding(10)
                                .background(theme.secondaryPanelBgColor)
                                .cornerRadius(12, corners: [.topRight, .bottomLeft, .bottomRight])

                                Spacer()
                            }
                        }

                        Color.clear.frame(height: 1).id("chatLogBottom")
                    }
                    .padding(.vertical, 4)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    autoScrollProxy = proxy
                }
                .onChange(of: session.chatHistory.count) { _ in
                    scrollToBottom()
                }
                .onChange(of: geminiManager.isAnalyzing) { _ in
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
                            .frame(width: 200, height: 260)
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

    // MARK: - Question composer

    private var questionCaptureSection: some View {
        VStack(spacing: 8) {
            if session.capturedPhoto == nil {
                Text("Take a photo in the Inspection tab to start asking questions.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(theme.secondaryTextColor)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 8) {
                Button(action: toggleQuestionListening) {
                    HStack(spacing: 6) {
                        Image(systemName: voiceQuestionManager.isListening ? "mic.fill" : "mic")
                        Text(voiceQuestionManager.isListening ? "STOP" : "ASK BY VOICE")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(voiceQuestionManager.isListening ? Color.red : (session.capturedPhoto != nil ? Color.blue : Color.gray.opacity(0.3)))
                    )
                }
                .disabled(session.capturedPhoto == nil || geminiManager.isAnalyzing)

                if voiceQuestionManager.isListening {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("LISTENING...")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))

                // TODO: keyboard/focus behavior here still feels off after the @FocusState +
                // toolbar "Done" button fix — revisit and pin down exactly what's wrong
                // (dismiss timing, focus not returning correctly, toolbar placement, etc.).
                TextField(session.hasAskedAboutCurrentPhoto ? "Ask a follow-up about this photo..." : "Tap the mic and ask, or type your question...", text: $questionText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(theme.primaryTextColor)
                    .font(.system(size: 13, design: .monospaced))
                    .disabled(session.capturedPhoto == nil)
                    .focused($isQuestionFieldFocused)
                    // NOTE: with axis: .vertical, TextField treats Return as "insert a newline",
                    // not "submit" — .onSubmit never fires here, so the keyboard needs an
                    // explicit dismiss point instead (the toolbar "Done" button below, plus
                    // auto-dismiss on send / on starting voice dictation).
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") {
                                isQuestionFieldFocused = false
                            }
                        }
                    }

                if !questionText.isEmpty {
                    Button(action: { questionText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(theme.secondaryTextColor)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(10)
            .background(theme.mainBgColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.textBorderColor, lineWidth: 1)
            )

            if let error = voiceQuestionManager.errorText {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }

            HStack(spacing: 10) {
                Button(action: retakePhoto) {
                    Text("CANCEL")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
                }
                .disabled(session.capturedPhoto == nil)

                Button(action: sendQuestion) {
                    HStack(spacing: 6) {
                        if geminiManager.isAnalyzing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("SENDING...")
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text(session.hasAskedAboutCurrentPhoto ? "ASK FOLLOW-UP" : "SEND")
                        }
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(canSendQuestion ? Color.blue : Color.gray.opacity(0.3))
                    )
                }
                .disabled(!canSendQuestion)
            }
        }
        .onChange(of: voiceQuestionManager.liveTranscript) { newValue in
            // Mirror the live transcript into the editable field while actively listening
            if voiceQuestionManager.isListening {
                questionText = newValue
            }
        }
    }

    private var canSendQuestion: Bool {
        session.capturedPhoto != nil && !questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !geminiManager.isAnalyzing
    }

    private func toggleQuestionListening() {
        isQuestionFieldFocused = false
        if voiceQuestionManager.isListening {
            questionText = voiceQuestionManager.stopAndFinish()
        } else {
            questionText = ""
            voiceQuestionManager.startListening()
        }
    }

    // MARK: - Actions & Logic

    /// Discards the captured photo and ends its conversation, then jumps back to the Inspection
    /// tab so the user can immediately capture a fresh photo instead of having to switch tabs
    /// manually.
    private func retakePhoto() {
        session.retakePhoto()
        questionText = ""
        geminiManager.startNewConversation()
        if voiceQuestionManager.isListening {
            voiceQuestionManager.cancel()
        }
        selectedTab = 1
    }

    /// Sends the transcribed/typed question to Gemini about the captured photo, using the
    /// selected use case's context prompt. The photo (and Gemini's conversation about it) stays
    /// active afterwards so the user can immediately ask a follow-up right there — tap "Cancel"
    /// to discard it, or capture a new photo from the Inspection tab to start over.
    @MainActor
    private func sendQuestion() {
        guard let image = session.capturedPhoto else { return }
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        let useCase = session.selectedUseCase
        let isFollowUp = session.hasAskedAboutCurrentPhoto

        // Clear the question field and mark this photo as "in conversation" immediately so the
        // UI is ready for a follow-up, but keep the photo itself around for that follow-up.
        questionText = ""
        session.hasAskedAboutCurrentPhoto = true
        voiceQuestionManager.cancel()
        isQuestionFieldFocused = false

        geminiManager.isAnalyzing = true
        geminiManager.analysisResult = "Analyzing photo..."

        Task {
            let trialId = UUID()

            // No imageThumbnail here — the photo was already posted to the log the moment it
            // was captured (see InspectionView.capturePhotoStep), so repeating it on every
            // question would be redundant.
            var userMsg = MessageItem(
                timestamp: Date(),
                isUser: true,
                text: isFollowUp ? "(follow-up) \(question)" : question,
                imageThumbnail: nil
            )
            userMsg.trialId = trialId
            session.chatHistory.append(userMsg)

            let answer = await geminiManager.analyzeFrame(
                image: image,
                useCase: useCase,
                customPrompt: question,
                isFollowUp: isFollowUp
            )

            var aiMsg = MessageItem(
                timestamp: Date(),
                isUser: false,
                text: answer,
                imageThumbnail: nil
            )
            aiMsg.trialId = trialId
            session.chatHistory.append(aiMsg)

            // Log trial in TelemetryManager
            let source = "live_device"
            let severity: String
            let lower = answer.lowercased()
            if lower.contains("critical") {
                severity = "critical"
            } else if lower.contains("warning") {
                severity = "warning"
            } else if lower.contains("nominal") || lower.contains("satisfactory") {
                severity = "nominal"
            } else {
                severity = "N/A"
            }

            TelemetryManager.shared.logTrial(
                 id: trialId,
                 phase: useCase.name,
                 source: source,
                 captureMode: "photo",
                 imageSize: image.size,
                 latency: geminiManager.lastResponseTime,
                 prompt: question,
                 response: answer,
                 severity: severity,
                 aiModel: geminiManager.selectedModel,
                 inputTokens: geminiManager.lastInputTokens,
                 textInputTokens: geminiManager.lastTextInputTokens,
                 imageInputTokens: geminiManager.lastImageInputTokens,
                 outputTokens: geminiManager.lastOutputTokens,
                 totalTokens: geminiManager.lastTotalTokens,
                 thinkingTokens: geminiManager.lastThinkingTokens
             )

            // Speak the response if voice feedback is enabled
            speechManager.speak(answer)
        }
    }

    private func scrollToBottom() {
        guard let proxy = autoScrollProxy else { return }
        withAnimation {
            proxy.scrollTo("chatLogBottom", anchor: .bottom)
        }
    }

    /// Parses the compliance level out of Gemini's response text
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
        session.resetForPurge()
        // Purging wipes the chat history back down to just the welcome message, so any
        // in-progress photo conversation is no longer meaningful either.
        questionText = ""
        geminiManager.startNewConversation()
    }

    private func exportCSV() {
        guard let url = TelemetryManager.shared.exportAsCSV() else { return }
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
