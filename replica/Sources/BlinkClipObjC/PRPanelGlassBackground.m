#import "PRPanelGlassBackground.h"
#import <QuartzCore/QuartzCore.h>

@protocol PRPanelGlassConfiguration
@property(nonatomic) CGFloat cornerRadius;
@end

@implementation PRPanelGlassBackground {
    NSView *_effect;
    CAShapeLayer *_topCornerMask;
    NSRect _maskedBounds;
    CGFloat _maskedRadius;
    BOOL _maskedFlipped;
    BOOL _hasMaskGeometry;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        if (@available(macOS 26.0, *)) {
            Class glassClass = NSClassFromString(@"NSGlassEffectView");
            if ([glassClass isSubclassOfClass:NSView.class]) {
                _effect = [[glassClass alloc] initWithFrame:self.bounds];
            }
        }
        if (!_effect) {
            NSVisualEffectView *visualEffect = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
            // passes material 5 on older systems.
            visualEffect.material = NSVisualEffectMaterialMenu;
            visualEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
            visualEffect.state = NSVisualEffectStateActive;
            _effect = visualEffect;
        }
        _effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        // Glass supplies its own four-corner rounding. Keep it rectangular and
        // let this stable outer layer clip only the two top corners.
        if ([_effect respondsToSelector:@selector(setCornerRadius:)]) {
            ((id<PRPanelGlassConfiguration>)_effect).cornerRadius = 0;
        }
        self.wantsLayer = YES;
        self.layer.masksToBounds = YES;
        _topCornerMask = [CAShapeLayer layer];
        _topCornerMask.fillColor = NSColor.blackColor.CGColor;
        self.layer.mask = _topCornerMask;
        [self addSubview:_effect];
        [self updateTopCornerMask];
    }
    return self;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    CGFloat radius = MAX(0, cornerRadius);
    if (_cornerRadius == radius) { return; }
    _cornerRadius = radius;
    [self updateTopCornerMask];
}

- (void)layout {
    [super layout];
    [self updateTopCornerMask];
}

- (void)updateTopCornerMask {
    NSRect bounds = self.bounds;
    CGFloat radius = MIN(_cornerRadius, MIN(NSWidth(bounds) / 2, NSHeight(bounds)));
    BOOL flipped = self.isFlipped;
    if (_hasMaskGeometry && NSEqualRects(_maskedBounds, bounds)
        && _maskedRadius == radius && _maskedFlipped == flipped) { return; }
    _maskedBounds = bounds;
    _maskedRadius = radius;
    _maskedFlipped = flipped;
    _hasMaskGeometry = YES;

    CGFloat left = NSMinX(bounds), right = NSMaxX(bounds);
    CGFloat top = flipped ? NSMinY(bounds) : NSMaxY(bounds);
    CGFloat bottom = flipped ? NSMaxY(bounds) : NSMinY(bounds);
    CGFloat innerTop = top + (flipped ? radius : -radius);
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, left, bottom);
    CGPathAddLineToPoint(path, NULL, right, bottom);
    CGPathAddLineToPoint(path, NULL, right, innerTop);
    CGPathAddArcToPoint(path, NULL, right, top, right - radius, top, radius);
    CGPathAddLineToPoint(path, NULL, left + radius, top);
    CGPathAddArcToPoint(path, NULL, left, top, left, innerTop, radius);
    CGPathCloseSubpath(path);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _topCornerMask.frame = bounds;
    _topCornerMask.path = path;
    [CATransaction commit];
    CGPathRelease(path);
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

@end
