// =====================================================================
//  eCPM 数值控制 v3.8  ——  视频同款复刻
//  ---------------------------------------------------------------
//  纯 dylib，不依赖 CydiaSubstrate / 越狱：
//    - 构造函数注入，App 启动 1 秒后出悬浮球
//    - 运行时扫进程内全部类，按「28万表」规则（10 前缀 × 8 关键词 = 80 条）
//      挂广告 SDK 的 eCPM getter，返回值按 替换/叠加 改写
//    - NSDictionary -objectForKey: 同步拦截 ecpm/cpm/price/bid/revenue
//    - 面板：输入框、应用、模式、日志、重新扫描、收起、版本历史记录
//  编译：Theos make package   或   .github/workflows/build.yml 云编译
// =====================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>
#import <stdlib.h>
#import <stdio.h>

#pragma mark - 全局状态

static double   gValue        = 50000.0;  // 写入的 eCPM
static NSInteger gMode        = 0;        // 0=替换 1=叠加
static BOOL     gEnabled      = NO;       // 应用后为 YES，未应用只统计不改写
static BOOL     gLogOn        = YES;
static BOOL     gScanning     = NO;

static volatile long gHits    = 0;        // getter 被调用次数
static volatile long gWrites  = 0;        // 实际改写次数
static char gLastCls[96] = "—";
static char gLastSel[96] = "";
static NSInteger gScope = 1;              // 0=全部80条 1=只ecpm+cpm 2=旧表9条(安全)
static BOOL gPaused = NO;                 // 点了「还原全部」后暂停扫描

static long gCandidateClasses = 0;        // 类名前缀命中的类数（面板 类X/31 的分母）
static long gMatchedClasses   = 0;        // 真正挂上方法的类数（分子）

static NSString *const kDefValue = @"EcpmCtrl38.value";
static NSString *const kDefMode  = @"EcpmCtrl38.mode";
static NSString *const kDefOn    = @"EcpmCtrl38.enabled";
static NSString *const kDefLog   = @"EcpmCtrl38.log";

#pragma mark - 规则表（28万表）

typedef struct {
    const char *prefix;   // 类名前缀
    const char *key;      // 方法名关键词（小写，contains 匹配）
    BOOL        legacy;   // 旧表 9 条
} EcpmRule;

#define RULE_COUNT 80

