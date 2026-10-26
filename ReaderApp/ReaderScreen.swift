import SwiftUI
#if os(macOS)
import AppKit
#endif
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
    @State private var managingGitHubAccess = false
    @State private var managingOfflineCache = false
    #if os(iOS)
    @State private var appearanceAvailableSize = CGSize(width: 375, height: 667)
    private var mobileAppearanceWidth: CGFloat { min(456, max(0, appearanceAvailableSize.width - 32)) }
    private var usesCompactPalette: Bool { mobileAppearanceWidth < 456 }
    #endif
    #if os(macOS)
    @State private var readingFrame = CGRect.zero
    @StateObject private var macSystemAppearance = MacSystemAppearance()
    #endif
    @State private var showAppearance = false
    @State private var draggingFolder: String?
    @State private var sourceInsertion: SourceInsertion?
    @AppStorage("pinnedSourcesExpanded") private var pinnedSourcesExpanded = true
    @State private var findRequest = 0
    @State private var anchor: String?
    @State private var prefersSingleColumn = false
    @State private var hasAdaptedLayout = false
    @State private var renderingID: UUID?
    @AppStorage("fontSize") private var fontSize = 17.0
    @AppStorage("readerLanguage") private var languageValue = ReaderLanguage.system.rawValue
    @AppStorage("readerPalette") private var paletteValue = ReaderPalette.mist.rawValue
    @AppStorage("readerTheme") private var theme = "system"
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #else
    @State private var findText = ""
    @State private var findFocusRequest = 0
    #endif
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var dark: Bool {
        #if os(macOS)
        theme == "dark" || (theme == "system" && macSystemAppearance.isDark)
        #else
        theme == "dark" || (theme == "system" && systemScheme == .dark)
        #endif
    }
    private var scaledSize: Double {
        #if os(iOS)
        UIFontMetrics(forTextStyle: .body).scaledValue(for: fontSize)
        #else
        fontSize
        #endif
    }
    private var leadingToolbar: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }
    private var trailingToolbar: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }
    private var searchText: String {
        #if os(macOS)
        findText
        #else
        ""
        #endif
    }
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

    private func sourceSections(_ sources: [FolderSource]) -> some View {
                    ForEach(sources) { source in
                        Section {
                            if let root = source.url {
                                TreeDirectory(store: store, source: source, url: root, level: 0, selection: colors.selection, draggingFolder: $draggingFolder, onOpenDocument: showReadingColumn)
                            } else {
                                Text("文件夹暂时无法访问，请稍后重试。")
                                    .font(.caption).foregroundStyle(.secondary).padding(14)
                            }
                        } header: {
                            SourceHeader(store: store, source: source, selection: colors.selection, draggingFolder: $draggingFolder, insertion: $sourceInsertion)
                                .background { SourceHeaderBackground() }
                        }
                    }
    }

    private var brandSpacing: CGFloat {
        #if os(macOS)
        8
        #else
        14
        #endif
    }

    private var readerBrand: some View {
                    HStack(spacing: brandSpacing) {
                        Image("ReaderBrand")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .accessibilityHidden(true)
                        Text(verbatim: "iMDReader")
                            .font(SidebarTypography.brand)
                            .lineLimit(1)
                            #if os(iOS)
                            .minimumScaleFactor(0.8)
                            #endif
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    #if os(iOS)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    #endif
                    .foregroundStyle(colors.ink)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    if store.orderedSources.contains(where: { store.isPinned($0) }) {
                        Button { pinnedSourcesExpanded.toggle() } label: {
                            HStack {
                                Text("置顶").font(.headline)
                                Spacer()
                                Image(systemName: pinnedSourcesExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }.padding(.horizontal, 14).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityValue(pinnedSourcesExpanded ? Text("已展开") : Text("已收起"))
                        if pinnedSourcesExpanded {
                            sourceSections(store.orderedSources.filter { store.isPinned($0) })
                        }
                    }
                    Text("资料库").font(SidebarTypography.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 16)
                    sourceSections(store.orderedSources.filter { !store.isPinned($0) })
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
                                }.font(SidebarTypography.row).padding(.leading, 10)
                                    .background(store.selectedKey == file.key ? colors.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }
                        } header: {
                            HStack {
                                Text("最近文件").font(SidebarTypography.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("清空") { store.clearRecentFiles() }
                                    .font(.caption).accessibilityLabel("清空最近文件")
                                    .frame(minWidth: 44, minHeight: 44)
                            }.padding(.horizontal, 12).background(colors.sidebar)
                        }
                    }
                    Text("仅阅读，不修改源文件").font(SidebarTypography.footnote).foregroundStyle(.secondary).padding(16)
                }.padding(.horizontal, 12)
            }
            .foregroundStyle(colors.ink)
            .background(colors.sidebar)
            .navigationTitle("")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: leadingToolbar) {
                    readerBrand
                }
                #endif
                #if os(macOS)
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .primaryAction) {
                        macNativeAddButton.glassEffect(.regular, in: Circle())
                    }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .primaryAction) { macNativeAddButton }
                }
                #else
                ToolbarItem(placement: trailingToolbar) {
                    Menu {
                        Button("打开 Markdown 文件", systemImage: "doc.text") { selectingMarkdown = true; importing = true }
                        Button("本地文件夹", systemImage: "folder") { selectingMarkdown = false; importing = true }
                        Button("GitHub 链接", systemImage: "link") { addingGitHub = true }
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("添加来源")
                }
                #endif
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
                        ReaderWebView(document: document, fontSize: scaledSize, dark: dark, palette: palette, language: language.resolved(), reduceMotion: reduceMotion, findRequest: findRequest, findText: searchText, anchor: $anchor,
                                      onProgress: { store.recordProgress($0, documentKey: document.key) },
                                      onInternalLink: { url in
                                          if let source = store.sources.first(where: { $0.id == document.sourceID }) { store.open(url, source: source) }
                                      }, onError: { store.error = $0 }, onReady: {
                                          if renderingID == document.id { renderingID = nil }
                                      })
                            .id(document.id)
                        HStack {
                            Text(documentFolderName).lineLimit(1)
                            if store.isReadingOffline && !document.isStandalone {
                                Label("缓存阅读", systemImage: "internaldrive").foregroundStyle(Color.accentColor)
                            }
                            Spacer()
                            Text(store.progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 10)
                    }
                } else if !store.isLoading {
                    ContentUnavailableView {
                        Label("留一点空间，开始阅读", systemImage: "book.closed")
                    } description: {
                        Text("从左侧选择文章，或添加文件夹与 GitHub 链接。")
                    } actions: {
                        Menu {
                            Button("打开 Markdown 文件", systemImage: "doc.text") { selectingMarkdown = true; importing = true }
                            Button("本地文件夹", systemImage: "folder") { selectingMarkdown = false; importing = true }
                            Button("GitHub 链接", systemImage: "link") { addingGitHub = true }
                        } label: { Label("添加来源", systemImage: "plus") }.buttonStyle(.bordered)
                    }
                }
                if store.isLoading || renderingID != nil {
                    ProgressView("正在打开文档…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            #if os(macOS)
            .background(ReadingFrameProbe { frame in
                if readingFrame != frame {
                    readingFrame = frame
                }
            })
            .navigationTitle("")
            .toolbar {
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .navigation) {
                        readerBrand.padding(.horizontal, 8)
                    }
                        .sharedBackgroundVisibility(.visible)
                } else {
                    ToolbarItem(placement: .navigation) {
                        readerBrand.padding(.horizontal, 8)
                    }
                }
                if #available(macOS 26.0, *) {
                    ToolbarItem(placement: .principal) { macReadingTitle }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .principal) { macReadingTitle }
                }
            }
            #else
            .navigationTitle(store.document.map { Text($0.url.lastPathComponent) } ?? Text("阅读"))
            #endif
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItemGroup(placement: trailingToolbar) {
                    if let document = store.document {
                        #if os(macOS)
                        MacFindField(text: $findText, focusRequest: findFocusRequest,
                                     placeholder: ReaderLanguage.message("文内查找", locale: language.locale),
                                     submit: { findRequest += 1 })
                            .frame(width: 140)
                        Button { findFocusRequest += 1; findRequest += 1 } label: { Label("查找下一个", systemImage: "magnifyingglass") }
                        #else
                        Button { findRequest += 1 } label: { Label("文内查找", systemImage: "magnifyingglass") }
                            .keyboardShortcut("f", modifiers: .command)
                            .disabled(store.isLoading || renderingID != nil)
                        #endif
                        Menu {
                            if document.rendered.headings.isEmpty { Text("这篇文章没有标题") }
                            ForEach(document.rendered.headings) { heading in
                                Button(String(repeating: "　", count: min(heading.level - 1, 2)) + heading.title) { anchor = heading.id }
                            }
                        } label: { Label("文章目录", systemImage: "list.bullet") }
                    }
                    #if os(macOS)
                    Button { showAppearance.toggle() } label: { Text("Aa").font(.system(.title3, design: .serif)) }
                        .accessibilityLabel("阅读外观")
                    #else
                    Button { showAppearance = true } label: { Text("Aa").font(.system(.title3, design: .serif)) }
                        .accessibilityLabel("阅读外观")
                        .popover(isPresented: $showAppearance) { appearancePanel }
                    #endif
                    if visibility != .detailOnly {
                        Button("沉浸阅读", systemImage: "arrow.up.left.and.arrow.down.right") { visibility = .detailOnly }
                    }
                    Menu {
                        Button("GitHub 授权", systemImage: "key") { managingGitHubAccess = true }
                        Button("离线缓存", systemImage: "internaldrive") { managingOfflineCache = true }
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("应用设置")
                }
            }
        }
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            if showAppearance { macAppearanceOverlay }
        }
        #endif
        .tint(readerTint)
        .accentColor(readerTint)
        #if os(macOS)
        .preferredColorScheme(dark ? .dark : .light)
        #else
        .preferredColorScheme(theme == "system" ? nil : (dark ? .dark : .light))
        #endif
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { adaptLayout(to: geometry.size) }
                    .onChange(of: geometry.size) { _, size in adaptLayout(to: size) }
        #if os(iOS)
                    .onChange(of: horizontalSizeClass) { _, _ in adaptLayout(to: geometry.size) }
        #endif
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
        .sheet(isPresented: $managingGitHubAccess) { GitHubAccessSheet(store: store) }
        .sheet(isPresented: $managingOfflineCache) { OfflineCacheSheet(store: store) }
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
        .task { await store.configureOfflineCache(); store.restoreLastDocument() }
        .environment(\.locale, language.locale)
        #if os(macOS)
        .focusedSceneValue(\.readerActions, ReaderActions(
            openFile: { selectingMarkdown = true; importing = true },
            openFolder: { selectingMarkdown = false; importing = true },
            addGitHub: { addingGitHub = true },
            find: { findFocusRequest += 1 }))
        #endif

    }

    private func showReadingColumn() {
        guard prefersSingleColumn else { return }
        compactColumn = .detail
        visibility = .detailOnly
    }

    private func adaptLayout(to size: CGSize) {
        #if os(iOS)
        appearanceAvailableSize = size
        #endif
        #if os(macOS)
        let singleColumn = false
        #else
        let singleColumn = size.width < 900 || size.width < size.height || horizontalSizeClass == .compact
        #endif
        // Rotation, keyboard and safe-area changes must not undo a user's return
        // to the library when the navigation layout itself has not changed.
        guard !hasAdaptedLayout || singleColumn != prefersSingleColumn else { return }
        hasAdaptedLayout = true
        prefersSingleColumn = singleColumn
        if prefersSingleColumn {
            if store.document != nil || store.selectedKey != nil { showReadingColumn() }
            else { compactColumn = .sidebar; visibility = .all }
        } else { visibility = .all }
    }

    private var fontSliderPosition: Binding<Double> {
        Binding(get: { ReaderFontScale.position(for: fontSize) },
                set: { fontSize = ReaderFontScale.size(at: $0) })
    }

    #if os(macOS)
    private var macNativeAddButton: some View {
                    NativeAddMenu(locale: language.locale,
                                  openFile: { selectingMarkdown = true; importing = true },
                                  openFolder: { selectingMarkdown = false; importing = true },
                                  openGitHub: { addingGitHub = true })
                        .frame(width: 36, height: 36)
    }

    private var macReadingTitle: some View {
        ReadingAreaTitle(title: store.document?.url.lastPathComponent ?? "", targetCenterX: readingFrame.midX)
            .frame(width: min(600, max(80, readingFrame.width - 320)), height: 24)
    }

    private var macAppearanceOverlay: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Button("关闭阅读外观") { showAppearance = false }
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0).clipped()
                    .accessibilityHidden(true)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showAppearance = false }
                ViewThatFits(in: .vertical) {
                    appearancePanel
                    ScrollView { appearancePanel }
                }
                .frame(width: min(456, max(0, geometry.size.width - 24)))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .padding(12)
            }
        }
    }
    #endif

    private var appearancePanel: some View {
        #if os(iOS)
        ViewThatFits(in: .vertical) {
            appearanceContents.fixedSize(horizontal: false, vertical: true)
            ScrollView { appearanceContents }
        }
        .frame(width: mobileAppearanceWidth)
        .frame(maxHeight: max(160, appearanceAvailableSize.height - 80))
        .presentationCompactAdaptation(.popover)
        #else
        appearanceContents
        #endif
    }

    private var appearanceContents: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("阅读外观").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("正文字号")
                    Text("\(Int(fontSize))").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: fontSliderPosition, in: 0...1) {
                    Text("正文字号")
                } minimumValueLabel: { Text("A").font(.caption) }
                  maximumValueLabel: { Text("A").font(.title3) }
                    .accessibilityValue("\(Int(fontSize)) 点")
            }
            #if os(macOS)
            MacAppearanceSegments(title: "明暗", options: [("跟随系统", "system"), ("浅色", "light"), ("深色", "dark")], selection: $theme, locale: language.locale, tint: readerTint)
                .frame(height: 24)
            #else
            Picker("明暗", selection: $theme) {
                Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark")
            }.pickerStyle(.segmented)
            #endif
            VStack(alignment: .leading, spacing: 12) {
                Text("配色").font(.subheadline)
                #if os(macOS)
                MacAppearanceSegments(title: "配色", options: ReaderPalette.allCases.map { ($0.name, $0.rawValue) }, selection: $paletteValue, locale: language.locale, tint: readerTint)
                    .frame(height: 24)
                #else
                if usesCompactPalette {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(ReaderPalette.allCases) { option in
                            Button { paletteValue = option.rawValue } label: {
                                Text(LocalizedStringKey(option.name))
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.bordered)
                            .tint(paletteValue == option.rawValue ? readerTint : .secondary)
                            .background(paletteValue == option.rawValue ? readerTint.opacity(0.18) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityAddTraits(paletteValue == option.rawValue ? .isSelected : [])
                        }
                    }
                } else {
                    Picker("配色", selection: $paletteValue) {
                        ForEach(ReaderPalette.allCases) { option in
                            Text(LocalizedStringKey(option.name)).tag(option.rawValue)
                        }
                    }.pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                }
                #endif
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("语言").font(.subheadline)
                #if os(macOS)
                MacAppearanceSegments(title: "语言", options: [("跟随系统", "system"), ("简体中文", "zh-Hans"), ("English", "en")], selection: $languageValue, locale: language.locale, tint: readerTint)
                    .frame(height: 24)
                #else
                Picker("语言", selection: $languageValue) {
                    Text("跟随系统").tag("system")
                    Text("简体中文").tag("zh-Hans")
                    Text("English").tag("en")
                }.pickerStyle(.segmented)
                #endif
            }
        }
        #if os(macOS)
        .labelsHidden()
        #endif
        .environment(\.locale, language.locale)
        .padding(28)
        #if os(macOS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        #else
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
        #if os(iOS)
        .preferredColorScheme(dark ? .dark : .light)
        #endif
        .tint(readerTint)
    }
}

