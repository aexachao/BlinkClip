public final class InitializedValue<Value> {
    private var value: Value?

    public init() { value = nil }

    public func requiredValue() -> Value {
        guard case let .some(value) = value else {
            preconditionFailure(String(describing: Value.self) + " must be defined")
        }
        return value
    }

    public func currentValue() -> Value? { value }

    public func setValueOnce(_ newValue: Value) {
        guard case .none = value else {
            preconditionFailure(String(describing: Value.self) + " has already been set")
        }
        value = .some(newValue)
    }

    public func memberAtKeyPath<Member>(_ keyPath: KeyPath<Value, Member>) -> Member {
        requiredValue()[keyPath: keyPath]
    }
}
