//
//  QRCodeUtil.m
//  二维码生成 / 图片解码
//

#import "QRCodeUtil.h"
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>

@implementation QRCodeUtil

#pragma mark - 生成

+ (UIImage *)qrImageWithString:(NSString *)content size:(CGFloat)size logo:(UIImage *)logo {
    if (content.length == 0 || size <= 0) return nil;

    CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [filter setDefaults];
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    [filter setValue:data forKey:@"inputMessage"];
    [filter setValue:@"H" forKey:@"inputCorrectionLevel"];   // 30% 容错，够贴 logo

    CIImage *output = filter.outputImage;
    if (!output) return nil;

    CGFloat scale = size / output.extent.size.width;
    CIImage *scaled = [output imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    UIImage *base = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        UIImage *tmp = [UIImage imageWithCIImage:scaled];
        [tmp drawInRect:CGRectMake(0, 0, size, size)];
    }];
    if (!logo) return base;

    CGFloat logoSize = size * 0.22;
    CGRect logoRect = CGRectMake((size - logoSize) / 2.0, (size - logoSize) / 2.0, logoSize, logoSize);
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [base drawInRect:CGRectMake(0, 0, size, size)];
        // 白底，防止二维码点阵透出来
        [[UIColor whiteColor] setFill];
        UIBezierPath *bg = [UIBezierPath bezierPathWithRoundedRect:logoRect cornerRadius:logoSize * 0.18];
        [bg fill];
        [logo drawInRect:CGRectInset(logoRect, logoSize * 0.08, logoSize * 0.08)];
    }];
}

#pragma mark - 解码

+ (NSString *)stringFromImage:(UIImage *)image {
    return [self stringFromImage:image symbologies:nil];
}

+ (NSString *)stringFromImage:(UIImage *)image symbologies:(NSArray<NSString *> *)symbologies {
    if (!image) return nil;

    // 1) Vision：支持二维码 + 一维码 + PDF417
    if (@available(iOS 11.0, *)) {
        VNDetectBarcodesRequest *request = [[VNDetectBarcodesRequest alloc] initWithCompletionHandler:nil];
        if (symbologies.count > 0) request.symbologies = symbologies;
        VNImageRequestHandler *handler =
            [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage
                                               orientation:kCGImagePropertyOrientationUp
                                                   options:@{}];
        NSError *err = nil;
        if ([handler performRequests:@[ request ] error:&err] && !err) {
            for (VNObservation *obs in request.results) {
                if ([obs isKindOfClass:[VNBarcodeObservation class]]) {
                    NSString *payload = [(VNBarcodeObservation *)obs payloadStringValue];
                    if (payload.length > 0) return payload;
                }
            }
        }
    }

    // 2) CIDetector 兜底（老系统 / Vision 抽风）
    CIImage *ci = [CIImage imageWithCGImage:image.CGImage];
    CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                              context:nil
                                              options:@{ CIDetectorAccuracy : CIDetectorAccuracyHigh }];
    for (CIFeature *f in [detector featuresInImage:ci]) {
        if ([f isKindOfClass:[CIQRCodeFeature class]]) {
            NSString *payload = [(CIQRCodeFeature *)f messageString];
            if (payload.length > 0) return payload;
        }
    }
    return nil;
}

@end
