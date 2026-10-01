import SwiftUI

struct CategoriesView: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false
    @State private var highlighted: UUID?

    var body: some View {
        let store = model.store
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let recent = store.summary(in: DateInterval(start: weekAgo, end: .now))
        let uncategorized = recent.items.filter { $0.category == nil }
        let uncategorizedTime = uncategorized.reduce(0) { $0 + $1.seconds }

        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Categories",
                           subtitle: "Rules map apps and websites to categories. Changes apply to all past data.") {
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { creating = true }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                            Text("New category")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(creating)
                }

                if creating {
                    NewCategoryForm(onCancel: {
                        withAnimation(.easeOut(duration: 0.18)) { creating = false }
                    }, onCreate: { category in
                        store.config.categories.append(category)
                        store.saveConfigIfNeeded()
                        creating = false
                        highlighted = category.id
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(category.id, anchor: .top) }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { if highlighted == category.id { highlighted = nil } }
                        }
                    })
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !uncategorized.isEmpty {
                    Panel(title: "Needs a category",
                          subtitle: "\(uncategorized.count) apps and sites · \(formatDuration(uncategorizedTime)) in the last 7 days",
                          padded: false) {
                        HStack(spacing: 6) {
                            StatusDot(color: T.amber, size: 6)
                            Text("Counted as neutral").font(.geist(12)).foregroundStyle(T.fg2)
                        }
                    } content: {
                        ItemTable(items: Array(uncategorized.prefix(20)), total: recent.total)
                    }
                }

                if !store.config.ignored.isEmpty {
                    Panel(title: "Not tracked", subtitle: "Tempo never records these. Their past time was deleted.",
                          padded: false) {
                        VStack(spacing: 0) {
                            ForEach(store.config.ignored, id: \.self) { item in
                                Hairline()
                                HStack(spacing: 12) {
                                    ItemAvatar(key: item)
                                    Text(item.value).font(.geist(13, .medium)).foregroundStyle(T.fg)
                                    Text(item.kind == .domain ? "website" : "app").font(.mono(11)).foregroundStyle(T.fg3)
                                    Spacer()
                                    Button("Resume tracking") { store.resumeTracking(item) }
                                        .buttonStyle(TempoButtonStyle(kind: .secondary, height: 28))
                                }
                                .padding(.horizontal, 20)
                                .frame(height: 48)
                            }
                        }
                    }
                }

                ForEach(store.config.categories) { category in
                    CategoryEditor(categoryID: category.id)
                        .overlay(RoundedRectangle(cornerRadius: T.radius)
                            .strokeBorder(T.blue, lineWidth: 2)
                            .opacity(highlighted == category.id ? 1 : 0))
                        .id(category.id)
                }
            }
        }
    }
}

struct NewCategoryForm: View {
    @Environment(AppModel.self) private var model
    let onCancel: () -> Void
    let onCreate: (Category) -> Void

    @State private var name = ""
    @State private var productivity: Productivity = .productive
    @State private var colorHex = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let existing = model.store.config.categories
        let isDuplicate = existing.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        let color = colorHex.isEmpty ? Config.palette[existing.count % Config.palette.count] : colorHex

        Panel(title: "New category", subtitle: "Then add websites and apps to it, or assign them from Overview.") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    TField(placeholder: "e.g. Learning, Writing, Admin", text: $name, autofocus: true, onSubmit: create)
                    Segmented(selection: $productivity, options: Productivity.allCases.map { ($0, $0.label) },
                              compact: true)
                }
                HStack(spacing: 8) {
                    Text("Colour").font(.geist(13)).foregroundStyle(T.fg2).frame(width: 52, alignment: .leading)
                    ForEach(Config.palette, id: \.self) { hex in
                        Button { colorHex = hex } label: {
                            RoundedRectangle(cornerRadius: 5).fill(Color(hex: hex))
                                .frame(width: 20, height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(T.fg, lineWidth: 1.5)
                                    .padding(-3)
                                    .opacity(color == hex ? 1 : 0))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if isDuplicate {
                    Text("A category with this name already exists.").font(.geist(12)).foregroundStyle(T.red)
                }
            }
        } footer: {
            HStack {
                Text("Press ↩ to create").font(.mono(11))
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(TempoButtonStyle(kind: .ghost, height: 30))
                    .keyboardShortcut(.cancelAction)
                Button("Create category", action: create)
                    .buttonStyle(TempoButtonStyle(kind: .primary, height: 30))
                    .disabled(trimmed.isEmpty || isDuplicate)
            }
        }
    }

    private func create() {
        let existing = model.store.config.categories
        guard !trimmed.isEmpty,
              !existing.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        let hex = colorHex.isEmpty ? Config.palette[existing.count % Config.palette.count] : colorHex
        onCreate(Category(name: trimmed, colorHex: hex, productivity: productivity))
    }
}

