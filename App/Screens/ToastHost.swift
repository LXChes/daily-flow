import SwiftUI

/// The short message that confirms an action. It floats above the content and never takes touches.
struct ToastHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast.text)
                    .dfStyle(.body)
                    .foregroundStyle(palette.toastInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(palette.toastBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: palette.scrim, radius: 18, y: 10)
                    .padding(.horizontal, 20)
                    .id(toast.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}
