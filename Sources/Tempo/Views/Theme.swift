import AppKit
import CoreText
import SwiftUI

// MARK: - Tokens

/// Geist-inspired palette: monochrome surfaces, hairline borders, colour only where it carries meaning.
enum T {
    static let bg = dynamic("#FFFFFF", "#000000")
    static let subtle = dynamic("#FAFAFA", "#0A0A0A")
    static let surface = dynamic("#FFFFFF", "#0A0A0A")
    static let hover = dynamic("#F2F2F2", "#1A1A1A")
    static let fill = dynamic("#EBEBEB", "#1F1F1F")
    static let border = dynamic("#EAEAEA", "#242424")
    static let borderStrong = dynamic("#D4D4D4", "#3A3A3A")

    static let fg = dynamic("#0A0A0A", "#EDEDED")
    static let fg2 = dynamic("#666666", "#A1A1A1")
    static let fg3 = dynamic("#8F8F8F", "#6B6B6B")
    static let inverted = dynamic("#FFFFFF", "#0A0A0A")

    static let blue = dynamic("#0070F3", "#3291FF")
    static let green = dynamic("#1A9A55", "#3FC37A")
    static let amber = dynamic("#D98300", "#F5A623")
    static let red = dynamic("#E5484D", "#F2555A")

    static let radius: CGFloat = 8

    static func dynamic(_ light: String, _ dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Type

enum Fonts {
    /// Registers the bundled Geist fonts (from the .app's Resources, or the repo when running tests).
    static func register() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../../Resources/Fonts").standardizedFileURL,
        ].compactMap { $0 }
        guard let dir = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist-\(name(weight, mono: false))", size: size)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("GeistMono-\(name(weight, mono: true))", size: size)
    }

    private static func name(_ weight: Font.Weight, mono: Bool) -> String {
        switch weight {
        case .medium: "Medium"
        case .semibold: "SemiBold"
        case .bold, .heavy, .black: mono ? "SemiBold" : "Bold"
        default: "Regular"
        }
    }
}

// MARK: - Semantic colours

extension Productivity {
    var tint: Color {
        switch self {
        case .productive: T.blue
        case .neutral: T.dynamic("#A8A8A8", "#5C5C5C")
        case .distracting: T.red
        }
    }
}

enum ScoreStatus {
    case great, okay, poor, none

    init(_ score: Double?) {
        guard let score else { self = .none; return }
        self = score >= 70 ? .great : score >= 45 ? .okay : .poor
    }

    var color: Color {
        switch self {
        case .great: T.green
        case .okay: T.amber
        case .poor: T.red
        case .none: T.fg3
        }
    }

    var label: String {
        switch self {
        case .great: "Focused"
        case .okay: "Mixed"
        case .poor: "Distracted"
        case .none: "No data"
        }
    }
}

// MARK: - Surfaces

/// Bordered card with optional header and footer, like a Vercel settings/analytics panel.
struct Panel<Content: View, Accessory: View, Footer: View>: View {
    var title: String?
    var subtitle: String?
    var padded = true
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || subtitle != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title { Text(title).font(.geist(14, .semibold)).foregroundStyle(T.fg) }
                        if let subtitle { Text(subtitle).font(.geist(13)).foregroundStyle(T.fg2) }
                    }
                    Spacer(minLength: 12)
                    accessory
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, padded ? 0 : 14)
            }
            content
                .padding(padded ? 20 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            if Footer.self != EmptyView.self {
                footer
                    .font(.geist(13))
                    .foregroundStyle(T.fg2)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(T.subtle)
                    .overlay(alignment: .top) { Hairline() }
            }
        }
        .background(T.surface)
        .clipShape(RoundedRectangle(cornerRadius: T.radius))
        .overlay(RoundedRectangle(cornerRadius: T.radius).strokeBorder(T.border))
    }
}

extension Panel where Accessory == EmptyView, Footer == EmptyView {
    init(title: String? = nil, subtitle: String? = nil, padded: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, padded: padded, accessory: { EmptyView() }, content: content,
                  footer: { EmptyView() })
    }
}