// 10 前缀 × 8 关键词 = 80 条，旧表 9 条散落其中（并集就是 80，和面板文案一致）
static const EcpmRule kRules[RULE_COUNT] = {
    // BU
    { "BU", "ecpm",        YES }, { "BU", "cpm",        NO  }, { "BU", "price",      NO  }, { "BU", "bid",        NO  },
    { "BU", "revenue",     NO  }, { "BU", "winprice",   NO  }, { "BU", "secondprice",NO  }, { "BU", "bidprice",   NO  },
    // CSJ
    { "CSJ","ecpm",        YES }, { "CSJ","cpm",        NO  }, { "CSJ","price",      NO  }, { "CSJ","bid",        NO  },
    { "CSJ","revenue",     NO  }, { "CSJ","winprice",   NO  }, { "CSJ","secondprice",NO  }, { "CSJ","bidprice",   NO  },
    // Pangle
    { "Pangle","ecpm",     NO  }, { "Pangle","cpm",     NO  }, { "Pangle","price",   YES }, { "Pangle","bid",     NO  },
    { "Pangle","revenue",  NO  }, { "Pangle","winprice",NO  }, { "Pangle","secondprice",NO }, { "Pangle","bidprice",NO },
    // PAG
    { "PAG","ecpm",        NO  }, { "PAG","cpm",        NO  }, { "PAG","price",      NO  }, { "PAG","bid",        NO  },
    { "PAG","revenue",     NO  }, { "PAG","winprice",   NO  }, { "PAG","secondprice",NO  }, { "PAG","bidprice",   NO  },
    // TTAd
    { "TTAd","ecpm",       NO  }, { "TTAd","cpm",       NO  }, { "TTAd","price",     NO  }, { "TTAd","bid",       YES },
    { "TTAd","revenue",    NO  }, { "TTAd","winprice",  NO  }, { "TTAd","secondprice",NO }, { "TTAd","bidprice",  NO  },
    // ABU
    { "ABU","ecpm",        YES }, { "ABU","cpm",        NO  }, { "ABU","price",      NO  }, { "ABU","bid",        NO  },
    { "ABU","revenue",     NO  }, { "ABU","winprice",   NO  }, { "ABU","secondprice",NO  }, { "ABU","bidprice",   NO  },
    // GDT（优量汇）
    { "GDT","ecpm",        YES }, { "GDT","cpm",        NO  }, { "GDT","price",      NO  }, { "GDT","bid",        NO  },
    { "GDT","revenue",     NO  }, { "GDT","winprice",   NO  }, { "GDT","secondprice",NO  }, { "GDT","bidprice",   NO  },
    // KS（快手）
    { "KS","ecpm",         YES }, { "KS","cpm",         NO  }, { "KS","price",       NO  }, { "KS","bid",         NO  },
    { "KS","revenue",      NO  }, { "KS","winprice",    NO  }, { "KS","secondprice", NO  }, { "KS","bidprice",    NO  },
    // BaiduMobAd
    { "BaiduMobAd","ecpm", YES }, { "BaiduMobAd","cpm", NO  }, { "BaiduMobAd","price",NO }, { "BaiduMobAd","bid", NO  },
    { "BaiduMobAd","revenue",NO }, { "BaiduMobAd","winprice",NO }, { "BaiduMobAd","secondprice",NO }, { "BaiduMobAd","bidprice",NO },
    // BUNative
    { "BUNative","ecpm",   NO  }, { "BUNative","cpm",   NO  }, { "BUNative","price", NO  }, { "BUNative","bid",   NO  },
    { "BUNative","revenue",YES }, { "BUNative","winprice",NO }, { "BUNative","secondprice",NO }, { "BUNative","bidprice",NO },
};

static inline double ModeValue(double base) {
    return (gMode == 1) ? (base + gValue) : gValue;
}

#pragma mark - Hook 槽位

typedef struct {
    Class       cls;       // 被挂的类（类方法时为 metaclass）
    const char *sel;       // 方法名，静态字符串（getter 名不会变，直接存 sel_getName）
    IMP         orig;
    Method      method;    // 原始 Method，安全模式下要还原
    int         rule;      // 命中的规则下标
} EcpmSlot;

static EcpmSlot gSlots[RULE_COUNT];
static int      gSlotCount = 0;
static long     gLegacyHooked = 0;

static BOOL IsNumericType(const char *enc) {
    if (!enc || !enc[0]) return NO;
    switch (enc[0]) {
        case 'f': case 'd':
        case 'i': case 's': case 'I': case 'S':
        case 'l': case 'L': case 'q': case 'Q':
            return YES;
        default:
            return NO;
    }
}

static IMP OrigIMP(id self, SEL cmd) {
    Class c = object_getClass(self);
    const char *s = sel_getName(cmd);
    while (c) {
        for (int i = 0; i < gSlotCount; i++) {
            if (gSlots[i].cls == c && strcmp(gSlots[i].sel, s) == 0) return gSlots[i].orig;
        }
        c = class_getSuperclass(c);
    }
    return NULL;
}

static void NoteHit(id self, SEL cmd) {
    __atomic_fetch_add(&gHits, 1L, __ATOMIC_RELAXED);
    Class c = object_getClass(self);
    if (class_isMetaClass(c)) c = object_getClass(c);
    // 不在 getter 里做 NSString 分配：高频调用 + 无 autorelease pool 的线程会堆内存
    snprintf(gLastCls, sizeof(gLastCls), "%s", class_getName(c));
    snprintf(gLastSel, sizeof(gLastSel), "%s", sel_getName(cmd));
}

