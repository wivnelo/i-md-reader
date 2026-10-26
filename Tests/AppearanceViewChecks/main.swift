// Hidden-window regression fixture; production theme adapters and selectors are extracted by the runner.
import AppKit
import SwiftUI

@MainActor final class Model: ObservableObject {
    @Published var theme = "light"
    @Published var language = "en"
    @Published var palette = "mist"
    var observed: ColorScheme?
    @Published var preferred = ["en-US"]
}
struct Capture: NSViewRepresentable {
    let scheme: ColorScheme
    let model: Model
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { model.observed = scheme }
}
struct SchemeCapture: View {
    @Environment(\.colorScheme) var scheme
    let model: Model
    var body: some View { Capture(scheme: scheme, model: model) }
}
struct Probe: View {
    @ObservedObject var model: Model
    @StateObject var systemAppearance = MacSystemAppearance()
    var dark: Bool { model.theme == "dark" || (model.theme == "system" && systemAppearance.isDark) }
    var body: some View {
        VStack {
            SchemeCapture(model: model).frame(height: 1)
            panel
        }
        .preferredColorScheme(dark ? .dark : .light)
    }
    var panel: some View {
        let locale = Locale(identifier: (ReaderLanguage(rawValue: model.language) ?? .system).resolved(preferred: model.preferred))
        let tint = ReaderPalette.resolve(model.palette).colors(dark: dark).accent
        return VStack(alignment: .leading) {
            MacAppearanceSegments(title: "明暗", options: [("跟随系统","system"),("浅色","light"),("深色","dark")], selection: $model.theme, locale: locale, tint: tint)
            MacAppearanceSegments(title: "配色", options: ReaderPalette.allCases.map { ($0.name,$0.rawValue) }, selection: $model.palette, locale: locale, tint: tint)
            MacAppearanceSegments(title: "语言", options: [("跟随系统","system"),("简体中文","zh-Hans"),("English","en")], selection: $model.language, locale: locale, tint: tint)
        }.frame(width: 400, height: 100)
    }
}
@MainActor func pump(_ window: NSWindow) {
    for _ in 0..<12 { window.contentView?.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.025)) }
}
@MainActor func controls(_ view: NSView) -> [NSSegmentedControl] {
    (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap { controls($0) }
}
@MainActor func verifyMatrix() {
    let model = Model()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 456, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: Probe(model: model))
    var count = 0
    for systemDark in [false, true] {
        NSApp.appearance = NSAppearance(named: systemDark ? .darkAqua : .aqua)
        for theme in ["light", "system", "dark", "system"] {
            for palette in ReaderPalette.allCases {
                for (language, preferred) in [("zh-Hans", ["en-US"]), ("en", ["zh-CN"]), ("system", ["zh-Hans"]), ("system", ["en-US"])] {
                    model.theme = theme; model.palette = palette.rawValue
                    model.language = language; model.preferred = preferred
                    pump(window)
                    let expectedDark = theme == "dark" || (theme == "system" && systemDark)
                    precondition(model.observed == (expectedDark ? .dark : .light), "Effective scheme mismatch")
                    precondition(window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == (expectedDark ? .darkAqua : .aqua), "Native presentation appearance mismatch")
                    let rows = controls(window.contentView!)
                    precondition(rows.count == 3, "Missing rendered native selectors")
                    let en = (ReaderLanguage(rawValue: language) ?? .system).resolved(preferred: preferred) == "en"
                    let expected = [en ? ["System", "Light", "Dark"] : ["跟随系统", "浅色", "深色"],
                                    en ? ["Mist Blue", "Distant Hills", "Moss", "Warm Sand"] : ["雾蓝", "远山", "青苔", "暖砂"],
                                    en ? ["System", "简体中文", "English"] : ["跟随系统", "简体中文", "English"]]
                    let actual = rows.map { row in (0..<row.segmentCount).map { row.label(forSegment: $0) ?? "" } }
                    precondition(Set(actual) == Set(expected), "Rendered localized labels mismatch: \(actual)")
                    let lefts = rows.map { $0.convert($0.bounds, to: nil).minX }
                    precondition((lefts.max()! - lefts.min()!) < 0.5, "Selectors not leading-aligned")
                    for row in rows {
                        precondition(abs(row.bounds.width - 400) < 0.5, "Selector width changed across locale")
                        for index in 0..<row.segmentCount {
                            let text = row.label(forSegment: index) ?? ""
                            let width = (text as NSString).size(withAttributes: [.font: row.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
                            precondition(width <= row.bounds.width / CGFloat(row.segmentCount) - 12, "Label does not fit readable native font")
                        }
                    }
                    let themeControl = rows.first { ($0.label(forSegment: 1) == (en ? "Light" : "浅色")) }!
                    precondition(themeControl.selectedSegment == ["system", "light", "dark"].firstIndex(of: theme), "Theme selection drift")
                    let paletteControl = rows.first { $0.segmentCount == 4 }!
                    precondition(paletteControl.selectedSegment == ReaderPalette.allCases.firstIndex(of: palette), "Palette selection drift")
                    count += 1
                }
            }
        }
    }
    // Exercise the actual native control action/binding, then the system observer.
    let rows = controls(window.contentView!)
    let themeControl = rows.first { $0.label(forSegment: 1) == "Light" }!
    themeControl.selectedSegment = 1
    themeControl.sendAction(themeControl.action, to: themeControl.target)
    pump(window)
    precondition(model.theme == "light" && model.observed == .light)
    themeControl.selectedSegment = 0
    themeControl.sendAction(themeControl.action, to: themeControl.target)
    pump(window)
    precondition(model.theme == "system" && model.observed == .dark)
    NSApp.appearance = NSAppearance(named: .aqua)
    pump(window)
    precondition(model.observed == .light)
    print("PASS: \(count) hosted-view combinations; system choice follows application appearance; native presentation matches; native actions; system appearance observation; all rendered labels; stable 400pt leading controls; readable label widths")
    window.close()
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
verifyMatrix()

// Test the production title view in controlled allocations, not native toolbar placement.
@MainActor func verifyTitleFrames() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1600, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1600, height: 700))
    window.contentView = root
    let title = ReadingAreaTitle.Title()
    title.label.stringValue = String(repeating: "Long document title 文件名 ", count: 30)
    root.addSubview(title)
    var count = 0
    for width: CGFloat in [760, 960, 1600] {
        window.setContentSize(NSSize(width: width, height: 700))
        for sidebar: CGFloat in [0, 280, 360] {
            let center = sidebar + (width - sidebar) / 2
            let available = max(40, width - sidebar - 320)
            title.frame = NSRect(x: center - available / 2, y: 650, width: available, height: 36)
            title.targetCenterX = center
            title.needsLayout = true
            title.layoutSubtreeIfNeeded()
            let frame = title.label.convert(title.label.bounds, to: nil)
            precondition(abs(frame.midX - center) < 0.5 && frame.width > 0)
            precondition(title.bounds.contains(title.label.frame))
            precondition(!title.label.isBordered && !title.label.isBezeled && !title.label.drawsBackground)
            precondition(title.label.lineBreakMode == .byTruncatingMiddle && title.label.maximumNumberOfLines == 1)
            count += 1
        }
    }
    print("PASS: \(count) controlled title allocations at 760/960/1600pt with sidebar 0/280/360; centered, bounded, plain and middle-ellipsis configured. Native toolbar allocation/visible pixels NOT covered.")
    window.close()
}
verifyTitleFrames()
