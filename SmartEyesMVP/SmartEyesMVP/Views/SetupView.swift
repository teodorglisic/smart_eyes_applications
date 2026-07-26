import SwiftUI

/// Setup tab: device connection, feed control, voice output, and API/model config —
/// everything you set up once per session, kept off the busier Inspection tab.
struct SetupView: View {
    @Environment(\.colorScheme) var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    @ObservedObject var wearableManager: WearableManager
    @ObservedObject var geminiManager: GeminiManager
    @ObservedObject var speechManager: SpeechManager

    @Binding var showDisconnectAlert: Bool
    @Binding var showSettingsSheet: Bool

    var body: some View {
        ZStack {
            theme.mainBgColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView(wearableManager: wearableManager, theme: theme, showDisconnectAlert: $showDisconnectAlert)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        deviceCard
                        voiceOutputCard
                        modelSettingsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Cards

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepLabel(number: 1, title: "Device", theme: theme)

            HStack {
                Text(wearableManager.isRegistered ? "Glasses connected" : "Not connected")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.primaryTextColor)
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
                        .foregroundColor(theme.secondaryTextColor)
                } else {
                    Text(wearableManager.isStreaming ? "Feed: Streaming" : "Feed: Idle")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.secondaryTextColor)
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
        }
        .padding(12)
        .background(theme.panelBgColor)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.panelBorderColor, lineWidth: 1))
    }

    private var voiceOutputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepLabel(number: 2, title: "Voice output", theme: theme)

            HStack {
                Text("Read answers aloud")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(theme.primaryTextColor)
                Spacer()
                Button(action: {
                    speechManager.isVoiceEnabled.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: speechManager.isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        Text(speechManager.isVoiceEnabled ? "VOICE ON" : "VOICE OFF")
                    }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(speechManager.isVoiceEnabled ? .green : theme.secondaryTextColor)
                }
            }
        }
        .padding(12)
        .background(theme.panelBgColor)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.panelBorderColor, lineWidth: 1))
    }

    private var modelSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepLabel(number: 3, title: "AI model", theme: theme)

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
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.panelBorderColor, lineWidth: 1))
    }
}
