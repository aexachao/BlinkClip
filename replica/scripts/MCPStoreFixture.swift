// Test-only adapter: operate exclusively on the caller's isolated MCP fixture directory.
import Foundation
import BlinkClipCore

@main
struct MCPStoreFixture {
    @MainActor
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 3 else { throw NSError(domain: "MCPStoreFixture", code: 64) }
        let store = try ClipboardStore(directoryURL: URL(fileURLWithPath: args[1]))
        switch args[0] {
        case "export": try store.exportArchive(to: URL(fileURLWithPath: args[2]))
        case "import": try store.importArchive(from: URL(fileURLWithPath: args[2]))
        case "soft-delete":
            guard let id = UUID(uuidString: args[2]) else { throw NSError(domain: "MCPStoreFixture", code: 65) }
            try store.delete(ids: [id])
        default: throw NSError(domain: "MCPStoreFixture", code: 64)
        }
    }
}
