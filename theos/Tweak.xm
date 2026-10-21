// =====================================================================
// eCPM 数值控制 v3.8  —— TrollFools / 轻松签 注入用的纯 dylib
// 不依赖 CydiaSubstrate，不需要越狱，靠 __attribute__((constructor)) 启动
// 编译产物：.theos/obj/EcpmCtrl.dylib（arm64 + arm64e）
// =====================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

static double gValue = 50000.0;     // 目标 eCPM
static int    gMode  = 0;           // 0=替换  1=叠加
static BOOL   gLog   = YES;
static long   gHits  = 0;
static long   gHooked = 0;
static NSMutableArray *gObserverLabels;

static void ecpmLog(NSString *msg) {
    if (gLog) NSLog(@"[eCPM] %@", msg);
    for (UILabel *l in gObserverLabels) {
        dispatch_async(dispatch_get_main_queue(), ^{ l.text = msg; });
    }
}

static double applyValue(double orig) { return (gMode == 1) ? (orig + gValue) : gValue; }

static double hookD(id self, SEL _cmd) { gHits++; return applyValue(0); }
static float  hookF(id self, SEL _cmd) { gHits++; return (float)applyValue(0); }
static long long hookQ(id self, SEL _cmd) { gHits++; return (long long)applyValue(0); }
static int    hookI(id self, SEL _cmd) { gHits++; return (int)applyValue(0); }
static id     hookN(id self, SEL _cmd) { gHits++; return @( applyValue(0) ); }

static BOOL isCandidateName(NSString *n) {
    static NSArray *prefixes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefixes = @[@"ABU", @"CSJ", @"BU", @"BD", @"Pangle", @"TTAd", @"GM", @"PAG", @"BUNative"];
    });
    for (NSString *p in prefixes) if ([n hasPrefix:p]) return YES;
    return NO;
}

static BOOL isCandidateSel(NSString *s) {
    NSString *low = s.lowercaseString;
    if ([low hasPrefix:@"set"] || [low containsString:@"init"] || [low containsString:@"dealloc"]) return NO;
    return ([low containsString:@"ecpm"] || [low containsString:@"cpm"] ||
            [low containsString:@"price"] || [low containsString:@"bid"] ||
            [low containsString:@"revenue"]);
}

static void scanClasses(void) {
    int clsCount = 0;
    @autoreleasepool {
        unsigned int total = 0;
        Class *classes = objc_copyClassList(&total);
        for (unsigned int i = 0; i < total; i++) {
            Class c = classes[i];
            const char *cn = class_getName(c);
            if (!cn) continue;
            if (!isCandidateName(@(cn))) continue;

            unsigned int mcount = 0;
            Method *methods = class_copyMethodList(c, &mcount);
            if (!methods) continue;
            int n = 0;
            for (unsigned int j = 0; j < mcount; j++) {
                NSString *selStr = NSStringFromSelector(method_getName(methods[j]));
                if (!isCandidateSel(selStr)) continue;
                const char *types = method_getTypeEncoding(methods[j]);
                if (!types || !types[0]) continue;
                char rt = types[0];
                if (rt == 'd') { method_setImplementation(methods[j], (IMP)hookD); n++; }
                else if (rt == 'f') { method_setImplementation(methods[j], (IMP)hookF); n++; }
                else if (rt == 'q') { method_setImplementation(methods[j], (IMP)hookQ); n++; }
                else if (rt == 'i') { method_setImplementation(methods[j], (IMP)hookI); n++; }
                /* 返回对象（'@'）的方法一律不碰：类型对不上会直接把 App 弄崩 */
            }
            free(methods);
            if (n) { clsCount++; gHooked += n; }
        }
        free(classes);
    }
    ecpmLog([NSString stringWithFormat:@"扫描完成：类 %d · 已挂 %ld 条", clsCount, gHooked]);
}

// ---------------- 悬浮面板 ----------------
@interface EcpmPanel : NSObject
@property (nonatomic, strong) UIWindow *win;
@end

@implementation EcpmPanel
+ (instancetype)shared {
    static EcpmPanel *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [EcpmPanel new]; });
    return s;
}

