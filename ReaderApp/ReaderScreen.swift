import SwiftUI
import UniformTypeIdentifiers
import ReaderCore

struct ReaderScreen: View {
    // Other installed apps can register the same extension under another UTI.
    // Include every system-resolved Markdown type; the store still validates the
    // actual extension before reading, rather than trusting a third-party UTI.
    private static var markdownPickerTypes: [UTType] {
        var types = [UTType(importedAs: "net.daringfireball.markdown")]
        for ext in ["md", "markdown"] {
            types += UTType.types(tag: ext, tagClass: .filenameExtension, conformingTo: nil)
        }
        return Array(Set(types))
    }

    @StateObject private var store = ReaderStore()
    @State private var visibility: NavigationSplitViewVisibility = .detailOnly
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var importing = false
    @State private var selectingMarkdown = false
    @State private var addingGitHub = false
    @State private var showAppearance = false
    @State private var draggingFolder: String?
    @State private var sourceInsertion: SourceInsertion?
    @State private var findRequest = 0
    @State private var anchor: String?
    @State private var prefersSingleColumn = false
    @State private var renderingID: UUID?
    @AppStorage("fontSize") private var fontSize = 17.0
    @AppStorage("readerLanguage") private var languageValue = ReaderLanguage.system.rawValue
    @AppStorage("readerPalette") private var paletteValue = ReaderPalette.mist.rawValue
    @AppStorage("readerTheme") private var theme = "system"
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dark: Bool { theme == "dark" || (theme == "system" && systemScheme == .dark) }
    private var scaledSize: Double { UIFontMetrics(forTextStyle: .body).scaledValue(for: fontSize) }
    private var language: ReaderLanguage { ReaderLanguage(rawValue: languageValue) ?? .system }
    private var palette: ReaderPalette { .resolve(paletteValue) }
    private var colors: ReaderColors { palette.colors(dark: dark) }
    private var readerBackground: Color { colors.paper }
    private var readerTint: Color { colors.accent }

