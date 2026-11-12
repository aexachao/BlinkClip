#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Uses the public runtime class so the app can also build with pre-Tahoe SDKs.
@interface PRPanelGlassBackground : NSView
/// Rounds only the physical top corners; the bottom corners remain square.
@property(nonatomic) CGFloat cornerRadius;
@end

NS_ASSUME_NONNULL_END
