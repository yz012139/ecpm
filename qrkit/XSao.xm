//
//  XSao.xm
//  扫码插件入口：宿主 App 里加一个悬浮「扫」按钮，点开就是苹果版扫码页
//  过滤器在 XSao.plist 里改 Bundle ID
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "QRScannerViewController.h"

static UIWindow *gSaoWindow = nil;
static UIButton *gSaoButton = nil;

static UIViewController *SaoTopViewController(void) {
    UIWindow *key = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
        if (key) break;
    }
    if (!key) key = UIApplication.sharedApplication.windows.firstObject;

    UIViewController *vc = key.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:[UINavigationController class]]) {
        vc = ((UINavigationController *)vc).topViewController;
    } else if ([vc isKindOfClass:[UITabBarController class]]) {
        vc = ((UITabBarController *)vc).selectedViewController;
    }
    return vc;
}

static void SaoPresentScanner(void) {
    UIViewController *top = SaoTopViewController();
    if (!top || [top isKindOfClass:[QRScannerViewController class]]) return;

    QRScannerViewController *scanner = [QRScannerViewController scannerWithCompletion:nil];
    __weak QRScannerViewController *weakScanner = scanner;
    scanner.completion = ^(NSString *text, NSString *format) {
        UIPasteboard.generalPasteboard.string = text;

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"扫码结果（%@）", format]
                                                message:text
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"复制并关闭"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            [weakScanner dismissViewControllerAnimated:YES completion:nil];
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"继续扫"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
        [weakScanner presentViewController:alert animated:YES completion:nil];
    };
    scanner.modalPresentationStyle = UIModalPresentationFullScreen;
    [top presentViewController:scanner animated:YES completion:nil];
}

static void SaoBuildButton(void) {
    if (gSaoWindow) { gSaoWindow.hidden = NO; return; }
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
    }
    if (!scene) return;

    UIWindow *win = [[UIWindow alloc] initWithWindowScene:scene];
    CGFloat side = 54;
    CGSize screen = UIScreen.mainScreen.bounds.size;
    win.frame = CGRectMake(screen.width - side - 10, screen.height * 0.45, side, side);
    win.windowLevel = UIWindowLevelAlert + 1;
    win.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    win.rootViewController = vc;

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(0, 0, side, side);
    [btn setTitle:@"扫" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    btn.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.9 alpha:0.95];
    btn.layer.cornerRadius = side / 2.0;
    btn.layer.masksToBounds = YES;
    [btn addTarget:btn action:@selector(saoTapped) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:btn];

    [btn addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(saoPan:)]];
    objc_setAssociatedObject(btn, "sao.pan", vc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    gSaoWindow = win;
    gSaoButton = btn;
    win.hidden = NO;
}

@interface UIButton (SaoAction)
- (void)saoTapped;
- (void)saoPan:(UIPanGestureRecognizer *)g;
@end

@implementation UIButton (SaoAction)

- (void)saoTapped {
    SaoPresentScanner();
}

- (void)saoPan:(UIPanGestureRecognizer *)g {
    UIWindow *win = gSaoWindow;
    if (!win) return;
    CGPoint t = [g translationInView:nil];
    CGRect f = win.frame;
    f.origin.x += t.x;
    f.origin.y += t.y;
    win.frame = f;
    [g setTranslation:CGPointZero inView:nil];
}

@end

__attribute__((constructor)) static void SaoInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SaoBuildButton();
    });
}