    private var documentFolderName: String {
        guard let document = store.document else { return "" }
        if document.isStandalone { return ReaderLanguage.message("单个文件", locale: language.locale) }
        if let source = store.sources.first(where: { $0.id == document.sourceID }), source.remote != nil { return source.name }
        return document.url.deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    Text("资料来源").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 16)
                    ForEach(store.orderedSources) { source in
                        Section {
                            if let root = source.url {
                                TreeDirectory(store: store, source: source, url: root, level: 0, selection: colors.selection, draggingFolder: $draggingFolder, onOpenDocument: showReadingColumn)
                            } else {
                                Text("文件夹暂时无法访问，请稍后重试。")
                                    .font(.caption).foregroundStyle(.secondary).padding(14)
                            }
                        } header: {
                            SourceHeader(store: store, source: source, background: colors.sidebar, selection: colors.selection, draggingFolder: $draggingFolder, insertion: $sourceInsertion)
                                .background(colors.sidebar)
                        }
                    }
                    if !store.recentFiles.isEmpty {
                        Section {
                            ForEach(store.recentFiles) { file in
                                HStack {
                                    Button { showReadingColumn(); store.openRecent(file) } label: {
                                        Label(file.name, systemImage: "doc.text").lineLimit(1).truncationMode(.middle)
                                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    }.buttonStyle(.plain)
                                    Menu {
                                        Button("重新打开", systemImage: "arrow.clockwise") { store.openRecent(file) }
                                        Button("移除记录", systemImage: "minus.circle", role: .destructive) { store.removeRecent(file) }
                                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                }.font(.subheadline).padding(.leading, 10)
                                    .background(store.selectedKey == file.key ? colors.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }
                        } header: {
                            HStack {
                                Text("最近文件").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("清空") { store.clearRecentFiles() }
                                    .font(.caption).accessibilityLabel("清空最近文件")
                                    .frame(minWidth: 44, minHeight: 44)
                            }.padding(.horizontal, 12).background(colors.sidebar)
                        }
                    }
                    Text("仅阅读，不修改源文件").font(.footnote).foregroundStyle(.secondary).padding(16)
                }.padding(.horizontal, 12)
            }
            .foregroundStyle(colors.ink)
            .background(colors.sidebar)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        Image("ReaderBrand")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .accessibilityHidden(true)
                        Text(verbatim: "iMDReader")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(colors.ink)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("打开 Markdown 文件", systemImage: "doc.text") { selectingMarkdown = true; importing = true }
                        Button("本地文件夹", systemImage: "folder") { selectingMarkdown = false; importing = true }
                        Button("公开 GitHub 链接", systemImage: "link") { addingGitHub = true }
                    } label: { Label("添加来源", systemImage: "plus") }
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 360)
        } detail: {
            ZStack {
                readerBackground.ignoresSafeArea()
                if let document = store.document {
                    VStack(spacing: 0) {
                        if document.isStandalone {
                            HStack(spacing: 12) {
                                Text("单文件不包含同级图片和文档的访问权限").font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 4)
                                Button("添加所在文件夹") { selectingMarkdown = false; importing = true }.font(.caption)
                            }.padding(.horizontal, 20).padding(.vertical, 8)
                        }
                        ReaderWebView(document: document, fontSize: scaledSize, dark: dark, palette: palette, language: language.resolved(), reduceMotion: reduceMotion, findRequest: findRequest, anchor: $anchor,
                                      onProgress: { store.recordProgress($0, documentKey: document.key) },
                                      onInternalLink: { url in
                                          if let source = store.sources.first(where: { $0.id == document.sourceID }) { store.open(url, source: source) }
                                      }, onError: { store.error = $0 }, onReady: {
                                          if renderingID == document.id { renderingID = nil }
                                      })
                            .id(document.id)
                        HStack {
                            Text(documentFolderName).lineLimit(1)
                            Spacer()
                            Text(store.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 10)
                    }
                } else if !store.isLoading {
                    ContentUnavailableView {
                        Label("留一点空间，开始阅读", systemImage: "book.closed")
                    } description: {
                        Text("从左侧选择文章，或添加文件夹与公开 GitHub 链接。")
                    } actions: {
                        Menu {
                            Button("打开 Markdown 文件", systemImage: "doc.text") { selectingMarkdown = true; importing = true }
                        Button("本地文件夹", systemImage: "folder") { selectingMarkdown = false; importing = true }
                            Button("公开 GitHub 链接", systemImage: "link") { addingGitHub = true }
                        } label: { Label("添加来源", systemImage: "plus") }.buttonStyle(.bordered)
                    }
                }
                if store.isLoading || renderingID != nil {
                    ProgressView("正在打开文档…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .navigationTitle(store.document.map { Text($0.url.lastPathComponent) } ?? Text("阅读"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let document = store.document {
                        Button { findRequest += 1 } label: { Label("文内查找", systemImage: "magnifyingglass") }
                            .keyboardShortcut("f", modifiers: .command)
                            .disabled(store.isLoading || renderingID != nil)
                        Menu {
                            if document.rendered.headings.isEmpty { Text("这篇文章没有标题") }
                            ForEach(document.rendered.headings) { heading in
                                Button(String(repeating: "　", count: min(heading.level - 1, 2)) + heading.title) { anchor = heading.id }
                            }
                        } label: { Label("文章目录", systemImage: "list.bullet") }
                    }
                    Button { showAppearance = true } label: { Text("Aa").font(.system(.title3, design: .serif)) }
                        .accessibilityLabel("阅读外观")
                        .popover(isPresented: $showAppearance) { appearancePanel }
                    if visibility != .detailOnly {
                        Button("沉浸阅读", systemImage: "arrow.up.left.and.arrow.down.right") { visibility = .detailOnly }
                    }
                }
            }
        }
        .tint(readerTint)
        .accentColor(readerTint)
        .preferredColorScheme(theme == "system" ? nil : (dark ? .dark : .light))
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { adaptLayout(to: geometry.size) }
                    .onChange(of: geometry.size) { _, size in adaptLayout(to: size) }
            }
        }
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            if sizeClass == .compact {
                prefersSingleColumn = true
                if store.selectedKey != nil { showReadingColumn() }
            }
        }
        .onChange(of: store.selectedKey) { _, key in
            if key != nil { showReadingColumn() }
        }
        .onChange(of: store.document?.id) { _, id in
            renderingID = id
            if id != nil { showReadingColumn() }
        }
        .sheet(isPresented: $addingGitHub) { GitHubAddSheet(store: store) }
        .onOpenURL { store.openFileURL($0); showReadingColumn() }
        .fileImporter(isPresented: $importing, allowedContentTypes: selectingMarkdown ? Self.markdownPickerTypes : [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if selectingMarkdown { store.openFileURL(url) }
                    else { store.addFolder(url) }
                }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .alert(ReaderLanguage.message("无法完成操作", locale: language.locale), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("好", role: .cancel) { store.error = nil }
        } message: { Text(ReaderLanguage.message(store.error ?? "", locale: language.locale)) }
        .task { store.restoreLastDocument() }
        .environment(\.locale, language.locale)

    }

    private func showReadingColumn() {
        guard prefersSingleColumn else { return }
        compactColumn = .detail
        visibility = .detailOnly
    }

    private func adaptLayout(to size: CGSize) {
        prefersSingleColumn = size.width < 900 || size.width < size.height || horizontalSizeClass == .compact
        if prefersSingleColumn {
            if store.document != nil || store.selectedKey != nil { showReadingColumn() }
            else { compactColumn = .sidebar; visibility = .all }
        } else { visibility = .all }
    }

    private var fontSliderPosition: Binding<Double> {
        Binding(get: { ReaderFontScale.position(for: fontSize) },
                set: { fontSize = ReaderFontScale.size(at: $0) })
    }

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("阅读外观").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("正文字号"); Spacer(); Text("\(Int(fontSize))").monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: fontSliderPosition, in: 0...1) {
                    Text("正文字号")
                } minimumValueLabel: { Text("A").font(.caption) }
                  maximumValueLabel: { Text("A").font(.title3) }
                    .accessibilityValue("\(Int(fontSize)) 点")
            }
            Picker("明暗", selection: $theme) {
                Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
            }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 12) {
                Text("配色").font(.subheadline)
                Picker("配色", selection: $paletteValue) {
                    ForEach(ReaderPalette.allCases) { option in
                        Text(LocalizedStringKey(option.name)).tag(option.rawValue)
                    }
                }.pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("语言").font(.subheadline)
                Picker("语言", selection: $languageValue) {
                    Text("跟随系统").tag("system")
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }.pickerStyle(.segmented)
            }
        }
        .environment(\.locale, language.locale)
        .padding(28).frame(minWidth: 360).presentationCompactAdaptation(.popover)
        .preferredColorScheme(dark ? .dark : .light)
        .tint(readerTint)
    }
}