#define HOOK_BODY(TYPE, ZERO)                                              \
    IMP o = OrigIMP(self, cmd);                                            \
    TYPE base = ZERO;                                                      \
    if (o) base = ((TYPE (*)(id, SEL))o)(self, cmd);                       \
    NoteHit(self, cmd);                                                    \
    if (!gEnabled) return base;                                            \
    __atomic_fetch_add(&gWrites, 1L, __ATOMIC_RELAXED);                    \
    return (TYPE)ModeValue((double)base);

static float hF(id self, SEL cmd)            { HOOK_BODY(float, 0.0f) }
static double hD(id self, SEL cmd)           { HOOK_BODY(double, 0.0) }
static int hI(id self, SEL cmd)              { HOOK_BODY(int, 0) }
static unsigned int hU(id self, SEL cmd)     { HOOK_BODY(unsigned int, 0) }
static long long hQ(id self, SEL cmd)        { HOOK_BODY(long long, 0) }
static unsigned long long hQU(id self, SEL cmd) { HOOK_BODY(unsigned long long, 0) }

static BOOL AlreadyHooked(Class cls, const char *sel) {
    for (int i = 0; i < gSlotCount; i++) {
        if (gSlots[i].cls == cls && strcmp(gSlots[i].sel, sel) == 0) return YES;
    }
    return NO;
}

static const EcpmRule *RuleFor(NSString *clsName, const char *selName) {
    NSString *low = @(selName).lowercaseString;
    for (int i = 0; i < RULE_COUNT; i++) {
        if (![clsName hasPrefix:@(kRules[i].prefix)]) continue;
        if ([low containsString:@(kRules[i].key)]) return &kRules[i];
    }
    return NULL;
}

static BOOL IsCandidateClass(NSString *name) {
    for (int i = 0; i < RULE_COUNT; i++) {
        if ([name hasPrefix:@(kRules[i].prefix)]) return YES;
    }
    return NO;
}

// 范围过滤：决定这条规则要不要挂
static BOOL ScopeAllows(NSString *clsName, const EcpmRule *r) {
    if (gScope == 2) return r->legacy;              // 安全：只旧表 9 条
    if (gScope == 1) {
        // 只 ecpm/cpm：不碰 price/bid/winprice，竞价请求和底价计算就不会被改坏
        if (strcmp(r->key, "ecpm") != 0 && strcmp(r->key, "cpm") != 0) return NO;
        NSString *low = clsName.lowercaseString;
        if ([low containsString:@"request"] || [low containsString:@"param"] ||
            [low containsString:@"config"] || [low containsString:@"setting"] ||
            [low containsString:@"bidding"] || [low containsString:@"slot"] ||
            [low containsString:@"reward"]  || [low containsString:@"verify"] ||
            [low containsString:@"claim"]   || [low containsString:@"callback"] ||
            [low containsString:@"track"]   || [low containsString:@"report"] ||
            [low containsString:@"stat"]    || [low containsString:@"cache"] ||
            [low containsString:@"mediation"] || [low containsString:@"adapter"] ||
            [low containsString:@"loader"] || [low containsString:@"service"]) return NO;
        return YES;
    }
    return YES;                                     // 全部 80 条
}

static BOOL HookOne(Class cls, Method m, const EcpmRule *rule, int ruleIndex) {
    const char *selName = sel_getName(method_getName(m));
    if (strchr(selName, ':')) return NO;                 // 只挂无参 getter
    if (strncmp(selName, "set", 3) == 0) return NO;      // 跳过 setter
    if (strstr(selName, "init") || strstr(selName, "alloc")) return NO;

    const char *enc = method_getTypeEncoding(m);
    if (!IsNumericType(enc)) return NO;                  // 对象/字符串返回值不碰

    if (AlreadyHooked(cls, selName)) return NO;
    if (gSlotCount >= RULE_COUNT) return NO;

    IMP newImp = NULL;
    switch (enc[0]) {
        case 'f': newImp = (IMP)hF;  break;
        case 'd': newImp = (IMP)hD;  break;
        case 'i': case 's': newImp = (IMP)hI;  break;
        case 'I': case 'S': newImp = (IMP)hU;  break;
        case 'q': case 'l': newImp = (IMP)hQ;  break;
        case 'Q': case 'L': newImp = (IMP)hQU; break;
        default: return NO;
    }

    IMP orig = method_setImplementation(m, newImp);
    if (!orig || orig == newImp) return NO;               // 已经是我们自己，别叠

    gSlots[gSlotCount].cls    = cls;
    gSlots[gSlotCount].sel    = selName;
    gSlots[gSlotCount].orig   = orig;
    gSlots[gSlotCount].method = m;
    gSlots[gSlotCount].rule   = ruleIndex;
    gSlotCount++;
    if (rule->legacy) gLegacyHooked++;
    return YES;
}

