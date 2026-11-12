import Foundation
import BlinkClipObjC

public struct ObjCExceptionError: Error {
    public let name: String
    public let reason: String?
}

/// Swift Result transport around the original synchronous Objective-C exception boundary.
public enum ObjCExceptionBridge {
    public static func withResult<T>(_ operation: () throws -> T) throws -> T {
        var result: Result<T, Error>?
        let exception = PRObjCExceptionCatcher.catchException(in: {
            do { result = .success(try operation()) }
            catch { result = .failure(error) }
        })
        if let exception {
            throw ObjCExceptionError(name: exception.name.rawValue, reason: exception.reason)
        }
        guard let result else {
            preconditionFailure("Objective-C exception boundary returned without a result")
        }
        return try result.get()
    }
}