private struct SourceReorder: ViewModifier {
    @ObservedObject var store: ReaderStore
    let item: String
    @Binding var dragging: String?
    var enabled = true
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    dragging = item
                    return NSItemProvider(object: item as NSString)
                }
                .accessibilityAction(named: "上移") { moveAccessibility(-1) }
                .accessibilityAction(named: "下移") { moveAccessibility(1) }
        } else { content }
    }
    private func moveAccessibility(_ direction: Int) {
        // Use the same root validation and persistence as touch dragging.
        store.moveSource(item, direction: direction)
    }
}

private struct SourceRowHeight: PreferenceKey {
    static var defaultValue: CGFloat { 56 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct SourceInsertion: Equatable {
    let target: String
    let after: Bool
}

private struct SourceDrop: ViewModifier {
    @ObservedObject var store: ReaderStore
    let item: String
    @Binding var dragging: String?
    @Binding var insertion: SourceInsertion?
    @State private var height: CGFloat = 56
    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: SourceRowHeight.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(SourceRowHeight.self) { height = $0 }
            .overlay(alignment: insertion?.after == true ? .bottom : .top) {
                if insertion?.target == item, let origin = dragging, store.canReorderSource(origin, over: item) {
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                        .padding(.horizontal, 4).allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.text], delegate: SourceInsertionDrop(
                store: store, item: item, height: height, dragging: $dragging, insertion: $insertion))
    }
}

private struct SourceInsertionDrop: DropDelegate {
    let store: ReaderStore
    let item: String
    let height: CGFloat
    @Binding var dragging: String?
    @Binding var insertion: SourceInsertion?