// 还原所有 hook（切安全模式 / 重启前用）
static void ResetHooks(void) {
    for (int i = 0; i < gSlotCount; i++) {
        if (gSlots[i].method && gSlots[i].orig) {
            method_setImplementation(gSlots[i].method, gSlots[i].orig);
        }
    }
    gSlotCount = 0;
    gLegacyHooked = 0;
    gMatchedClasses = 0;
    gCandidateClasses = 0;
}

// 扫一个类（含 metaclass）
static BOOL HookClass(Class cls, NSString *name) {
    if (!cls) return NO;
    BOOL any = NO;
    for (int pass = 0; pass < 2; pass++) {
        if (pass == 1 && gScope == 1) break;        // 只ecpm模式：只挂实例方法，不碰类方法
        Class target = (pass == 0) ? cls : object_getClass(cls);
        unsigned int mc = 0;
        Method *ms = class_copyMethodList(target, &mc);
        if (!ms) continue;
        for (unsigned int i = 0; i < mc && gSlotCount < RULE_COUNT; i++) {
            const char *selName = sel_getName(method_getName(ms[i]));
            const EcpmRule *rule = RuleFor(name, selName);
            if (!rule) continue;
            if (!ScopeAllows(name, rule)) continue;   // 按当前范围过滤
            // 领奖/校验/回调链路一个都不碰：挂上去会把领奖流程改坏
            if (strstr(selName, "reward") || strstr(selName, "verify") ||
                strstr(selName, "claim") || strstr(selName, "callback")) continue;
            int idx = (int)(rule - kRules);
            if (HookOne(target, ms[i], rule, idx)) any = YES;
        }
        free(ms);
    }
    return any;
}

static void ScanClasses(void) {
    if (gPaused) return;
    if (gScanning) return;
    gScanning = YES;

    unsigned int total = 0;
    Class *classes = objc_copyClassList(&total);
    long cand = 0, matched = 0;

    if (classes) {
        @autoreleasepool {
            for (unsigned int i = 0; i < total && gSlotCount < RULE_COUNT; i++) {
                Class cls = classes[i];
                if (!cls) continue;
                const char *cn = class_getName(cls);
                if (!cn) continue;
                NSString *name = @(cn);
                if (!IsCandidateClass(name)) continue;
                cand++;
                if (HookClass(cls, name)) matched++;
            }
        }
        free(classes);
    }

    gCandidateClasses = cand;
    gMatchedClasses   = matched;
    gScanning = NO;

    if (gLogOn) {
        NSLog(@"[eCPM] 扫描完成：候选类 %ld · 命中类 %ld · 已挂 %d/80 · 旧表 %ld/9",
              cand, matched, gSlotCount, gLegacyHooked);
    }
}

// 注意：v3.8.1 起彻底不挂 NSDictionary -objectForKey:。
// 上一版就是这么闪退的：hook 之后 NSUserDefaults / CFPreferences 读字典时
// 找不到对应子类的原 IMP 返回 nil，调用方直接崩。只挂广告 SDK 的 getter。

#pragma mark - 面板

static UIWindow *gPrevKeyWindow = nil;

