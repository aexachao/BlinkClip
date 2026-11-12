import AppKit

public enum SearchFilterSymbols {
    private static func slot(_ value: String) -> UnsafePointer<String> {
        let pointer = UnsafeMutablePointer<String>.allocate(capacity: 1)
        pointer.initialize(to: value)
        return UnsafePointer(pointer)
    }

    private static let application = slot("app.dashed")
    private static let calendar = slot("calendar")
    private static let board = slot("circle.fill")
    private static let file = slot("doc")
    private static let unrecognizedType = slot("exclamationmark.triangle.fill")
    private static let link = slot("link")
    private static let devices = slot("macbook.and.iphone")
    private static let color = slot("paintpalette")
    private static let image = slot("photo")
    private static let unknown = slot("questionmark.app")
    private static let text = slot("text.alignleft")

    public static func currentApplication() -> UnsafePointer<String> { application }
    public static func currentCalendar() -> UnsafePointer<String> { calendar }
    public static func currentBoard() -> UnsafePointer<String> { board }
    public static func currentFile() -> UnsafePointer<String> { file }
    public static func currentUnrecognizedType() -> UnsafePointer<String> { unrecognizedType }
    public static func currentLink() -> UnsafePointer<String> { link }
    public static func currentDevices() -> UnsafePointer<String> { devices }
    public static func currentColor() -> UnsafePointer<String> { color }
    public static func currentImage() -> UnsafePointer<String> { image }
    public static func currentUnknown() -> UnsafePointer<String> { unknown }
    public static func currentText() -> UnsafePointer<String> { text }

    public static func symbolForFilterKind(kind: UInt8, value: String) -> String? {
        let symbol: UnsafePointer<String>
        switch kind {
        case 0: symbol = currentApplication()
        case 1:
            switch value.lowercased() {
            case "link": symbol = currentLink()
            case "image": symbol = currentImage()
            case "color": symbol = currentColor()
            case "text": symbol = currentText()
            case "file": symbol = currentFile()
            case "unknown": symbol = currentUnknown()
            default: symbol = currentUnrecognizedType()
            }
        case 2: return nil
        case 3: symbol = currentCalendar()
        case 4: symbol = currentDevices()
        default: symbol = currentBoard()
        }
        return symbol.pointee
    }
}

@MainActor
public enum SystemImageFunctions {
    public static func makeSystemImage(_ name: String, imageType: NSImage.Type = NSImage.self) -> NSImage? {
        imageType.init(systemSymbolName: name, accessibilityDescription: nil)
    }
}
