#import "ShopViewController.h"
#import "GameStore.h"
#import <StoreKit/StoreKit.h>

@interface ShopViewController () <UITableViewDataSource, UITableViewDelegate,
                                   SKProductsRequestDelegate, SKPaymentTransactionObserver>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *coinLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSArray<SKProduct *> *products;
@end

@implementation ShopViewController

- (instancetype)init {
    if (self = [super init]) {
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    }
    return self;
}

- (void)dealloc {
    [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"商店";
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.09 blue:0.13 alpha:1];

    self.coinLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, self.view.bounds.size.width - 32, 30)];
    self.coinLabel.font = [UIFont boldSystemFontOfSize:22];
    self.coinLabel.textColor = [UIColor colorWithRed:1 green:0.83 blue:0.35 alpha:1];
    [self.view addSubview:self.coinLabel];

    self.table = [[UITableView alloc] initWithFrame:CGRectMake(0, 52, self.view.bounds.size.width,
                                                               self.view.bounds.size.height - 52)
                                              style:UITableViewStyleInsetGrouped];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = self.view.backgroundColor;
    [self.view addSubview:self.table];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, 0, 0)];
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    self.statusLabel.numberOfLines = 0;

    [self loadProducts];
    [self refreshCoins];
}

- (void)refreshCoins {
    self.coinLabel.text = [NSString stringWithFormat:@"%ld 币", (long)[GameStore shared].coins];
}

#pragma mark - 商品

- (void)loadProducts {
    NSSet *ids = [NSSet setWithObjects:kSaoGameProductSmall, kSaoGameProductMid, kSaoGameProductLarge, nil];
    SKProductsRequest *req = [[SKProductsRequest alloc] initWithProductIdentifiers:ids];
    req.delegate = self;
    [req start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    NSArray *sorted = [response.products sortedUsingComparator:^NSComparisonResult(SKProduct *a, SKProduct *b) {
        return [a.price compare:b.price];
    }];
    self.products = sorted;
    [self.table reloadData];
    if (sorted.count == 0) {
        self.statusLabel.text = @"没取到商品：App Store Connect 里还没建这三个商品，或者这个包不是商店签名。\n商品 ID：com.fj.saogame.coins.300 / 1000 / 3000";
    }
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    self.statusLabel.text = [NSString stringWithFormat:@"商品加载失败：%@", error.localizedDescription];
    [self.table reloadData];
}

#pragma mark - 购买

- (void)buyProduct:(SKProduct *)product {
    if (![SKPaymentQueue canMakePayments]) {
        [self alert:@"这台设备关了 App 内购买"];
        return;
    }
    SKPayment *payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
    self.statusLabel.text = @"购买中…";
    [self.table reloadData];
}

- (void)restore {
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
    self.statusLabel.text = @"正在恢复购买…";
    [self.table reloadData];
}

- (NSInteger)coinsForProduct:(NSString *)productID {
    if ([productID isEqualToString:kSaoGameProductSmall]) return 300;
    if ([productID isEqualToString:kSaoGameProductMid]) return 1000;
    if ([productID isEqualToString:kSaoGameProductLarge]) return 3000;
    return 100;
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    for (SKPaymentTransaction *t in transactions) {
        switch (t.transactionState) {
            case SKPaymentTransactionStatePurchased:
            case SKPaymentTransactionStateRestored: {
                NSInteger coins = [self coinsForProduct:t.payment.productIdentifier];
                [[GameStore shared] addCoins:coins];
                [queue finishTransaction:t];
                [self refreshCoins];
                self.statusLabel.text = [NSString stringWithFormat:@"到账 %ld 币", (long)coins];
                [self.table reloadData];
                [self alert:[NSString stringWithFormat:@"+%ld 币", (long)coins]];
                break;
            }
            case SKPaymentTransactionStateFailed: {
                [queue finishTransaction:t];
                self.statusLabel.text = @"购买失败 / 已取消";
                [self.table reloadData];
                break;
            }
            case SKPaymentTransactionStateDeferred:
                self.statusLabel.text = @"等待家长批准…";
                [self.table reloadData];
                break;
            default:
                break;
        }
    }
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    self.statusLabel.text = @"恢复完成";
    [self.table reloadData];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return MAX(1, (NSInteger)self.products.count);
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"金币礼包" : @"其它";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"真机购买需要：App Store Connect 建好商品 + 用商店签名/沙盒账号测试。TrollStore 装的非商店包买不了，别浪费时间。";
    }
    return self.statusLabel.text;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"cell"];
    cell.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
    cell.textLabel.textColor = UIColor.whiteColor;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1];

    if (indexPath.section == 0) {
        if (self.products.count == 0) {
            cell.textLabel.text = @"商品加载中 / 未配置";
            cell.detailTextLabel.text = @"点一下重试";
        } else {
            SKProduct *p = self.products[indexPath.row];
            cell.textLabel.text = p.localizedTitle ?: p.productIdentifier;
            NSNumberFormatter *f = [NSNumberFormatter new];
            f.numberStyle = NSNumberFormatterCurrencyStyle;
            f.locale = p.priceLocale;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ 币",
                                         [f stringFromNumber:p.price],
                                         @([self coinsForProduct:p.productIdentifier])];
        }
    } else {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"恢复购买";
            cell.detailTextLabel.text = @"换机/重装后点这个";
        } else {
            cell.textLabel.text = @"本地体验 +500 币";
            cell.detailTextLabel.text = @"没上架时用来试玩法，不计入真实购买";
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (self.products.count == 0) {
            [self loadProducts];
        } else {
            [self buyProduct:self.products[indexPath.row]];
        }
    } else if (indexPath.row == 0) {
        [self restore];
    } else {
        [[GameStore shared] addCoins:500];
        [self refreshCoins];
        self.statusLabel.text = @"已加 500 币（本地体验）";
        [self.table reloadData];
    }
}

- (void)alert:(NSString *)text {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:text
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
}

@end
