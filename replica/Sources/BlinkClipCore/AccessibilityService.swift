import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Permission observation is separate from the original explicit modal request actions.
public final class AccessibilityService {
    public init() {}

    public func AXIsProcessTrusted() -> Bool {
        ApplicationServices.AXIsProcessTrusted()
    }

    /// Direct paste posts CGEvents; check that capability rather than inferring it
    /// from AX trust. Both checks are read-only and never request permission.
    public func canPostEvents() -> Bool {
        CGPreflightPostEventAccess()
    }

    public func postEventAccessChanges() -> AnyPublisher<Bool, Never> {
        Just(canPostEvents()).merge(with:
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                .map { [weak self] _ in self?.canPostEvents() ?? false })
            .removeDuplicates().eraseToAnyPublisher()
    }

    public func trustedStatusPublisher() -> AnyPublisher<Bool, Never> {
        let initial = Just(self.AXIsProcessTrusted())
        let changes = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .map { [weak self] _ in
                guard self != nil else { return false }
                return ApplicationServices.AXIsProcessTrusted()
            }
        return initial.merge(with: changes)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
