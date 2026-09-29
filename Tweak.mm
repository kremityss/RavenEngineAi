#import <UIKit/UIKit.h>
#import <CoreML/CoreML.h>
#import <Vision/Vision.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <CoreImage/CoreImage.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <string.h>
#import <stdio.h>

#import "RavenMenu.h"

#define CAPTURE_INTERVAL 0.1
#define ASCRIPT_HOST "127.0.0.1"
#define ASCRIPT_PORT 5055

@class ScreenAnalyzer;
static ScreenAnalyzer *analyzer = nil;

typedef NS_ENUM(NSInteger, RavenGameEngine) {
    RavenGameEngineUnknown = 0,
    RavenGameEngineUnity,
    RavenGameEngineUnreal4,
    RavenGameEngineUnreal5
};

typedef struct {
    float targetX;
    float targetY;
    float deltaX;
    float deltaY;
    float confidence;
    float screenWidth;
    float screenHeight;
    int engine;
} RavenAimPacket;

static BOOL RavenImageLoaded(const char *needle) {
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, needle)) {
            return YES;
        }
    }

    return NO;
}

static RavenGameEngine RavenDetectGameEngine(void) {
    if (RavenImageLoaded("UnityFramework") ||
        RavenImageLoaded("libunity") ||
        RavenImageLoaded("GameAssembly")) {
        return RavenGameEngineUnity;
    }

    if (RavenImageLoaded("UE5")) {
        return RavenGameEngineUnreal5;
    }

    if (RavenImageLoaded("UE4") ||
        RavenImageLoaded("Unreal")) {
        return RavenGameEngineUnreal4;
    }

    return RavenGameEngineUnknown;
}

static CAMetalLayer *RavenFindMetalLayer(UIView *view) {
    if ([view.layer isKindOfClass:[CAMetalLayer class]]) {
        return (CAMetalLayer *)view.layer;
    }

    for (UIView *subview in view.subviews) {
        CAMetalLayer *layer = RavenFindMetalLayer(subview);
        if (layer) return layer;
    }

    return nil;
}


static NSURL *RavenSiblingURL(NSString *relativePath) {
    Dl_info info = {0};
    if (dladdr((const void *)&RavenDetectGameEngine, &info) == 0 || !info.dli_fname) {
        return nil;
    }
    NSString *dylibPath = [NSString stringWithUTF8String:info.dli_fname];
    NSString *dir = [dylibPath stringByDeletingLastPathComponent];
    NSString *candidate = [dir stringByAppendingPathComponent:relativePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
        return [NSURL fileURLWithPath:candidate isDirectory:YES];
    }
    return nil;
}

@interface ScreenAnalyzer : NSObject
@property (nonatomic, strong) MLModel *model;
@property (nonatomic, strong) VNCoreMLModel *vnModel;
@property (nonatomic, strong) VNCoreMLRequest *vnRequest;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) CAShapeLayer *overlayShape;
@property (nonatomic, strong) NSTimer *timer;
@property (atomic, assign) BOOL isProcessing;

@property (atomic, assign) BOOL espEnabled;
@property (atomic, assign) BOOL boxESPEnabled;
@property (atomic, assign) BOOL coreMLEnabled;
@property (atomic, assign) BOOL ascriptEnabled;
@property (atomic, assign) BOOL aiAimEnabled;
@property (atomic, assign) BOOL unityDetectionEnabled;
@property (atomic, assign) BOOL unrealDetectionEnabled;

@property (atomic, assign) CGFloat confidenceThreshold;
@property (atomic, assign) CGFloat espThickness;
@property (atomic, assign) CGFloat espOpacity;
@property (atomic, assign) CGFloat fovRadius;
@end

@implementation ScreenAnalyzer

#pragma mark - Init

- (instancetype)init {
    self = [super init];

    if (self) {
        _espEnabled = YES;
        _boxESPEnabled = YES;
        _coreMLEnabled = YES;
        _ascriptEnabled = YES;
        _aiAimEnabled = YES;
        _unityDetectionEnabled = YES;
        _unrealDetectionEnabled = YES;

        _confidenceThreshold = 0.50;
        _espThickness = 2.0;
        _espOpacity = 0.95;
        _fovRadius = 150.0;

        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                [self startAnalyzer];
            }
        );
    }

    return self;
}