@interface EcpmPanel : NSObject <UITextFieldDelegate>
@property (nonatomic, strong) UIWindow    *win;     // 悬浮球
@property (nonatomic, strong) UIWindow    *card;    // 面板
@property (nonatomic, strong) UIButton    *ball;
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UILabel     *line0;   // 范围：28万表  模式：替换  日志：开
@property (nonatomic, strong) UILabel     *line1;   // 范围：28万表80条（旧9+新71）· 类12／31 · 已挂13/80
@property (nonatomic, strong) UILabel     *line2;   // 旧表9条 5/9
@property (nonatomic, strong) UILabel     *line3;   // 替换=50000
@property (nonatomic, strong) UILabel     *line4;   // 命中585 · 已改写585
@property (nonatomic, strong) UILabel     *line5;   // 最近 ABUAdPackage.ecpm
@property (nonatomic, strong) UIButton    *modeBtn;
@property (nonatomic, strong) UIButton    *logBtn;
@property (nonatomic, strong) UIButton    *scopeBtn;
+ (instancetype)shared;
- (void)showBubble;
- (void)openCard;
@end

static EcpmPanel *gPanel = nil;

@implementation EcpmPanel

+ (instancetype)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gPanel = [EcpmPanel new]; });
    return gPanel;
}

- (UIWindowScene *)scene {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    }
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

- (UILabel *)label:(NSString *)t frame:(CGRect)f size:(CGFloat)s color:(UIColor *)c bold:(BOOL)b {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.text = t;
    l.font = b ? [UIFont boldSystemFontOfSize:s] : [UIFont systemFontOfSize:s];
    l.textColor = c;
    l.backgroundColor = UIColor.clearColor;
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)button:(NSString *)t frame:(CGRect)f color:(UIColor *)c {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = c;
    b.layer.cornerRadius = 8;
    b.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    return b;
}

- (void)showBubble {
    if (self.win) { self.win.hidden = NO; return; }
    UIWindowScene *sc = [self scene];
    if (!sc) return;

    UIWindow *w = [[UIWindow alloc] initWithWindowScene:sc];
    CGRect screen = UIScreen.mainScreen.bounds;
    w.frame = CGRectMake(screen.size.width - 64, 150, 54, 54);
    w.windowLevel = UIWindowLevelAlert + 2;
    w.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    w.rootViewController = vc;

    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(0, 0, 54, 54);
    [b setTitle:@"eCPM" forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    b.backgroundColor = [UIColor colorWithRed:1.0 green:0.45 blue:0.1 alpha:0.95];
    b.layer.cornerRadius = 27;
    b.layer.masksToBounds = YES;
    [b addTarget:self action:@selector(openCard) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:b];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panBall:)];
    [b addGestureRecognizer:pan];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(toggleSafe:)];
    lp.minimumPressDuration = 0.8;
    [b addGestureRecognizer:lp];

    self.ball = b;
    self.win = w;
    w.hidden = NO;
}

// 长按球 = 循环切范围（全部 -> 只ecpm -> 安全9条），没广告时的快捷开关
- (void)toggleSafe:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    if (!self.card) [self buildCard];
    [self cycleScope];
}

- (void)openCard {
    if (!self.card) [self buildCard];
    gPrevKeyWindow = UIApplication.sharedApplication.keyWindow;
    self.card.hidden = NO;
    [self.card makeKeyAndVisible];
    [self refresh];
}

