#import "RavenMenu.h"
#import <QuartzCore/QuartzCore.h>

static UIColor *RVBackground(void) {
    return [UIColor colorWithRed:0.035 green:0.037 blue:0.045 alpha:0.97];
}

static UIColor *RVPanel(void) {
    return [UIColor colorWithRed:0.065 green:0.068 blue:0.082 alpha:1.0];
}

static UIColor *RVPanel2(void) {
    return [UIColor colorWithRed:0.085 green:0.09 blue:0.105 alpha:1.0];
}

static UIColor *RVAccent(void) {
    return [UIColor colorWithRed:0.92 green:0.08 blue:0.13 alpha:1.0];
}

static UIColor *RVText(void) {
    return [UIColor colorWithWhite:0.96 alpha:1];
}

static UIColor *RVSubText(void) {
    return [UIColor colorWithWhite:0.62 alpha:1];
}

@interface RavenToggle : UIControl

@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *subtitleLabel;
@property(nonatomic, strong) UIView *track;
@property(nonatomic, strong) UIView *knob;
@property(nonatomic, assign) BOOL enabledValue;

@end

@implementation RavenToggle

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        self.backgroundColor = RVPanel2();
        self.layer.cornerRadius = 12;

        _titleLabel = [UILabel new];
        _titleLabel.text = title;
        _titleLabel.textColor = RVText();
        _titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];

        _subtitleLabel = [UILabel new];
        _subtitleLabel.text = subtitle;
        _subtitleLabel.textColor = RVSubText();
        _subtitleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];

        _track = [UIView new];
        _track.layer.cornerRadius = 10;
        _track.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1];

        _knob = [UIView new];
        _knob.layer.cornerRadius = 8;
        _knob.backgroundColor = UIColor.whiteColor;

        [self addSubview:_titleLabel];
        [self addSubview:_subtitleLabel];
        [self addSubview:_track];
        [_track addSubview:_knob];

        [self addTarget:self
                 action:@selector(togglePressed)
       forControlEvents:UIControlEventTouchUpInside];
    }

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    self.titleLabel.frame =
        CGRectMake(14, 9, self.bounds.size.width - 85, 18);

    self.subtitleLabel.frame =
        CGRectMake(14, 28, self.bounds.size.width - 85, 15);

    self.track.frame =
        CGRectMake(self.bounds.size.width - 56, 16, 42, 20);

    CGFloat x = self.enabledValue ? 23 : 3;

    self.knob.frame = CGRectMake(x, 2, 16, 16);
}

- (void)togglePressed {
    self.enabledValue = !self.enabledValue;

    [UIView animateWithDuration:0.18
                     animations:^{
        self.track.backgroundColor =
            self.enabledValue
            ? RVAccent()
            : [UIColor colorWithWhite:0.18 alpha:1];

        [self setNeedsLayout];
        [self layoutIfNeeded];
    }];

    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

@end

@interface RavenMenu ()

@property(nonatomic, strong) UIView *menu;
@property(nonatomic, strong) UIView *header;
@property(nonatomic, strong) UIView *sidebar;
@property(nonatomic, strong) UIScrollView *content;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *statusLabel;

@property(nonatomic, strong) UIButton *orbButton;

@property(nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property(nonatomic, assign) RavenTab currentTab;

@property(nonatomic, assign) CGPoint dragOffset;

@end

@implementation RavenMenu

+ (instancetype)shared {
    static RavenMenu *shared = nil;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        shared = [[RavenMenu alloc] initWithFrame:CGRectZero];
    });

    return shared;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        self.backgroundColor = UIColor.clearColor;

        _tabButtons = [NSMutableArray array];
        _currentTab = RavenTabAim;

        [self buildUI];
    }

    return self;
}

#pragma mark - Setup

