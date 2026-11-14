import AppKit
import Combine
import CryptoKit
import BlinkClipCore
import SwiftUI

@MainActor
final class CloudKitSyncController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isBusy = false
    @Published private(set) var statusText: String
    @Published private(set) var lastSyncDate: Date?
    let canSync: Bool
    let containerIdentifier: String?
    private let configuration: BlinkClipCloudKitConfiguration?
    private let store: ClipboardStore
    private let drive: ICloudDriveSyncController
    private let defaults: UserDefaults
    private let key: String
    private var engine: CloudKitSyncEngine?
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var generation = UUID()

    init(store: ClipboardStore, drive: ICloudDriveSyncController, defaults: UserDefaults = .standard) {
        self.store = store; self.drive = drive; self.defaults = defaults
        configuration = try? BlinkClipCloudKitConfiguration.current()
        containerIdentifier = configuration?.containerIdentifier
        canSync = configuration != nil && store.directoryURL.standardizedFileURL.resolvingSymlinksInPath()
            == ClipboardStore.defaultDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let digest = SHA256.hash(data: Data(store.directoryURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        key = "blinkclip.cloudkit.\(digest).enabled"
        // This row lives on the settings page, so its status copy is trilingual
        // like the rest of the pane; it used to be Simplified for every language.
        statusText = configuration == nil
            ? SettingsCopy.trilingual(
                "此构建未配置 \(ReplicaBrand.name) 自有 CloudKit 容器和开发者签名，暂不能连接 iCloud。",
                "此版本未設定 \(ReplicaBrand.name) 專屬 CloudKit 容器與開發者簽章，暫時無法連線 iCloud。",
                "This build has no \(ReplicaBrand.name) CloudKit container or Developer ID signing yet, so iCloud cannot connect.")
            : SettingsCopy.trilingual("尚未开启 CloudKit 同步。", "尚未開啟 CloudKit 同步。", "CloudKit sync is not on yet.")
    }

    deinit { timer?.invalidate(); task?.cancel() }

    func start() {
        guard canSync, defaults.bool(forKey: key), !drive.isEnabled else { return }
        enable()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled else { disable(); return }
        guard canSync else { return }
        let alert = NSAlert()
        alert.messageText = SettingsCopy.trilingual("开启 iCloud 同步？", "開啟 iCloud 同步？", "Turn on iCloud Sync?")
        alert.informativeText = SettingsCopy.trilingual(
            "将本机历史和收藏分组同步到 \(ReplicaBrand.name) 自有的 iCloud 容器，并合并其他 Mac 的内容与删除。不会访问原版 Paste 的云数据。开启后将关闭独立的 iCloud Drive 文件同步。",
            "將本機歷史與收藏分組同步到 \(ReplicaBrand.name) 專屬的 iCloud 容器，並合併其他 Mac 的內容與刪除。不會存取原版 Paste 的雲端資料。開啟後將關閉獨立的 iCloud Drive 檔案同步。",
            "Sync this Mac's history and saved groups to \(ReplicaBrand.name)'s own iCloud container, and merge other Macs' items and deletions. The original Paste's cloud data is never accessed. Turning this on disables the separate iCloud Drive file sync.")
        alert.addButton(withTitle: SettingsCopy.trilingual("开启并同步", "開啟並同步", "Turn On and Sync"))
        alert.addButton(withTitle: SettingsCopy.trilingual("取消", "取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        drive.setEnabled(false)
        enable()
    }

    private func enable() {
        guard canSync, let configuration, !isEnabled else { return }
        generation = UUID(); let token = generation
        let engine = CloudKitSyncEngine(store: store, configuration: configuration)
        self.engine = engine
        engine.statusChanged = { [weak self, weak engine] message in
            guard let self, generation == token else { return }
            statusText = message
            if engine?.isRunning == false {
                isEnabled = false; defaults.set(false, forKey: key); timer?.invalidate(); timer = nil
            }
        }
        isEnabled = true; isBusy = true
        defaults.set(true, forKey: key)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncNow() }
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.start()
                NSApplication.shared.registerForRemoteNotifications()
                guard generation == token, !Task.isCancelled else { await engine.stop(); return }
                try await engine.synchronize()
                if generation == token { lastSyncDate = Date() }
            } catch {
                if generation == token {
                    statusText = error.localizedDescription
                    if !engine.isRunning { isEnabled = false; defaults.set(false, forKey: key); timer?.invalidate(); timer = nil }
                }
            }
            if generation == token { isBusy = false; task = nil }
        }
    }

    private func disable() {
        generation = UUID(); timer?.invalidate(); timer = nil; task?.cancel(); task = nil
        isEnabled = false; isBusy = false; defaults.set(false, forKey: key)
        if let engine { Task { await engine.stop() } }
        engine = nil
        statusText = SettingsCopy.trilingual("同步已关闭，本地内容与 iCloud 数据均保留。",
                                             "同步已關閉，本機內容與 iCloud 資料均保留。",
                                             "Sync is off. Local items and iCloud data are both kept.")
    }

    func syncNow() {
        guard isEnabled, !isBusy, let engine else { return }
        if drive.isEnabled {
            disable()
            statusText = SettingsCopy.trilingual("已开启独立 iCloud Drive 同步，CloudKit 同步已暂停。",
                                                 "已開啟獨立 iCloud Drive 同步，CloudKit 同步已暫停。",
                                                 "Separate iCloud Drive sync is on, so CloudKit sync is paused.")
            return
        }
        let token = generation; isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            do { try await engine.synchronize(); if token == generation { lastSyncDate = Date() } }
            catch { if token == generation { statusText = error.localizedDescription } }
            if token == generation { isBusy = false; task = nil }
        }
    }
}

@MainActor
struct ICloudSyncGeneralRow: View {
    @ObservedObject var sync: CloudKitSyncController
    @ObservedObject var drive: ICloudDriveSyncController

    private var enabled: Bool { drive.isEnabled || sync.isEnabled }
    private var summary: String {
        if drive.isBusy || sync.isBusy { return SettingsCopy.trilingual("正在同步…", "正在同步…", "Syncing…") }
        guard enabled else { return drive.statusText.hasPrefix("无法开启") ? SettingsCopy.trilingual("无法开启", "無法開啟", "Could Not Enable") : SettingsCopy.trilingual("未开启", "未開啟", "Off") }
        if let date = drive.isEnabled ? drive.lastSyncDate : sync.lastSyncDate {
            return (drive.isEnabled ? SettingsCopy.trilingual("本地合并 ", "本地合併 ", "Merged Locally ") : SettingsCopy.trilingual("最近更新 ", "最近更新 ", "Last Updated ")) + date.formatted(date: .omitted, time: .shortened)
        }
        return SettingsCopy.trilingual("等待同步", "等待同步", "Waiting to Sync")
    }

    var body: some View {
        HStack {
            Text(SettingsCopy.trilingual("iCloud 同步", "iCloud 同步", "iCloud Sync"))
            Spacer()
            Text(summary).font(.caption).foregroundStyle(.secondary)
            Toggle(SettingsCopy.trilingual("iCloud 同步", "iCloud 同步", "iCloud Sync"), isOn: Binding(get: { enabled }, set: { value in
                if value { drive.setEnabled(true) }
                else {
                    if drive.isEnabled { drive.setEnabled(false) }
                    if sync.isEnabled { sync.setEnabled(false) }
                }
            })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                .disabled(!drive.canSync && !sync.canSync)
        }
        .help(drive.isEnabled || !sync.isEnabled ? drive.statusText : sync.statusText)
    }
}
