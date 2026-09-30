import SwiftUI

struct CategoriesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let store = model.store
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let recent = store.summary(in: DateInterval(start: weekAgo, end: .now))
        let uncategorized = recent.items.filter { $0.category == nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Categories").font(.title2.bold())
                    Spacer()
                    Button {
                        let hex = Config.palette[store.config.categories.count % Config.palette.count]
                        store.config.categories.append(
                            Category(name: "New category", colorHex: hex, productivity: .neutral))
                        store.saveConfigIfNeeded()
                    } label: {
                        Label("Add category", systemImage: "plus")
                    }
                }
                Text("Rules apply retroactively, so recategorizing something updates all past days and pomodoro scores.")
                    .foregroundStyle(.secondary)

                if !uncategorized.isEmpty {
                    Card(title: "Uncategorized — last 7 days") {
                        ItemList(items: Array(uncategorized.prefix(25)), total: recent.total)
                    }
                }

                ForEach(store.config.categories) { category in
                    CategoryEditor(categoryID: category.id)
                }
            }
            .padding(24)
        }
    }
}

private struct CategoryEditor: View {
    @Environment(AppModel.self) private var model
    let categoryID: UUID
    @State private var newPattern = ""
    @State private var newKind: RuleKind = .domain
    @State private var expanded = false

    var body: some View {
        @Bindable var store = model.store
        if let index = store.config.categories.firstIndex(where: { $0.id == categoryID }) {
            let category = store.config.categories[index]
            let rules = store.config.rules.filter { $0.categoryID == categoryID }
                .sorted { ($0.kind.rawValue, $0.pattern) < ($1.kind.rawValue, $1.pattern) }

            Card {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(Config.palette, id: \.self) { hex in
                            Button {
                                store.config.categories[index].colorHex = hex
                                store.saveConfigIfNeeded()
                            } label: {
                                Label(hex, systemImage: "circle.fill")
                            }
                        }
                    } label: {
                        Circle().fill(category.color).frame(width: 16, height: 16)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    TextField("Name", text: $store.config.categories[index].name)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .onSubmit { store.saveConfigIfNeeded() }

                    Picker("", selection: $store.config.categories[index].productivity) {
                        ForEach(Productivity.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    .onChange(of: category.productivity) { store.saveConfigIfNeeded() }

                    Button {
                        withAnimation { expanded.toggle() }
                    } label: {
                        Text("\(rules.count) rules")
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive) {
                        store.deleteCategory(categoryID)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                if expanded {
                    FlowRules(rules: rules) { rule in
                        store.config.rules.removeAll { $0.id == rule.id }
                        store.saveConfigIfNeeded()
                    }
                    HStack {
                        Picker("", selection: $newKind) {
                            Text("Website").tag(RuleKind.domain)
                            Text("App").tag(RuleKind.app)
                        }
                        .frame(width: 110)
                        TextField(newKind == .domain ? "e.g. github.com" : "e.g. Xcode or com.apple.dt.Xcode",
                                  text: $newPattern)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addRule)
                        Button("Add rule", action: addRule).disabled(newPattern.isEmpty)
                    }
                }
            }
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

private struct FlowRules: View {
    let rules: [Rule]
    let onDelete: (Rule) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(rules) { rule in
                HStack(spacing: 5) {
                    Image(systemName: rule.kind == .domain ? "globe" : "app.dashed").foregroundStyle(.secondary)
                    Text(rule.pattern).lineLimit(1)
                    Button { onDelete(rule) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.quaternary.opacity(0.6), in: Capsule())
            }
        }
    }
}
