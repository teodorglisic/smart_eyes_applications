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
    @StateObject private var voiceQuestionManager = VoiceQuestionManager.shared

    @State private var selectedUseCase: UseCase = .pipeAnalysis
    @State private var chatHistory: [MessageItem] = [
        MessageItem(
            timestamp: Date().addingTimeInterval(-60),
            isUser: false,
            text: "Welcome to Smart Eyes. In the Inspection tab: connect your Meta Glasses, choose a use case, and take a photo. Then come back here to ask your question.",
            imageThumbnail: nil
        )
    ]

    // UI states
    @State private var autoScrollProxy: ScrollViewProxy? = nil
    @State private var showDisconnectAlert = false
    @State private var showSettingsSheet = false
    @State private var isCapturingPhoto = false
    @State private var capturedPhoto: UIImage? = nil
    @State private var questionText = ""
    @State private var hasAskedAboutCurrentPhoto = false
    @State private var selectedTab = 0
    @FocusState private var isQuestionFieldFocused: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: Setup — device connection, mode, voice output, API/model config
            ZStack {
                mainBgColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 16) {
                            setupPanel
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .tabItem {
                Label("Setup", systemImage: "gearshape.fill")
            }
            .tag(0)

            // Tab 1: Live Inspection View
            ZStack {
                mainBgColor
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 16) {
                            videoFeedPanel
                            controlPanel
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .tabItem {
                Label("Inspection", systemImage: "sparkles.tv")
            }
            .tag(1)

            // Tab 2: Audit Log — also the live chat surface for the photo captured in
            // the Inspection tab (see the composer pinned below chatLogPanel).
            ZStack {
                mainBgColor
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    headerView()
                    chatLogPanel
                    questionCaptureSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .tabItem {
                Label("Audit Log", systemImage: "doc.text.magnifyingglass")
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
    
    // MARK: - Component Subviews
    
    private func headerView() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SMART EYES: MVP")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(primaryTextColor)

                Text("AI Visual Safety Assistant")
                    .font(.caption)
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()

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
            
            // Bottom status strip — feed start/stop lives on the Setup tab now
            HStack {
                if wearableManager.isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    Text(wearableManager.isStreaming ? "Connected" : "Feed not started — go to Setup")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                }

                Spacer()
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
            
            Text("Go to the Setup tab to connect your glasses and start the feed.")
                .font(.system(size: 10))
                .foregroundColor(secondaryTextColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var controlPanel: some View {
        VStack(spacing: 12) {
            // Step 1: Use Case Selector
            stepLabel(number: 1, title: "Choose a use case")

            Menu {
                ForEach(UseCase.all) { useCase in
                    Button(action: {
                        selectedUseCase = useCase
                    }) {
                        Label(useCase.name, systemImage: useCase.icon)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedUseCase.icon)
                        .foregroundColor(.blue)
                        .frame(width: 18)

                    Text(selectedUseCase.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(primaryTextColor)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.blue.opacity(0.4), lineWidth: 1)
                )
            }
            .disabled(capturedPhoto != nil)
            .opacity(capturedPhoto != nil ? 0.5 : 1.0)
            .padding(.horizontal, 4)

            Divider().padding(.vertical, 2)

            // Step 2: Take Photo
            stepLabel(number: 2, title: "Take a photo")

            if let photo = capturedPhoto {
                HStack(spacing: 10) {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(hasAskedAboutCurrentPhoto ? "In conversation in the Audit Log (\(selectedUseCase.name))" : "Captured for \(selectedUseCase.name) — ask about it in the Audit Log")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)

                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            Button(action: capturePhotoStep) {
                HStack(spacing: 8) {
                    if isCapturingPhoto {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("CAPTURING PHOTO...")
                    } else {
                        Image(systemName: "camera.fill")
                        Text(capturedPhoto == nil ? "TAKE PHOTO" : "TAKE NEW PHOTO")
                    }
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canScan && !isCapturingPhoto ? Color.green : Color.gray.opacity(0.3))
                )
            }
            .disabled(!canScan || isCapturingPhoto)
        }
        .padding(12)
        .background(panelBgColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(panelBorderColor, lineWidth: 1)
        )
    }

    /// Setup tab: device connection, feed control, simulation mode, voice output, and API/model
    /// config — everything you set up once per session, kept off the busier Inspection tab.
    private var setupPanel: some View {
        VStack(spacing: 16) {
            // Device connection & feed card
            VStack(alignment: .leading, spacing: 10) {
                stepLabel(number: 1, title: "Device")

                HStack {
                    Text(wearableManager.isRegistered ? (wearableManager.isMockMode ? "Simulator connected" : "Glasses connected") : "Not connected")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(primaryTextColor)
                    Spacer()
                    Button(action: {
                        if wearableManager.isRegistered {
                            showDisconnectAlert = true
                        } else {
                            wearableManager.registerDevice()
                        }
                    }) {
                        Text(wearableManager.isRegistered ? "Disconnect" : "Connect")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(wearableManager.isRegistered ? .red : .blue)
                    }
                }

                Divider()

                HStack {
                    if wearableManager.isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    } else {
                        Text(wearableManager.isStreaming ? "Feed: Streaming" : "Feed: Idle")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(secondaryTextColor)
                    }

                    Spacer()

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

                Divider()

                HStack {
                    Text("Mode: \(wearableManager.isMockMode ? "Simulation" : "Live Device")")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Button(action: {
                        wearableManager.toggleMockMode()
                    }) {
                        Text(wearableManager.isMockMode ? "Switch to Live Device" : "Switch to Simulation")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(12)
            .background(panelBgColor)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(panelBorderColor, lineWidth: 1))

            // Voice output card
            VStack(alignment: .leading, spacing: 10) {
                stepLabel(number: 2, title: "Voice output")

                HStack {
                    Text("Read answers aloud")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(primaryTextColor)
                    Spacer()
                    Button(action: {
                        speechManager.isVoiceEnabled.toggle()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: speechManager.isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            Text(speechManager.isVoiceEnabled ? "VOICE ON" : "VOICE OFF")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(speechManager.isVoiceEnabled ? .green : secondaryTextColor)
                    }
                }
            }
            .padding(12)
            .background(panelBgColor)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(panelBorderColor, lineWidth: 1))

            // API & model settings card
            VStack(alignment: .leading, spacing: 10) {
                stepLabel(number: 3, title: "AI model")

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
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(panelBorderColor, lineWidth: 1))
        }
    }

    /// Small numbered step header used to walk the user through each tab's flow.
    private func stepLabel(number: Int, title: String) -> some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.blue))

            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(secondaryTextColor)

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    /// Mic button to dictate a question, an editable transcript field so the user can fix
    /// misheard words, and explicit Cancel / Send controls (manual confirm, no auto-submit).
    /// Lives at the bottom of the Audit Log tab, pinned below the chat thread, so asking a
    /// follow-up about the currently captured photo never requires leaving that screen.
    private var questionCaptureSection: some View {
        VStack(spacing: 8) {
            if capturedPhoto == nil {
                Text("Take a photo in the Inspection tab to start asking questions.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
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
                            .fill(voiceQuestionManager.isListening ? Color.red : (capturedPhoto != nil ? Color.blue : Color.gray.opacity(0.3)))
                    )
                }
                .disabled(capturedPhoto == nil || geminiManager.isAnalyzing)

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
                TextField(hasAskedAboutCurrentPhoto ? "Ask a follow-up about this photo..." : "Tap the mic and ask, or type your question...", text: $questionText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(primaryTextColor)
                    .font(.system(size: 13, design: .monospaced))
                    .disabled(capturedPhoto == nil)
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
                .disabled(capturedPhoto == nil)

                Button(action: sendQuestion) {
                    HStack(spacing: 6) {
                        if geminiManager.isAnalyzing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("SENDING...")
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text(hasAskedAboutCurrentPhoto ? "ASK FOLLOW-UP" : "SEND")
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
        capturedPhoto != nil && !questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !geminiManager.isAnalyzing
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

    private var chatLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AUDIT LOG")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(secondaryTextColor)

                Spacer()

                Text(wearableManager.isMockMode ? "SIMULATION" : "LIVE DEVICE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(secondaryTextColor)
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

                        if geminiManager.isAnalyzing {
                            HStack(alignment: .top, spacing: 8) {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: secondaryTextColor))
                                        .scaleEffect(0.7)
                                    Text(geminiManager.analysisResult)
                                        .font(.system(size: 13))
                                        .foregroundColor(secondaryTextColor)
                                }
                                .padding(10)
                                .background(secondaryPanelBgColor)
                                .cornerRadius(12, corners: [.topRight, .bottomLeft, .bottomRight])

                                Spacer()
                            }
                        }

                        Color.clear.frame(height: 1).id("auditLogBottom")
                    }
                    .padding(.vertical, 4)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    autoScrollProxy = proxy
                }
                .onChange(of: chatHistory.count) { _ in
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
                    // Image thumbnail representing what was scanned
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
    
    /// Captures a high-res photo (falling back to the current stream frame), holds it in
    /// `capturedPhoto`, then jumps to the Audit Log tab — that's where questions about it get
    /// asked, so the photo needs to already be waiting there when the user arrives.
    @MainActor
    private func capturePhotoStep() {
        guard let fallbackFrame = wearableManager.currentFrame else { return }

        isCapturingPhoto = true
        hasAskedAboutCurrentPhoto = false
        geminiManager.startNewConversation()

        Task {
            if let highResPhoto = await wearableManager.capturePhoto() {
                capturedPhoto = highResPhoto
                print("Using high-resolution photo for analysis: \(highResPhoto.size)")
            } else {
                capturedPhoto = fallbackFrame
                print("Using stream frame for analysis: \(fallbackFrame.size)")
            }

            // Post the photo to the log right away, before any question is asked — so it's
            // visible in the Audit Log as soon as the user arrives there, not only once they've
            // typed/sent a question about it.
            if let photo = capturedPhoto {
                chatHistory.append(MessageItem(
                    timestamp: Date(),
                    isUser: true,
                    text: "Photo captured for \(selectedUseCase.name)",
                    imageThumbnail: photo
                ))
            }

            isCapturingPhoto = false
            selectedTab = 2
        }
    }

    /// Discards the captured photo and ends its conversation. To start a new one, the user
    /// goes back to the Inspection tab and captures a fresh photo.
    private func retakePhoto() {
        capturedPhoto = nil
        questionText = ""
        hasAskedAboutCurrentPhoto = false
        geminiManager.startNewConversation()
        if voiceQuestionManager.isListening {
            voiceQuestionManager.cancel()
        }
    }

    /// Sends the transcribed/typed question to Gemini about the captured photo, using the
    /// selected use case's context prompt. Called from the Audit Log tab's composer. The photo
    /// (and Gemini's conversation about it) stays active afterwards so the user can immediately
    /// ask a follow-up right there — tap "Cancel" to discard it, or capture a new photo from the
    /// Inspection tab to start over.
    @MainActor
    private func sendQuestion() {
        guard let image = capturedPhoto else { return }
        let question = questionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        let useCase = selectedUseCase
        let isFollowUp = hasAskedAboutCurrentPhoto

        // Clear the question field and mark this photo as "in conversation" immediately so the
        // UI is ready for a follow-up, but keep the photo itself around for that follow-up.
        questionText = ""
        hasAskedAboutCurrentPhoto = true
        voiceQuestionManager.cancel()
        isQuestionFieldFocused = false

        geminiManager.isAnalyzing = true
        geminiManager.analysisResult = "Analyzing photo..."

        Task {
            let trialId = UUID()

            // No imageThumbnail here — the photo was already posted to the log the moment it
            // was captured (see capturePhotoStep), so repeating it on every question would be
            // redundant.
            var userMsg = MessageItem(
                timestamp: Date(),
                isUser: true,
                text: isFollowUp ? "(follow-up) \(question)" : question,
                imageThumbnail: nil
            )
            userMsg.trialId = trialId
            chatHistory.append(userMsg)

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
            proxy.scrollTo("auditLogBottom", anchor: .bottom)
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
                text: "Welcome to Smart Eyes. In the Inspection tab: connect your Meta Glasses, choose a use case, and take a photo. Then come back here to ask your question.",
                imageThumbnail: nil
            )
        ]
        // Purging wipes chatHistory back down to just the welcome message, so any in-progress
        // photo conversation is no longer meaningful either.
        capturedPhoto = nil
        questionText = ""
        hasAskedAboutCurrentPhoto = false
        geminiManager.startNewConversation()
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
                            Text("Gemini 3.1 Flash Lite Preview").tag("gemini-3.1-flash-lite-preview")
                            Text("Gemini 3 Flash Preview").tag("gemini-3-flash-preview")
                            Text("Gemini Flash Lite Latest").tag("gemini-flash-lite-latest")
                            Text("Gemini 2.5 Flash").tag("gemini-2.5-flash")
                            Text("Gemini 2.5 Flash Lite").tag("gemini-2.5-flash-lite")
                            Text("Gemini Robotics-ER 1.6 Preview").tag("gemini-robotics-er-1.6-preview")
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
