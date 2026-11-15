import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import BlinkClipCapture
import BlinkClipCore
import QuickLookUI

@MainActor
struct ReplicaPreviewView: View {
    @ObservedObject var state: ReplicaUIState
    let itemID: UUID
    @State private var selectedFile = 0
    private var item: ClipboardItem? { state.store.items.first { $0.id == itemID } }

    var body: some View {
        Group {
            if let item {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        SourceAppIcon(item: item, store: state.store).frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title.isEmpty ? item.kind.displayName : item.title).font(.headline).lineLimit(2)
                            Text("\(item.sourceName) · \(item.kind.displayName) · \(itemSummary(item))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.isDeleted { Text("已删除").foregroundStyle(.secondary) }
                    }
                    Divider()
                    if item.kind == .files, !itemFileURLs(item).isEmpty {
                        filePreview(urls: itemFileURLs(item))
                    } else if item.kind == .image, let image = itemImage(item) {
                        ImageTextSelection(item: item, image: image)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            ReplicaItemContent(item: item, compact: false,
                                               linkPreviewsEnabled: state.store.preferences.linkPreviewsEnabled)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(8)
                        }
                    }
                    HStack {
                        Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if item.plainText != nil {
                            Button("编辑…") { state.controller?.showEditor(item: item) }
                        }
                        Button("拷贝") {
                            state.controller?.copy(item: item, plainTextOnly: false)
                        }.disabled(item.isDeleted)
                    }
                }
                .padding(22)
            } else {
                ContentUnavailableView("项目不存在", systemImage: "doc.questionmark", description: Text("这个项目已被移除。"))
            }
        }
        .frame(minWidth: 360, minHeight: 280)
        .preferredColorScheme(state.preferredScheme)
    }

    private func filePreview(urls: [URL]) -> some View {
        let index = min(selectedFile, urls.count - 1)
        let url = urls[index]
        return VStack(spacing: 8) {
            if urls.count > 1 {
                Picker("文件", selection: $selectedFile) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, file in
                        Text(file.lastPathComponent).tag(index)
                    }
                }
            }
            if FileManager.default.fileExists(atPath: url.path) {
                NativeFilePreview(url: url).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("文件不可用", systemImage: "doc.questionmark",
                                       description: Text("文件可能已移动或删除。\n\(url.lastPathComponent)"))
            }
        }
    }
}

@MainActor
struct NativeFilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.shouldCloseWithWindow = false
        view.autostarts = false
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if nsView.previewItem?.previewItemURL != url { nsView.previewItem = url as NSURL }
    }
    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) { nsView.close() }
}

@MainActor
struct ReplicaEditorView: View {
    @ObservedObject var state: ReplicaUIState
    let item: ClipboardItem?
    let close: () -> Void
    @StateObject private var document: ReplicaRichTextDocument
    @Environment(\.colorScheme) private var colorScheme

    init(state: ReplicaUIState, item: ClipboardItem?, close: @escaping () -> Void) {
        self.state = state
        self.item = item
        self.close = close
        let initial: NSAttributedString
        if let data = item?.payloads["public.rtf"], let rich = NSAttributedString(rtf: data, documentAttributes: nil) {
            initial = rich
        } else {
            initial = NSAttributedString(string: item?.plainText ?? "", attributes: [
                .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.textColor
            ])
        }
        _document = StateObject(wrappedValue: ReplicaRichTextDocument(content: initial))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button("取消", action: close)
                        .buttonStyle(.plain).padding(.horizontal, 10).frame(height: 22)
                        .overlay(Capsule().stroke(.gray.opacity(0.16)))
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(item == nil ? "创建" : "保存", action: save)
                        .buttonStyle(.plain).foregroundStyle(.white)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(document.content.length == 0 ? Color.gray.opacity(0.30) : .blue, in: Capsule())
                        .disabled(document.content.length == 0)
                        .keyboardShortcut("s", modifiers: .command)
                        .accessibilityIdentifier("editor-save")
                }
                HStack(spacing: 24) {
                    formatButton("B", format: .bold, active: document.bold)
                        .fontWeight(.bold).keyboardShortcut("b", modifiers: .command)
                    formatButton("I", format: .italic, active: document.italic)
                        .italic().keyboardShortcut("i", modifiers: .command)
                    formatButton("U", format: .underline, active: document.underlined)
                        .underline().keyboardShortcut("u", modifiers: .command)
                    formatButton("S", format: .strikethrough, active: document.struck).strikethrough()
                }
            }
            .padding(.horizontal, 8).frame(height: 38)
            ReplicaRichTextInput(document: document, save: save)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.horizontal, 5)
            HStack {
                Text("\(document.characterCount) 个字符  ·  \(document.wordCount) 单词  ·  \(document.lineCount) 行")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 12).frame(height: 38)
        }
        .frame(width: 500, height: 360)
        .background(colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.19)
                    : Color(red: 0.87, green: 0.85, blue: 0.83))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .preferredColorScheme(state.preferredScheme)
    }

    private func formatButton(_ label: String, format: ReplicaRichTextDocument.Format, active: Bool) -> some View {
        Button { document.toggle(format) } label: {
            Text(label).font(.system(size: 14)).frame(width: 16, height: 24)
                .background(active ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(format == .bold ? "粗体" : format == .italic ? "斜体" : format == .underline ? "下划线" : "删除线")
    }

    private func save() {
        guard document.content.length > 0 else { return }
        do {
            if let item {
                try state.store.updateRichTextItem(id: item.id, attributedString: document.content)
            } else {
                let rtf = try document.content.data(from: NSRange(location: 0, length: document.content.length),
                                                     documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
                let new = ClipboardItem(title: String(document.content.string.prefix(80)),
                                        kind: .richText, plainText: document.content.string, sourceName: ReplicaBrand.name,
                                        sourceBundleID: Bundle.main.bundleIdentifier,
                                        payloads: ["public.rtf": rtf, NSPasteboard.PasteboardType.string.rawValue: Data(document.content.string.utf8)])
                let id = try state.store.add(new)
                if let board = state.pinboardID { try state.store.assign(ids: [id], to: board) }
            }
            state.normalizeSelection()
            close()
        } catch { state.controller?.presentError(error) }
    }
}

@MainActor
struct ReplicaStackView: View {
    @ObservedObject var state: ReplicaUIState
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("\(ReplicaBrand.name) Stack").font(.system(size: 12, weight: .medium))
                HStack {
                    Button { state.controller?.hideStack() } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("关闭 \(ReplicaBrand.name) Stack")
                    Spacer()
                    Button { state.reverseStack() } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("反转 Stack 顺序")
                }.buttonStyle(.plain).padding(.horizontal, 8)
            }.frame(height: 32)
            if state.stackItemIDs.isEmpty {
                Text("Empty").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: 44)
            } else {
                ReplicaStackTable(state: state)
                    .frame(height: CGFloat(min(10, max(1, state.stackItemIDs.count)) * 44))
            }
        }
        .frame(width: 264)
        .background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 10))
        .preferredColorScheme(state.preferredScheme)
    }
}

@MainActor
struct ReplicaStackTable: NSViewRepresentable {
    @ObservedObject var state: ReplicaUIState