- (void)buildUI {
    self.menu = [UIView new];
    self.menu.backgroundColor = RVBackground();
    self.menu.layer.cornerRadius = 18;
    self.menu.layer.borderWidth = 1;
    self.menu.layer.borderColor =
        [UIColor colorWithWhite:1 alpha:0.06].CGColor;

    self.menu.layer.shadowColor = UIColor.blackColor.CGColor;
    self.menu.layer.shadowOpacity = 0.45;
    self.menu.layer.shadowRadius = 30;
    self.menu.layer.shadowOffset = CGSizeMake(0, 14);

    [self addSubview:self.menu];

    self.header = [UIView new];
    self.header.backgroundColor =
        [UIColor colorWithRed:0.055 green:0.057 blue:0.07 alpha:1];

    [self.menu addSubview:self.header];

    UIView *accent = [UIView new];
    accent.backgroundColor = RVAccent();
    accent.layer.cornerRadius = 2;

    [self.header addSubview:accent];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = @"RAVEN";
    self.titleLabel.textColor = RVText();
    self.titleLabel.font =
        [UIFont systemFontOfSize:20 weight:UIFontWeightBlack];

    [self.header addSubview:self.titleLabel];

    UILabel *build = [UILabel new];
    build.text = @"ENGINE AI";
    build.textColor = RVAccent();
    build.font =
        [UIFont systemFontOfSize:9 weight:UIFontWeightBold];

    [self.header addSubview:build];

    self.statusLabel = [UILabel new];
    self.statusLabel.text = @"● ACTIVE";
    self.statusLabel.textAlignment = NSTextAlignmentRight;
    self.statusLabel.textColor =
        [UIColor colorWithRed:0.3 green:1 blue:0.45 alpha:1];
    self.statusLabel.font =
        [UIFont monospacedSystemFontOfSize:9
                                   weight:UIFontWeightBold];

    [self.header addSubview:self.statusLabel];

    self.sidebar = [UIView new];
    self.sidebar.backgroundColor =
        [UIColor colorWithWhite:0.045 alpha:1];

    [self.menu addSubview:self.sidebar];

    self.content = [UIScrollView new];
    self.content.showsVerticalScrollIndicator = NO;

    [self.menu addSubview:self.content];

    NSArray *tabs = @[
        @"AIM",
        @"ESP",
        @"VISUALS",
        @"MODELS",
        @"SETTINGS",
        @"INFO"
    ];

    NSArray *icons = @[
        @"scope",
        @"viewfinder",
        @"sparkles",
        @"cpu",
        @"slider.horizontal.3",
        @"info.circle"
    ];

    for (NSInteger i = 0; i < tabs.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];

        button.tag = i;
        button.tintColor = RVSubText();
        button.contentHorizontalAlignment =
            UIControlContentHorizontalAlignmentLeft;

        UIImage *icon =
            [UIImage systemImageNamed:icons[i]];

        [button setImage:icon
                forState:UIControlStateNormal];

        [button setTitle:
            [NSString stringWithFormat:@"  %@", tabs[i]]
              forState:UIControlStateNormal];

        [button setTitleColor:RVSubText()
                     forState:UIControlStateNormal];

        button.titleLabel.font =
            [UIFont systemFontOfSize:11
                              weight:UIFontWeightBold];

        button.layer.cornerRadius = 10;

        [button addTarget:self
                   action:@selector(tabPressed:)
         forControlEvents:UIControlEventTouchUpInside];

        [self.sidebar addSubview:button];
        [self.tabButtons addObject:button];
    }

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(handlePan:)];

    [self.header addGestureRecognizer:pan];
    self.header.userInteractionEnabled = YES;

    self.orbButton =
        [UIButton buttonWithType:UIButtonTypeCustom];

    self.orbButton.backgroundColor = RVAccent();
    self.orbButton.layer.cornerRadius = 24;

    UIImage *orbIcon =
        [UIImage systemImageNamed:@"bird.fill"];

    [self.orbButton setImage:orbIcon
                    forState:UIControlStateNormal];

    self.orbButton.tintColor = UIColor.whiteColor;

    self.orbButton.layer.shadowColor =
        RVAccent().CGColor;

    self.orbButton.layer.shadowOpacity = 0.65;
    self.orbButton.layer.shadowRadius = 16;

    [self.orbButton addTarget:self
                       action:@selector(toggleMenu)
             forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:self.orbButton];

    [self selectTab:RavenTabAim];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width =
        MIN(self.bounds.size.width * 0.88, 720);

    CGFloat height =
        MIN(self.bounds.size.height * 0.72, 470);

    if (self.menu.frame.size.width == 0) {
        self.menu.frame =
            CGRectMake(
                (self.bounds.size.width - width) / 2,
                (self.bounds.size.height - height) / 2,
                width,
                height
            );
    }

    self.header.frame =
        CGRectMake(0, 0, width, 58);

    CGFloat sidebarWidth = 132;

    self.sidebar.frame =
        CGRectMake(
            0,
            58,
            sidebarWidth,
            height - 58
        );

    self.content.frame =
        CGRectMake(
            sidebarWidth,
            58,
            width - sidebarWidth,
            height - 58
        );

    NSArray<UIView *> *headerViews =
        self.header.subviews;

    if (headerViews.count >= 4) {
        ((UIView *)headerViews[0]).frame =
            CGRectMake(16, 17, 4, 24);

        self.titleLabel.frame =
            CGRectMake(30, 11, 100, 24);

        ((UIView *)headerViews[2]).frame =
            CGRectMake(31, 34, 100, 12);

        self.statusLabel.frame =
            CGRectMake(width - 100, 18, 80, 20);
    }

    CGFloat y = 18;

    for (UIButton *button in self.tabButtons) {
        button.frame =
            CGRectMake(10, y, sidebarWidth - 20, 42);

        y += 48;
    }

    self.orbButton.frame =
        CGRectMake(
            self.bounds.size.width - 66,
            self.bounds.size.height - 70,
            48,
            48
        );
}