private struct SourceReorder: ViewModifier {
    @ObservedObject var store: ReaderStore
    let item: String
    @Binding var dragging: String?
    var enabled = true
    func body(content: Content) -> some View {
        if enabled && store.canDragSource(item) {
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

// Section headers can remain hosted while sources move between pinned groups.
// Observe appearance here so their backgrounds do not depend on a captured Color.
private struct SourceHeaderBackground: View {
    @AppStorage("readerPalette") private var paletteValue = ReaderPalette.mist.rawValue
    @AppStorage("readerTheme") private var theme = "system"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = theme == "dark" || (theme == "system" && colorScheme == .dark)
        ReaderPalette.resolve(paletteValue).colors(dark: dark).sidebar
    }
}

private struct SourceHeader: View {
    @ObservedObject var store: ReaderStore
    let source: FolderSource
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
                        Label(source.name, systemImage: "folder").font(SidebarTypography.row).fontWeight(.semibold)
                        Spacer()
                        Button("重试") { Task { await store.retryLocalSource(source) } }
                    }.padding(14).frame(minHeight: 56)
                        .modifier(SourceReorder(store: store, item: source.id.uuidString + "|", dragging: $draggingFolder))
                }
            }
            .frame(maxWidth: .infinity)
            .background { SourceHeaderBackground() }
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
        .contextMenu {
            Button { store.togglePin(source) } label: {
                Label(store.isPinned(source) ? "取消置顶" : "置顶来源", systemImage: store.isPinned(source) ? "pin.slash" : "pin")
            }
        }
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
                }.font(SidebarTypography.row).padding(.leading, CGFloat(min(level, 5) * 14 + 10)).padding(.trailing, 10).frame(minHeight: level == 0 ? 56 : 44).contentShape(Rectangle())
              }.buttonStyle(.plain)
                .accessibilityLabel(level == 0 ? (source.remote == nil ? Text("\(accessibleName)，文件夹来源") : Text("\(accessibleName)，GitHub 来源")) : Text(url.lastPathComponent))
                .accessibilityValue(isExpanded ? Text("已展开") : Text("已收起"))
                .accessibilityHint(level == 0 ? (store.isPinned(source) ? Text("已置顶，取消置顶后可拖动") : Text("长按并上下拖动可调整来源顺序")) : Text(url.lastPathComponent))
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
                    ForEach(nodes) { node in
                        if node.isDirectory {
                            // Type erase only the recursive edge; the tree is loaded one directory at a time.
                            AnyView(TreeDirectory(store: store, source: source, url: node.url, level: level + 1, selection: selection, draggingFolder: $draggingFolder, onOpenDocument: onOpenDocument))
                        } else {
                            let selected = store.selectedKey == store.key(source: source, url: node.url)
                            Button { onOpenDocument(); store.open(node.url, source: source) } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: node.isMarkdown ? "doc.text" : "doc").foregroundStyle(.secondary)
                                    Text(node.name).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }.font(SidebarTypography.row).padding(.leading, CGFloat(min(level + 1, 5) * 14 + 32)).padding(.trailing, 12)
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .disabled(!node.isMarkdown)
                                .foregroundStyle(node.isMarkdown ? .primary : .tertiary)
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