    func makeCoordinator() -> StackTableController { StackTableController() }
    func makeNSView(context: Context) -> NSScrollView {
        state.controller?.stackTableController = context.coordinator
        return context.coordinator.scrollView
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        let controller = context.coordinator
        controller.removeActionTitle = ShortcutRecorder.removeTitle
        controller.removeSnippet = { expectedIDs, row in
            let visibleOffsets = state.stackIDs.indices.filter { index in
                state.hasStackItem(state.stackIDs[index])
            }
            guard visibleOffsets.indices.contains(row),
                  visibleOffsets.map({ state.stackIDs[$0] }) == expectedIDs else { return false }
            state.stackIDs.remove(at: visibleOffsets[row])
            return true
        }
        controller.makeNativeCell = { [weak controller] input, row in
            let expectedIDs = controller?.snippetIDs ?? []
            return NSHostingView(rootView:
                StackSnippetCellView(input: input, imageProvider: { current in
                    if let rawType = current.previewRawType() {
                        return StackCategoryIcons.image(for: PasteboardContentKind(rawValue: UInt8(rawType)) ?? .unknown)
                    }
                    return StackCategoryIcons.image(for: state.store.originalContentKind(of: current.resolvedItem()))
                }).frame(maxWidth: .infinity).frame(height: 44)
                .contextMenu {
                    Button("复制") { state.controller?.copy(input: input, plainTextOnly: false) }
                    Button("粘贴") {
                        if state.controller?.pasteStackItem(id: input.id, plainTextOnly: false) == true {
                            controller?.removeRow(at: row, expectedIDs: expectedIDs)
                            if state.stackItemIDs.isEmpty { state.controller?.hideStack() }
                        }
                    }
                    Button("预览") { state.controller?.showPreview(item: input.resolvedItem(), input: input) }
                    Button("移除") { controller?.removeRow(at: row, expectedIDs: expectedIDs) }
                })
        }
        controller.updateNativeSnippets(state.stackSnippetInputs)
    }
}

/// 设置侧栏「关于闪贴」的入口。
///
/// 关于窗口既可以从应用菜单打开（`ReplicaAppDelegate.about`），也可以从设置侧栏
/// 打开。这里保留一份共享控制器，重复点击只是把同一个窗口提到最前；Sparkle 的
/// updater 本身是进程内单例（`BlinkClipInAppUpdater`），两条入口不会各起一个。
@MainActor
enum BlinkClipAboutWindow {
    private static var controller: BlinkClipAboutWindowController?

    /// 打开关于窗口。`onClose` 只给设置侧栏用：窗口关闭时把侧栏选中态落回点击前的
    /// 分区；菜单入口不传，行为与之前完全一致。
    static func present(onClose: (() -> Void)? = nil) {
        if controller == nil {
            controller = BlinkClipAboutWindowController(checker: BlinkClipUpdateChecker()) {
                try BlinkClipInAppUpdater().checkForUpdates()
            }
        }
        controller?.onClose = onClose
        controller?.showWindow(nil)
    }
}

/// 权限状态模型的持有者。
///
/// 标题行的「刷新状态」和卡片里的两条权限行必须是**同一份**模型，否则刷新按钮刷的
/// 是另一个对象；同时用 `lazy` 保持旧行为——只有第一次渲染隐私分区时才真正跑一次
/// 探针，打开设置（停在别的分区）不会白起一个子进程。
@MainActor
final class PermissionStatusModelProvider: ObservableObject {
    private let injected: PermissionStatusModel?
    private lazy var stored: PermissionStatusModel = injected ?? PermissionStatusModel()

    init(injected: PermissionStatusModel?) { self.injected = injected }

    var model: PermissionStatusModel { stored }
}

@MainActor
struct ReplicaSettingsView: View {
    @ObservedObject var state: ReplicaUIState
    /// 打开时默认选中的分区。深链（OCR/编辑器里的「打开设置」）用它落到「截图」。
    /// 必须有默认值：`Tests/Native/UIInteractionHarness.swift` 仍然用单参构造。
    var initialTab: Int = 0
    @StateObject private var permissionProvider: PermissionStatusModelProvider
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedExclusions: Set<String> = []
    @State private var showingMCPConfiguration = false
    @State private var tab: Int?
    /// 点「关于闪贴」之前的分区：关于窗关闭后侧栏选中态要落回这里。
    @State private var aboutReturnTab: Int?
    @State private var shortcutError = ""
    @State private var shortcutRowErrors: [String: String] = [:]
    @State private var shortcutRowGenerations: [String: Int] = [:]
    @State private var shortcutResetAlert: NSAlert?
    @State private var shortcutResetGeneration = 0
    @State private var backgroundEnabled = BackgroundService.isEnabled
    // 「截图」分区自己没有 UserDefaults 回调，用这两份 @State 做即时回显：
    // 初值在根视图构造时读一次（与 `initialTab` 同一时机），写入同时落到桥接层。
    @State private var screenshotPostCaptureAction = BlinkClipScreenshotSettings.postCaptureAction
    @State private var appleTranslationEnabled = TranslationSettingsBridge.appleTranslationEnabled
    // 「键盘快捷键 → 截图」：录制器要显示当前组合，靠这两份 @State + 通知回填；
    // 注册失败状态同理（改键后立刻显示，不必重开窗口）。
    @State private var screenshotRegionShortcut = BlinkClipScreenshotSettings.effectiveShortcut(for: .region)
    @State private var screenshotFullScreenShortcut = BlinkClipScreenshotSettings.effectiveShortcut(for: .fullScreen)
    @State private var screenshotHotKeyRegistrations = BlinkClipScreenshotSettings.lastRegistration
    // 「自动检查更新」：读的与写入的都是 Sparkle 自己那一个键
    // （`SUEnableAutomaticChecks` / `SPUUpdater.automaticallyChecksForUpdates`），
    // 所以重开设置窗、重启应用都保持同值，不另存一份偏好。
    @State private var automaticUpdates = BlinkClipInAppUpdater.automaticallyChecksForUpdates

    init(state: ReplicaUIState, initialTab: Int = 0, permissionModel: PermissionStatusModel? = nil) {
        _state = ObservedObject(wrappedValue: state)
        self.initialTab = initialTab
        _permissionProvider = StateObject(wrappedValue: PermissionStatusModelProvider(injected: permissionModel))
        // `@State` 的初值只在根视图被构造时读取；窗口已经开过就只能换一份新根视图
        // 才能换分区（见 `ReplicaUIController.installSettingsContent`）。
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        SettingsSplitView(title: paneTitle, sidebar: AnyView(sidebar), detail: AnyView(detail))
            .frame(minWidth: 640)
            .preferredColorScheme(state.preferredScheme)
            // 截图热键的回显与注册失败提示靠通知回填：录制器是独立子视图，
            // 父视图不会自动重算；挂在根视图而不是「截图」分区上，
            // 是为了在别的分区里发生的重注册（录制结束会重挂两个热键）也不漏。
            .onReceive(NotificationCenter.default.publisher(for: BlinkClipScreenshotSettings.hotKeysDidChange)) { _ in
                screenshotRegionShortcut = BlinkClipScreenshotSettings.effectiveShortcut(for: .region)
                screenshotFullScreenShortcut = BlinkClipScreenshotSettings.effectiveShortcut(for: .fullScreen)
            }
            .onReceive(NotificationCenter.default.publisher(for: BlinkClipScreenshotSettings.registrationDidChange)) { _ in
                screenshotHotKeyRegistrations = BlinkClipScreenshotSettings.lastRegistration
            }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: sidebarSelection) {
                ForEach(SettingsSection.allCases) { section in
                    sidebarRow(section.title, icon: section.icon, index: section.rawValue)
                }
                // 「AI 工具」之后的动作行：不参与分区选中，点开关于窗口。
                aboutRow
            }
            .listStyle(.sidebar)
            .padding(.top, sidebarTopInset)
            // 页脚只留帮助入口。原来的「闪贴设置」产品名一行已删掉：产品身份现在由
            // 分区列表末尾的「关于闪贴」承载。
            Link(destination: URL(string: "https://github.com/aexachao/BlinkClip#readme")!) {
                Label(SettingsCopy.text("general.help-center"), systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(16)
        }
    }

