import SwiftUI

struct ContentView: View {
    /// True when the on-device store could not open and changes will not be kept.
    var isTemporaryStore = false

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    private let chrome = LinearGradient(
        colors: [
            Color(red: 0.93, green: 0.95, blue: 0.98),
            Color(red: 0.56, green: 0.61, blue: 0.68),
            Color(red: 0.86, green: 0.89, blue: 0.94),
            Color(red: 0.36, green: 0.40, blue: 0.47)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.045, blue: 0.055)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("DAILY")
                    .font(.system(size: 68, weight: .semibold, design: .serif))
                    .tracking(8)
                    .foregroundStyle(chrome)

                Text(isTemporaryStore ? "Temporary storage · changes not saved" : "Core engine · M2")
                    .font(.footnote)
                    .tracking(2)
                    .foregroundStyle(.secondary)

                Text(versionText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    ContentView()
}