#pragma mark - Analyzer Setup

- (NSURL *)findRavenModelURL {
    NSFileManager *fm = [NSFileManager defaultManager];

    NSArray<NSString *> *relativePaths = @[
        @"RavenModel.mlmodelc",
        @"RavenModel.mlpackage",
        @"Resources/RavenModel.mlmodelc",
        @"Resources/RavenModel.mlpackage"
    ];

    for (NSString *relativePath in relativePaths) {
        NSURL *url = RavenSiblingURL(relativePath);
        if (url && [fm fileExistsAtPath:url.path]) return url;
    }

    NSURL *compiled = [[NSBundle mainBundle] URLForResource:@"RavenModel"
                                              withExtension:@"mlmodelc"];
    if (compiled) return compiled;

    NSURL *package = [[NSBundle mainBundle] URLForResource:@"RavenModel"
                                             withExtension:@"mlpackage"];
    if (package) return package;

    NSString *documents = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    for (NSString *name in @[@"RavenModel.mlmodelc", @"RavenModel.mlpackage"]) {
        NSString *path = [documents stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:path]) {
            return [NSURL fileURLWithPath:path isDirectory:YES];
        }
    }

    return nil;
}

- (BOOL)loadRavenModel {
    NSURL *sourceURL = [self findRavenModelURL];
    if (!sourceURL) {
        NSLog(@"[RAVEN] RavenModel not found");
        return NO;
    }

    NSURL *loadURL = sourceURL;
    NSString *extension = sourceURL.pathExtension.lowercaseString;

    if ([extension isEqualToString:@"mlpackage"] ||
        [extension isEqualToString:@"mlmodel"]) {
        NSError *compileError = nil;
        loadURL = [MLModel compileModelAtURL:sourceURL error:&compileError];
        if (!loadURL) {
            NSLog(@"[RAVEN] CoreML compile failed: %@", compileError);
            return NO;
        }
    }

    MLModelConfiguration *configuration = [[MLModelConfiguration alloc] init];
    configuration.computeUnits = MLComputeUnitsAll;

    NSError *loadError = nil;
    self.model = [MLModel modelWithContentsOfURL:loadURL
                                   configuration:configuration
                                           error:&loadError];
    if (!self.model) {
        NSLog(@"[RAVEN] CoreML load failed: %@", loadError);
        return NO;
    }

    NSError *visionError = nil;
    self.vnModel = [VNCoreMLModel modelForMLModel:self.model error:&visionError];
    if (!self.vnModel) {
        NSLog(@"[RAVEN] Vision model creation failed: %@", visionError);
        return NO;
    }

    NSLog(@"[RAVEN] CoreML ready: %@", sourceURL.lastPathComponent);
    return YES;
}

