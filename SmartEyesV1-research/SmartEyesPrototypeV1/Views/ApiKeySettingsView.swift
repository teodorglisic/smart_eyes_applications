import SwiftUI

/// "API & Model Settings" sheet, opened from the Audit Log tab's gear icon or the Inspection
/// tab's settings row. The API key itself is managed by Firebase (via GoogleService-Info.plist)
/// and never entered here — this screen only lets the user pick which Gemini/Gemma model to
/// target, from `GeminiModel.all` (see GeminiModelCatalog.swift).
struct ApiKeySettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    private var theme: Theme { Theme(colorScheme: colorScheme) }

    @State private var selectedModel: String = GeminiModel.default.id

    var body: some View {
        NavigationView {
            ZStack {
                theme.mainBgColor
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    Text("Configure Gemini Model")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(theme.primaryTextColor)
                        .padding(.top, 16)

                    Text("Choose which Gemini model to use for live analysis. The API key is managed securely via Firebase and does not need to be entered here.")
                        .font(.footnote)
                        .foregroundColor(theme.secondaryTextColor)
                        .lineSpacing(4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("TARGET AI MODEL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)

                        Picker("Select Model", selection: $selectedModel) {
                            ForEach(GeminiModel.all) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(theme.panelBgColor)
                        .cornerRadius(8)
                        .foregroundColor(theme.primaryTextColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.panelBorderColor, lineWidth: 1)
                        )
                    }

                    Spacer()

                    Button(action: saveConfiguration) {
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
            selectedModel = UserDefaults.standard.string(forKey: "GEMINI_MODEL_NAME") ?? GeminiModel.default.id
        }
    }

    private func saveConfiguration() {
        UserDefaults.standard.set(selectedModel, forKey: "GEMINI_MODEL_NAME")
        GeminiManager.shared.updateModel(selectedModel)
        dismiss()
    }
}
