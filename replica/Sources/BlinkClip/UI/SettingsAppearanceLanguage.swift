import BlinkClipCore
import Foundation

/// 「通用 → 外观与语言」的两条偏好：主题（`preferences.appearance`）与界面语言
/// （`appLanguage` 键）。
///
/// 这里只做三件事，不新造存储：把存量字符串映射成可选项、把选项写回原来的键、
/// 把「界面语言变了」这件事发出去。主题的落点就是既有
/// `WindowAppearancePreferenceObservation` 盯着的 `preferences.appearance`
/// （`system` / `light` / `dark`），所以写进 store 后既有的 `applyAppearance()`
/// 立刻生效；语言沿用 vendored 捕获模块 `Defaults.language` 的存储规则
/// （键 `appLanguage`、值取 `AppLanguage.rawValue`、缺键 = 跟随系统）。
enum SettingsAppearanceChoice: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// `preferences.appearance` 的存量取值，与 `ReplicaUIController.applyAppearance()` 同一套字符串。
    var storedValue: String { rawValue }

    /// 读到不认识的值（例如未来新增的选项）时按「跟随系统」显示，不回写存储。
    init(stored: String) {
        self = SettingsAppearanceChoice(rawValue: stored) ?? .system
    }

    /// 选项名是行为描述，跟着界面语言走三语表；`light` / `dark` 不是语言自称。
    var title: String {
        switch self {
        case .system: return SettingsCopy.text("settings.appearance.follow-system")
        case .light: return SettingsCopy.text("settings.appearance.theme.light")
        case .dark: return SettingsCopy.text("settings.appearance.theme.dark")
        }
    }
}

/// 设置页能渲染的界面语言，加上「跟随系统」。
///
/// 选项名按语言**自称**显示（简体中文 / 繁體中文 / English），不随界面语言翻译，
/// 与 `AppLanguage.displayName` 同一套写法；只有「跟随系统」跟着界面语言走。
enum SettingsAppLanguageChoice: String, CaseIterable, Sendable {
    case system
    case zhHans
    case zhHant
    case en

    /// 写进 `appLanguage` 的值；`nil` 表示跟随系统（等于删掉这个键）。
    ///
    /// 取值必须是 `AppLanguage` 的 rawValue：简中是 `zh`（不是 `zh-Hans`），
    /// 繁中是 `zh-Hant`。捕获模块的 `Defaults.language` 按 `AppLanguage(rawValue:)`
    /// 读同一份存储，写 `zh-Hans` 会被判成「不支持」而回落。
    var storedValue: String? {
        switch self {
        case .system: return nil
        case .zhHans: return "zh"
        case .zhHant: return "zh-Hant"
        case .en: return "en"
        }
    }

    /// 语言名按自称显示；「跟随系统」是行为描述，走三语表。
    var title: String {
        switch self {
        case .system: return SettingsCopy.text("settings.appearance.follow-system")
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        }
    }

    /// 回显用：读存储里那份 `appLanguage`，缺键或不认识的值都显示「跟随系统」。
    ///
    /// 不认识的值（`ja` 这类设置页没有表、但有存储的语言）不回写：用户不动这一行
    /// 时存储保持原样，用户选「跟随系统」才把键删掉。
    static func current(defaults: UserDefaults = .standard) -> SettingsAppLanguageChoice {
        switch defaults.string(forKey: SettingsLanguage.preferenceKey) {
        case "zh", "zh-Hans": return .zhHans
        case "zh-Hant": return .zhHant
        case "en": return .en
        default: return .system
        }
    }

    /// 写回 `appLanguage`：选一门语言写它的 rawValue，选「跟随系统」删除该键；
    /// 然后发 `.appLanguageDidChange`，让已经打开的设置页按新语言重算文案。
    func apply(defaults: UserDefaults = .standard,
               notificationCenter: NotificationCenter = .default) {
        switch storedValue {
        case .some(let value): defaults.set(value, forKey: SettingsLanguage.preferenceKey)
        case .none: defaults.removeObject(forKey: SettingsLanguage.preferenceKey)
        }
        notificationCenter.post(name: .appLanguageDidChange, object: nil)
    }
}

extension Notification.Name {
    /// 与 vendored `BlinkClipCapture` 的 `Notification.Name.languageDidChange`
    /// （`blinkclip.languageDidChange`，由 `Defaults.language` 的 setter 发出）同名同值。
    ///
    /// 那一份是模块内可见，设置页发不到；`NotificationCenter` 按名字字符串匹配，
    /// 所以这里带一份同值名字，两边得到的是同一个通知。
    static let appLanguageDidChange = Notification.Name("blinkclip.languageDidChange")
}