- (void)buildCard {
    UIWindowScene *sc = [self scene];
    if (!sc) return;

    CGFloat W = 320, H = 452;
    UIWindow *w = [[UIWindow alloc] initWithWindowScene:sc];
    w.frame = CGRectMake((UIScreen.mainScreen.bounds.size.width - W) / 2, 70, W, H);
    w.windowLevel = UIWindowLevelAlert + 3;
    w.backgroundColor = UIColor.clearColor;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    w.rootViewController = vc;

    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, H)];
    box.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.97];
    box.layer.cornerRadius = 16;
    box.layer.masksToBounds = YES;
    [vc.view addSubview:box];

    UILabel *title = [self label:@"eCPM 数值控制 v3.8" frame:CGRectMake(16, 12, W - 32, 22) size:16 color:UIColor.whiteColor bold:YES];
    [box addSubview:title];

    [box addSubview:[self label:@"叠加=原值+输入，替换=强制等于输入；范围只认28万表里的类名+方法名"
                        frame:CGRectMake(16, 36, W - 32, 30) size:10.5 color:UIColor.grayColor bold:NO]];

    self.field = [[UITextField alloc] initWithFrame:CGRectMake(16, 70, 176, 38)];
    self.field.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    self.field.textColor = UIColor.whiteColor;
    self.field.keyboardType = UIKeyboardTypeDecimalPad;
    self.field.placeholder = @"输入 eCPM";
    self.field.font = [UIFont boldSystemFontOfSize:17];
    self.field.layer.cornerRadius = 8;
    self.field.text = [NSString stringWithFormat:@"%.0f", gValue];
    self.field.delegate = self;
    [box addSubview:self.field];

    UIButton *apply = [self button:@"应用" frame:CGRectMake(200, 70, 104, 38)
                             color:[UIColor colorWithRed:0.13 green:0.68 blue:0.32 alpha:1]];
    [apply addTarget:self action:@selector(apply) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:apply];

    self.modeBtn = [self button:(gMode == 0 ? @"模式:替换" : @"模式:叠加")
                          frame:CGRectMake(16, 116, 92, 32) color:[UIColor colorWithRed:0.22 green:0.52 blue:1 alpha:1]];
    [self.modeBtn addTarget:self action:@selector(toggleMode) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:self.modeBtn];

    self.logBtn = [self button:(gLogOn ? @"日志:开" : @"日志:关")
                         frame:CGRectMake(116, 116, 84, 32) color:[UIColor colorWithWhite:0.28 alpha:1]];
    [self.logBtn addTarget:self action:@selector(toggleLog) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:self.logBtn];

    UIButton *rescan = [self button:@"重新扫描" frame:CGRectMake(208, 116, 96, 32)
                              color:[UIColor colorWithRed:0.15 green:0.45 blue:0.95 alpha:1]];
    rescan.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [rescan addTarget:self action:@selector(rescan) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:rescan];

    // 范围：全部80条 / 只 ecpm+cpm / 安全(旧表9条)。没广告时先切「只ecpm」
    self.scopeBtn = [self button:[self scopeTitle] frame:CGRectMake(16, 152, 150, 32)
                           color:[UIColor colorWithRed:0.55 green:0.4 blue:0.85 alpha:1]];
    self.scopeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self.scopeBtn addTarget:self action:@selector(cycleScope) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:self.scopeBtn];

    // 一键还原：把挂过的 IMP 全还回去，停用改写
    UIButton *restore = [self button:@"还原全部" frame:CGRectMake(174, 152, 130, 32)
                               color:[UIColor colorWithRed:0.85 green:0.25 blue:0.2 alpha:1]];
    restore.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [restore addTarget:self action:@selector(restoreAll) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:restore];

    UIColor *green = [UIColor colorWithRed:0.5 green:0.92 blue:0.62 alpha:1];
    self.line0 = [self label:@"" frame:CGRectMake(16, 192, W - 32, 16) size:11.5 color:green bold:NO];
    self.line1 = [self label:@"" frame:CGRectMake(16, 210, W - 32, 16) size:11.5 color:green bold:NO];
    self.line2 = [self label:@"" frame:CGRectMake(16, 228, W - 32, 16) size:11.5 color:green bold:NO];
    self.line3 = [self label:@"" frame:CGRectMake(16, 246, W - 32, 16) size:11.5 color:green bold:NO];
    self.line4 = [self label:@"" frame:CGRectMake(16, 264, W - 32, 16) size:11.5 color:green bold:NO];
    self.line5 = [self label:@"" frame:CGRectMake(16, 282, W - 32, 16) size:11.5 color:[UIColor colorWithRed:0.95 green:0.75 blue:0.35 alpha:1] bold:NO];
    for (UILabel *l in @[self.line0, self.line1, self.line2, self.line3, self.line4, self.line5]) [box addSubview:l];

    [box addSubview:[self label:@"范围：28万表 —— 80条规则；没广告就把范围切「只ecpm」，还不行点「还原全部」。表外的类一个都不碰，进程里没有的类自动跳过；改完点应用，再让游戏刷一次广告。"
                        frame:CGRectMake(16, 300, W - 32, 86) size:9.5 color:[UIColor colorWithWhite:0.58 alpha:1] bold:NO]];

    UIButton *fold = [self button:@"收起" frame:CGRectMake(16, 400, 140, 36) color:[UIColor darkGrayColor]];
    [fold addTarget:self action:@selector(fold) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:fold];

    UIButton *hist = [self button:@"版本历史记录" frame:CGRectMake(164, 400, 140, 36)
                            color:[UIColor colorWithWhite:0.22 alpha:1]];
    hist.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [hist addTarget:self action:@selector(history) forControlEvents:UIControlEventTouchUpInside];
    [box addSubview:hist];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panCard:)];
    [title addGestureRecognizer:pan];
    title.userInteractionEnabled = YES;

    self.card = w;
    [self refresh];
}