private struct OfflineCacheSheet: View {
    @State private var failure: String?
    @ObservedObject var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let failure { Text(ReaderLanguage.message(failure, locale: locale)).foregroundStyle(.red) }
                    LabeledContent("已用空间", value: ByteCountFormatter.string(fromByteCount: Int64(store.cachedBytes), countStyle: .file))
                    Picker("容量上限", selection: Binding(get: { store.cacheCapacityMB }, set: { value in
                        Task { await store.setCacheCapacity(value) }
                    })) {
                        ForEach([64, 128, 256], id: \.self) { value in Text("\(value) MB").tag(value) }
                    }
                    Button("清空离线缓存", role: .destructive) {
                        Task {
                            failure = nil
                            await store.clearOfflineCache()
                            failure = store.error; store.error = nil
                        }
                    }
                        .disabled(store.isClearingCache || store.isLoading)
                } footer: {
                    Text("自动缓存读过的 GitHub 文章、已列举目录和加载过的图片。断网或限流时使用已有缓存，不下载整个仓库。清空后保留当前页面、来源和授权，未缓存内容仍需联网。")
                }
                Section {
                    Text("私有缓存按令牌隔离并加密；清除授权会删除对应缓存。本地原文件不复制到缓存。缓存仅保留在本机，不是跨设备同步。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(ReaderLanguage.message("离线缓存", locale: locale))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.task { await store.refreshCacheUsage() }
    }
}