    /// 分区行的 tag 是分区 rawValue；这一行用一个不会被分区占用的值，绑定把它拦下来。
    private static let aboutRowTag = 1_000
    private static let aboutRowTitleKey = "updates.about-title"

    private var aboutRow: some View {
        Label(SettingsCopy.text(Self.aboutRowTitleKey), systemImage: "info.circle")
            .font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(Self.aboutRowTag)
            .accessibilityLabel(SettingsCopy.text(Self.aboutRowTitleKey))
            .accessibilityIdentifier("BlinkClipSettingsAbout")
    }

    /// 分区选中仍然直接写进 `tab`；「关于闪贴」那一行改成打开关于窗口，不改分区。
    ///
    /// 点动作行时**不动** `tab`（右侧内容与标题都留在原分区），只记住点击前的分区；
    /// 关于窗关闭时再把这个分区写回选中态。原生侧栏在点击那一下已经把自己高亮到
    /// 动作行上，而 `tab` 没变、SwiftUI 不会重画选区，所以关闭时要显式「清一帧再
    /// 落回」（见 `restoreSidebarAfterAbout`），否则高亮会一直停在动作行。
    private var sidebarSelection: Binding<Int?> {
        Binding(get: { tab }, set: { value in
            guard let value else { return }
            if value == Self.aboutRowTag {
                aboutReturnTab = tab ?? 0
                BlinkClipAboutWindow.present { restoreSidebarAfterAbout() }
                return
            }
            tab = value
        })
    }

    /// 关于窗关闭后把侧栏选中态落回点击前的分区，内容与标题跟着一起回去。
    ///
    /// 先置空一帧再写回原值：值没变化时 SwiftUI 不会重新应用选中态，原生
    /// `NSOutlineView` 就留在动作行上。两帧之间内容与标题都指向同一个分区，不会出现
    /// 「内容 A、标题 B」的错配。
    private func restoreSidebarAfterAbout() {
        guard let target = aboutReturnTab else { return }
        aboutReturnTab = nil
        tab = nil
        DispatchQueue.main.async { tab = target }
    }

    private var sidebarTopInset: CGFloat {
        if #available(macOS 26, *) { return -16 }
        return 0
    }

    private var paneTitle: String {
        SettingsSection(rawValue: tab ?? 0)?.title ?? SettingsSection.general.title
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch tab ?? 0 {
                case 1: privacy
                case 2: screenshot
                case 3: clipboard
                case 4: shortcuts
                case 5: mcp
                default: general
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipped()
    }

    private func sidebarRow(_ title: String, icon: String, index: Int) -> some View {
        Label(title, systemImage: icon).font(.system(size: 13))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(index)
            .accessibilityLabel(title)
    }

    private func pasteDestination(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(SettingsCopy.text(title))
            Text(SettingsCopy.text(subtitle))
                .font(.caption).settingsSecondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// 行内布局的唯一实现：左侧文字块（标题 + 可选说明）与右侧控件。
    ///
    /// 对齐靠 `HStack(alignment: .center)`，不靠上下 padding：多出来的行高由
    /// `frame(minHeight:)` 平均分给上下两边，右侧控件的外框中心与文字块中心落在
    /// 同一条中线上——单行对文字行高中心，双行对整个文字块中心。`Spacer` 的
    /// `minLength` 是文字与控件之间的最小间距，控件因此始终贴行右端。
    private func settingsRow<Trailing: View>(
        minHeight: CGFloat,
        spacing: CGFloat = 12,
        @ViewBuilder text: () -> some View,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) { text() }
            Spacer(minLength: spacing)
            trailing()
        }
        .frame(minHeight: minHeight)
    }

    private func settingsToggle(_ title: String, subtitle: String, isOn: Binding<Bool>,
                               identifier: String? = nil) -> some View {
        settingsRow(minHeight: 42) {
            Text(SettingsCopy.text(title))
            Text(ReplicaBrand.replacingName(in: SettingsCopy.text(subtitle)))
                .font(.caption).settingsSecondaryText()
                .fixedSize(horizontal: false, vertical: true)
                // 说明行带自己的键做标识：行内对齐断言按「标题 + 说明」整块量中线。
                .accessibilityIdentifier(subtitle)
        } trailing: {
            settingsRowSwitch(title: SettingsCopy.text(title), isOn: isOn, identifier: identifier)
        }
    }

    private func settingsSwitch(_ title: String, isOn: Binding<Bool>,
                                identifier: String? = nil) -> some View {
        settingsRow(minHeight: 30) {
            Text(title)
        } trailing: {
            settingsRowSwitch(title: title, isOn: isOn, identifier: identifier)
        }
    }

    /// 行内开关：与其它行控件同一写法（`.mini` 外观、隐藏标签），
    /// 外框即 26×15 的轨道，中心可被 AX 断言直接量到。
    private func settingsRowSwitch(title: String, isOn: Binding<Bool>,
                                   identifier: String?) -> some View {
        Toggle(title, isOn: isOn)
            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            .accessibilityIdentifierIfPresent(identifier)
    }