extension Panel where Footer == EmptyView {
    init(title: String? = nil, subtitle: String? = nil, padded: Bool = true,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, padded: padded, accessory: accessory, content: content,
                  footer: { EmptyView() })
    }
}

extension Panel where Accessory == EmptyView {
    init(title: String? = nil, subtitle: String? = nil, padded: Bool = true,
         @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.init(title: title, subtitle: subtitle, padded: padded, accessory: { EmptyView() }, content: content,
                  footer: footer)
    }
}

struct Hairline: View {
    var vertical = false
    var body: some View {
        T.border.frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.mono(11, .medium))
            .tracking(0.6)
            .foregroundStyle(T.fg3)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.geist(30, .semibold)).tracking(-1.1).foregroundStyle(T.fg)
                if let subtitle { Text(subtitle).font(.geist(14)).foregroundStyle(T.fg2) }
            }
            Spacer()
            trailing
        }
    }
}

// MARK: - Metrics

struct Metric: View {
    let label: String
    let value: String
    var unit: String?
    var detail: String?
    var delta: Double?
    var deltaUnit = ""
    var dot: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(label).font(.geist(13)).foregroundStyle(T.fg2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.geist(28, .semibold)).tracking(-0.9).foregroundStyle(T.fg)
                    .monospacedDigit()
                if let unit { Text(unit).font(.geist(14)).foregroundStyle(T.fg3) }
                Spacer(minLength: 0)
                if let delta { DeltaBadge(delta: delta, unit: deltaUnit) }
            }
            if let detail {
                Text(detail).font(.geist(12)).foregroundStyle(T.fg3).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A single bordered strip of metrics separated by hairlines.
struct MetricStrip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            _VariadicView.Tree(Divided()) { content }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(T.surface)
        .clipShape(RoundedRectangle(cornerRadius: T.radius))
        .overlay(RoundedRectangle(cornerRadius: T.radius).strokeBorder(T.border))
    }

    private struct Divided: _VariadicView_MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            ForEach(children) { child in
                if child.id != children.first?.id { Hairline(vertical: true) }
                child.padding(20)
            }
        }
    }
}

struct DeltaBadge: View {
    let delta: Double
    var unit = ""
    var text: String?

    var body: some View {
        let rounded = Int(delta.rounded())
        let color = rounded > 0 ? T.green : rounded < 0 ? T.red : T.fg2
        HStack(spacing: 2) {
            Image(systemName: rounded > 0 ? "arrow.up.right" : rounded < 0 ? "arrow.down.right" : "minus")
                .font(.system(size: 9, weight: .bold))
            Text(text ?? "\(abs(rounded))\(unit)").font(.mono(11, .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .background(Circle().fill(color.opacity(0.25)).frame(width: size + 6, height: size + 6))
    }
}

/// Thin segmented bar: productive / neutral / distracting.
struct ProductivityBar: View {
    let summary: Summary
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if summary.total > 0 {
                    ForEach(Productivity.allCases) { p in
                        let fraction = summary.seconds(p) / summary.total
                        if fraction > 0.002 {
                            RoundedRectangle(cornerRadius: height / 2).fill(p.tint)
                                .frame(width: max(height, (geo.size.width - 4) * fraction))
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: height / 2).fill(T.fill)
                }
            }
        }
        .frame(height: height)
    }
}

struct ProductivityLegend: View {
    var summary: Summary?

    var body: some View {
        HStack(spacing: summary == nil ? 14 : 0) {
            ForEach(Productivity.allCases) { p in
                if summary != nil, p != .productive { Spacer(minLength: 8) }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(p.tint).frame(width: 8, height: 8)
                    Text(p.label).font(.geist(12)).foregroundStyle(T.fg2).lineLimit(1).fixedSize()
                    if let summary {
                        Text(formatDuration(summary.seconds(p))).font(.mono(11)).foregroundStyle(T.fg3).fixedSize()
                    }
                }
            }
        }
    }
}

/// Analytics-style row with a faint proportional bar behind it.
struct BarRow<Leading: View, Trailing: View>: View {
    let fraction: Double
    var tint: Color = T.hover
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            leading
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5)
                    .fill(hovering ? T.fill : tint)
                    .frame(width: max(4, geo.size.width * min(1, fraction)))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Controls