#pragma mark - Tabs

- (void)tabPressed:(UIButton *)button {
    [self selectTab:(RavenTab)button.tag];
}

- (void)selectTab:(RavenTab)tab {
    self.currentTab = tab;

    for (UIButton *button in self.tabButtons) {
        BOOL selected =
            button.tag == tab;

        button.backgroundColor =
            selected
            ? [RVAccent() colorWithAlphaComponent:0.14]
            : UIColor.clearColor;

        [button setTitleColor:
            selected ? UIColor.whiteColor : RVSubText()
                   forState:UIControlStateNormal];

        button.tintColor =
            selected ? RVAccent() : RVSubText();
    }

    [self rebuildTab];
}

#pragma mark - Tab Content

- (void)clearContent {
    for (UIView *view in self.content.subviews) {
        [view removeFromSuperview];
    }
}

- (void)rebuildTab {
    [self clearContent];

    switch (self.currentTab) {
        case RavenTabAim:
            [self buildAimTab];
            break;

        case RavenTabESP:
            [self buildESPTab];
            break;

        case RavenTabVisuals:
            [self buildVisualsTab];
            break;

        case RavenTabModels:
            [self buildModelsTab];
            break;

        case RavenTabSettings:
            [self buildSettingsTab];
            break;

        case RavenTabInfo:
            [self buildInfoTab];
            break;
    }
}

#pragma mark - Components

- (UILabel *)section:(NSString *)title y:(CGFloat)y {
    UILabel *label = [UILabel new];

    label.text =
        [title uppercaseString];

    label.textColor = RVAccent();

    label.font =
        [UIFont systemFontOfSize:10
                          weight:UIFontWeightBlack];

    label.frame =
        CGRectMake(18, y, self.content.bounds.size.width - 36, 20);

    [self.content addSubview:label];

    return label;
}