- (void)startAnalyzer {
    if (![self loadRavenModel]) {
        [self attachUIOnly];
        return;
    }

    __weak typeof(self) weakSelf = self;

    self.vnRequest = [[VNCoreMLRequest alloc]
        initWithModel:self.vnModel
        completionHandler:^(VNRequest *req, NSError *err) {
            ScreenAnalyzer *strongSelf = weakSelf;
            if (!strongSelf) return;

            if (err) {
                NSLog(@"[RAVEN] Vision request error: %@", err);
                strongSelf.isProcessing = NO;
                return;
            }

            MLMultiArray *coordinates = nil;
            MLMultiArray *confidence = nil;

            for (VNObservation *obs in req.results) {
                if (![obs isKindOfClass:[VNCoreMLFeatureValueObservation class]]) continue;
                VNCoreMLFeatureValueObservation *featureObs =
                    (VNCoreMLFeatureValueObservation *)obs;
                MLMultiArray *array = featureObs.featureValue.multiArrayValue;
                if (!array) continue;

                if ([featureObs.featureName isEqualToString:@"coordinates"]) {
                    coordinates = array;
                } else if ([featureObs.featureName isEqualToString:@"confidence"]) {
                    confidence = array;
                }
            }

            if (!coordinates || !confidence) {
                NSLog(@"[RAVEN] Missing NMS outputs (coordinates/confidence)");
                strongSelf.isProcessing = NO;
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [strongSelf drawNMSCoordinates:coordinates confidence:confidence];
                strongSelf.isProcessing = NO;
            });
        }
    ];

    self.vnRequest.imageCropAndScaleOption = VNImageCropAndScaleOptionScaleFill;

    self.overlayView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.overlayView.userInteractionEnabled = NO;
    self.overlayView.backgroundColor = UIColor.clearColor;
    self.overlayView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;

    self.overlayShape = [CAShapeLayer layer];
    self.overlayShape.frame = self.overlayView.bounds;
    self.overlayShape.strokeColor = UIColor.redColor.CGColor;
    self.overlayShape.fillColor = UIColor.clearColor.CGColor;
    self.overlayShape.lineWidth = self.espThickness;
    self.overlayShape.opacity = self.espOpacity;
    self.overlayShape.contentsScale = UIScreen.mainScreen.scale;

    [self.overlayView.layer addSublayer:self.overlayShape];

    UIWindow *win = [self currentKeyWindow];
    if (win) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [win addSubview:self.overlayView];
            [[RavenMenu shared] attachToWindow:win];
            [self wireMenuCallbacks];
        });
    }

    self.timer = [NSTimer scheduledTimerWithTimeInterval:CAPTURE_INTERVAL
                                                   target:self
                                                 selector:@selector(captureAndAnalyze)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)attachUIOnly {
    UIWindow *win = [self currentKeyWindow];
    if (!win) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[RavenMenu shared] attachToWindow:win];
        [self wireMenuCallbacks];
    });
}

#pragma mark - Menu Wiring

- (void)wireMenuCallbacks {
    __weak typeof(self) weakSelf = self;

    [RavenMenu shared].toggleChanged = ^(NSString *feature, BOOL enabled) {
        ScreenAnalyzer *strongSelf = weakSelf;
        if (!strongSelf) return;

        if ([feature isEqualToString:@"ESP Master"]) {
            strongSelf.espEnabled = enabled;
            strongSelf.overlayView.hidden = !enabled;
        } else if ([feature isEqualToString:@"Box ESP"]) {
            strongSelf.boxESPEnabled = enabled;
            strongSelf.overlayShape.hidden = !enabled;
        } else if ([feature isEqualToString:@"CoreML"]) {
            strongSelf.coreMLEnabled = enabled;
        } else if ([feature isEqualToString:@"AScript Bridge"]) {
            strongSelf.ascriptEnabled = enabled;
        } else if ([feature isEqualToString:@"AI Aim"]) {
            strongSelf.aiAimEnabled = enabled;
        } else if ([feature isEqualToString:@"Unity Detection"]) {
            strongSelf.unityDetectionEnabled = enabled;
        } else if ([feature isEqualToString:@"UE4 / UE5 Detection"]) {
            strongSelf.unrealDetectionEnabled = enabled;
        }
    };

    [RavenMenu shared].sliderChanged = ^(NSString *feature, CGFloat value) {
        ScreenAnalyzer *strongSelf = weakSelf;
        if (!strongSelf) return;

        if ([feature isEqualToString:@"ESP Thickness"]) {
            strongSelf.espThickness = value;
            strongSelf.overlayShape.lineWidth = value;
        } else if ([feature isEqualToString:@"ESP Opacity"]) {
            strongSelf.espOpacity = value;
            strongSelf.overlayShape.opacity = value;
        } else if ([feature isEqualToString:@"Confidence"]) {
            strongSelf.confidenceThreshold = value;
        } else if ([feature isEqualToString:@"FOV"]) {
            strongSelf.fovRadius = value;
        }
    };
}

#pragma mark - Window

- (UIWindow *)currentKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        for (UIWindow *w in windowScene.windows) {
            if (w.isKeyWindow) return w;
        }

        if (windowScene.windows.count > 0) {
            return windowScene.windows.firstObject;
        }
    }

    id<UIApplicationDelegate> del = UIApplication.sharedApplication.delegate;

    if (del && [del respondsToSelector:@selector(window)]) {
        return [del window];
    }

    return nil;
}