struct TempoButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    var kind: Kind = .secondary
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, height: height)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let kind: Kind
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.geist(13, .medium))
                .padding(.horizontal, kind == .ghost ? 8 : 12)
                .frame(height: height)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if kind == .secondary {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(hovering ? T.borderStrong : T.border)
                    }
                }
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var foreground: Color {
            switch kind {
            case .primary: T.inverted
            case .danger: T.red
            case .secondary: T.fg
            case .ghost: hovering ? T.fg : T.fg2
            }
        }

        private var background: Color {
            switch kind {
            case .primary: hovering ? T.fg.opacity(0.85) : T.fg
            case .secondary: hovering ? T.hover : T.surface
            case .ghost, .danger: hovering ? T.hover : .clear
            }
        }
    }
}

extension ButtonStyle where Self == TempoButtonStyle {
    static var primary: TempoButtonStyle { TempoButtonStyle(kind: .primary) }
    static var secondary: TempoButtonStyle { TempoButtonStyle(kind: .secondary) }
    static var ghost: TempoButtonStyle { TempoButtonStyle(kind: .ghost) }
    static var danger: TempoButtonStyle { TempoButtonStyle(kind: .danger) }
}

struct Kbd: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(.mono(10, .medium))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ForegroundStyle().opacity(0.35)))
            .opacity(0.8)
    }
}

/// Bordered segmented control with a filled active item.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = value }
                } label: {
                    Text(label)
                        .font(.geist(compact ? 12 : 13, .medium))
                        .foregroundStyle(selection == value ? T.fg : T.fg2)
                        .padding(.horizontal, compact ? 8 : 12)
                        .frame(height: compact ? 24 : 28)
                        .background(selection == value ? T.hover : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 5).strokeBorder(T.border)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(T.border))
    }
}

struct TField: View {
    let placeholder: String
    @Binding var text: String
    var mono = false
    /// Focus the field whenever its window becomes key (e.g. each time the menu bar popover opens).
    var autofocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @State private var window: NSWindow?

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(T.fg3))
            .textFieldStyle(.plain)
            .font(mono ? .mono(13) : .geist(14))
            .foregroundStyle(T.fg)
            .focused($focused)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(T.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(focused ? T.fg2 : T.border))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? T.fg3.opacity(0.25) : .clear, lineWidth: 3).padding(-3))
            .onSubmit(onSubmit)
            .background { if autofocus { WindowReader(window: $window) } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                guard autofocus, let window, note.object as? NSWindow === window else { return }
                focused = true
            }
            .onAppear { if autofocus { DispatchQueue.main.async { focused = true } } }
    }
}

/// Reports the NSWindow hosting a view.
struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { window = view.window }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window !== window { DispatchQueue.main.async { window = nsView.window } }
    }
}

struct NumberStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit = ""

    var body: some View {
        HStack(spacing: 0) {
            button("minus") { value = max(range.lowerBound, value - step) }.disabled(value <= range.lowerBound)
            Hairline(vertical: true)
            Text("\(value)\(unit)").font(.mono(13, .medium)).foregroundStyle(T.fg).frame(minWidth: 72)
            Hairline(vertical: true)
            button("plus") { value = min(range.upperBound, value + step) }.disabled(value >= range.upperBound)
        }
        .frame(height: 32)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(T.border))
        .fixedSize()
    }

    private func button(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(T.fg2)
    }
}

// MARK: - Category bits

struct CategoryDot: View {
    let category: Category?
    var size: CGFloat = 8
    var body: some View {
        RoundedRectangle(cornerRadius: size / 3.5)
            .fill(category?.color ?? T.fg3.opacity(0.5))
            .frame(width: size, height: size)
    }
}

/// Pill that opens a menu for (re)assigning an app or site to a category. Each choice saves a permanent
/// rule that applies to all past and future activity; sites cover their whole domain by default.
struct AssignMenu: View {
    @Environment(AppModel.self) private var model
    let item: ItemKey
    let current: Category?
    @State private var hovering = false

