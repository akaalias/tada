import SwiftUI

/// Banner shown at the top of content views when no valid API key is configured.
struct APIKeyBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundColor(.orange)

            Text("Anthropic API key not configured")
                .font(.system(size: Theme.fontSize))

            Spacer()

            Button("Open Settings") {
                SettingsWindowManager.shared.openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    APIKeyBanner()
        .padding()
}
