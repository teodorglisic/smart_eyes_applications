import SwiftUI

/// Inspection tab: live glasses video feed, voice-trigger mic, phase selector (radio buttons
/// over `Phase.all`), optional custom prompt, and the three capture actions (high-res analyse,
/// low-res analyse, capture-only). Each trigger captures, analyzes, and logs to `chatLog` in one
/// go, then jumps to the Audit Log tab to show progress/results.
struct InspectionView: View {
    @Environment(\.colorScheme) var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    @ObservedObject var wearableManager: WearableManager
    @ObservedObject var geminiManager: GeminiManager
    @ObservedObject var telemetryManager: TelemetryManager
    @ObservedObject var voiceTriggerManager: VoiceTriggerManager
    @ObservedObject var chatLog: ChatLogStore

    @Binding var showDisconnectAlert: Bool
    @Binding var showSettingsSheet: Bool
    @Binding var selectedTab: Int

    @State private var selectedPhase: Phase = .phase1
    @State private var isCapturingOnlyPhoto = false
    @State private var customPromptText = ""

    var body: some View {
        ZStack {
            theme.mainBgColor
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HeaderView(
                    wearableManager: wearableManager,
                    geminiManager: geminiManager,
                    theme: theme,
                    showSettingsGear: false,
                    showDisconnectAlert: $showDisconnectAlert,
                    showSettingsSheet: $showSettingsSheet
                )
                videoFeedPanel
                controlPanel
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Video feed

    private var videoFeedPanel: some View {
        VStack(spacing: 0) {
            ZStack {
                if let frame = wearableManager.currentFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 240)
                        .clipped()
                } else {
                    cameraPlaceholderView
                }

                VStack {
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: wearableManager.isMockMode ? "pc" : "eyeglasses")
                            Text(wearableManager.isMockMode ? "MOCK" : "DAT LIVE")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(4)

                        Spacer()

                        if wearableManager.isStreaming {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                Text("STREAMING")
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.6))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                        }
                    }
                    .padding(8)
                    Spacer()
                }
            }
            .frame(height: 240)
            .background(theme.panelBgColor)
            .cornerRadius(12, corners: [.topLeft, .topRight])
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.panelBorderColor, lineWidth: 1)
            )

            // Bottom Stream Control Bar
            HStack {
                if wearableManager.isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    Text(wearableManager.isStreaming ? "Connected" : "Idle")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                }

                Spacer()

                // Voice Control mic toggle button
                Button(action: {
                    if voiceTriggerManager.isListening {
                        voiceTriggerManager.stopListening()
                    } else {
                        voiceTriggerManager.startListening {
                            triggerInspection(highRes: true)
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: voiceTriggerManager.isListening ? "mic.fill" : "mic.slash.fill")
                        Text(voiceTriggerManager.isListening ? "Listening" : "Voice On")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(voiceTriggerManager.isListening ? .green : .gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(voiceTriggerManager.isListening ? Color.green.opacity(0.12) : Color.gray.opacity(0.12))
                    .cornerRadius(6)
                }

                Button(action: {
                    if wearableManager.isStreaming {
                        wearableManager.stopStream()
                    } else {
                        wearableManager.startStream()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: wearableManager.isStreaming ? "stop.fill" : "play.fill")
                        Text(wearableManager.isStreaming ? "Stop Feed" : "Start Feed")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(wearableManager.isStreaming ? .red : .green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(wearableManager.isStreaming ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                    .cornerRadius(6)
                }
            }
            .padding(10)
            .background(theme.secondaryPanelBgColor)
            .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
        }
    }

    private var cameraPlaceholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.system(size: 32))
                .foregroundColor(theme.secondaryTextColor)

            Text("NO CAMERA FEED ACTIVE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(theme.secondaryTextColor)

            Text("Click Start Feed below or register your glasses to stream visual data.")
                .font(.system(size: 10))
                .foregroundColor(theme.secondaryTextColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Phase picker + capture

    private var controlPanel: some View {
        VStack(spacing: 12) {
            // Vertical Radio Button Phase Select
            VStack(spacing: 8) {
                ForEach(Phase.all) { phase in
                    Button(action: {
                        selectedPhase = phase
                    }) {
                        HStack(spacing: 12) {
                            Circle()
                                .strokeBorder(selectedPhase == phase ? Color.blue : Color.gray.opacity(0.5), lineWidth: 2)
                                .background(
                                    Circle()
                                        .fill(selectedPhase == phase ? Color.blue : Color.clear)
                                        .padding(4)
                                )
                                .frame(width: 18, height: 18)

                            Text(phase.name)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(theme.primaryTextColor)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPhase == phase ? Color.blue.opacity(0.12) : theme.secondaryPanelBgColor.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedPhase == phase ? Color.blue.opacity(0.4) : theme.panelBorderColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 4)

            // Optional Custom Text Prompt
            HStack(spacing: 8) {
                Image(systemName: "pencil.and.outline")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))

                TextField("Optional: Ask a specific question...", text: $customPromptText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(theme.primaryTextColor)
                    .font(.system(size: 13, design: .monospaced))

                if !customPromptText.isEmpty {
                    Button(action: { customPromptText = "" }) {
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
            .padding(.horizontal, 4)

            // High-res analyse button (1080×1440 photo capture)
            Button(action: { triggerInspection(highRes: true) }) {
                HStack(spacing: 8) {
                    if geminiManager.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("COMPILING REPORT...")
                    } else {
                        Image(systemName: "sparkles")
                        Text("ANALYSE CURRENT FRAME (1080×1440)")
                    }
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canScan && !isCapturingOnlyPhoto ? Color.blue : Color.gray.opacity(0.3))
                )
            }
            .disabled(!canScan || geminiManager.isAnalyzing || isCapturingOnlyPhoto)

            // Low-res analyse button (360×640 stream frame)
            Button(action: { triggerInspection(highRes: false) }) {
                HStack(spacing: 8) {
                    if geminiManager.isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("COMPILING REPORT...")
                    } else {
                        Image(systemName: "sparkles")
                        Text("ANALYSE CURRENT FRAME (360×640)")
                    }
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canScan && !isCapturingOnlyPhoto ? Color.indigo : Color.gray.opacity(0.3))
                )
            }
            .disabled(!canScan || geminiManager.isAnalyzing || isCapturingOnlyPhoto)

            // Capture Photo Only Button (bypass Gemini API for verification)
            Button(action: captureOnlyPhoto) {
                HStack(spacing: 8) {
                    if isCapturingOnlyPhoto {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("CAPTURING PHOTO...")
                    } else {
                        Image(systemName: "camera.fill")
                        Text("CAPTURE HIGH-RES ONLY")
                    }
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(wearableManager.isStreaming && !geminiManager.isAnalyzing && !isCapturingOnlyPhoto ? Color.green : Color.gray.opacity(0.3))
                )
            }
            .disabled(!wearableManager.isStreaming || geminiManager.isAnalyzing || isCapturingOnlyPhoto)

            Divider()
                .padding(.vertical, 4)

            // App settings link directly in the control panel
            Button(action: {
                showSettingsSheet = true
            }) {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.blue)
                    Text("API & Model Settings")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                    Spacer()
                    if !geminiManager.hasAPIKey {
                        Text("KEY MISSING")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    } else {
                        Text(geminiManager.selectedModel.replacingOccurrences(of: "gemini-", with: ""))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.secondaryTextColor)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryTextColor)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(theme.panelBgColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.panelBorderColor, lineWidth: 1)
        )
    }

    // MARK: - Actions

    private var canScan: Bool {
        wearableManager.isStreaming && wearableManager.currentFrame != nil
    }

    @MainActor
    private func triggerInspection(highRes: Bool) {
        guard let fallbackFrame = wearableManager.currentFrame else { return }

        let promptToSend = customPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        customPromptText = "" // Clear input field immediately

        // Switch to the Audit Log tab so they can see the progress of the analysis
        selectedTab = 1

        // Set analyzing state immediately so the button disables and displays "COMPILING REPORT..."
        geminiManager.isAnalyzing = true
        geminiManager.analysisResult = highRes ? "Capturing high-res photo..." : "Analysing stream frame..."

        Task {
            let trialId = UUID()
            let imageToAnalyze: UIImage
            let captureMode: String

            if highRes, let highResPhoto = await wearableManager.capturePhoto() {
                imageToAnalyze = highResPhoto
                captureMode = "high_res_photo"
                print("Using high-resolution photo for analysis: \(highResPhoto.size)")
            } else {
                imageToAnalyze = fallbackFrame
                captureMode = "stream_frame"
                print("Using stream frame for analysis: \(fallbackFrame.size)")
            }

            // Add User query placeholder with the selected image
            let userMsgText = promptToSend.isEmpty ? "Inspecting workspace (Mode: \(selectedPhase.name))" : promptToSend
            var userMsg = MessageItem(
                timestamp: Date(),
                isUser: true,
                text: userMsgText,
                imageThumbnail: imageToAnalyze
            )
            userMsg.trialId = trialId
            chatLog.chatHistory.append(userMsg)

            // Call analyzeFrame which will internally perform analysis and update isAnalyzing / analysisResult
            let answer = await geminiManager.analyzeFrame(
                image: imageToAnalyze,
                phase: selectedPhase,
                customPrompt: promptToSend.isEmpty ? nil : promptToSend
            )

            // Add Gemini response item
            var aiMsg = MessageItem(
                timestamp: Date(),
                isUser: false,
                text: answer,
                imageThumbnail: nil
            )
            aiMsg.trialId = trialId
            chatLog.chatHistory.append(aiMsg)

            // Log trial in TelemetryManager
            let source = wearableManager.isMockMode ? "simulator" : "live_device"
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
                 phase: selectedPhase.name,
                 source: source,
                 captureMode: captureMode,
                 imageSize: imageToAnalyze.size,
                 latency: geminiManager.lastResponseTime,
                 prompt: promptToSend.isEmpty ? selectedPhase.defaultPrompt : promptToSend,
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
            SpeechManager.shared.speak(answer)
        }
    }

    @MainActor
    private func captureOnlyPhoto() {
        guard wearableManager.isStreaming else { return }

        isCapturingOnlyPhoto = true

        Task {
            if let highResPhoto = await wearableManager.capturePhoto() {
                print("Successfully captured high-res photo: \(highResPhoto.size)")
                let msg = MessageItem(
                    timestamp: Date(),
                    isUser: false,
                    text: "Successfully captured and saved high-resolution photo (\(Int(highResPhoto.size.width))x\(Int(highResPhoto.size.height))) to Photos Library.",
                    imageThumbnail: highResPhoto
                )
                chatLog.chatHistory.append(msg)
            } else {
                print("Failed or timed out capturing high-res photo.")
                let msg = MessageItem(
                    timestamp: Date(),
                    isUser: false,
                    text: "Error: Failed to capture high-resolution photo from glasses.",
                    imageThumbnail: nil
                )
                chatLog.chatHistory.append(msg)
            }
            isCapturingOnlyPhoto = false
        }
    }
}
