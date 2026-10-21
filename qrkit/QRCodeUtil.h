//
//  QRCodeUtil.h
//  生成 / 解码二维码（对标 Android CodeUtils.createQRCode / decodeQRCode）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QRCodeUtil : NSObject

/// 生成二维码 UIImage
/// @param content 内容
/// @param size    边长（像素）
/// @param logo    中间 logo，可空
+ (nullable UIImage *)qrImageWithString:(NSString *)content
                                   size:(CGFloat)size
                                   logo:(nullable UIImage *)logo;

/// 从图片里解码（Vision 优先，CIDetector 兜底）
+ (nullable NSString *)stringFromImage:(UIImage *)image;

/// 条形码也一起试
+ (nullable NSString *)stringFromImage:(UIImage *)image symbologies:(nullable NSArray<NSString *> *)symbologies;

@end

NS_ASSUME_NONNULL_END
