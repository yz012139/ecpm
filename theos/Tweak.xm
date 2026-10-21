// =====================================================================
// eCPM 鏁板€兼帶鍒?v3.8  鈥斺€?TrollFools / 杞绘澗绛?娉ㄥ叆鐢ㄧ殑绾?dylib
// 涓嶄緷璧?CydiaSubstrate锛屼笉闇€瑕佽秺鐙憋紝闈?__attribute__((constructor)) 鍚姩
// 缂栬瘧浜х墿锛?theos/obj/EcpmCtrl.dylib锛坅rm64 + arm64e锛?// =====================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>
#import <Foundation/Foundation.h>

static double gValue = 50000.0;     // 鐩爣 eCPM
static int    gMode  = 0;           // 0=鏇挎崲  1=鍙犲姞
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
                /* 杩斿洖瀵硅薄锛?@'锛夌殑鏂规硶涓€寰嬩笉纰帮細绫诲瀷瀵逛笉涓婁細鐩存帴鎶?App 寮勫穿 */
            }
            free(methods);
            if (n) { clsCount++; gHooked += n; }
        }
        free(classes);
    }
    ecpmLog([NSString stringWithFormat:@"鎵弿瀹屾垚锛氱被 %d 路 宸叉寕 %ld 鏉?, clsCount, gHooked]);
}

// ---------------- 瀛楀吀鎷︽埅锛氭妸 JSON 閲岀殑 ecpm / cpm 閿鍑烘潵鏀规垚 50000 ----------------
static Class gDictCls[16];
static IMP   gDictOrig[16];
static int   gDictCount = 0;
static long  gDictHits = 0;

static BOOL keyWanted(NSString *k) {
    if (![k isKindOfClass:[NSString class]]) return NO;
    NSUInteger len = k.length;
    if (len < 3 || len > 40) return NO;
    const char *s = k.UTF8String;
    if (!s) return NO;
    // 涓嶅尯鍒嗗ぇ灏忓啓鎵?ecpm / cpm
    for (const char *p = s; *p; p++) {
        char c = *p;
        if (c == 'e' || c == 'E') {
            if (!strncasecmp(p, "ecpm", 4)) return YES;
        }
        if (c == 'c' || c == 'C') {
            if (!strncasecmp(p, "cpm", 3)) return YES;
        }
    }
    return NO;
}

static id hookObjectForKey(id self, SEL _cmd, id key) {
    Class c = object_getClass(self);
    IMP orig = NULL;
    for (int i = 0; i < gDictCount; i++) {
        if (gDictCls[i] == c) { orig = gDictOrig[i]; break; }
    }
    if (!orig) return nil;
    id v = ((id (*)(id, SEL, id))orig)(self, _cmd, key);
    if (keyWanted((NSString *)key)) {
        gDictHits++;
        return @( applyValue([v isKindOfClass:[NSNumber class]] ? [v doubleValue] : 0) );
    }
    return v;
}

static void hookDictionaries(void) {
    NSArray *names = @[@"__NSDictionaryI", @"__NSDictionaryM", @"__NSDictionary0",
                       @"NSDictionary", @"NSMutableDictionary"];
    SEL sel = @selector(objectForKey:);
    for (NSString *n in names) {
        Class c = NSClassFromString(n);
        if (!c) continue;
        Method m = class_getInstanceMethod(c, sel);
        if (!m) continue;
        IMP orig = method_getImplementation(m);
        if ((void *)orig == (void *)hookObjectForKey) continue;
        if (gDictCount < 16) {
            gDictCls[gDictCount] = c;
            gDictOrig[gDictCount] = orig;
            gDictCount++;
        }
        method_setImplementation(m, (IMP)hookObjectForKey);
    }
    ecpmLog([NSString stringWithFormat:@"瀛楀吀鎷︽埅宸叉寕 %d 涓被", gDictCount]);
}

// ---------------- 鎮诞闈㈡澘 ----------------
@interface EcpmPanel : NSObject
@property (nonatomic, strong) UIWindow *win;
@property (nonatomic, strong) UIWindow *bubble;
- (void)bubbleShow:(BOOL)showFlag;
- (void)onBubblePan:(UIPanGestureRecognizer *)g;
- (UIWindowScene *)anyScene;
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

        [v addSubview:[self label:@"eCPM 鏁板€兼帶鍒?v3.8" frame:CGRectMake(12, 10, 260, 22) size:16 color:UIColor.whiteColor]];
        [v addSubview:[self label:@"鍙犲姞=鍘熷€?杈撳叆锛屾浛鎹?寮哄埗绛変簬杈撳叆" frame:CGRectMake(12, 34, 276, 34) size:11 color:UIColor.grayColor]];

        UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(12, 72, 276, 34)];
        field.text = [NSString stringWithFormat:@"%.0f", gValue];
        field.backgroundColor = UIColor.whiteColor;
        field.textColor = UIColor.blackColor;
        field.keyboardType = UIKeyboardTypeNumberPad;
        [v addSubview:field];

        UILabel *status = [self label:@"绛夊緟鎵弿鈥? frame:CGRectMake(12, 116, 276, 40) size:11 color:UIColor.greenColor];
        [v addSubview:status];
        if (!gObserverLabels) gObserverLabels = [NSMutableArray array];
        [gObserverLabels addObject:status];

        UIButton *apply = [self button:@"搴旂敤" frame:CGRectMake(12, 160, 84, 34) color:UIColor.systemBlueColor];
        [apply addAction:[UIAction actionWithHandler:^(UIAction *a) {
            gValue = field.text.doubleValue;
            ecpmLog([NSString stringWithFormat:@"宸插簲鐢?%.0f", gValue]);
        }] forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:apply];

        UIButton *mode = [self button:@"妯″紡:鏇挎崲" frame:CGRectMake(104, 160, 84, 34) color:UIColor.orangeColor];
        [mode addAction:[UIAction actionWithHandler:^(UIAction *a) {
            gMode = (gMode == 0) ? 1 : 0;
            [(UIButton *)a.sender setTitle:(gMode ? @"妯″紡:鍙犲姞" : @"妯″紡:鏇挎崲") forState:UIControlStateNormal];
        }] forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:mode];

        UIButton *rescan = [self button:@"閲嶆柊鎵弿" frame:CGRectMake(196, 160, 92, 34) color:UIColor.systemGreenColor];
        [rescan addAction:[UIAction actionWithHandler:^(UIAction *a) {
            dispatch_async(dispatch_get_global_queue(0, 0), ^{ scanClasses(); });
        }] forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:rescan];

        UIButton *hide = [self button:@"鏀惰捣" frame:CGRectMake(12, 204, 276, 34) color:UIColor.darkGrayColor];
        [hide addAction:[UIAction actionWithHandler:^(UIAction *a) {
            self.win.hidden = YES;
            [self bubbleShow:YES];
        }] forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:hide];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [v addGestureRecognizer:pan];

        self.win.hidden = NO;
        [self.win makeKeyAndVisible];
        ecpmLog(@"闈㈡澘宸叉樉绀?);
    });
}