- (RavenToggle *)toggle:(NSString *)title
               subtitle:(NSString *)subtitle
                      y:(CGFloat)y {

    RavenToggle *toggle =
        [[RavenToggle alloc]
            initWithTitle:title
                 subtitle:subtitle];

    toggle.frame =
        CGRectMake(
            18,
            y,
            self.content.bounds.size.width - 36,
            52
        );

    toggle.accessibilityIdentifier = title;

    [toggle addTarget:self
               action:@selector(toggleValueChanged:)
     forControlEvents:UIControlEventValueChanged];

    [self.content addSubview:toggle];

    return toggle;
}

- (UISlider *)slider:(NSString *)title
                 min:(CGFloat)min
                 max:(CGFloat)max
               value:(CGFloat)value
                   y:(CGFloat)y {

    UILabel *label = [UILabel new];

    label.text =
        [NSString stringWithFormat:
            @"%@   %.1f",
            title,
            value];

    label.textColor = RVText();
    label.font =
        [UIFont systemFontOfSize:12
                          weight:UIFontWeightSemibold];

    label.frame =
        CGRectMake(
            18,
            y,
            self.content.bounds.size.width - 36,
            20
        );

    UISlider *slider = [UISlider new];

    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.value = value;

    slider.minimumTrackTintColor = RVAccent();
    slider.maximumTrackTintColor =
        [UIColor colorWithWhite:0.18 alpha:1];

    slider.accessibilityIdentifier = title;

    slider.frame =
        CGRectMake(
            18,
            y + 22,
            self.content.bounds.size.width - 36,
            28
        );

    [slider addTarget:self
               action:@selector(sliderChangedInternal:)
     forControlEvents:UIControlEventValueChanged];

    [self.content addSubview:label];
    [self.content addSubview:slider];

    return slider;
}

#pragma mark - Aim Tab

- (void)buildAimTab {
    CGFloat y = 18;

    [self section:@"Targeting" y:y];
    y += 28;

    [self toggle:@"AI Aim"
        subtitle:@"CoreML assisted target selection"
               y:y];

    y += 60;

    [self toggle:@"Target Lock"
        subtitle:@"Keep current target while valid"
               y:y];

    y += 68;

    [self section:@"Tuning" y:y];
    y += 28;

    [self slider:@"FOV"
             min:10
             max:400
           value:150
               y:y];

    y += 62;

    [self slider:@"Smoothing"
             min:0
             max:100
           value:24
               y:y];

    y += 62;

    [self slider:@"Confidence"
             min:0
             max:1
           value:0.70
               y:y];

    y += 62;

    [self slider:@"Aim Speed"
             min:1
             max:100
           value:65
               y:y];

    y += 68;

    [self section:@"Selection" y:y];
    y += 28;

    [self toggle:@"Closest Target"
        subtitle:@"Prioritize nearest valid detection"
               y:y];

    y += 60;

    [self toggle:@"Visible Only"
        subtitle:@"Ignore invalid or occluded detections"
               y:y];

    self.content.contentSize =
        CGSizeMake(0, y + 85);
}

#pragma mark - ESP Tab

- (void)buildESPTab {
    CGFloat y = 18;

    [self section:@"Players" y:y];
    y += 28;

    [self toggle:@"ESP Master"
        subtitle:@"Enable Raven visual overlay"
               y:y];

    y += 60;

    [self toggle:@"Box ESP"
        subtitle:@"High quality Raven corner boxes"
               y:y];

    y += 60;

    [self toggle:@"Skeleton"
        subtitle:@"Pose / bone visualization"
               y:y];

    y += 60;

    [self toggle:@"Snaplines"
        subtitle:@"Draw target connection lines"
               y:y];

    y += 60;

    [self toggle:@"Name"
        subtitle:@"Detection label"
               y:y];

    y += 60;

    [self toggle:@"Confidence"
        subtitle:@"Show model confidence"
               y:y];

    y += 68;

    [self section:@"Appearance" y:y];
    y += 28;

    [self slider:@"ESP Thickness"
             min:0.5
             max:6
           value:2
               y:y];

    y += 62;

    [self slider:@"ESP Opacity"
             min:0.1
             max:1
           value:0.95
               y:y];

    self.content.contentSize =
        CGSizeMake(0, y + 90);
}

