import SwiftUI

// MARK: - Chat model

struct MessageItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let isUser: Bool
    let text: String
    let imageThumbnail: UIImage?
    var trialId: UUID? = nil
}

// MARK: - Shared small components

/// App title + glasses connect/disconnect status pill, with an optional settings gear (shown
/// only on the Audit Log tab, matching the original layout). Identical across both tabs, so it
/// lives here once instead of being copy-pasted per tab.
struct HeaderView: View {
    @ObservedObject var wearableManager: WearableManager
    @ObservedObject var geminiManager: GeminiManager
    let theme: Theme
    let showSettingsGear: Bool
    @Binding var showDisconnectAlert: Bool
    @Binding var showSettingsSheet: Bool

    private var statusColor: Color {
        if wearableManager.isRegistered {
            return wearableManager.isMockMode ? .orange : .green
        }
        return .red
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SMART EYES")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(theme.primaryTextColor)

                Text("AI Visual Safety Assistant")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
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
}

// MARK: - Formatting helpers

func formattedTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

// MARK: - Rounded-corner shape helper (used by chat bubbles & panels)

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
