#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RavenTab) {
    RavenTabAim = 0,
    RavenTabESP,
    RavenTabVisuals,
    RavenTabModels,
    RavenTabSettings,
    RavenTabInfo
};

@interface RavenMenu : UIView

+ (instancetype)shared;
- (void)attachToWindow:(UIWindow *)window;
- (void)toggleMenu;
- (void)showMenu;
- (void)hideMenu;

@property(nonatomic, copy, nullable) void (^toggleChanged)(
    NSString *feature,
    BOOL enabled
);

@property(nonatomic, copy, nullable) void (^sliderChanged)(
    NSString *feature,
    CGFloat value
);

@property(nonatomic, copy, nullable) void (^optionChanged)(
    NSString *feature,
    NSInteger index
);

@end

NS_ASSUME_NONNULL_END
