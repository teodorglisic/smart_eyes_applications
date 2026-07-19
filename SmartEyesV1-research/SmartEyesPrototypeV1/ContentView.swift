import SwiftUI
import AudioToolbox

struct MessageItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let isUser: Bool
    let text: String
    let imageThumbnail: UIImage?
    var trialId: UUID? = nil
}

struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.1, green: 0.12, blue: 0.16)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : Color(red: 0.45, green: 0.47, blue: 0.52)
    }
    
    private var mainBgColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.12) : Color(red: 0.96, green: 0.97, blue: 0.98)
    }
    
    private var panelBgColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.18) : Color.white
    }
    
    private var secondaryPanelBgColor: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.17, blue: 0.22) : Color(red: 0.91, green: 0.92, blue: 0.95)
    }
    
    private var panelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }
    
    private var textBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.12)
    }

    @StateObject private var wearableManager = WearableManager.shared
    @StateObject private var geminiManager = GeminiManager.shared
    @StateObject private var speechManager = SpeechManager.shared
    @StateObject private var telemetryManager = TelemetryManager.shared
    @StateObject private var voiceTriggerManager = VoiceTriggerManager.shared
    
    @State private var selectedMode: InspectionMode = .phase1
    @State private var chatHistory: [MessageItem] = [
        MessageItem(
            timestamp: Date().addingTimeInterval(-60),
            isUser: false,
            text: "Welcome to Smart Eyes. Connect your Meta Glasses and select an inspection mode to begin your compliance audit.",
            imageThumbnail: nil
        )
    ]
    
    // UI states
    @State private var autoScrollProxy: ScrollViewProxy? = nil
    @State private var showDisconnectAlert = false
    @State private var showSettingsSheet = false
    @State private var isCapturingOnlyPhoto = false
    @State private var customPromptText = ""
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Live Inspection View
            ZStack {
                mainBgColor
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    headerView(showSettingsGear: false)
                    videoFeedPanel
                    controlPanel
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .tabItem {
                Label("Inspection", systemImage: "sparkles.tv")
            }
            .tag(0)
            
            // Tab 2: Audit History Log
            ZStack {
                mainBgColor
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    headerView(showSettingsGear: true)
                    chatLogPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
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
    
    // MARK: - Component Subviews
    
    private func headerView(showSettingsGear: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SMART EYES")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(primaryTextColor)
                
                Text("AI Visual Safety Assistant")
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                // Connection Status / Registration Button
                Button(action: {
                    if wearableManager.isRegistered {
                        showDisconnectAlert = true
                    } else {
                        wearableManager.registerDevice()
                    }
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                            .shadow(color: statusColor, radius: 4)
                        
                        Text(wearableManager.isRegistered ? (wearableManager.isMockMode ? "SIMULATOR" : "READY") : "CONNECT GLASSES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(statusColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor.opacity(0.12))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(statusColor.opacity(0.3), lineWidth: 1)
                    )
                }
                
                if showSettingsGear {
                    // Settings Gear Button with API Key status indicator
                    Button(action: {
                        showSettingsSheet = true
                    }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Circle())
                            
                            // API Key Status Indicator Dot
                            Circle()
                                .fill(geminiManager.hasAPIKey ? Color.green : Color.red)
                                .frame(width: 7, height: 7)
                                .offset(x: 1, y: -1)
                                .shadow(color: geminiManager.hasAPIKey ? .green : .red, radius: 2)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
    
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
                    // Placeholder when stream is off
                    cameraPlaceholderView
                }
                
                // Top Overlays
                VStack {
                    HStack {
                        // Battery or Source Indicator
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
                        
                        // Active Stream indicator
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
            .background(panelBgColor)
            .cornerRadius(12, corners: [.topLeft, .topRight])
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(panelBorderColor, lineWidth: 1)
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
            .background(secondaryPanelBgColor)
            .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
        }
    }
    
    private var cameraPlaceholderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "video.slash")
                .font(.system(size: 32))
                .foregroundColor(secondaryTextColor)
            
            Text("NO CAMERA FEED ACTIVE")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(secondaryTextColor)
            
            Text("Click Start Feed below or register your glasses to stream visual data.")
                .font(.system(size: 10))
                .foregroundColor(secondaryTextColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var controlPanel: some View {
        VStack(spacing: 12) {
            // Vertical Radio Button Mode Select
            VStack(spacing: 8) {
                ForEach(InspectionMode.allCases) { mode in
                    Button(action: {
                        selectedMode = mode
                    }) {
                        HStack(spacing: 12) {
                            // Radio indicator
                            Circle()
                                .strokeBorder(selectedMode == mode ? Color.blue : Color.gray.opacity(0.5), lineWidth: 2)
                                .background(
                                    Circle()
                                        .fill(selectedMode == mode ? Color.blue : Color.clear)
                                        .padding(4)
                                )
                                .frame(width: 18, height: 18)
                            
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(primaryTextColor)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedMode == mode ? Color.blue.opacity(0.12) : secondaryPanelBgColor.opacity(0.3))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedMode == mode ? Color.blue.opacity(0.4) : panelBorderColor, lineWidth: 1)
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
                    .foregroundColor(primaryTextColor)
                    .font(.system(size: 13, design: .monospaced))
                
                if !customPromptText.isEmpty {
                    Button(action: { customPromptText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(secondaryTextColor)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(10)
            .background(mainBgColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(textBorderColor, lineWidth: 1)
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
                            .foregroundColor(secondaryTextColor)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(panelBgColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(panelBorderColor, lineWidth: 1)
        )
    }
    
    private var chatLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AUDIT LOG")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
                
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
                    .foregroundColor(speechManager.isVoiceEnabled ? .green : secondaryTextColor)
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
                    .foregroundColor(secondaryTextColor)
                
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
                        ForEach(chatHistory) { item in
                            chatBubble(item)
                                .id(item.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    autoScrollProxy = proxy
                }
                .onChange(of: chatHistory.count) { _ in
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
                    // Image thumbnail representing what was scanned
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
                        .foregroundColor(secondaryTextColor)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Compliance Rating Badge
                    if let badge = complianceBadge(for: message.text) {
                        badge
                    }
                    
                    Text(message.text)
                        .font(.system(size: 14))
                        .foregroundColor(message.text.contains("Error") ? .red : primaryTextColor)
                        .padding(12)
                        .background(secondaryPanelBgColor)
                        .cornerRadius(12, corners: [.topRight, .bottomLeft, .bottomRight])
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(message.text.contains("Error") ? Color.red.opacity(0.3) : panelBorderColor.opacity(0.5), lineWidth: 1)
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
                    .foregroundColor(secondaryTextColor)
                    
                    if let trialId = message.trialId {
                        feedbackRow(for: trialId)
                    }
                }
                
                Spacer()
            }
        }
    }
    
    // MARK: - Actions & Logic
    
    private var canScan: Bool {
        return wearableManager.isStreaming && wearableManager.currentFrame != nil
    }
    
    private var statusColor: Color {
        if wearableManager.isRegistered {
            return wearableManager.isMockMode ? .orange : .green
        }
        return .red
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
            let userMsgText = promptToSend.isEmpty ? "Inspecting workspace (Mode: \(selectedMode.rawValue))" : promptToSend
            var userMsg = MessageItem(
                timestamp: Date(),
                isUser: true,
                text: userMsgText,
                imageThumbnail: imageToAnalyze
            )
            userMsg.trialId = trialId
            chatHistory.append(userMsg)
            
            // Call analyzeFrame which will internally perform analysis and update isAnalyzing / analysisResult
            let answer = await geminiManager.analyzeFrame(
                image: imageToAnalyze,
                mode: selectedMode,
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
            chatHistory.append(aiMsg)
            
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
            
            let defaultPrompt = selectedMode == .phase1 ? "Identify the baseline objects and features in this image." : selectedMode == .phase2 ? "Perform high-precision technical inspection of this view." : "Analyze visual stress factors, anomalies, or degradation in this view."
            
            TelemetryManager.shared.logTrial(
                 id: trialId,
                 phase: selectedMode.rawValue,
                 source: source,
                 captureMode: captureMode,
                 imageSize: imageToAnalyze.size,
                 latency: geminiManager.lastResponseTime,
                 prompt: promptToSend.isEmpty ? defaultPrompt : promptToSend,
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
                chatHistory.append(msg)
            } else {
                print("Failed or timed out capturing high-res photo.")
                let msg = MessageItem(
                    timestamp: Date(),
                    isUser: false,
                    text: "Error: Failed to capture high-resolution photo from glasses.",
                    imageThumbnail: nil
                )
                chatHistory.append(msg)
            }
            isCapturingOnlyPhoto = false
        }
    }
    

    
    private func scrollToBottom() {
        guard let proxy = autoScrollProxy, let last = chatHistory.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
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
                        .foregroundColor(secondaryTextColor)
                    
                    Button(action: {
                        TelemetryManager.shared.submitFeedback(recordId: trialId, isCorrect: true, rating: record.rating1To5)
                    }) {
                        Image(systemName: record.isCorrect == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .foregroundColor(record.isCorrect == true ? .green : secondaryTextColor)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        TelemetryManager.shared.submitFeedback(recordId: trialId, isCorrect: false, rating: record.rating1To5)
                    }) {
                        Image(systemName: record.isCorrect == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .foregroundColor(record.isCorrect == false ? .red : secondaryTextColor)
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
                                .foregroundColor((record.rating1To5 ?? 0) >= star ? .yellow : secondaryTextColor)
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
        chatHistory = [
            MessageItem(
                timestamp: Date(),
                isUser: false,
                text: "Welcome to Smart Eyes. Connect your Meta Glasses and select an inspection mode to begin your compliance audit.",
                imageThumbnail: nil
            )
        ]
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

// MARK: - Extension for Custom Corner Shapes
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
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

struct ApiKeySettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedModel: String = "gemini-3.5-flash"
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.1, green: 0.12, blue: 0.16)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : Color(red: 0.45, green: 0.47, blue: 0.52)
    }
    
    private var mainBgColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.12) : Color(red: 0.96, green: 0.97, blue: 0.98)
    }
    
    private var panelBgColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.18) : Color.white
    }
    
    private var panelBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                mainBgColor
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 20) {
                    Text("Configure Gemini Model")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(primaryTextColor)
                        .padding(.top, 16)

                    Text("Choose which Gemini model to use for live analysis. The API key is managed securely via Firebase and does not need to be entered here.")
                        .font(.footnote)
                        .foregroundColor(secondaryTextColor)
                        .lineSpacing(4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("TARGET AI MODEL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                        
                        Picker("Select Model", selection: $selectedModel) {
                            Text("Gemini 3.5 Flash").tag("gemini-3.5-flash")
                            Text("Gemini 3.1 Flash Lite").tag("gemini-3.1-flash-lite")
                            Text("Gemini 3 Flash").tag("gemini-3-flash")
                            Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                            Text("Gemini 2.5 Flash Lite").tag("gemini-2.5-flash-lite")
                            Text("Gemma 4 26B (MoE)").tag("gemma-4-26b-a4b-it")
                            Text("Gemma 4 31B (Dense)").tag("gemma-4-31b-it")
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(panelBgColor)
                        .cornerRadius(8)
                        .foregroundColor(primaryTextColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(panelBorderColor, lineWidth: 1)
                        )
                    }
                    
                    Spacer()
                    
                    Button(action: saveKey) {
                        Text("SAVE CONFIGURATION")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .padding(.bottom, 16)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Dismiss") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            selectedModel = UserDefaults.standard.string(forKey: "GEMINI_MODEL_NAME") ?? "gemini-3.5-flash"
        }
    }

    private func saveKey() {
        UserDefaults.standard.set(selectedModel, forKey: "GEMINI_MODEL_NAME")
        GeminiManager.shared.updateModel(selectedModel)
        dismiss()
    }
}