private struct CategoryEditor: View {
    @Environment(AppModel.self) private var model
    let categoryID: UUID
    @State private var newPattern = ""
    @State private var newKind: RuleKind = .domain
    @State private var showAllRules = false

    var body: some View {
        @Bindable var store = model.store
        if let index = store.config.categories.firstIndex(where: { $0.id == categoryID }) {
            let category = store.config.categories[index]
            let rules = store.config.rules.filter { $0.categoryID == categoryID }
                .sorted { ($0.kind.rawValue, $0.pattern) < ($1.kind.rawValue, $1.pattern) }

            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(Config.palette, id: \.self) { hex in
                                Button {
                                    store.config.categories[index].colorHex = hex
                                    store.saveConfigIfNeeded()
                                } label: {
                                    Image(nsImage: swatch(hex))
                                    Text(hex)
                                }
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 6).fill(category.color)
                                .frame(width: 22, height: 22)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.fg.opacity(0.1)))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Change colour")

                        TextField("", text: $store.config.categories[index].name)
                            .textFieldStyle(.plain)
                            .font(.geist(16, .semibold))
                            .foregroundStyle(T.fg)
                            .onSubmit { store.saveConfigIfNeeded() }

                        Segmented(
                            selection: Binding(
                                get: { store.config.categories[index].productivity },
                                set: { store.config.categories[index].productivity = $0; store.saveConfigIfNeeded() }),
                            options: Productivity.allCases.map { ($0, $0.label) },
                            compact: true)

                        Menu {
                            Button("Delete category", role: .destructive) { store.deleteCategory(categoryID) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(T.fg2)
                                .frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }

                    if rules.isEmpty {
                        Text("No rules yet — add a website or app below, or assign items from the Overview tab.")
                            .font(.geist(13)).foregroundStyle(T.fg3)
                    } else {
                        let limit = 12
                        FlowLayout(spacing: 6) {
                            ForEach(showAllRules ? rules : Array(rules.prefix(limit))) { rule in
                                RuleChip(rule: rule) {
                                    store.config.rules.removeAll { $0.id == rule.id }
                                    store.saveConfigIfNeeded()
                                }
                            }
                            if rules.count > limit {
                                Button(showAllRules ? "Show less" : "+\(rules.count - limit) more") {
                                    withAnimation(.easeOut(duration: 0.15)) { showAllRules.toggle() }
                                }
                                .buttonStyle(TempoButtonStyle(kind: .ghost, height: 26))
                            }
                        }
                    }
                }
            } footer: {
                HStack(spacing: 8) {
                    Text("\(rules.count) \(rules.count == 1 ? "rule" : "rules")").font(.mono(11))
                    Spacer()
                    Segmented(selection: $newKind, options: [(.domain, "Website"), (.app, "App")], compact: true)
                    TField(placeholder: newKind == .domain ? "github.com" : "Xcode", text: $newPattern, mono: true,
                           onSubmit: addRule)
                        .frame(width: 220)
                    Button("Add", action: addRule)
                        .buttonStyle(TempoButtonStyle(kind: .primary, height: 30))
                        .disabled(newPattern.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func swatch(_ hex: String) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            NSColor(hex: hex).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            return true
        }
    }

    private func addRule() {
        var pattern = newPattern.trimmingCharacters(in: .whitespaces).lowercased()
        if newKind == .domain {
            pattern = URL(string: pattern.contains("://") ? pattern : "https://\(pattern)")?.host ?? pattern
            if pattern.hasPrefix("www.") { pattern = String(pattern.dropFirst(4)) }
        }
        guard !pattern.isEmpty else { return }
        model.store.assign(ItemKey(kind: newKind, value: pattern), to: categoryID)
        newPattern = ""
    }
}

private struct RuleChip: View {
    let rule: Rule
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: rule.kind == .domain ? "globe" : "macwindow")
                .font(.system(size: 10)).foregroundStyle(T.fg3)
            Text(rule.pattern).font(.mono(12)).foregroundStyle(T.fg).lineLimit(1)
            Button(action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? T.fg : T.fg3)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove rule")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 26)
        .background(hovering ? T.hover : T.subtle, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.border))
        .onHover { hovering = $0 }
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in row.items {
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var items: [(Int, CGFloat)] = []; var y: CGFloat; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row(y: 0)]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].items.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let x = rows[rows.count - 1].width
            rows[rows.count - 1].items.append((index, x))
            rows[rows.count - 1].width = x + size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
