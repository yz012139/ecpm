//
//  QRScannerViewController.h
//  苹果版扫码控件（AVFoundation + Vision），对标 Android com.uuzuche.lib_zxing
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class QRScannerViewController;

@protocol QRScannerDelegate <NSObject>
@optional
- (void)qrScanner:(QRScannerViewController *)scanner
    didFinishWithResult:(NSString *)text
                 format:(NSString *)format;
- (void)qrScannerDidCancel:(QRScannerViewController *)scanner;
@end

@interface QRScannerViewController : UIViewController

/// 扫到结果回调（text=原始内容，format=码制，例如 QR / EAN13）
@property (nonatomic, copy, nullable) void (^completion)(NSString *text, NSString *format);
@property (nonatomic, weak, nullable) id<QRScannerDelegate> delegate;

/// 取景框（相对 view 的坐标），默认屏幕中央 260x260；只认框内的码
@property (nonatomic, assign) CGRect scanRect;

/// 连续扫（默认 NO：扫到一条就停）。YES 时每次都回调
@property (nonatomic, assign) BOOL continuous;

/// 识别成功震动（默认 YES）
@property (nonatomic, assign) BOOL vibrateOnSuccess;

/// 是否显示相册按钮（默认 YES）
@property (nonatomic, assign) BOOL showsPhotoButton;

/// 便捷构造
+ (instancetype)scannerWithCompletion:(nullable void (^)(NSString *, NSString *))completion;

/// 相册图片解码（不弹相机）
+ (nullable NSString *)decodeImage:(UIImage *)image;

@end

NS_ASSUME_NONNULL_END
