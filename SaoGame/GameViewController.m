#import "GameViewController.h"
#import "GameStore.h"
#import "ShopViewController.h"
#import "QRScannerViewController.h"
#import "QRCodeUtil.h"

@interface GameViewController ()
@property (nonatomic, strong) UILabel *coinLabel;
@property (nonatomic, strong) UILabel *statLabel;
@property (nonatomic, strong) UITextView *logView;
@end

@implementation GameViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"扫码小游戏";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.13 alpha:1];

    [self buildUI];
    [self refresh];
}

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;

    self.coinLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 24, w - 40, 46)];
    self.coinLabel.font = [UIFont boldSystemFontOfSize:38];
    self.coinLabel.textColor = [UIColor colorWithRed:1 green:0.83 blue:0.35 alpha:1];
    [self.view addSubview:self.coinLabel];

    self.statLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 76, w - 40, 20)];
    self.statLabel.font = [UIFont systemFontOfSize:13];
    self.statLabel.textColor = [UIColor colorWithWhite:0.65 alpha:1];
    [self.view addSubview:self.statLabel];

    UIButton *scan = [self button:@"扫 一 扫" color:[UIColor colorWithRed:0.12 green:0.55 blue:0.92 alpha:1]];
    scan.frame = CGRectMake(20, 112, w - 40, 64);
    scan.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [scan addTarget:self action:@selector(scanTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:scan];

    CGFloat y = 194;
    NSArray *titles = @[ @"抽卡（50 币）", @"商店", @"卡册", @"重置" ];
    NSArray *sels = @[ @"drawTapped", @"shopTapped", @"cardsTapped", @"resetTapped" ];
    CGFloat bw = (w - 40 - 24) / 2.0;
    for (int i = 0; i < titles.count; i++) {
        UIButton *b = [self button:titles[i] color:[UIColor colorWithWhite:0.17 alpha:1]];
        CGFloat x = 20 + (i % 2) * (bw + 24);
        CGFloat yy = y + (i / 2) * 60;
        b.frame = CGRectMake(x, yy, bw, 48);
        b.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        SEL sel = NSSelectorFromString(sels[i]);
        [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
    }

    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(20, y + 126, w - 40, 34)];
    tip.text = @"扫到新内容 +20 币，重复 +2 币\n60 秒内连扫有连击加成";
    tip.numberOfLines = 2;
    tip.font = [UIFont systemFontOfSize:12];
    tip.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    tip.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:tip];

    CGFloat logY = y + 170;
    self.logView = [[UITextView alloc] initWithFrame:CGRectMake(16, logY, w - 32, self.view.bounds.size.height - logY - 24)];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1];
    self.logView.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    self.logView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.logView.editable = NO;
    self.logView.layer.cornerRadius = 10;
    self.logView.text = @"";
    [self.view addSubview:self.logView];
}

- (UIButton *)button:(NSString *)title color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.layer.cornerRadius = 12;
    return b;
}

- (void)refresh {
    GameStore *s = [GameStore shared];
    self.coinLabel.text = [NSString stringWithFormat:@"%ld 币", (long)s.coins];
    self.statLabel.text = [NSString stringWithFormat:@"已扫码 %ld 次 · 卡牌 %lu 种",
                           (long)s.scanCount, (unsigned long)s.cards.count];
}

- (void)appendLog:(NSString *)text {
    self.logView.text = [NSString stringWithFormat:@"%@\n%@", text, self.logView.text ?: @""];
    NSRange top = NSMakeRange(0, 0);
    [self.logView scrollRangeToVisible:top];
}

#pragma mark - 动作

- (void)scanTapped {
    QRScannerViewController *vc = [QRScannerViewController scannerWithCompletion:nil];
    __weak typeof(self) weakSelf = self;
    __weak QRScannerViewController *weakVC = vc;
    vc.completion = ^(NSString *text, NSString *format) {
        [weakVC dismissViewControllerAnimated:YES completion:^{
            [weakSelf handleScan:text format:format];
        }];
    };
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)handleScan:(NSString *)text format:(NSString *)format {
    NSDictionary *reward = [[GameStore shared] rewardForPayload:text];
    NSInteger coins = [reward[@"coins"] integerValue];
    BOOL isNew = [reward[@"isNew"] boolValue];
    NSInteger streak = [reward[@"streak"] integerValue];

    NSString *shortText = text.length > 60 ? [text substringToIndex:60] : text;
    [self appendLog:[NSString stringWithFormat:@"[%@] %@ → +%ld 币%@%@",
                     format, shortText, (long)coins,
                     isNew ? @"（新）" : @"（重复）",
                     streak > 1 ? [NSString stringWithFormat:@" 连击%d", (int)streak] : @""]];
    [self refresh];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"+%ld 币", (long)coins]
                                            message:[NSString stringWithFormat:@"%@：%@\n%@",
                                                     format, shortText,
                                                     isNew ? @"首次扫到，奖励翻倍" : @"这张之前扫过了"]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续扫" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self scanTapped]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"收下" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)drawTapped {
    NSDictionary *card = [[GameStore shared] drawCard];
    if (!card) {
        [self toast:@"币不够，去商店补点"];
        return;
    }
    [self refresh];

    NSInteger star = [card[@"star"] integerValue];
    NSString *stars = [@"" stringByPaddingToLength:star withString:@"★" startingAtIndex:0];
    NSString *title = [NSString stringWithFormat:@"%@ %@", stars, card[@"name"]];
    NSString *msg = card[@"desc"];
    if (![card[@"isNew"] boolValue]) {
        msg = [NSString stringWithFormat:@"%@\n\n重复卡，返还 10 币", msg];
    }
    [self appendLog:[NSString stringWithFormat:@"抽卡 → %@", title]];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"再来一次" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *a) { [self drawTapped]; }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)shopTapped {
    ShopViewController *shop = [ShopViewController new];
    [self.navigationController pushViewController:shop animated:YES];
}

- (void)cardsTapped {
    GameStore *s = [GameStore shared];
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *card in [s allCards]) {
        NSInteger owned = [s.cards[card[@"name"]] integerValue];
        NSInteger star = [card[@"star"] integerValue];
        NSString *stars = [@"" stringByPaddingToLength:star withString:@"★" startingAtIndex:0];
        [text appendFormat:@"%@ %@  ×%ld\n", stars, card[@"name"], (long)owned];
    }
    if (text.length == 0) text = [@"还没抽过卡" mutableCopy];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"卡册" message:text
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空存档？"
                                                                   message:@"金币、卡牌、扫码记录都会没"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *a) {
        [[GameStore shared] resetProgress];
        [self refresh];
        [self appendLog:@"存档已清空"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"算了" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refresh];
}

- (void)toast:(NSString *)text {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:text
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
}

@end