- (UIWindowScene *)anyScene {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

- (void)bubbleShow:(BOOL)showFlag {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (showFlag && !self.bubble) {
            UIWindowScene *sc = [self anyScene];
            CGRect bf = CGRectMake(10, 200, 56, 56);
            if (sc) self.bubble = [[UIWindow alloc] initWithWindowScene:sc];
            else self.bubble = [[UIWindow alloc] initWithFrame:bf];
            self.bubble.frame = bf;
            self.bubble.windowLevel = UIWindowLevelAlert + 101;
            self.bubble.backgroundColor = UIColor.clearColor;
            UIViewController *bvc = [UIViewController new];
            self.bubble.rootViewController = bvc;
            UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
            b.frame = CGRectMake(0, 0, 56, 56);
            [b setTitle:@"e" forState:UIControlStateNormal];
            [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
            b.layer.cornerRadius = 28;
            [b addAction:[UIAction actionWithHandler:^(UIAction *a) {
                self.bubble.hidden = YES;
                self.win.hidden = NO;
                [self.win makeKeyAndVisible];
            }] forControlEvents:UIControlEventTouchUpInside];
            [bvc.view addSubview:b];
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onBubblePan:)];
            [bvc.view addGestureRecognizer:pan];
        }
        self.bubble.hidden = !showFlag;
    });
}

- (void)onBubblePan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.bubble.superview];
    CGRect f = self.bubble.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    self.bubble.frame = f;
    [g setTranslation:CGPointZero inView:self.bubble.superview];
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.win.superview];
    CGRect f = self.win.frame;
    f.origin.x += t.x; f.origin.y += t.y;
    self.win.frame = f;
    [g setTranslation:CGPointZero inView:self.win.superview];
}
@end

// ---------------- 鏋勯€犲嚱鏁帮紙dylib 鍔犺浇鍗虫墽琛岋級 ----------------
__attribute__((constructor))
static void ecpm_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(0, 0), ^{
        scanClasses();
        hookDictionaries();
        [[EcpmPanel shared] show];
        [NSTimer scheduledTimerWithTimeInterval:15 repeats:YES block:^(NSTimer *t) { scanClasses(); }];
    });
}