    func validateDrop(info: DropInfo) -> Bool {
        guard let origin = dragging else { return false }
        return store.canReorderSource(origin, over: item) && info.hasItemsConforming(to: [UTType.text])
    }
    func dropEntered(info: DropInfo) { updateInsertion(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        updateInsertion(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        if insertion?.target == item { insertion = nil }
    }
    private func updateInsertion(_ info: DropInfo) {
        if validateDrop(info: info) {
            insertion = SourceInsertion(target: item, after: info.location.y >= height / 2)
        } else if insertion?.target == item { insertion = nil }
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info), let origin = dragging,
              let provider = info.itemProviders(for: [UTType.text]).first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        let after = info.location.y >= height / 2
        let destination = item
        let owner = store
        insertion = nil
        dragging = nil
        _ = provider.loadObject(ofClass: NSString.self) { object, error in
            guard error == nil, let payload = object as? String, payload == origin else { return }
            Task { @MainActor in owner.reorderSource(payload, over: destination, after: after) }
        }
        return true
    }
}

private struct SourceHeader: View {
    @ObservedObject var store: ReaderStore
    let source: FolderSource
    let background: Color
    let selection: Color
    @Binding var draggingFolder: String?
    @Binding var insertion: SourceInsertion?
    @State private var showingRemove = false
    @GestureState private var drag: CGFloat = 0
    private let actionWidth: CGFloat = 104
    var body: some View {
        ZStack(alignment: .trailing) {
            if !source.isSample {
                Button(role: .destructive) { store.remove(source) } label: {
                    Text("移除来源").font(.subheadline).foregroundStyle(.white)
                        .frame(width: actionWidth).frame(maxHeight: .infinity)
                        .background(Color.red)
                }.buttonStyle(.plain)
                    .accessibilityHidden(!showingRemove)
            }
            Group {
                if let root = source.url {
                    TreeDirectory(store: store, source: source, url: root, level: 0, selection: selection, draggingFolder: $draggingFolder).directoryHeader
                } else {
                    HStack {
                        Label(source.name, systemImage: "folder").font(.subheadline).fontWeight(.semibold)
                        Spacer()
                        Button("重试") { Task { await store.retryLocalSource(source) } }
                    }.padding(14).frame(minHeight: 56)
                        .modifier(SourceReorder(store: store, item: source.id.uuidString + "|", dragging: $draggingFolder))
                }
            }
            .frame(maxWidth: .infinity)
            .background(background)
            .offset(x: source.isSample ? 0 : min(0, max(-actionWidth, (showingRemove ? -actionWidth : 0) + drag)))
            .simultaneousGesture(DragGesture(minimumDistance: 24)
                .updating($drag) { value, state, _ in
                    if abs(value.translation.width) > abs(value.translation.height) * 1.5 {
                        state = value.translation.width
                    }
                }.onEnded { value in
                    guard !source.isSample, abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    showingRemove = value.translation.width < -35 || (showingRemove && value.translation.width < 35)
                })
        }
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        .clipped()
        .overlay(alignment: .bottom) { Divider().opacity(insertion == nil ? 1 : 0) }
        .modifier(SourceDrop(store: store, item: source.id.uuidString + "|", dragging: $draggingFolder, insertion: $insertion))
        .accessibilityAction(named: "移除来源") { if !source.isSample { store.remove(source) } }
    }
}

private struct CollapseAllIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 20
        let box = CGRect(x: rect.midX - 7.5 * scale, y: rect.midY - 7.5 * scale,
                         width: 15 * scale, height: 15 * scale)
        var path = Path()
        path.addRoundedRect(in: box, cornerSize: CGSize(width: 3 * scale, height: 3 * scale))
        path.move(to: CGPoint(x: rect.midX - 3.5 * scale, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + 3.5 * scale, y: rect.midY))
        return path
    }
}

