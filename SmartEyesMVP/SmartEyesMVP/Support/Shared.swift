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

/// Small numbered step header used to walk the user through a tab's flow (e.g. "1. Choose a
/// use case", "2. Take a photo"). Shared by SetupView and InspectionView so the two don't drift
/// in styling.
struct StepLabel: View {
    let number: Int
    let title: String
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.blue))

            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(theme.secondaryTextColor)

            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

/// App title + glasses connect/disconnect status pill. Identical across all three tabs, so it
/// lives here once instead of being copy-pasted per tab.
struct HeaderView: View {
    @ObservedObject var wearableManager: WearableManager
    let theme: Theme
    @Binding var showDisconnectAlert: Bool

    private var statusColor: Color {
        wearableManager.isRegistered ? .green : .red
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SMART EYES: MVP")
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(theme.primaryTextColor)

                Text("AI Visual Safety Assistant")
                    .font(.caption)
                    .foregroundColor(theme.secondaryTextColor)
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

                    Text(wearableManager.isRegistered ? "READY" : "CONNECT GLASSES")
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