#pragma mark - Capture

- (void)captureAndAnalyze {
    if (!self.coreMLEnabled) return;
    if (self.isProcessing) return;

    UIWindow *window = [self currentKeyWindow];
    if (!window) return;

    self.isProcessing = YES;

    RavenGameEngine engine = RavenDetectGameEngine();
    CAMetalLayer *metalLayer = RavenFindMetalLayer(window);

    BOOL supportedEngine = NO;

    if (engine == RavenGameEngineUnity && self.unityDetectionEnabled) {
        supportedEngine = YES;
    }
    else if ((engine == RavenGameEngineUnreal4 ||
              engine == RavenGameEngineUnreal5) &&
             self.unrealDetectionEnabled) {
        supportedEngine = YES;
    }
    else if (engine == RavenGameEngineUnknown) {
        supportedEngine = YES;
    }

    if (!supportedEngine) {
        self.isProcessing = NO;
        return;
    }

    // Current fallback capture path. Metal layer detection is already present so
    // this can later be replaced with drawable/texture capture without changing
    // the CoreML or menu pipeline.
    if (metalLayer) {
        [self captureUIKitWindow:window];
    }
    else {
        [self captureUIKitWindow:window];
    }
}

- (void)captureUIKitWindow:(UIWindow *)keyWindow {
    CGSize targetSize = CGSizeMake(640.0, 640.0);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            __block UIImage *screenshot = nil;

            dispatch_sync(dispatch_get_main_queue(), ^{
                UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);

                [keyWindow drawViewHierarchyInRect:CGRectMake(0,
                                                               0,
                                                               targetSize.width,
                                                               targetSize.height)
                                         afterScreenUpdates:NO];

                screenshot = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            });

            if (!screenshot || !screenshot.CGImage) {
                self.isProcessing = NO;
                return;
            }

            VNImageRequestHandler *handler =
                [[VNImageRequestHandler alloc]
                    initWithCGImage:screenshot.CGImage
                    options:@{}];

            NSError *err = nil;
            [handler performRequests:@[self.vnRequest] error:&err];

            if (err) {
                NSLog(@"[RAVEN] Inference error: %@", err);
                self.isProcessing = NO;
            }
        }
    });
}

#pragma mark - AScript Bridge

- (void)sendAScriptPacket:(const void *)data length:(size_t)length {
    if (!self.ascriptEnabled) return;

    static int sock = -1;
    static struct sockaddr_in addr;

    if (sock == -1) {
        sock = socket(AF_INET, SOCK_DGRAM, 0);

        if (sock < 0) {
            NSLog(@"[RAVEN] Failed to create AScript UDP socket");
            return;
        }

        memset(&addr, 0, sizeof(addr));
        addr.sin_family = AF_INET;
        addr.sin_port = htons(ASCRIPT_PORT);

        inet_pton(AF_INET, ASCRIPT_HOST, &addr.sin_addr);
    }

    sendto(sock,
           data,
           length,
           MSG_DONTWAIT,
           (struct sockaddr *)&addr,
           sizeof(addr));
}

- (void)sendTargetToAScript:(CGRect)target confidence:(float)confidence {
    if (!self.aiAimEnabled) return;
    if (!self.ascriptEnabled) return;

    CGSize size = UIScreen.mainScreen.bounds.size;

    CGPoint center = CGPointMake(size.width * 0.5,
                                 size.height * 0.5);

    CGPoint targetCenter = CGPointMake(CGRectGetMidX(target),
                                       CGRectGetMidY(target));

    CGFloat dx = targetCenter.x - center.x;
    CGFloat dy = targetCenter.y - center.y;

    CGFloat distance = hypot(dx, dy);

    if (self.fovRadius > 0 && distance > self.fovRadius) {
        return;
    }

    RavenAimPacket packet = {
        .targetX = (float)targetCenter.x,
        .targetY = (float)targetCenter.y,
        .deltaX = (float)dx,
        .deltaY = (float)dy,
        .confidence = confidence,
        .screenWidth = (float)size.width,
        .screenHeight = (float)size.height,
        .engine = (int)RavenDetectGameEngine()
    };

    [self sendAScriptPacket:&packet length:sizeof(packet)];
}