private struct GitHubAccessSheet: View {
    @ObservedObject var store: ReaderStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var token = ""
    @State private var failure: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(store.hasGitHubCredential ? "已保存授权" : "尚未保存授权", systemImage: "key")
                    SecureField("细粒度访问令牌", text: $token)
        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
        #endif
                        .privacySensitive()
                    Button("保存授权") { update(token) }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("令牌仅存入此设备的 Keychain，不显示已保存的令牌。保存不代表已验证仓库权限，添加来源时会检查。")
                }
                Section {
                    Link("前往 GitHub 创建令牌", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                } footer: {
                    Text("在 GitHub 创建 fine-grained token，选择需要阅读的仓库，将 Contents 设为 Read-only，并设置有效期。不要授予写入权限。")
                }
                if store.hasGitHubCredential {
                    Section {
                        Button("清除授权", role: .destructive) { update(nil) }
                    } footer: {
                        Text("清除本机令牌和 GitHub 阅读内容、目录及内存缓存，保留来源链接。本地文件不受影响；撤销令牌本身需到 GitHub 操作。")
                    }
                }
                if let failure { Text(ReaderLanguage.message(failure, locale: locale)).foregroundStyle(.red) }
                if working { ProgressView() }
            }
            .disabled(working)
            .navigationTitle(ReaderLanguage.message("GitHub 授权", locale: locale))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { token = ""; dismiss() }.disabled(working) } }
        }
        .interactiveDismissDisabled(working)
        .onDisappear { token = "" }
    }

    private func update(_ value: String?) {
        working = true; failure = nil
        let candidate = value
        token = ""
        Task {
            if !(await store.setGitHubCredential(candidate)) {
                failure = store.error; store.error = nil
            }
            working = false
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
        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        #endif
                        .accessibilityLabel("GitHub 链接")
                } footer: {
                    Text("支持仓库、目录或 Markdown 文件。私有仓库需先在“GitHub 授权”中保存只读令牌。")
                }
                DisclosureGroup("指定分支或标签（可选）") {
                    TextField("例如 main 或 feature/notes", text: $reference)
        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
        #endif
                    Text("链接存在歧义时填写；留空则自动解析。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let failure { Text(ReaderLanguage.message(failure, locale: locale)).foregroundStyle(.red).font(.callout) }
                if store.isAddingGitHub { HStack { ProgressView(); Text("正在读取来源…").foregroundStyle(.secondary) } }
            }
            .disabled(store.isAddingGitHub)
            .navigationTitle(ReaderLanguage.message("添加 GitHub 来源", locale: locale))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
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

private enum SidebarTypography {
    #if os(macOS)
    static let row = Font.system(size: 15)
    static let caption = Font.system(size: 12)
    static let footnote = Font.system(size: 12)
    static let brand = Font.system(size: 17, weight: .semibold)
    #else
    static let row = Font.subheadline
    static let caption = Font.caption
    static let footnote = Font.footnote
    static let brand = Font.headline
    #endif
}

#if os(macOS)
/// A full-width native segmented control; localized titles never determine its width.
private struct MacAppearanceSegments: NSViewRepresentable {
    let title: String
    let options: [(label: String, value: String)]
    @Binding var selection: String
    let locale: Locale
    let tint: Color

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.target = context.coordinator
        control.action = #selector(Coordinator.selectSegment(_:))
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.segmentCount = options.count
        for (index, option) in options.enumerated() {
            control.setLabel(ReaderLanguage.message(option.label, locale: locale), forSegment: index)
        }
        control.selectedSegmentBezelColor = NSColor(tint)
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
        control.setAccessibilityLabel(ReaderLanguage.message(title, locale: locale))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: 24)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: MacAppearanceSegments
        init(_ parent: MacAppearanceSegments) { self.parent = parent }
        @objc func selectSegment(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment].value
        }
    }
}
#endif

