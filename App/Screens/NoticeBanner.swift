import SwiftUI

/// The iridescent banner shown only on a notice day (or while previewing one).
struct NoticeBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            SparkleShape()
                .fill(Palette.onIridescent)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.bannerTitle)
                    .dfStyle(.heading)
                    .lineLimit(2)
                Text("Notice \u{00B7} all day \u{00B7} only shows on the day")
                    .dfStyle(.caption)
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.onIridescent)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            IridescentFill()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(model.palette.bevel, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