    private func excludedApplication(_ identifier: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        return HStack(spacing: 8) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                  ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                .resizable().frame(width: 20, height: 20)
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? identifier).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(identifier)
    }

    private func removeExcludedApps() {
        guard !selectedExclusions.isEmpty else { return }
        state.store.preferences.excludedBundleIDs.removeAll { selectedExclusions.contains($0) }
        selectedExclusions.removeAll()
        state.perform { try state.store.save() }
    }

    /// 通用页：按职责拆成三组小标题卡片，与剪贴板等页的
    /// `settingsSectionTitle` + `settingsCard` 模式一致。
    ///
    /// 「启动与运行」是应用生命周期，「同步与更新」是后台数据与网络行为，
    /// 「声音」是纯本地反馈：一张卡最多两项，超过就分组，避免单卡里塞五种
    /// 不同性质的行为。组内保留分隔线，组间只用 20pt 间距，不再加 Divider。
    private var general: some View {
        SettingsPageScroll {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(SettingsCopy.text("settings.general.startup-section.title"))
                    settingsCard {
                        settingsSwitch(SettingsCopy.text("settings.open-at-login.title"),
                                       isOn: Binding(get: { state.store.preferences.launchAtLogin },
                                                     set: { value in setLaunchAtLogin(value) }),
                                       identifier: "settings.open-at-login.toggle")
                        Divider()
                        settingsSwitch(SettingsCopy.text("settings.run-in-background.title"),
                                       isOn: Binding(get: { backgroundEnabled }, set: { value in
                                           BackgroundService.setEnabled(value)
                                       }),
                                       identifier: "settings.run-in-background.toggle")
                        .onReceive(BackgroundService.enabledChanges) { backgroundEnabled = $0 }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(SettingsCopy.text("settings.general.sync-section.title"))
                    settingsCard {
                        ICloudSyncGeneralRow(sync: state.originalCloudSync, drive: state.cloudSync)
                            .frame(minHeight: 42)
                        Divider()
                        // 「自动检查更新」紧跟 iCloud 同步：两者都是会自己发起后台
                        // 网络请求的行为，放在同一组里按「同步 → 更新」递进。
                        settingsToggle("settings.automatic-updates.title",
                                       subtitle: "settings.automatic-updates.subtitle",
                                       isOn: automaticUpdatesBinding,
                                       identifier: "settings.automatic-updates.toggle")
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(SettingsCopy.text("settings.general.sound-section.title"))
                    settingsCard {
                        // Same trilingual table as the rest of this pane: the Core
                        // bundle has no zh-Hant table, so String(localized:) would
                        // fall back to English for a Traditional reader.
                        settingsSwitch(SettingsCopy.text("settings.sound-effects.title"),
                                       isOn: preference(\.playSounds),
                                       identifier: "settings.sound-effects.toggle")
                    }
                }
            }
        }
    }

    /// 「自动检查更新」：打开写入 Sparkle 自己的 `SUEnableAutomaticChecks`
    /// （`SPUUpdater.automaticallyChecksForUpdates`），关掉写回 false；手动
    /// 「检查更新」按钮永远可用，不经过这个开关。回显用 `@State`，不重开窗口也
    /// 能立刻看到新状态。
    private var automaticUpdatesBinding: Binding<Bool> {
        Binding(get: { automaticUpdates }, set: { enabled in
            automaticUpdates = enabled
            BlinkClipInAppUpdater.automaticallyChecksForUpdates = enabled
        })
    }

    private var clipboard: some View {
        SettingsPageScroll {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(SettingsCopy.text("settings.paste-items.title"))
                    settingsCard {
                        ZStack(alignment: state.store.preferences.pasteToActiveApp ? .topTrailing : .bottomTrailing) {
                            Picker(SettingsCopy.text("settings.paste-items.title"), selection: preference(\.pasteToActiveApp)) {
                                pasteDestination("settings.paste-items.active-app.title", subtitle: "settings.paste-items.active-app.info").tag(true)
                                pasteDestination("settings.paste-items.clipboard.title", subtitle: "settings.paste-items.clipboard.info").tag(false)
                            }
                            .pickerStyle(.radioGroup).labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 100)
                            if let illustration = SettingsIllustrations.image(directPaste: state.store.preferences.pasteToActiveApp, dark: colorScheme == .dark) {
                                Image(nsImage: illustration).resizable().scaledToFit()
                                    .frame(width: 96, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                                    .allowsHitTesting(false)
                            }
                        }
                        Divider().padding(.vertical, 8)
                        Toggle(SettingsCopy.text("settings.paste-items.plain-text.title"), isOn: preference(\.alwaysPastePlainText))
                            .toggleStyle(.checkbox)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(SettingsCopy.text("settings.history.title"))
                    settingsCard {
                        HistoryRetentionPicker(days: state.store.preferences.historyRetentionDays) { days in
                            let previous = state.store.preferences.historyRetentionDays
                            try HistoryRetentionSaving.apply(days, previous: previous,
                                assign: { state.store.preferences.historyRetentionDays = $0 },
                                save: { try state.store.save() })
                        }
                        .padding(.vertical, 4)
                    }
                }
                // 不可撤销的动作放在页尾（与「快捷键」页的「恢复全部快捷键…」同一区域策略），
                // 并用系统红标出它的性质；确认弹窗再写明这一次会清掉多少条。
                settingsFooterAction(SettingsCopy.text("general.action.erase-history") + "…",
                                     identifier: "settings.clear-history", destructive: true) {
                    state.controller?.clearHistory()
                }
            }
        }
    }

    private func settingsSectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 10)
            .accessibilityIdentifier("settings.section-title")
    }

    /// 页尾动作：影响面大或不可撤销的管理动作统一放在**内容区底部、右对齐**。
    ///
    /// 「清空历史记录…」和「恢复全部快捷键…」共用这一条区域策略：不再挤进卡片正文，
    /// 也不占页首。`destructive` 只用系统红（`NSColor.systemRed`）做语义强调，
    /// 不引入新的视觉体系。
    private func settingsFooterAction(_ title: String, identifier: String,
                                      destructive: Bool = false,
                                      action: @escaping () -> Void) -> some View {
        HStack {
            Spacer(minLength: 8)
            Button(action: action) {
                Text(title)
                    .foregroundStyle(destructive ? Color(nsColor: .systemRed) : Color(nsColor: .linkColor))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func settingsCard<Content: View>(verticalPadding: CGFloat = 10, @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SettingsSurfaceStyle.cornerRadius)
        return VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, SettingsSurfaceStyle.contentPadding).padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsSurfaceStyle.cardBackgroundColor(dark: colorScheme == .dark), in: shape)
            .overlay(shape.strokeBorder(SettingsSurfaceStyle.cardBorderColor(dark: colorScheme == .dark),
                                        lineWidth: SettingsSurfaceStyle.borderWidth))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.card")
    }

    /// 「截图」分区（侧栏 index 2）。
    ///
    /// 截图后行为和翻译开关；所有快捷键统一位于「键盘快捷键」分区。
    private var screenshot: some View {
        SettingsPageScroll {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(ScreenshotSettingsCopy.text(.postCaptureSectionTitle))
                    settingsCard {
                        Picker(ScreenshotSettingsCopy.text(.postCaptureSectionTitle),
                               selection: screenshotPostCaptureActionBinding) {
                            ForEach(BlinkClipScreenshotAction.allCases, id: \.self) { action in
                                screenshotActionOption(action).tag(action)
                            }
                        }
                        // 用 `.radioGroup` 而不是 `.segmented`：内容列固定 440pt，
                        // 五个选项名分段排不进；而且每项要带一句后果说明，
                        // 分段控件显示不了副标题。这也与「粘贴目标」那组保持同一写法。
                        .pickerStyle(.radioGroup).labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ScreenshotSettingsCopy.text(.postCaptureFootnote))
                            .font(.caption).settingsSecondaryText()
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(ScreenshotSettingsCopy.text(.translationSectionTitle))
                    settingsCard {
                        screenshotTranslationRow
                    }
                }
            }
        }
    }

    private func screenshotActionOption(_ action: BlinkClipScreenshotAction) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(screenshotActionTitle(action))
            Text(screenshotActionSubtitle(action))
                .font(.caption).settingsSecondaryText()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func screenshotActionTitle(_ action: BlinkClipScreenshotAction) -> String {
        switch action {
        case .edit: return ScreenshotSettingsCopy.text(.postCaptureEditTitle)
        case .quickPin: return ScreenshotSettingsCopy.text(.postCaptureQuickPinTitle)
        case .textRecognition: return ScreenshotSettingsCopy.text(.postCaptureTextRecognitionTitle)
        case .copyImageText: return ScreenshotSettingsCopy.text(.postCaptureCopyImageTextTitle)
        case .screenshotTranslation: return ScreenshotSettingsCopy.text(.postCaptureTranslationTitle)
        }
    }

    private func screenshotActionSubtitle(_ action: BlinkClipScreenshotAction) -> String {
        switch action {
        case .edit: return ScreenshotSettingsCopy.text(.postCaptureEditSubtitle)
        case .quickPin: return ScreenshotSettingsCopy.text(.postCaptureQuickPinSubtitle)
        case .textRecognition: return ScreenshotSettingsCopy.text(.postCaptureTextRecognitionSubtitle)
        case .copyImageText: return ScreenshotSettingsCopy.text(.postCaptureCopyImageTextSubtitle)
        case .screenshotTranslation: return ScreenshotSettingsCopy.text(.postCaptureTranslationSubtitle)
        }
    }

    private var screenshotPostCaptureActionBinding: Binding<BlinkClipScreenshotAction> {
        Binding(get: { screenshotPostCaptureAction }, set: { action in
            screenshotPostCaptureAction = action
            // 写的是 capcap 侧那一个键（`blinkclip.screenshot.postCaptureAction`），
            // 区域截图入口 `CaptureEntry.presentRegionEditor` 下次触发时读它。
            BlinkClipScreenshotSettings.postCaptureAction = action
        })
    }

    /// 截图翻译的开关：读写的仍是 capcap 既有的 `translation.apple.enabled`，
    /// 「配置」这件事交给 TranslationConfigStore，BlinkClip 侧不新增键。
    private var screenshotTranslationRow: some View {
        let available = TranslationSettingsBridge.isAppleTranslationAvailableOnSystem
        let subtitle = available
            ? ScreenshotSettingsCopy.text(.appleTranslationSubtitle)
            : ScreenshotSettingsCopy.text(.appleTranslationUnavailable)
        // 与隐私页同构：走同一个 `settingsRow`，开关中心钉在文字块中心，
        // 单行对文字行高中心、双行对整个文字块中心（不再各页各写一套 HStack）。
        return settingsRow(minHeight: 42) {
            Text(ScreenshotSettingsCopy.text(.appleTranslationTitle))
            Text(subtitle)
                .font(.caption).settingsSecondaryText()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.apple-translation.subtitle")
        } trailing: {
            settingsRowSwitch(title: ScreenshotSettingsCopy.text(.appleTranslationTitle),
                              isOn: appleTranslationEnabledBinding,
                              identifier: "settings.apple-translation.toggle")
        }
        // 系统不到 macOS 15：整行禁用，副标题直接写原因，避免「打开了但不生效」。
        .disabled(!available)
    }

    private var appleTranslationEnabledBinding: Binding<Bool> {
        Binding(get: { appleTranslationEnabled }, set: { enabled in
            appleTranslationEnabled = enabled
            TranslationSettingsBridge.appleTranslationEnabled = enabled
        })
    }

    // MARK: - 截图 → 快捷键（B 档：两个截图热键可改）

    /// 一行截图热键：标题（+ 注册失败提示）与录制器。
    ///
    /// 录制器复用 `ReplicaShortcutRecorder`：系统快捷键与菜单冲突检测在
    /// `ShortcutValidation` 里，接上即得，不重复实现一套录制/校验。冲突与校验提示都
    /// 落在**这一行正下方**（4pt），并指名占用者；录制态不结束，可以直接改按别的组合。
    private func screenshotHotKeyRow(_ slot: BlinkClipScreenshotHotKeySlot) -> some View {
        let row: SettingsShortcutRow = slot == .region ? .region : .fullScreen
        let title = slot == .region
            ? ScreenshotSettingsCopy.text(.hotKeyRegionTitle)
            : ScreenshotSettingsCopy.text(.hotKeyFullScreenTitle)
        // 注册失败提示挂在这一行**下方**：只把系统给的 `OSStatus` 原样报出来，
        // 不解释错误码含义（不同 macOS 版本同一码的含义并不稳定，杜撰会误导排查）。
        var failureText: String?
        if let registration = screenshotHotKeyRegistrations[slot], !registration.succeeded {
            failureText = String(format: ScreenshotSettingsCopy.text(.hotKeyRegistrationFailureFormat),
                                 registration.combo, registration.status)
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                restoreShortcutButton(row)
                ReplicaShortcutRecorder(shortcut: screenshotHotKeyBinding(slot),
                                        label: title,
                                        error: { message in shortcutRowErrors[row.rawValue] = message.isEmpty ? nil : message },
                                        recordingChanged: { recording in
                                            // 录制期间必须摘掉两个截图热键：Carbon 热键会把
                                            // 用户想录的组合吞掉（表现为「录不上」）。
                                            // 走 begin/end 计数：两个录制器重叠时，先结束的那个
                                            // 不能把仍在等键的另一个的「让位」撤掉。
                                            setHotKeyRecording(recording)
                                        },
                                        allowsClearing: true,
                                        conflict: { value in shortcutConflictMessage(value, excluding: row) },
                                        conflictChanged: { shortcutRowErrors[row.rawValue] = $0 })
                    .id(shortcutResetGeneration)
                    .accessibilityIdentifier("settings.shortcut.recorder." + (slot == .region ? "region" : "fullScreen"))
                    .frame(width: 120, height: 24)
            }
            .frame(minHeight: 36)
            shortcutRowError(row)
            if let failureText {
                HStack(spacing: 8) {
                    Text(failureText)
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                    // 注册失败多半是「这个组合被别的 App 占着」。那个 App 退出后偏好值一个字节
                    // 都没变，`storeHotKey` 也就不会再发通知（值未变即返回），所以这里必须有一条
                    // **不依赖值变化**的重试入口：直接请协调器按当前偏好重注册一次。
                    Button(ScreenshotSettingsCopy.text(.hotKeyRetryRegistration)) {
                        shortcutRowErrors[row.rawValue] = nil
                        BlinkClipScreenshotSettings.requestHotKeyReload()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 录制器要的是 `BlinkClipCore.KeyboardShortcut?`；截图热键自己存在
    /// `BlinkClipScreenshotSettings`（不进 `AppPreferences`），这里只做形状转换。
    private func screenshotHotKeyBinding(_ slot: BlinkClipScreenshotHotKeySlot) -> Binding<BlinkClipCore.KeyboardShortcut?> {
        Binding(get: {
            guard let hotKey = slot == .region ? screenshotRegionShortcut : screenshotFullScreenShortcut else { return nil }
            return BlinkClipCore.KeyboardShortcut(keyCode: hotKey.keyCode,
                                              modifierRawValue: hotKey.modifierRawValue)
        }, set: { value in
            let row: SettingsShortcutRow = slot == .region ? .region : .fullScreen
            guard let value else {
                shortcutRowErrors[row.rawValue] = nil
                BlinkClipScreenshotSettings.clearShortcut(for: slot)
                if slot == .region { screenshotRegionShortcut = nil }
                else { screenshotFullScreenShortcut = nil }
                return
            }
            // 冲突正常由录制器的 `conflict:` 拦下（提示落在本行下方、录制态保持）；
            // 这里保留同一口径的兜底，防止别处直接写这个绑定。
            if let message = shortcutConflictMessage(value, excluding: row) {
                shortcutRowErrors[row.rawValue] = message
                return
            }
            shortcutRowErrors[row.rawValue] = nil
            applyScreenshotHotKey(BlinkClipScreenshotHotKey(keyCode: value.keyCode,
                                                        modifierRawValue: value.modifierRawValue),
                                  for: slot)
        })
    }

    private func applyScreenshotHotKey(_ hotKey: BlinkClipScreenshotHotKey,
                                       for slot: BlinkClipScreenshotHotKeySlot,
                                       force: Bool = false) {
        switch slot {
        case .region: screenshotRegionShortcut = hotKey
        case .fullScreen: screenshotFullScreenShortcut = hotKey
        }
        // 写偏好会发 `hotKeysDidChange`，`ScreenshotCoordinator` 据此注销旧键、注册新键。
        BlinkClipScreenshotSettings.setShortcut(hotKey, for: slot, force: force)
    }

    /// 录制器报「开始等键/结束等键」。截图热键的让位由 `ScreenshotCoordinator` 按
    /// `BlinkClipScreenshotSettings` 的计数落地（0→1 摘掉、1→0 挂回）。
    private func setHotKeyRecording(_ recording: Bool) {
        let wasRecording = BlinkClipScreenshotSettings.isRecording
        if recording { BlinkClipScreenshotSettings.beginRecording() }
        else { BlinkClipScreenshotSettings.endRecording() }
        let isRecording = BlinkClipScreenshotSettings.isRecording
        if wasRecording != isRecording {
            state.controller?.hotKeyRecordingChanged?(isRecording)
        }
    }

    /// 冲突检查的唯一口径：6 条路径 =「快捷键」分区四条 BlinkClip 命令 + 截图区域 + 截图全屏。
    ///
    /// 返回的是**占用者**而不是布尔：提示要指名「已被「打开堆栈面板」占用」，用户才知道
    /// 该去改哪一行。必须把两个截图槽位一起算：底层 `GlobalShortcutMonitor.registerShortcut`
    /// 遇到同值会先注销再登记，同值注册**不会**返回错误，只会静默顶掉另一条热键。
    private func shortcutOccupantTitle(_ value: BlinkClipCore.KeyboardShortcut,
                                       excluding row: SettingsShortcutRow) -> String? {
        // 八行统一比对：四条应用命令走偏好，两条截图热键走 `rowScreenshotValue` 的生效值。
        if let owner = SettingsShortcutRow.occupant(of: value, excluding: row,
                                                    preferences: state.store.preferences,
                                                    screenshots: { rowScreenshotValue($0) }) {
            return owner.title
        }
        let slot: BlinkClipScreenshotHotKeySlot? = row == .region ? .region : (row == .fullScreen ? .fullScreen : nil)
        if let occupying = BlinkClipScreenshotSettings.slot(occupyingKeyCode: value.keyCode,
                                                            modifierRawValue: value.modifierRawValue,
                                                            excluding: slot) {
            return occupying == .region
                ? ScreenshotSettingsCopy.text(.hotKeyRegionTitle)
                : ScreenshotSettingsCopy.text(.hotKeyFullScreenTitle)
        }
        return nil
    }

    /// 行下方的冲突文案。命中占用者才算冲突，`nil` 表示这一行可以赋值。
    private func shortcutConflictMessage(_ value: BlinkClipCore.KeyboardShortcut,
                                         excluding row: SettingsShortcutRow) -> String? {
        guard let owner = shortcutOccupantTitle(value, excluding: row) else { return nil }
        return SettingsCopy.trilingual("此快捷键已被「\(owner)」占用。",
                                       "此快捷鍵已被「\(owner)」占用。",
                                       "That shortcut is already used by “\(owner)”.")
    }

    private var privacy: some View {
        SettingsPageScroll {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    // 刷新入口落在卡片标题行右侧：它作用于整张卡片（两条权限行 + 授权
                    // 补救说明），不再像旧实现那样缩在卡片底部、看着只刷新某一条。
                    HStack(spacing: 8) {
                        settingsSectionTitle(PermissionCopy.text("系统权限", "系統權限", "System Permissions"))
                        Spacer(minLength: 8)
                        PermissionRefreshControl(model: permissionProvider.model)
                    }
                    settingsCard { PermissionStatusView(model: permissionProvider.model) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(SettingsCopy.trilingual("显示与预览", "顯示與預覽", "Display and Previews"))
                    settingsCard {
                    settingsToggle("settings.privacy.screensharing.title", subtitle: "settings.privacy.screensharing.subtitle", isOn: preference(\.showDuringScreenSharing), identifier: "settings.privacy.screensharing.toggle")
                    Divider()
                    settingsToggle("replica.settings.privacy.saved-link-preview.title", subtitle: "replica.settings.privacy.saved-link-preview.subtitle", isOn: preference(\.linkPreviewsEnabled), identifier: "settings.privacy.saved-link-preview.toggle")
                }
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(SettingsCopy.trilingual("内容过滤", "內容過濾", "Content Filters"))
                    settingsCard {
                    settingsToggle("settings.privacy.confidential-content.title", subtitle: "settings.privacy.confidential-content.subtitle", isOn: preference(\.ignoreConcealedContent))
                    Divider()
                    settingsToggle("settings.privacy.autogenerated-content.title", subtitle: "settings.privacy.autogenerated-content.subtitle", isOn: preference(\.ignoreTransientContent))
                }
                }
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(SettingsCopy.text("settings.privacy.applications-history.title")).font(.system(size: 13, weight: .semibold))
                        Text(SettingsCopy.text("settings.privacy.applications-history.subtitle"))
                            .font(.callout).settingsSecondaryText()
                    }.padding(.horizontal, 10).padding(.top, 8)
                    VStack(spacing: 0) {
                        List(state.store.preferences.excludedBundleIDs, id: \.self, selection: $selectedExclusions) { identifier in
                            excludedApplication(identifier).tag(identifier)
                                .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                                .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain).scrollContentBackground(.hidden)
                        .onDeleteCommand(perform: removeExcludedApps)
                        .overlay {
                            if state.store.preferences.excludedBundleIDs.isEmpty {
                                Text(SettingsCopy.text("settings.privacy.applications-history.empty"))
                                    .settingsSecondaryText().allowsHitTesting(false)
                            }
                        }
                        .frame(height: min(180, max(40, CGFloat(state.store.preferences.excludedBundleIDs.count) * 40)))
                        Divider()
                        HStack(spacing: 0) {
                            Button(action: chooseExcludedApp) { Image(systemName: "plus").frame(width: 20, height: 24) }
                                .accessibilityLabel(SettingsCopy.trilingual("添加应用", "加入應用程式", "Add App"))
                            Divider().frame(height: 16)
                            Button(action: removeExcludedApps) { Image(systemName: "minus").frame(width: 20, height: 24) }
                                .disabled(selectedExclusions.isEmpty).accessibilityLabel(SettingsCopy.trilingual("移除应用", "移除應用程式", "Remove App"))
                            Spacer()
                        }.buttonStyle(.borderless)
                    }
                    .background(SettingsSurfaceStyle.cardBackgroundColor(dark: colorScheme == .dark),
                                in: RoundedRectangle(cornerRadius: SettingsSurfaceStyle.cornerRadius))
                    .clipShape(RoundedRectangle(cornerRadius: SettingsSurfaceStyle.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: SettingsSurfaceStyle.cornerRadius)
                        .strokeBorder(SettingsSurfaceStyle.cardBorderColor(dark: colorScheme == .dark),
                                      lineWidth: SettingsSurfaceStyle.borderWidth))
                }
            }
        }
    }

    private var shortcuts: some View {
        SettingsPageScroll {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(ScreenshotSettingsCopy.text(.applicationShortcutsTitle))
                    settingsCard(verticalPadding: 0) {
                        shortcutRecorder(ReplicaBrand.replacingName(in: SettingsCopy.text("settings.shortcuts.activate-paste.title")), path: \.historyShortcut)
                        Divider()
                        shortcutRecorder(ReplicaBrand.replacingName(in: SettingsCopy.text("settings.shortcuts.activate-paste-stack.title")), path: \.stackShortcut)
                    }
                    .help(state.hotKeyStatusMessage)
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(ScreenshotSettingsCopy.text(.groupShortcutsTitle))
                    settingsCard(verticalPadding: 0) {
                        shortcutRecorder(SettingsCopy.text("blinkclip.settings.shortcuts.next-group.title"), path: \.nextPinboardShortcut)
                        Divider()
                        shortcutRecorder(SettingsCopy.text("blinkclip.settings.shortcuts.previous-group.title"), path: \.previousPinboardShortcut)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(ScreenshotSettingsCopy.text(.pasteShortcutsTitle))
                    settingsCard(verticalPadding: 0) {
                        HStack {
                            Text(SettingsCopy.text("settings.shortcuts.quick-paste.title"))
                            Spacer()
                            restoreShortcutButton(.quickPaste)
                            modifierPicker(.quickPaste)
                        }.frame(minHeight: 36)
                        shortcutRowError(.quickPaste)
                        Divider()
                        HStack {
                            Text(SettingsCopy.text("settings.shortcuts.plain-text.title"))
                            Spacer()
                            restoreShortcutButton(.plainText)
                            modifierPicker(.plainText)
                        }.frame(minHeight: 36)
                        shortcutRowError(.plainText)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    settingsSectionTitle(ScreenshotSettingsCopy.text(.hotKeySectionTitle))
                    // 冲突/校验提示都在各自那一行正下方（`shortcutHotKeyRow`/`shortcutRecorder`
                    // 的 4pt 间距），不再有「卡片下方一整组红字」：提示与行一一对应。
                    settingsCard(verticalPadding: 0) {
                        screenshotHotKeyRow(.region)
                        Divider()
                        screenshotHotKeyRow(.fullScreen)
                    }
                }
                // 管理动作放在页尾（与「清空历史记录…」同一区域策略）：它不再是内容区的
                // 第一眼焦点，首屏节奏回到「小标题 + 卡片」。失败提示跟着动作走。
                VStack(alignment: .trailing, spacing: 8) {
                    if !shortcutError.isEmpty {
                        Text(shortcutError).foregroundStyle(.red).font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.shortcuts.error")
                    }
                    settingsFooterAction(SettingsCopy.text("settings.shortcuts.reset-all"),
                                         identifier: "settings.reset-all-shortcuts") { resetShortcuts() }
                }
            }
        }
    }

    /// Compact selected symbols keep the number range legible; menu options retain full names.
    private func modifierPicker(_ row: SettingsShortcutRow) -> some View {
        let path = row.modifierPath!
        let value = state.store.preferences[keyPath: path]
        let symbols = ShortcutFunctions.modifierLabel(verbose: false, modifierRawValue: value)
        let selected = value == 0 ? SettingsCopy.trilingual("未设置", "未設定", "Not Set") : symbols
        return Menu {
            Picker(row.title, selection: preference(path)) {
                if row == .quickPaste {
                    Text("⌘ Command").tag(NSEvent.ModifierFlags.command.rawValue)
                } else {
                    Text("⇧ Shift").tag(NSEvent.ModifierFlags.shift.rawValue)
                }
                Text("⌥ Option").tag(NSEvent.ModifierFlags.option.rawValue)
                Text("⌃ Control").tag(NSEvent.ModifierFlags.control.rawValue)
                Text(SettingsCopy.trilingual("未设置", "未設定", "Not Set")).tag(UInt(0))
            }.labelsHidden().pickerStyle(.inline)
        } label: {
            Text(selected + (row == .quickPaste ? " + 1...9" : ""))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .frame(width: 120, height: 24, alignment: .trailing)
        .accessibilityLabel(row.title)
    }

    /// 一行应用命令快捷键：标题、恢复默认、录制器。
    ///
    /// 冲突在这一层判定并把**占用者**交给录制器（`conflict:`/`conflictChanged:`），
    /// 提示落在这一行正下方 4pt 处；被拒的组合不会写进偏好，也不会结束录制态，
    /// 用户可以直接改按别的组合键。旧实现把冲突文案写进整页共享的 `shortcutError`，
    /// 提示跑到页面最底部，离正在编辑的那一行很远。
    private func shortcutRecorder(_ title: String, path: WritableKeyPath<AppPreferences, BlinkClipCore.KeyboardShortcut?>) -> some View {
        let row = SettingsShortcutRow.allCases.first { $0.path == path }!
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                restoreShortcutButton(row)
                ReplicaShortcutRecorder(shortcut: Binding(get: { state.store.preferences[keyPath: path] }, set: { value in
                    // 冲突已在录制器里拦下；这里只写确认可用的组合，保存失败仍回滚并报在本行。
                    let previous = state.store.preferences[keyPath: path]
                    state.store.preferences[keyPath: path] = value
                    do {
                        try state.store.save()
                        shortcutRowErrors[row.rawValue] = nil
                        state.controller?.hotKeyConfigurationChanged?()
                    } catch {
                        state.store.preferences[keyPath: path] = previous
                        shortcutRowErrors[row.rawValue] = error.localizedDescription
                        shortcutRowGenerations[row.rawValue, default: 0] += 1
                    }
                }), label: title,
                   error: { message in shortcutRowErrors[row.rawValue] = message.isEmpty ? nil : message },
                   recordingChanged: { recording in
                       // 录制时截图热键也要让位，否则用户想录的组合可能被它吞掉。
                       // 计数口径：另一个录制器还在等键时，这里的结束不能让热键提前挂回。
                       setHotKeyRecording(recording)
                   },
                   conflict: { value in shortcutConflictMessage(value, excluding: row) },
                   conflictChanged: { shortcutRowErrors[row.rawValue] = $0 })
                    .id("\(shortcutResetGeneration)-\(shortcutRowGenerations[row.rawValue, default: 0])")
                    .accessibilityIdentifier("settings.shortcut.recorder." + row.rawValue)
                    .frame(width: 120, height: 24)
            }.frame(minHeight: 36)
            shortcutRowError(row)
        }
    }

    private func rowScreenshotValue(_ row: SettingsShortcutRow) -> BlinkClipCore.KeyboardShortcut? {
        guard row == .region || row == .fullScreen else { return nil }
        guard let value = row == .region ? screenshotRegionShortcut : screenshotFullScreenShortcut else { return nil }
        return .init(keyCode: value.keyCode, modifierRawValue: value.modifierRawValue)
    }

    @ViewBuilder private func shortcutRowError(_ row: SettingsShortcutRow) -> some View {
        if let message = shortcutRowErrors[row.rawValue] {
            Text(message).font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.shortcut.error." + row.rawValue)
        }
    }

    @ViewBuilder private func restoreShortcutButton(_ row: SettingsShortcutRow) -> some View {
        if row.isModified(state.store.preferences, screenshots: rowScreenshotValue) {
            Button(SettingsCopy.trilingual("恢复默认", "復原預設", "Restore Default")) { restoreShortcut(row) }
                .buttonStyle(.link).fixedSize()
                .accessibilityIdentifier("settings.shortcut.restore." + row.rawValue)
        }
    }

    private func restoreShortcut(_ row: SettingsShortcutRow) {
        do {
            try row.restore(store: state.store, screenshots: rowScreenshotValue,
                commitScreenshot: { target in
                    let slot: BlinkClipScreenshotHotKeySlot = target == .region ? .region : .fullScreen
                    applyScreenshotHotKey(BlinkClipScreenshotSettings.default(for: slot), for: slot, force: true)
                }, reload: { state.controller?.hotKeyConfigurationChanged?() })
            screenshotRegionShortcut = BlinkClipScreenshotSettings.effectiveShortcut(for: .region)
            screenshotFullScreenShortcut = BlinkClipScreenshotSettings.effectiveShortcut(for: .fullScreen)
            shortcutRowErrors[row.rawValue] = nil
        } catch {
            shortcutRowErrors[row.rawValue] = error.localizedDescription
        }
    }

    private func resetShortcuts() {
        let alert = SettingsShortcutReset.makeAlert()
        shortcutResetAlert = alert
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            SettingsShortcutReset.present(alert, on: window) { confirmed in
                if confirmed { applyDefaultShortcuts() }
                shortcutResetAlert = nil
            }
        } else {
            DispatchQueue.main.async { SettingsShortcutReset.configureSafeCancel(alert) }
            if alert.runModal() == .alertSecondButtonReturn { applyDefaultShortcuts() }
            shortcutResetAlert = nil
        }
    }

    /// 在全部热键让位期间恢复最终的六条默认组合；不拿即将被覆盖的旧值互相判冲突。
    private func applyDefaultShortcuts() {
        do {
            try SettingsShortcutReset.apply(confirmed: true, store: state.store,
                commitScreenshots: {
                    setHotKeyRecording(true)
                    defer { setHotKeyRecording(false) }
                    BlinkClipScreenshotSettings.restoreAllShortcutDefaults()
                },
                reload: { state.controller?.hotKeyConfigurationChanged?() })
            screenshotRegionShortcut = BlinkClipScreenshotSettings.effectiveShortcut(for: .region)
            screenshotFullScreenShortcut = BlinkClipScreenshotSettings.effectiveShortcut(for: .fullScreen)
            shortcutRowErrors = [:]
            shortcutResetGeneration += 1
            shortcutError = ""
        } catch {
            shortcutError = SettingsCopy.text("settings.shortcuts.reset-all.failed") + " " + error.localizedDescription
        }
    }

    private var mcpExecutable: URL {
        (Bundle.main.executableURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent())
            .appendingPathComponent("blinkclip-mcp")
    }

    private var mcpConfiguration: String {
        let object: [String: Any] = ["mcpServers": ["blinkclip": [
            "command": mcpExecutable.path, "args": ["--data-dir", state.store.directoryURL.path]
        ]]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    private var mcp: some View {
        let executable = FileManager.default.isExecutableFile(atPath: mcpExecutable.path)
        return SettingsPageScroll {
            VStack(alignment: .leading, spacing: 20) {
                settingsCard {
                    // 「正常/不正常」的图标语言与隐私页统一：同一个 7pt 状态圆点，
                    // 语义不同由文字区分（「本机服务可用」≠「已授权」）。
                    // `.center` 显式对齐：圆点中心 = 状态标题文字中心（≤0.5pt）。
                    HStack(alignment: .center, spacing: SettingsStatusDot.textSpacing) {
                        SettingsStatusDot(level: executable ? .normal : .problem)
                        Text(executable
                             ? SettingsCopy.trilingual("本机服务可用", "本機服務可用", "Local service available")
                             : SettingsCopy.trilingual("未找到本机服务", "找不到本機服務", "Local service not found"))
                            .font(.system(size: 13, weight: .semibold))
                            .accessibilityIdentifier("settings.mcp.status")
                    }
                    // 说明行与状态标题文字左对齐：让出「圆点 + 间距」的宽度，
                    // 不再像旧的 Label 那样比标题左出 19pt。
                    Text(SettingsCopy.trilingual("允许支持 MCP 的 AI 工具搜索、读取和整理历史记录。", "允許支援 MCP 的 AI 工具搜尋、讀取和整理歷史記錄。", "Let an MCP-compatible AI tool search, read, and organize your history."))
                        .font(.callout).settingsSecondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, SettingsStatusDot.side + SettingsStatusDot.textSpacing)
                        .padding(.top, 6)
                        .accessibilityIdentifier("settings.mcp.description")
                    // 与隐私页「刷新状态」同构：分隔线 + 右对齐按钮，放在卡片底部；
                    // 不再把按钮甩到卡外、在它下面留 440pt 空白。
                    Divider().padding(.vertical, 8)
                    HStack {
                        Spacer()
                        Button(SettingsCopy.text("settings.mcp.connect.action.connect-to")) {
                            showingMCPConfiguration = true
                        }
                        .disabled(!executable)
                        .accessibilityIdentifier("settings.mcp.connect")
                    }
                }
            }
        }
        .sheet(isPresented: $showingMCPConfiguration) {
            VStack(alignment: .leading, spacing: 16) {
                Text(SettingsCopy.trilingual("连接 AI 工具", "連線 AI 工具", "Connect an AI Tool")).font(.headline)
                Text(SettingsCopy.trilingual("复制下方 MCP 配置并添加到客户端。客户端会在本机启动闪贴服务。", "複製下方 MCP 設定並加入到用戶端。用戶端會在本機啟動閃貼服務。", "Copy the MCP configuration below and add it to your client. The client starts the BlinkClip service on this Mac."))
                    .font(.callout).foregroundStyle(.secondary)
                ScrollView {
                    Text(mcpConfiguration).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                .frame(height: 180)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button(SettingsCopy.text("settings.mcp.copy")) {
                        let pasteboard = state.controller?.pasteboard ?? .general
                        pasteboard.clearContents()
                        if !pasteboard.setString(mcpConfiguration, forType: .string) {
                            state.controller?.showError(message: SettingsCopy.trilingual("无法复制配置，请重试。", "無法複製設定，請重試。", "Could not copy the configuration. Try again."))
                        }
                    }
                    Spacer()
                    Button(SettingsCopy.text("settings.mcp.connection-sheet.done")) {
                        showingMCPConfiguration = false
                    }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(24).frame(width: 420)
        }
    }

    private func preference<Value>(_ keyPath: WritableKeyPath<AppPreferences, Value>) -> Binding<Value> {
        Binding(get: { state.store.preferences[keyPath: keyPath] }, set: { value in
            state.store.preferences[keyPath: keyPath] = value
            if (keyPath as AnyKeyPath) == (\AppPreferences.isMonitoringPaused as AnyKeyPath) {
                state.store.preferences.pauseUntil = nil
            }
            state.perform { try state.store.save() }
        })
    }

    private func chooseExcludedApp() {
        let panel = NSOpenPanel()
        panel.title = SettingsCopy.trilingual("选择不记录的应用", "選擇不記錄的應用程式", "Choose Apps to Exclude")
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            state.store.preferences.excludedBundleIDs = Array(Set(state.store.preferences.excludedBundleIDs + identifiers)).sorted()
            state.perform { try state.store.save() }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: complete) }
        else { complete(panel.runModal()) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            state.store.preferences.launchAtLogin = enabled
            try state.store.save()
        } catch { state.controller?.presentError(error) }
    }
}