private struct TreeDirectory: View {
    @ObservedObject var store: ReaderStore
    @Environment(\.locale) private var locale
    let source: FolderSource
    let url: URL
    let level: Int
    let selection: Color
    @Binding var draggingFolder: String?
    var onOpenDocument: () -> Void = {}
    var key: String { store.key(source: source, url: url) }
    var isExpanded: Bool { store.expanded.contains(key) }
    private var accessibleName: String { source.isSample ? ReaderLanguage.message(source.name, locale: locale) : source.name }
    var directoryHeader: some View {
            HStack(spacing: 0) {
              Button { store.toggle(source: source, directory: url) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).frame(width: 12, height: 12)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .contentTransition(.identity)
                    if level == 0 && source.remote != nil {
                        Image("GitHubMark").resizable().scaledToFit().frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: level == 0 ? "folder.fill" : "folder")
                            .foregroundStyle(level == 0 ? Color.accentColor : Color.secondary)
                    }
                    (source.isSample && level == 0 ? Text("阅读示例") : Text(level == 0 ? source.name : url.lastPathComponent))
                        .fontWeight(level == 0 ? .semibold : .regular)
                        .lineLimit(level == 0 ? 2 : 1).truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.font(.subheadline).padding(.leading, CGFloat(min(level, 5) * 14 + 10)).padding(.trailing, 10).frame(minHeight: level == 0 ? 56 : 44).contentShape(Rectangle())
              }.buttonStyle(.plain)
                .accessibilityLabel(level == 0 ? (source.remote == nil ? Text("\(accessibleName)，文件夹来源") : Text("\(accessibleName)，GitHub 来源")) : Text(url.lastPathComponent))
                .accessibilityValue(isExpanded ? Text("已展开") : Text("已收起"))
                .accessibilityHint(level == 0 ? Text("长按并上下拖动可调整来源顺序") : Text(url.lastPathComponent))
                .modifier(SourceReorder(store: store, item: key, dragging: $draggingFolder, enabled: level == 0))
              if level == 0 && isExpanded {
                  Button {
                      store.collapseSubdirectories(in: source)
                  } label: {
                      CollapseAllIcon()
                          .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                          .frame(width: 20, height: 20)
                          .frame(width: 44, height: 44).contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .disabled(!store.hasExpandedSubdirectories(in: source))
                  .accessibilityLabel("收起全部子目录")
                  .help("收起全部子目录")
              } else if level == 0 {
                  Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
              }
              if level == 0 && !source.isSample {
                  Button {
                      Task { await store.refresh(source) }
                  } label: {
                      Group {
                          if store.refreshingSources.contains(source.id) { ProgressView().controlSize(.small) }
                          else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18)).foregroundStyle(.secondary) }
                      }.frame(width: 20, height: 20)
                          .frame(width: 44, height: 44).contentShape(Rectangle())
                  }
                  .buttonStyle(.plain).disabled(store.refreshingSources.contains(source.id))
                  .accessibilityLabel("刷新来源：\(accessibleName)")
                  .accessibilityHint(source.remote == nil ? Text("重新读取目录和当前文档，不修改源文件") : Text("拉取最新目录和当前文档，不上传任何修改"))
              } else if level == 0 {
                  Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
              }
            }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if level > 0 { directoryHeader }
            if isExpanded {
                if let error = store.directoryErrors[key] {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ReaderLanguage.message(error, locale: locale)).font(.caption).foregroundStyle(.secondary)
                        if source.remote == nil {
                            Button("重试") { Task { await store.loadChildren(source: source, directory: url, reload: true) } }
                        }
                    }.padding(.leading, 24)
                } else if let nodes = store.nodes[key] {
                    if nodes.isEmpty { Text("没有 Markdown 文档").font(.caption).foregroundStyle(.secondary).padding(.leading, 30).padding(.vertical, 8) }
                    ForEach(nodes) { node in
                        if node.isDirectory {
                            // Type erase only the recursive edge; the tree is loaded one directory at a time.
                            AnyView(TreeDirectory(store: store, source: source, url: node.url, level: level + 1, selection: selection, draggingFolder: $draggingFolder, onOpenDocument: onOpenDocument))
                        } else {
                            let selected = store.selectedKey == store.key(source: source, url: node.url)
                            Button { onOpenDocument(); store.open(node.url, source: source) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                                    Text(node.name).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }.font(.subheadline).padding(.leading, CGFloat(min(level + 1, 5) * 14 + 32)).padding(.trailing, 12)
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .background(selected ? selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .accessibilityHint(node.url.path)
                        }
                    }
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
            }
        }
        // Keep expanding/collapsing text rows crisp, including inherited system
        // transactions. Only this tree opts out; reading and navigation retain theirs.
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .task(id: "\(key)-\(isExpanded)-\(store.sourceVersions[source.id, default: 0])") {
            if isExpanded { await store.loadChildren(source: source, directory: url) }
        }
    }
}

private struct GitHubAddSheet: View {
    @ObservedObject var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var url = ""
    @State private var reference = ""
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://github.com/owner/repository", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityLabel("GitHub 链接")
                } footer: {
                    Text("支持公开仓库、目录或 Markdown 文件。私有仓库暂未开放。")
                }
                DisclosureGroup("指定分支或标签（可选）") {
                    TextField("例如 main 或 feature/notes", text: $reference)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("链接存在歧义时填写；留空则自动解析。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let failure { Text(ReaderLanguage.message(failure, locale: locale)).foregroundStyle(.red).font(.callout) }
                if store.isAddingGitHub { HStack { ProgressView(); Text("正在读取来源…").foregroundStyle(.secondary) } }
            }
            .disabled(store.isAddingGitHub)
            .navigationTitle(ReaderLanguage.message("添加 GitHub 来源", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { task?.cancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        failure = nil
                        task = Task {
                            if await store.addGitHub(url, reference: reference) { dismiss() }
                            else if !Task.isCancelled { failure = store.error; store.error = nil }
                        }
                    }.disabled(store.isAddingGitHub || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(store.isAddingGitHub)
        .onDisappear { task?.cancel() }
    }
}
