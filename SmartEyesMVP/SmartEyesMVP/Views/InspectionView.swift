import SwiftUI

/// Inspection tab: live glasses video feed, use-case picker, and the "take a photo" action.
/// Capturing a photo here hands it off to `session` and jumps to the Chat Log tab, where the
/// actual question gets asked about it.
struct InspectionView: View {
    @Environment(\.colorScheme) var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    @ObservedObject var wearableManager: WearableManager
    @ObservedObject var geminiManager: GeminiManager
    @ObservedObject var session: InspectionSessionState

    @Binding var showDisconnectAlert: Bool
    @Binding var selectedTab: Int

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
                        videoFeedPanel
                        controlPanel
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
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
                            Image(systemName: "eyeglasses")
                            Text("DAT LIVE")
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

            Text("Go to the Setup tab to connect your glasses and start the feed.")
                .font(.system(size: 10))
                .foregroundColor(theme.secondaryTextColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Use case + capture

    private var controlPanel: some View {
        VStack(spacing: 12) {
            // Step 1: Use Case Selector
            StepLabel(number: 1, title: "Choose a use case", theme: theme)

            Menu {
                ForEach(UseCase.all) { useCase in
                    Button(action: {
                        session.selectedUseCase = useCase
                    }) {
                        Label(useCase.name, systemImage: useCase.icon)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: session.selectedUseCase.icon)
                        .foregroundColor(.blue)
                        .frame(width: 18)

                    Text(session.selectedUseCase.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.primaryTextColor)

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
            .disabled(session.capturedPhoto != nil)
            .opacity(session.capturedPhoto != nil ? 0.5 : 1.0)
            .padding(.horizontal, 4)

            Divider().padding(.vertical, 2)

            // Step 2: Take Photo
            StepLabel(number: 2, title: "Take a photo", theme: theme)

            if let photo = session.capturedPhoto {
                HStack(spacing: 10) {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Text(session.hasAskedAboutCurrentPhoto ? "In conversation in the Chat Log (\(session.selectedUseCase.name))" : "Captured for \(session.selectedUseCase.name) — ask about it in the Chat Log")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.secondaryTextColor)

                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            Button(action: capturePhotoStep) {
                HStack(spacing: 8) {
                    if session.isCapturingPhoto {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("CAPTURING PHOTO...")
                    } else {
                        Image(systemName: "camera.fill")
                        Text(session.capturedPhoto == nil ? "TAKE PHOTO" : "TAKE NEW PHOTO")
                    }
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canScan && !session.isCapturingPhoto ? Color.green : Color.gray.opacity(0.3))
                )
            }
            .disabled(!canScan || session.isCapturingPhoto)
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

    /// Captures a high-res photo (falling back to the current stream frame), holds it in
    /// `session.capturedPhoto`, then jumps to the Chat Log tab — that's where questions about it
    /// get asked, so the photo needs to already be waiting there when the user arrives.
    @MainActor
    private func capturePhotoStep() {
        guard let fallbackFrame = wearableManager.currentFrame else { return }

        session.isCapturingPhoto = true
        session.hasAskedAboutCurrentPhoto = false
        geminiManager.startNewConversation()

        Task {
            let photo: UIImage
            if let highResPhoto = await wearableManager.capturePhoto() {
                photo = highResPhoto
                print("Using high-resolution photo for analysis: \(highResPhoto.size)")
            } else {
                photo = fallbackFrame
                print("Using stream frame for analysis: \(fallbackFrame.size)")
            }
            session.capturedPhoto = photo

            // Post the photo to the log right away, before any question is asked — so it's
            // visible in the Chat Log as soon as the user arrives there, not only once they've
            // typed/sent a question about it.
            session.chatHistory.append(MessageItem(
                timestamp: Date(),
                isUser: true,
                text: "Photo captured for \(session.selectedUseCase.name)",
                imageThumbnail: photo
            ))

            session.isCapturingPhoto = false
            selectedTab = 2
        }
    }
}