    var body: some View {
        let broader = item.broaderDomain
        Menu {
            if let broader {
                Section("All of \(broader)") { categoryButtons(ItemKey(kind: .domain, value: broader)) }
                Menu("Only \(item.value)") { categoryButtons(item) }
            } else {
                Section(item.value) { categoryButtons(item) }
            }
            Divider()
            Button("Uncategorized") { apply(item, nil) }
        } label: {
            HStack(spacing: 6) {
                CategoryDot(category: current, size: 7)
                Text(current?.name ?? "Uncategorized")
                    .font(.geist(12, .medium))
                    .foregroundStyle(current == nil ? T.fg3 : T.fg2)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(T.fg3)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(hovering ? T.hover : T.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(current == nil ? T.borderStrong : T.border,
                                                                     style: StrokeStyle(lineWidth: 1, dash: current == nil ? [3, 2] : [])))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func categoryButtons(_ target: ItemKey) -> some View {
        ForEach(Productivity.allCases) { productivity in
            let categories = model.store.config.categories.filter { $0.productivity == productivity }
            if !categories.isEmpty {
                Divider()
                Text(productivity.label)
                ForEach(categories) { category in
                    Button(category.name) { apply(target, category) }
                }
            }
        }
    }

    private func apply(_ target: ItemKey, _ category: Category?) {
        let store = model.store
        let previous = store.config.rules
        // A broader rule must also clear the exact-subdomain rule, or that would keep winning.
        store.assign(target, to: category?.id, clearing: target == item ? [] : [item])
        model.show(Toast(
            message: category.map { "\(target.value) → \(target.kind == .domain && target != item ? "\($0.name) (whole domain)" : $0.name)" }
                ?? "\(target.value) is now uncategorized",
            detail: "Saved as a rule — applies to all past and future activity.",
            undo: { [weak store] in
                store?.config.rules = previous
                store?.saveConfigIfNeeded()
            }))
    }
}

/// Small hover button that hides an app or site everywhere (with undo).
struct HideButton: View {
    @Environment(AppModel.self) private var model
    let item: ItemKey

    var body: some View {
        Button {
            let store = model.store
            store.hide(item)
            model.show(Toast(message: "Hidden \(item.value)",
                             detail: "Excluded from all totals and scores. Unhide it under Categories.",
                             undo: { [weak store] in store?.unhide(item) }))
        } label: {
            Image(systemName: "eye.slash").font(.system(size: 11))
        }
        .buttonStyle(TempoButtonStyle(kind: .ghost, height: 24))
        .help("Hide \(item.value)")
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: Toast

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(T.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message).font(.geist(13, .medium)).foregroundStyle(T.fg)
                if let detail = toast.detail {
                    Text(detail).font(.geist(12)).foregroundStyle(T.fg2)
                }
            }
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    model.dismissToast()
                }
                .buttonStyle(TempoButtonStyle(kind: .secondary, height: 28))
            }
            Button { model.dismissToast() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(TempoButtonStyle(kind: .ghost, height: 24))
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(T.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.borderStrong))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}

/// Letter avatar standing in for app icons / favicons.
struct ItemAvatar: View {
    let key: ItemKey
    var size: CGFloat = 20

    var body: some View {
        let letter = key.value.first.map { String($0).uppercased() } ?? "?"
        ZStack {
            RoundedRectangle(cornerRadius: key.kind == .domain ? size / 2 : 5)
                .fill(T.subtle)
                .overlay(RoundedRectangle(cornerRadius: key.kind == .domain ? size / 2 : 5).strokeBorder(T.border))
            Text(letter).font(.geist(size * 0.5, .semibold)).foregroundStyle(T.fg2)
        }
        .frame(width: size, height: size)
    }
}

struct TempoMark: View {
    var size: CGFloat = 18
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(T.fg)
            .overlay(TempoGlyphView().foregroundStyle(T.inverted).padding(size * 0.2))
            .frame(width: size, height: size)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(T.fg3)
                .frame(width: 40, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.border))
            Text(title).font(.geist(14, .medium)).foregroundStyle(T.fg)
            Text(message).font(.geist(13)).foregroundStyle(T.fg2).multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
