import SwiftUI

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(tint)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
    }
}

/// Horizontal bar split into productive / neutral / distracting.
struct ProductivityBar: View {
    let summary: Summary
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                if summary.total > 0 {
                    ForEach(Productivity.allCases) { p in
                        let fraction = summary.seconds(p) / summary.total
                        if fraction > 0 {
                            p.color.frame(width: max(2, geo.size.width * fraction - 1))
                        }
                    }
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

struct CategoryChip: View {
    let category: Category?

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(category?.color ?? Color.gray.opacity(0.45)).frame(width: 8, height: 8)
            Text(category?.name ?? "Uncategorized")
                .foregroundStyle(category == nil ? .secondary : .primary)
        }
        .font(.callout)
    }
}

/// Menu for (re)assigning an app or site to a category — creates a rule.
struct AssignMenu: View {
    @Environment(AppModel.self) private var model
    let item: ItemKey
    let current: Category?

    var body: some View {
        Menu {
            ForEach(model.store.config.categories) { category in
                Button {
                    model.store.assign(item, to: category.id)
                } label: {
                    Text("\(category.name) · \(category.productivity.label)")
                }
            }
            Divider()
            Button("Uncategorized") { model.store.assign(item, to: nil) }
        } label: {
            CategoryChip(category: current)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
    }
}

struct ItemIcon: View {
    let item: ItemTotal

    var body: some View {
        Image(systemName: item.key.kind == .domain ? "globe" : "app.dashed")
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }
}

struct ScoreRing: View {
    let score: Double?
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: (score ?? 0) / 100)
                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(formatScore(score))
                .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
        }
        .frame(width: size, height: size)
    }
}
