#import "GameStore.h"

NSString *const kSaoGameProductSmall = @"com.fj.saogame.coins.300";
NSString *const kSaoGameProductMid   = @"com.fj.saogame.coins.1000";
NSString *const kSaoGameProductLarge = @"com.fj.saogame.coins.3000";

static NSString *const kSaveKey = @"SaoGame.save.v1";
static const NSInteger kDrawCost = 50;

@implementation GameStore {
    NSMutableDictionary *_save;
    NSMutableDictionary<NSString *, NSNumber *> *_cards;
    NSMutableDictionary<NSString *, NSString *> *_seen;   // payload -> dayKey
}

+ (instancetype)shared {
    static GameStore *g;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ g = [GameStore new]; });
    return g;
}

- (instancetype)init {
    if (self = [super init]) {
        NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:kSaveKey];
        _save = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
        _cards = [(_save[@"cards"] ?: @{}) mutableCopy];
        _seen = [(_save[@"seen"] ?: @{}) mutableCopy];
    }
    return self;
}

#pragma mark - 读

- (NSInteger)coins { return [_save[@"coins"] integerValue]; }
- (NSInteger)scanCount { return [_save[@"scanCount"] integerValue]; }
- (NSDictionary<NSString *, NSNumber *> *)cards { return [_cards copy]; }

#pragma mark - 存

- (void)persist {
    _save[@"coins"] = @(self.coins);
    _save[@"scanCount"] = @(self.scanCount);
    _save[@"cards"] = _cards;
    _save[@"seen"] = _seen;
    [NSUserDefaults.standardUserDefaults setObject:_save forKey:kSaveKey];
}

- (NSString *)todayKey {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd";
    return [f stringFromDate:[NSDate date]];
}

#pragma mark - 金币

- (void)addCoins:(NSInteger)amount {
    if (amount <= 0) return;
    _save[@"coins"] = @(self.coins + amount);
    [self persist];
}

- (BOOL)spendCoins:(NSInteger)amount {
    if (amount <= 0) return YES;
    if (self.coins < amount) return NO;
    _save[@"coins"] = @(self.coins - amount);
    [self persist];
    return YES;
}

#pragma mark - 扫码奖励

- (NSDictionary *)rewardForPayload:(NSString *)payload {
    if (payload.length == 0) return @{ @"coins": @0, @"isNew": @NO, @"streak": @0 };

    NSString *day = [self todayKey];
    BOOL isNew = ![_seen[payload] isEqualToString:day];
    if (isNew) _seen[payload] = day;

    // 跨天清一次去重表，防止无限增长
    if (![_save[@"day"] isEqualToString:day]) {
        _save[@"day"] = day;
        [_seen removeAllObjects];
        _seen[payload] = day;
        isNew = YES;
    }

    NSInteger coins = isNew ? 20 : 2;
    NSInteger streak = 0;
    NSTimeInterval last = [_save[@"lastScan"] doubleValue];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (last > 0 && now - last < 60) {
        streak = (NSInteger)MIN(5, [_save[@"streak"] integerValue] + 1);
        coins += streak * 2;
    } else {
        streak = 1;
    }
    _save[@"streak"] = @(streak);
    _save[@"lastScan"] = @(now);
    _save[@"scanCount"] = @(self.scanCount + 1);

    [self addCoins:coins];
    return @{ @"coins": @(coins), @"isNew": @(isNew), @"streak": @(streak) };
}

#pragma mark - 卡池

- (NSArray<NSDictionary *> *)allCards {
    static NSArray *pool;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pool = @[
            @{ @"name": @"铜钥匙",   @"star": @1, @"weight": @30, @"desc": @"打开第一道门" },
            @{ @"name": @"旧车票",   @"star": @1, @"weight": @28, @"desc": @"去往没人记得的站台" },
            @{ @"name": @"灰羽毛",   @"star": @1, @"weight": @26, @"desc": @"落在窗台的那一根" },
            @{ @"name": @"碎镜片",   @"star": @2, @"weight": @20, @"desc": @"照出另一个你" },
            @{ @"name": @"夜班灯",   @"star": @2, @"weight": @18, @"desc": @"三点了还亮着" },
            @{ @"name": @"纸月亮",   @"star": @2, @"weight": @16, @"desc": @"剪下来挂在床头" },
            @{ @"name": @"雨里唱片", @"star": @3, @"weight": @10, @"desc": @"B 面一直是雨声" },
            @{ @"name": @"猫的眼睛", @"star": @3, @"weight": @9,  @"desc": @"黑夜里两盏灯" },
            @{ @"name": @"空白信",   @"star": @3, @"weight": @8,  @"desc": @"写了又擦掉的那种" },
            @{ @"name": @"蓝火焰",   @"star": @4, @"weight": @4,  @"desc": @"烧不暖，但很好看" },
            @{ @"name": @"第七个梦", @"star": @4, @"weight": @3,  @"desc": @"醒来就记不住" },
            @{ @"name": @"富江的心", @"star": @5, @"weight": @1,  @"desc": @"切下来还会再长一颗" },
        ];
    });
    return pool;
}

- (NSDictionary *)drawCard {
    if (![self spendCoins:kDrawCost]) return nil;

    NSArray<NSDictionary *> *pool = [self allCards];
    NSInteger total = 0;
    for (NSDictionary *c in pool) total += [c[@"weight"] integerValue];
    NSInteger roll = arc4random_uniform((uint32_t)MAX(1, total));
    NSInteger acc = 0;
    NSDictionary *picked = pool.lastObject;
    for (NSDictionary *c in pool) {
        acc += [c[@"weight"] integerValue];
        if (roll < acc) { picked = c; break; }
    }

    NSString *name = picked[@"name"];
    NSInteger owned = [_cards[name] integerValue];
    _cards[name] = @(owned + 1);
    BOOL isNew = (owned == 0);
    if (!isNew) {
        // 重复卡返 10 币
        [self addCoins:10];
    }
    [self persist];

    NSMutableDictionary *result = [picked mutableCopy];
    result[@"isNew"] = @(isNew);
    result[@"refund"] = isNew ? @0 : @10;
    return result;
}

- (void)resetProgress {
    [_save removeAllObjects];
    [_cards removeAllObjects];
    [_seen removeAllObjects];
    [self persist];
}

@end