private extension View {
    /// 只有需要被测试或无障碍工具精确定位的行才带标识符；其余行保持原样。
    @ViewBuilder func accessibilityIdentifierIfPresent(_ identifier: String?) -> some View {
        if let identifier { accessibilityIdentifier(identifier) } else { self }
    }
}

/// 设置内容区的内边距：六个分区共用一套节奏。
///
/// 内容**顶部对齐**：第一个内容块距内容区顶 16pt（`topInset`），底边留 20pt
/// 收尾，内容超出一屏时从顶部起滚动。上下不再取同一个值——那是「装得下就
/// 居中」规则留下的写法，页面级居中已撤销，余量不再需要平分。
enum SettingsPageMetrics {
    static let horizontalInset: CGFloat = 20
    /// 内容区顶到第一个内容块的固定距离（回归断言直接量这一值）。
    static let topInset: CGFloat = 16
    /// 内容区底到最后一个内容块的距离，滚到底时成立。
    static let bottomInset: CGFloat = 20
}

/// 设置内容区的滚动容器：所有分区一律从顶部 16pt 起排，超出一屏才滚动。
///
/// 这里只做「内边距 + ScrollView」，不套 `GeometryReader`、不做
/// `frame(minHeight:alignment: .center)`：上一轮把内容块放进最小高度等于
/// 可视高度的 frame 里求垂直居中，结果是短页整体浮在内容区中间，与「设置项
/// 在自己的行内居中」是两件事。页面从头对齐后，六页的顶部节奏只有一个值。
struct SettingsPageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, SettingsPageMetrics.horizontalInset)
                .padding(.top, SettingsPageMetrics.topInset)
                .padding(.bottom, SettingsPageMetrics.bottomInset)
        }
        .accessibilityIdentifier("settings.page-scroll")
    }
}
