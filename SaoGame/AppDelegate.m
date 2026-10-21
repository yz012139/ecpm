#import "AppDelegate.h"
#import "GameViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    GameViewController *root = [GameViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];
    nav.navigationBar.translucent = NO;
    nav.navigationBar.barTintColor = [UIColor colorWithRed:0.09 green:0.11 blue:0.16 alpha:1];
    nav.navigationBar.tintColor = UIColor.whiteColor;
    nav.navigationBar.titleTextAttributes = @{ NSForegroundColorAttributeName : UIColor.whiteColor };
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