- (void)refresh {
    NSString *scopeName = (gScope == 0 ? @"全部" : (gScope == 1 ? @"只ecpm" : @"安全"));
    self.line0.text = [NSString stringWithFormat:@"范围：28万表   模式：%@   日志：%@   范围:%@",
                       (gMode == 0 ? @"替换" : @"叠加"), (gLogOn ? @"开" : @"关"), scopeName];
    self.line1.text = [NSString stringWithFormat:@"范围：28万表80条（旧9+新71）· 类%ld／%ld · 已挂%d/80",
                       gMatchedClasses, gCandidateClasses, gSlotCount];
    self.line2.text = [NSString stringWithFormat:@"旧表9条 %ld/9", gLegacyHooked];
    self.line3.text = [NSString stringWithFormat:@"%@=%.0f", (gMode == 0 ? @"替换" : @"叠加"), gValue];
    self.line4.text = [NSString stringWithFormat:@"命中%ld · 已改写%ld", gHits, gWrites];
    if (gLastSel[0]) {
        self.line5.text = [NSString stringWithFormat:@"最近 %s.%s", gLastCls, gLastSel];
    } else {
        self.line5.text = @"最近 —";
    }
}

- (void)panBall:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:nil];
    CGRect f = self.win.frame;
    f.origin.x += t.x;
    f.origin.y += t.y;
    CGRect screen = UIScreen.mainScreen.bounds;
    f.origin.x = MAX(0, MIN(screen.size.width - 54, f.origin.x));
    f.origin.y = MAX(40, MIN(screen.size.height - 54, f.origin.y));
    self.win.frame = f;
    [g setTranslation:CGPointZero inView:nil];
}

- (void)panCard:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self.card];
    CGRect f = self.card.frame;
    f.origin.x += t.x;
    f.origin.y += t.y;
    self.card.frame = f;
    [g setTranslation:CGPointZero inView:self.card];
}

- (void)apply {
    gPaused = NO;
    gValue = self.field.text.doubleValue;
    gEnabled = YES;
    [self.field resignFirstResponder];

    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setDouble:gValue forKey:kDefValue];
    [d setBool:YES forKey:kDefOn];
    [d setInteger:gMode forKey:kDefMode];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        ScanClasses();
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
    });

    [self refresh];
    if (gLogOn) NSLog(@"[eCPM] 已应用 %.0f mode=%ld", gValue, (long)gMode);
}

- (void)toggleMode {
    gMode = (gMode == 0) ? 1 : 0;
    [self.modeBtn setTitle:(gMode == 0 ? @"模式:替换" : @"模式:叠加") forState:UIControlStateNormal];
    [NSUserDefaults.standardUserDefaults setInteger:gMode forKey:kDefMode];
    [self refresh];
}

- (void)toggleLog {
    gLogOn = !gLogOn;
    [self.logBtn setTitle:(gLogOn ? @"日志:开" : @"日志:关") forState:UIControlStateNormal];
    [NSUserDefaults.standardUserDefaults setBool:gLogOn forKey:kDefLog];
    [self refresh];
}