- (UILabel *)label:(NSString *)t frame:(CGRect)f size:(CGFloat)s color:(UIColor *)c {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.text = t; l.font = [UIFont boldSystemFontOfSize:s]; l.textColor = c; l.numberOfLines = 0;
    return l;
}

- (UIButton *)button:(NSString *)t frame:(CGRect)f color:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = c;
    b.layer.cornerRadius = 6;
    return b;
}

- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
        }
        CGRect frame = CGRectMake(10, 120, 300, 290);
        if (scene) self.win = [[UIWindow alloc] initWithWindowScene:scene];
        else self.win = [[UIWindow alloc] initWithFrame:frame];
        self.win.frame = frame;
        self.win.windowLevel = UIWindowLevelAlert + 100;
        self.win.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.92];
        self.win.layer.cornerRadius = 12;
        self.win.layer.masksToBounds = YES;

        UIViewController *vc = [UIViewController new];
        self.win.rootViewController = vc;
        UIView *v = vc.view;
        v.frame = CGRectMake(0, 0, 300, 290);

        [v addSubview:[self label:@"eCPM 数值控制 v3.8" frame:CGRectMake(12, 10, 260, 22) size:16 color:UIColor.whiteColor]];
        [v addSubview:[self label:@"叠加=原值+输入，替换=强制等于输入" frame:CGRectMake(12, 34, 276, 34) size:11 color:UIColor.grayColor]];

        UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(12, 72, 276, 34)];
        field.text = [NSString stringWithFormat:@"%.0f", gValue];
        field.backgroundColor = UIColor.whiteColor;
        field.textColor = UIColor.blackColor;
        field.keyboardType = UIKeyboardTypeNumberPad;
        [v addSubview:field];

        UILabel *status = [self label:@"等待扫描…" frame:CGRectMake(12, 116, 276, 40) size:11 color:UIColor.greenColor];
        [v addSubview:status];
        if (!gObserverLabels) gObserverLabels = [NSMutableArray array];
        [gObserverLabels addObject:status];

        UIButton *apply = [self button:@"应用" frame:CGRectMake(12, 160, 84, 34) color:UIColor.systemBlueColor];
        [apply addAction:[UIAction actionWithHandler:^(UIAction *a) {
            gValue = field.text.doubleValue;
            ecpmLog([NSString stringWithFormat:@"已应用 %.0f", gValue]);
        }] forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:apply];

        UIButton *mode = [self button:@"模式:替换" frame:CGRectMake(104, 160, 84, 34) color:UIColor.orangeColor];
        [mode addAction:[UIAction actionWithHandler:^(UIAction *a) {
            gMode = (gMode == 0) ? 1 : 0;
            [(UIButton *)a.sender setTitle:(gMode ? @"模式:叠加" : @"模式:替换") forState:UIControlStateNormal];
        }] forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:mode];

        UIButton *rescan = [self button:@"重新扫描" frame:CGRectMake(196, 160, 92, 34) color:UIColor.systemGreenColor];
        [rescan addAction:[UIAction actionWithHandler:^(UIAction *a) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{ scanClasses(); });
        }] forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:rescan];

        UIButton *hide = [self button:@"收起" frame:CGRectMake(12, 204, 276, 34) color:UIColor.darkGrayColor];
        [hide addAction:[UIAction actionWithHandler:^(UIAction *a) { self.win.hidden = YES; }]
              forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:hide];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [v addGestureRecognizer:pan];

        self.win.hidden = NO;
        [self.win makeKeyAndVisible];
        ecpmLog(@"面板已显示");
    });
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.win.superview];
    CGRect f = self.win.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    self.win.frame = f;
    [g setTranslation:CGPointZero inView:self.win.superview];
}
@end

// ---------------- 构造函数（dylib 加载即执行） ----------------
__attribute__((constructor))
static void ecpm_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(0, 0), ^{
        scanClasses();
        [[EcpmPanel shared] show];
        [NSTimer scheduledTimerWithTimeInterval:15 repeats:YES block:^(NSTimer *t) { scanClasses(); }];
    });
}
