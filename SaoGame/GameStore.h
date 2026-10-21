//
//  GameStore.h
//  存档 / 金币 / 卡池 / 扫码奖励（对标原 App 的扫码去重与积分逻辑）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kSaoGameProductSmall;   // 300 币
extern NSString *const kSaoGameProductMid;     // 1000 币
extern NSString *const kSaoGameProductLarge;   // 3000 币

@interface GameStore : NSObject

@property (nonatomic, assign, readonly) NSInteger coins;
@property (nonatomic, assign, readonly) NSInteger scanCount;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSNumber *> *cards;

+ (instancetype)shared;

/// 扫码奖励：返回 @{ @"coins": @(n), @"isNew": @(YES/NO), @"streak": @(n) }
- (NSDictionary *)rewardForPayload:(NSString *)payload;

- (BOOL)spendCoins:(NSInteger)amount;
- (void)addCoins:(NSInteger)amount;

/// 抽卡（自动扣 50 币），返回卡片字典；币不够返回 nil
- (nullable NSDictionary *)drawCard;

/// 卡池全表
- (NSArray<NSDictionary *> *)allCards;

- (void)resetProgress;

@end

NS_ASSUME_NONNULL_END