#if os(macOS)
private struct MacFindField: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let placeholder: String
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitSearch)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            field.window?.makeFirstResponder(field)
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacFindField
        var lastFocusRequest: Int
        init(_ parent: MacFindField) {
            self.parent = parent
            lastFocusRequest = parent.focusRequest
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        @objc func submitSearch() { parent.submit() }
    }
}

private struct ReadingFrameProbe: NSViewRepresentable {
    let changed: (CGRect) -> Void
    func makeNSView(context: Context) -> Probe { Probe(changed: changed) }
    func updateNSView(_ view: Probe, context: Context) { view.changed = changed; view.report() }
    final class Probe: NSView {
        var changed: (CGRect) -> Void
        init(changed: @escaping (CGRect) -> Void) { self.changed = changed; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func layout() { super.layout(); report() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        func report() {
            guard window != nil else { return }
            let rect = convert(bounds, to: nil)
            DispatchQueue.main.async { [weak self] in self?.changed(rect) }
        }
    }
}

private struct ReadingAreaTitle: NSViewRepresentable {
    let title: String
    let targetCenterX: CGFloat
    func makeNSView(context: Context) -> Title { Title() }
    func updateNSView(_ view: Title, context: Context) {
        view.label.stringValue = title
        view.label.toolTip = title
        view.targetCenterX = targetCenterX
        view.needsLayout = true
    }
    final class Title: NSView {
        let label = NSTextField(labelWithString: "")
        var targetCenterX: CGFloat = 0
        init() {
            super.init(frame: .zero)
            label.drawsBackground = false
            label.isBordered = false
            label.isBezeled = false
            label.alignment = .center
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            guard window != nil else { return }
            let center = convert(NSPoint(x: targetCenterX, y: 0), from: nil).x
            let width = max(0, 2 * min(center - bounds.minX, bounds.maxX - center))
            label.frame = CGRect(x: center - width / 2, y: (bounds.height - 20) / 2, width: width, height: 20)
        }
    }
}
#endif

#if os(macOS)
private struct NativeAddMenu: NSViewRepresentable {
    let locale: Locale
    let openFile: () -> Void
    let openFolder: () -> Void
    let openGitHub: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        button.bezelStyle = .circular
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.controlSize = .large
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        let title = ReaderLanguage.message("添加来源", locale: locale)
        button.setAccessibilityLabel(title)
        button.toolTip = title
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSButton, context: Context) -> CGSize? {
        CGSize(width: 36, height: 36)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeAddMenu
        init(_ parent: NativeAddMenu) { self.parent = parent }
        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            let options: [(String, Selector)] = [
                ("打开 Markdown 文件", #selector(openFile)),
                ("本地文件夹", #selector(openFolder)),
                ("GitHub 链接", #selector(openGitHub))
            ]
            for (title, action) in options {
                let item = NSMenuItem(title: ReaderLanguage.message(title, locale: parent.locale), action: action, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        }
        @objc func openFile() { parent.openFile() }
        @objc func openFolder() { parent.openFolder() }
        @objc func openGitHub() { parent.openGitHub() }
    }
}
#endif

#if os(macOS)
/// System appearance must not be inferred from a window with a reader override.
@MainActor private final class MacSystemAppearance: ObservableObject {
    @Published private(set) var isDark: Bool
    private var observation: NSKeyValueObservation?
    init() {
        isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
        }
    }
}


#endif