- (NSString *)scopeTitle {
    if (gScope == 0) return @"范围:全部80条";
    if (gScope == 1) return @"范围:只ecpm";
    return @"范围:安全9条";
}

// 切范围：先还原已挂 IMP，再按新范围重扫
- (void)cycleScope {
    gPaused = NO;
    gScope = (gScope + 1) % 3;
    [NSUserDefaults.standardUserDefaults setInteger:gScope forKey:@"EcpmCtrl38.scope"];
    [self.scopeBtn setTitle:[self scopeTitle] forState:UIControlStateNormal];
    ResetHooks();
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        ScanClasses();
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
    });
    [self refresh];
    if (gLogOn) NSLog(@"[eCPM] 范围 -> %ld", (long)gScope);
}

// 一键还原：所有 hook 回原样，停止改写
- (void)restoreAll {
    gPaused = YES;
    gEnabled = NO;
    ResetHooks();
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    [d setBool:NO forKey:kDefOn];
    [self refresh];
    if (gLogOn) NSLog(@"[eCPM] 已还原全部 hook（广告 SDK 下次加载就是原样）");
}

- (void)rescan {
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        ScanClasses();
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
    });
    [self refresh];
    if (gLogOn) NSLog(@"[eCPM] 重新扫描 已挂 %d/80", gSlotCount);
}

- (void)fold {
    self.card.hidden = YES;
    self.win.hidden = NO;
    if (gPrevKeyWindow && !gPrevKeyWindow.hidden) [gPrevKeyWindow makeKeyWindow];
}

- (void)history {
    NSString *msg =
        @"新功能版本 7.3.9 · 2周前\n"
        @"· 28万表并集整理完成，旧表9条并入，共80条\n"
        @"· 命中/改写计数与最近命中项实时刷新\n\n"
        @"v3.8.3 · 只ecpm模式再排除领奖/校验/上报类，不挂类方法\n"
        @"         · 补扫间隔 12 秒，减少反复扫描\n"
        @"v3.8.2 · 新增范围切换（全部/只ecpm/安全）与「还原全部」\n"
        @"         · 没广告时切「只ecpm」不碰 price/bid\n"
        @"v3.8.1 · 移除 NSDictionary hook（点应用闪退修复）\n"
        @"         · 长按球 = 切范围\n"
        @"v3.8 · 支持 ABUAdPackage、BaiduMobAd\n"
        @"v3.7 · 增加叠加模式\n"
        @"v3.6 · 穿山甲 / 优量汇 / 快手通杀\n"
        @"v1.0 · 初版";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"版本历史记录"
                                                              message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self.card.rootViewController presentViewController:a animated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }

@end

#pragma mark - 入口

__attribute__((constructor)) static void EcpmInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([bid isEqualToString:@"com.apple.springboard"]) return;

        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        gValue   = [d doubleForKey:kDefValue];
        gMode    = [d integerForKey:kDefMode];
        gEnabled = [d boolForKey:kDefOn];
        if ([d objectForKey:kDefLog]) gLogOn = [d boolForKey:kDefLog];
        gScope = [d integerForKey:@"EcpmCtrl38.scope"];
        if (gScope < 0 || gScope > 2) gScope = 1;   // 默认只 ecpm+cpm，保证广告能出
        if (gValue <= 0) gValue = 50000.0;

        [[EcpmPanel shared] showBubble];

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            ScanClasses();
            dispatch_async(dispatch_get_main_queue(), ^{ [[EcpmPanel shared] refresh]; });
        });

        // 广告 SDK 懒加载：定时补扫；挂载已稳定就把间隔拉长，避免反复扫描拖 CPU
        [NSTimer scheduledTimerWithTimeInterval:12.0 repeats:YES block:^(NSTimer *t) {
            if (gSlotCount >= RULE_COUNT) return;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ ScanClasses(); });
        }];
    });
}
