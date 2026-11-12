import AppKit
import QuartzCore

@MainActor
public enum ViewAnimation {
    public static func easeOutTimingFunction() -> CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeOut)
    }

    public static func easeInEaseOutTimingFunction() -> CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeInEaseOut)
    }

    public static func configureAnimationContext(_ context: NSAnimationContext, duration: TimeInterval?,
                                  timingFunction: CAMediaTimingFunction?, animations: () -> Void) {
        if let duration { context.duration = duration }
        context.timingFunction = timingFunction
        context.allowsImplicitAnimation = true
        animations()
    }

    public static func invokeCompletion(_ completion: (() -> Void)?) { completion?() }

    public static func runAnimation(duration: TimeInterval?, timingFunction: CAMediaTimingFunction?,
                                  animated: Bool, animations: () -> Void,
                                  completion: (() -> Void)? = nil) {
        if !animated {
            animations()
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            configureAnimationContext(context, duration: duration, timingFunction: timingFunction, animations: animations)
        } completionHandler: {
            invokeCompletion(completion)
        }
    }
}