#pragma mark - Visuals

- (void)buildVisualsTab {
    CGFloat y = 18;

    [self section:@"Overlay" y:y];
    y += 28;

    [self toggle:@"RGB ESP"
        subtitle:@"Animated Raven spectrum"
               y:y];

    y += 60;

    [self toggle:@"FOV Circle"
        subtitle:@"Show targeting radius"
               y:y];

    y += 60;

    [self toggle:@"Crosshair"
        subtitle:@"Centered Raven reticle"
               y:y];

    y += 60;

    [self toggle:@"FPS HUD"
        subtitle:@"Device and inference metrics"
               y:y];

    y += 68;

    [self section:@"Style" y:y];
    y += 28;

    [self slider:@"UI Scale"
             min:0.75
             max:1.35
           value:1
               y:y];

    y += 62;

    [self slider:@"Menu Opacity"
             min:0.35
             max:1
           value:0.96
               y:y];

    y += 62;

    [self slider:@"RGB Speed"
             min:0
             max:10
           value:4
               y:y];

    self.content.contentSize =
        CGSizeMake(0, y + 90);
}

#pragma mark - Models

- (void)buildModelsTab {
    CGFloat y = 18;

    [self section:@"Inference" y:y];
    y += 28;

    [self toggle:@"CoreML"
        subtitle:@"Hardware accelerated inference"
               y:y];

    y += 60;

    [self toggle:@"Vision Pipeline"
        subtitle:@"VNCoreML request processing"
               y:y];

    y += 60;

    [self toggle:@"Adaptive FPS"
        subtitle:@"Scale detection rate dynamically"
               y:y];

    y += 68;

    [self section:@"Performance" y:y];
    y += 28;

    [self slider:@"Model FPS"
             min:5
             max:120
           value:30
               y:y];

    y += 62;

    [self slider:@"Input Size"
             min:320
             max:640
           value:640
               y:y];

    y += 62;

    [self slider:@"NMS Threshold"
             min:0.1
             max:0.9
           value:0.45
               y:y];

    self.content.contentSize =
        CGSizeMake(0, y + 90);
}

#pragma mark - Settings

- (void)buildSettingsTab {
    CGFloat y = 18;

    [self section:@"Interface" y:y];
    y += 28;

    [self toggle:@"Animations"
        subtitle:@"Smooth Raven transitions"
               y:y];

    y += 60;

    [self toggle:@"Haptics"
        subtitle:@"UI feedback"
               y:y];

    y += 60;

    [self toggle:@"Auto Center"
        subtitle:@"Center menu when opened"
               y:y];

    y += 60;

    [self toggle:@"Remember Position"
        subtitle:@"Preserve draggable menu position"
               y:y];

    y += 68;

    [self section:@"Runtime" y:y];
    y += 28;

    [self toggle:@"Unity Detection"
        subtitle:@"Auto detect Unity runtime"
               y:y];

    y += 60;

    [self toggle:@"UE4 / UE5 Detection"
        subtitle:@"Auto detect Unreal runtime"
               y:y];

    y += 60;

    [self toggle:@"AScript Bridge"
        subtitle:@"Local target-data output"
               y:y];

    self.content.contentSize =
        CGSizeMake(0, y + 90);
}

#pragma mark - Info

