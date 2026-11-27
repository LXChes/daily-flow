import SwiftUI

/// The full list for today: tick, title, category and time, and the urgent bell.
struct TodaySection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TODAY")
                .dfStyle(.cardTitle)
                .tracking(0.8)
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)

            if model.items.isEmpty {
                Text("Nothing on today. Tap + to add something.")
                    .dfStyle(.label)
                    .foregroundStyle(palette.inkSecondary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.items) { item in
                        TaskRow(item: item)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .animation(model.animated(Motion.settle), value: model.items)
            }

            Text("Tap + to add for today or any future day")
                .dfStyle(.caption)
                .foregroundStyle(palette.inkSecondary)
                .padding(.vertical, 12)
        }
    }
}

private struct TaskRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let item: TaskItem

    var body: some View {
        HStack(spacing: 4) {
            TickButton(isDone: item.isDone, label: "Tick off \(item.title)", size: 28) {
                model.toggleDone(item.id)
            }
            .padding(.leading, -8)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .dfStyle(.rowTitle)
                    .strikethrough(item.isDone)
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                detail
            }
            .opacity(item.isDone ? 0.45 : 1)

            Spacer(minLength: 4)

            Button {
                model.toggleUrgent(item.id)
            } label: {
                Image(systemName: item.isUrgent ? "bell.fill" : "bell")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.isUrgent ? palette.urgent : palette.inkSecondary)
                    .symbolEffect(.bounce, value: item.isUrgent)
                    .frame(width: Metrics.hit, height: Metrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.88))
            .accessibilityLabel("Urgent reminder for \(item.title)")
            .accessibilityValue(item.isUrgent ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
        }
        .frame(minHeight: 58)
        .background(item.isUrgent && !item.isDone ? palette.urgentTint : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.line).frame(height: 1)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move to tomorrow", systemImage: "arrow.turn.down.right") {
                model.moveToTomorrow(item.id)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.delete(item.id)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: some View {
        HStack(spacing: 6) {
            if item.isUrgent && !item.isDone {
                Text("URGENT")
                    .dfStyle(.badge)
                    .foregroundStyle(palette.knob)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.urgent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            if model.isSorted {
                Circle()
                    .fill(palette.category(item.category))
                    .frame(width: 7, height: 7)
                Text(item.category.title)
                Text("\u{00B7}")
            }
            Text(item.spanText)
        }
        .dfFont(.caption)
        .foregroundStyle(palette.inkSecondary)
    }
}