#pragma mark - Detection Drawing

- (double)valueFromArray:(MLMultiArray *)array index:(NSInteger)index {
    if (!array || index < 0 || index >= array.count) return 0.0;
    return [array[index] doubleValue];
}

- (void)drawNMSCoordinates:(MLMultiArray *)coordinates
                 confidence:(MLMultiArray *)confidence {
    if (!coordinates || !confidence) {
        self.overlayShape.path = nil;
        return;
    }

    NSInteger detectionCount = coordinates.count / 4;
    if (detectionCount <= 0) {
        self.overlayShape.path = nil;
        return;
    }

    NSInteger confidenceColumns =
        MAX((NSInteger)1, confidence.count / MAX((NSInteger)1, detectionCount));

    CGSize screenSize = UIScreen.mainScreen.bounds.size;
    CGRect screenBounds = CGRectMake(0, 0, screenSize.width, screenSize.height);
    CGPoint screenCenter = CGPointMake(screenSize.width * 0.5,
                                       screenSize.height * 0.5);

    UIBezierPath *combined = [UIBezierPath bezierPath];
    float bestConf = 0.0f;
    CGFloat bestDistance = CGFLOAT_MAX;
    CGRect bestRect = CGRectZero;

    for (NSInteger i = 0; i < detectionCount; i++) {
        NSInteger base = i * 4;

        double x = [self valueFromArray:coordinates index:base + 0];
        double y = [self valueFromArray:coordinates index:base + 1];
        double w = [self valueFromArray:coordinates index:base + 2];
        double h = [self valueFromArray:coordinates index:base + 3];

        float conf = 0.0f;
        NSInteger confBase = i * confidenceColumns;
        for (NSInteger col = 0; col < confidenceColumns; col++) {
            NSInteger idx = confBase + col;
            if (idx >= confidence.count) break;
            conf = MAX(conf, (float)[self valueFromArray:confidence index:idx]);
        }

        if (conf < self.confidenceThreshold || w <= 0.0 || h <= 0.0) continue;

        CGFloat centerX = (CGFloat)x * screenSize.width;
        CGFloat centerY = (CGFloat)y * screenSize.height;
        CGFloat boxW = (CGFloat)w * screenSize.width;
        CGFloat boxH = (CGFloat)h * screenSize.height;

        CGRect rectScreen = CGRectMake(centerX - boxW * 0.5,
                                       centerY - boxH * 0.5,
                                       boxW,
                                       boxH);

        rectScreen = CGRectIntersection(rectScreen, screenBounds);
        if (CGRectIsNull(rectScreen) || CGRectIsEmpty(rectScreen)) continue;

        if (self.espEnabled && self.boxESPEnabled) {
            [combined appendPath:[UIBezierPath bezierPathWithRect:rectScreen]];
        }

        CGPoint boxCenter = CGPointMake(CGRectGetMidX(rectScreen),
                                        CGRectGetMidY(rectScreen));
        CGFloat dx = boxCenter.x - screenCenter.x;
        CGFloat dy = boxCenter.y - screenCenter.y;
        CGFloat distance = hypot(dx, dy);
        BOOL inFOV = (self.fovRadius <= 0.0 || distance <= self.fovRadius);

        if (inFOV &&
            (distance < bestDistance ||
             (fabs(distance - bestDistance) < 1.0 && conf > bestConf))) {
            bestDistance = distance;
            bestConf = conf;
            bestRect = rectScreen;
        }
    }

    self.overlayShape.path = combined.CGPath;

    if (bestConf >= self.confidenceThreshold && !CGRectIsEmpty(bestRect)) {
        [self sendTargetToAScript:bestRect confidence:bestConf];
    }
}


@end

__attribute__((constructor))
static void init_analyzer(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        analyzer = [ScreenAnalyzer new];
    });
}