- (void)buildInfoTab {
    CGFloat y = 22;

    NSArray *rows = @[
        @[@"ENGINE", @"RavenEngine AI"],
        @[@"UI", @"Raven Glass V2"],
        @[@"BACKEND", @"CoreML + Vision"],
        @[@"RENDER", @"UIKit / Metal"],
        @[@"TARGET", @"Unity / UE4 / UE5"],
        @[@"BRIDGE", @"AScript"],
        @[@"STATUS", @"Ready"]
    ];

    for (NSArray *row in rows) {
        UIView *card = [UIView new];

        card.backgroundColor = RVPanel2();
        card.layer.cornerRadius = 11;

        card.frame =
            CGRectMake(
                18,
                y,
                self.content.bounds.size.width - 36,
                42
            );

        UILabel *left = [UILabel new];
        left.text = row[0];
        left.textColor = RVSubText();
        left.font =
            [UIFont monospacedSystemFontOfSize:9
                                       weight:UIFontWeightBold];

        left.frame =
            CGRectMake(12, 10, 100, 22);

        UILabel *right = [UILabel new];
        right.text = row[1];
        right.textColor = RVText();
        right.textAlignment = NSTextAlignmentRight;
        right.font =
            [UIFont systemFontOfSize:11
                              weight:UIFontWeightSemibold];

        right.frame =
            CGRectMake(
                110,
                10,
                card.bounds.size.width - 122,
                22
            );

        [card addSubview:left];
        [card addSubview:right];

        [self.content addSubview:card];

        y += 50;
    }

    self.content.contentSize =
        CGSizeMake(0, y + 30);
}

#pragma mark - Events

- (void)toggleValueChanged:(RavenToggle *)sender {
    if (self.toggleChanged) {
        self.toggleChanged(
            sender.accessibilityIdentifier ?: @"",
            sender.enabledValue
        );
    }
}

- (void)sliderChangedInternal:(UISlider *)sender {
    UIView *container = sender.superview;

    for (UIView *view in container.subviews) {
        if (![view isKindOfClass:[UILabel class]]) continue;

        UILabel *label = (UILabel *)view;

        if ([label.text hasPrefix:
            sender.accessibilityIdentifier ?: @""]) {

            label.text =
                [NSString stringWithFormat:
                    @"%@   %.2f",
                    sender.accessibilityIdentifier,
                    sender.value];

            break;
        }
    }

    if (self.sliderChanged) {
        self.sliderChanged(
            sender.accessibilityIdentifier ?: @"",
            sender.value
        );
    }
}

#pragma mark - Drag

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation =
        [gesture translationInView:self];

    CGPoint center = self.menu.center;

    center.x += translation.x;
    center.y += translation.y;

    CGFloat halfW =
        self.menu.bounds.size.width / 2;

    CGFloat halfH =
        self.menu.bounds.size.height / 2;

    center.x =
        MAX(
            halfW + 6,
            MIN(self.bounds.size.width - halfW - 6,
                center.x)
        );

    center.y =
        MAX(
            halfH + 6,
            MIN(self.bounds.size.height - halfH - 6,
                center.y)
        );

    self.menu.center = center;

    [gesture setTranslation:CGPointZero
                     inView:self];
}

#pragma mark - Visibility

- (void)attachToWindow:(UIWindow *)window {
    self.frame = window.bounds;
    self.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    [window addSubview:self];
}

- (void)toggleMenu {
    self.menu.hidden
        ? [self showMenu]
        : [self hideMenu];
}

- (void)showMenu {
    self.menu.hidden = NO;

    self.menu.alpha = 0;
    self.menu.transform =
        CGAffineTransformMakeScale(0.93, 0.93);

    [UIView animateWithDuration:0.22
                     animations:^{
        self.menu.alpha = 1;
        self.menu.transform =
            CGAffineTransformIdentity;
    }];
}

- (void)hideMenu {
    [UIView animateWithDuration:0.18
                     animations:^{
        self.menu.alpha = 0;
        self.menu.transform =
            CGAffineTransformMakeScale(0.94, 0.94);
    }
                     completion:^(BOOL finished) {
        self.menu.hidden = YES;
        self.menu.transform =
            CGAffineTransformIdentity;
    }];
}

@end
