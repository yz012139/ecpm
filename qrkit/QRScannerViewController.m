//
//  QRScannerViewController.m
//  扫码页：AVCaptureSession 取帧 -> Vision 解码 -> 回调
//  流程和 Android com.uuzuche.lib_zxing 完全对应：
//     CameraManager(预览/对焦/闪光) -> PreviewCallback(取帧) ->
//     DecodeHandler(裁剪取景框 + MultiFormatReader) -> 结果回调
//

#import "QRScannerViewController.h"
#import "QRCodeUtil.h"

#import <AVFoundation/AVFoundation.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>
#import <AudioToolbox/AudioToolbox.h>

static const CGFloat kScanBoxSide = 260.0;

@interface QRScannerViewController () <
    AVCaptureVideoDataOutputSampleBufferDelegate,
    UIImagePickerControllerDelegate,
    UINavigationControllerDelegate
>

@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVCaptureVideoDataOutput *output;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) dispatch_queue_t outputQueue;

@property (nonatomic, strong) UIView *maskView;
@property (nonatomic, strong) CAShapeLayer *maskLayer;
@property (nonatomic, strong) CAShapeLayer *cornerLayer;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UIButton *torchButton;
@property (nonatomic, strong) UIButton *photoButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UILabel *deniedLabel;

@property (nonatomic, assign) BOOL isProcessing;
@property (nonatomic, assign) NSTimeInterval lastScanTime;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL torchOn;

@end

@implementation QRScannerViewController

+ (instancetype)scannerWithCompletion:(void (^)(NSString *, NSString *))completion {
    QRScannerViewController *vc = [QRScannerViewController new];
    vc.completion = completion;
    vc.continuous = NO;
    vc.vibrateOnSuccess = YES;
    vc.showsPhotoButton = YES;
    return vc;
}

- (instancetype)init {
    if (self = [super init]) {
        _continuous = NO;
        _vibrateOnSuccess = YES;
        _showsPhotoButton = YES;
        _outputQueue = dispatch_queue_create("qrcode.scan.output", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

+ (NSString *)decodeImage:(UIImage *)image {
    return [QRCodeUtil stringFromImage:image];
}

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.scanRect = CGRectMake((CGRectGetWidth(self.view.bounds) - kScanBoxSide) / 2.0,
                               (CGRectGetHeight(self.view.bounds) - kScanBoxSide) / 2.0 - 30,
                               kScanBoxSide, kScanBoxSide);

    [self buildUI];
    [self checkPermission];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(appWillResign)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    if (self.session) [self startSession];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopSession];
}

- (void)appWillResign {
    [self stopSession];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
    [self layoutMask];
}

#pragma mark - UI

- (void)buildUI {
    // 取景遮罩 + 中间镂空
    self.maskView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.maskView.backgroundColor = [UIColor clearColor];
    self.maskView.userInteractionEnabled = NO;
    [self.view addSubview:self.maskView];

    self.maskLayer = [CAShapeLayer layer];
    self.maskLayer.fillRule = kCAFillRuleEvenOdd;
    self.maskLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.45].CGColor;
    [self.maskView.layer addSublayer:self.maskLayer];

    // 四角
    self.cornerLayer = [CAShapeLayer layer];
    self.cornerLayer.strokeColor = [UIColor colorWithRed:0.3 green:0.95 blue:0.6 alpha:1].CGColor;
    self.cornerLayer.fillColor = UIColor.clearColor.CGColor;
    self.cornerLayer.lineWidth = 4;
    self.cornerLayer.lineCap = kCALineCapRound;
    [self.maskView.layer addSublayer:self.cornerLayer];

    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.hintLabel.text = @"将二维码 / 条形码放入框内，即可自动扫描";
    self.hintLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
    self.hintLabel.font = [UIFont systemFontOfSize:13];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.numberOfLines = 2;
    [self.view addSubview:self.hintLabel];

    self.torchButton = [self toolButton:@"手电筒" action:@selector(toggleTorch)];
    [self.view addSubview:self.torchButton];

    self.photoButton = [self toolButton:@"相册" action:@selector(openAlbum)];
    [self.view addSubview:self.photoButton];

    self.closeButton = [self toolButton:@"取消" action:@selector(close)];
    [self.view addSubview:self.closeButton];

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapToFocus:)];
    [self.view addGestureRecognizer:tap];
}

- (UIButton *)toolButton:(NSString *)title action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(0, 0, 84, 40);
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    b.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.75];
    b.layer.cornerRadius = 20;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)layoutMask {
    CGRect bounds = self.view.bounds;
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:bounds];
    [path appendPath:[UIBezierPath bezierPathWithRoundedRect:self.scanRect cornerRadius:10]];
    self.maskLayer.path = path.CGPath;
    self.maskLayer.frame = bounds;
    self.cornerLayer.frame = bounds;

    CGFloat len = 24;
    UIBezierPath *corners = [UIBezierPath bezierPath];
    CGRect r = self.scanRect;
    // 左上
    [corners moveToPoint:CGPointMake(r.origin.x, r.origin.y + len)];
    [corners addLineToPoint:CGPointMake(r.origin.x, r.origin.y)];
    [corners addLineToPoint:CGPointMake(r.origin.x + len, r.origin.y)];
    // 右上
    [corners moveToPoint:CGPointMake(CGRectGetMaxX(r) - len, r.origin.y)];
    [corners addLineToPoint:CGPointMake(CGRectGetMaxX(r), r.origin.y)];
    [corners addLineToPoint:CGPointMake(CGRectGetMaxX(r), r.origin.y + len)];
    // 右下
    [corners moveToPoint:CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r) - len)];
    [corners addLineToPoint:CGPointMake(CGRectGetMaxX(r), CGRectGetMaxY(r))];
    [corners addLineToPoint:CGPointMake(CGRectGetMaxX(r) - len, CGRectGetMaxY(r))];
    // 左下
    [corners moveToPoint:CGPointMake(r.origin.x + len, CGRectGetMaxY(r))];
    [corners addLineToPoint:CGPointMake(r.origin.x, CGRectGetMaxY(r))];
    [corners addLineToPoint:CGPointMake(r.origin.x, CGRectGetMaxY(r) - len)];
    self.cornerLayer.path = corners.CGPath;

    CGFloat w = CGRectGetWidth(bounds);
    CGFloat y = CGRectGetMaxY(self.scanRect) + 24;
    self.hintLabel.frame = CGRectMake(30, y, w - 60, 40);

    CGFloat bottom = CGRectGetHeight(bounds) - 44;
    self.photoButton.frame = CGRectMake(24, bottom, 84, 40);
    self.closeButton.frame = CGRectMake((w - 84) / 2.0, bottom, 84, 40);
    self.torchButton.frame = CGRectMake(w - 108, bottom, 84, 40);
}

#pragma mark - 权限

- (void)checkPermission {
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                 completionHandler:^(BOOL granted) {
                                     dispatch_async(dispatch_get_main_queue(), ^{
                                         if (granted) [weakSelf setupSession];
                                         else [weakSelf showDenied];
                                     });
                                 }];
    } else if (status == AVAuthorizationStatusDenied || status == AVAuthorizationStatusRestricted) {
        [self showDenied];
    } else {
        [self setupSession];
    }
}

- (void)showDenied {
    if (self.deniedLabel) return;
    self.deniedLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 32, 0)];
    self.deniedLabel.text = @"没有相机权限。\n设置 → 隐私 → 相机，打开本 App 的开关。";
    self.deniedLabel.textColor = UIColor.whiteColor;
    self.deniedLabel.font = [UIFont systemFontOfSize:15];
    self.deniedLabel.textAlignment = NSTextAlignmentCenter;
    self.deniedLabel.numberOfLines = 0;
    [self.view addSubview:self.deniedLabel];
}

#pragma mark - 相机

- (BOOL)setupSession {
    if (self.session) return YES;

    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                                 mediaType:AVMediaTypeVideo
                                                                  position:AVCaptureDevicePositionBack];
    if (!device) {
        [self showDenied];
        return NO;
    }
    self.device = device;

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        NSLog(@"[QR] 相机输入创建失败: %@", error);
        return NO;
    }

    self.session = [AVCaptureSession new];
    if ([self.session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        self.session.sessionPreset = AVCaptureSessionPreset1280x720;
    }
    if ([self.session canAddInput:input]) [self.session addInput:input];

    self.output = [AVCaptureVideoDataOutput new];
    self.output.alwaysDiscardsLateVideoFrames = YES;
    self.output.videoSettings = @{
        (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    };
    [self.output setSampleBufferDelegate:self queue:self.outputQueue];
    if ([self.session canAddOutput:self.output]) [self.session addOutput:self.output];

    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.view.bounds;
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];

    for (AVCaptureConnection *conn in self.output.connections) {
        if (conn.isVideoOrientationSupported) conn.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    if (self.previewLayer.connection.isVideoOrientationSupported) {
        self.previewLayer.connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }

    [self configureDevice];
    [self startSession];
    return YES;
}

- (void)configureDevice {
    AVCaptureDevice *device = self.device;
    if (!device) return;
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
        if ([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        }
        if ([device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
            device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        }
        if ([device isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance]) {
            device.whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
        }
        [device unlockForConfiguration];
    }
}

- (void)startSession {
    if (!self.session || self.running) return;
    self.running = YES;
    dispatch_async(self.outputQueue, ^{
        if (!self.session.isRunning) [self.session startRunning];
    });
}

- (void)stopSession {
    if (!self.session || !self.running) return;
    self.running = NO;
    dispatch_async(self.outputQueue, ^{
        if (self.session.isRunning) [self.session stopRunning];
    });
}

- (void)toggleTorch {
    if (!self.device || ![self.device hasTorch]) return;
    NSError *error = nil;
    if ([self.device lockForConfiguration:&error]) {
        self.torchOn = !self.torchOn;
        self.device.torchMode = self.torchOn ? AVCaptureTorchModeOn : AVCaptureTorchModeOff;
        [self.device unlockForConfiguration];
        [self.torchButton setTitle:(self.torchOn ? @"关灯" : @"手电筒") forState:UIControlStateNormal];
    }
}

- (void)tapToFocus:(UITapGestureRecognizer *)g {
    if (!self.device) return;
    CGPoint p = [g locationInView:self.view];
    CGPoint point = [self.previewLayer captureDevicePointOfInterestForPoint:p];
    NSError *error = nil;
    if ([self.device lockForConfiguration:&error]) {
        if ([self.device isFocusPointOfInterestSupported]) {
            self.device.focusPointOfInterest = point;
            self.device.focusMode = AVCaptureFocusModeAutoFocus;
        }
        if ([self.device isExposurePointOfInterestSupported]) {
            self.device.exposurePointOfInterest = point;
            self.device.exposureMode = AVCaptureExposureModeAutoExpose;
        }
        [self.device unlockForConfiguration];
    }
}

#pragma mark - 取帧解码

- (CGImagePropertyOrientation)exifOrientation {
    switch (UIDevice.currentDevice.orientation) {
        case UIDeviceOrientationPortraitUpsideDown: return kCGImagePropertyOrientationLeft;
        case UIDeviceOrientationLandscapeLeft:      return kCGImagePropertyOrientationUp;
        case UIDeviceOrientationLandscapeRight:     return kCGImagePropertyOrientationDown;
        case UIDeviceOrientationPortrait:
        default:                                    return kCGImagePropertyOrientationRight;
    }
}

- (NSArray<VNBarcodeSymbology> *)symbologies {
    NSMutableArray *list = [NSMutableArray arrayWithObjects:
        VNBarcodeSymbologyQR,
        VNBarcodeSymbologyAztec,
        VNBarcodeSymbologyPDF417,
        VNBarcodeSymbologyDataMatrix,
        VNBarcodeSymbologyCode128,
        VNBarcodeSymbologyCode39,
        VNBarcodeSymbologyCode93,
        VNBarcodeSymbologyEAN13,
        VNBarcodeSymbologyEAN8,
        VNBarcodeSymbologyUPCE,
        VNBarcodeSymbologyITF14,
        nil];
    return list;
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
           fromConnection:(AVCaptureConnection *)connection {
    if (self.isProcessing) return;
    NSTimeInterval now = CACurrentMediaTime();
    if (now - self.lastScanTime < 0.15) return;
    self.lastScanTime = now;
    self.isProcessing = YES;

    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) {
        self.isProcessing = NO;
        return;
    }

    VNDetectBarcodesRequest *request = [[VNDetectBarcodesRequest alloc] initWithCompletionHandler:nil];
    request.symbologies = [self symbologies];

    VNImageRequestHandler *handler =
        [[VNImageRequestHandler alloc] initWithCVPixelBuffer:pixelBuffer
                                                 orientation:[self exifOrientation]
                                                     options:@{}];
    NSError *error = nil;
    [handler performRequests:@[ request ] error:&error];

    NSString *payload = nil;
    NSString *format = nil;
    if (!error) {
        CGRect roi = [self.previewLayer metadataOutputRectOfInterestForRect:self.scanRect];
        for (VNObservation *obs in request.results) {
            if (![obs isKindOfClass:[VNBarcodeObservation class]]) continue;
            VNBarcodeObservation *barcode = (VNBarcodeObservation *)obs;
            CGRect bb = barcode.boundingBox;   // 左下原点，0~1
            CGRect topLeft = CGRectMake(bb.origin.x, 1.0 - CGRectGetMaxY(bb),
                                        bb.size.width, bb.size.height);
            if (!CGRectIntersectsRect(topLeft, roi)) continue;
            if (barcode.payloadStringValue.length == 0) continue;
            payload = barcode.payloadStringValue;
            format = barcode.symbology;
            break;
        }
    }

    self.isProcessing = NO;
    if (payload.length > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self handleResult:payload format:format ?: @"QR"];
        });
    }
}

#pragma mark - 结果

- (void)handleResult:(NSString *)text format:(NSString *)format {
    if (self.vibrateOnSuccess) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    }
    if (!self.continuous) [self stopSession];

    if (self.completion) self.completion(text, format);
    if ([self.delegate respondsToSelector:@selector(qrScanner:didFinishWithResult:format:)]) {
        [self.delegate qrScanner:self didFinishWithResult:text format:format];
    }

    if (self.continuous) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [weakSelf startSession]; });
    }
}

- (void)close {
    [self stopSession];
    if ([self.delegate respondsToSelector:@selector(qrScannerDidCancel:)]) {
        [self.delegate qrScannerDidCancel:self];
    }
    if (self.navigationController) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 相册

- (void)openAlbum {
    if (!self.showsPhotoButton) return;
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [picker dismissViewControllerAnimated:YES completion:^{
        NSString *text = [QRCodeUtil stringFromImage:image];
        if (text.length > 0) [self handleResult:text format:@"QR"];
        else [self flashHint:@"图片里没识别到二维码"];
    }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)flashHint:(NSString *)text {
    NSString *old = self.hintLabel.text;
    self.hintLabel.text = text;
    self.hintLabel.textColor = [UIColor colorWithRed:1 green:0.5 blue:0.35 alpha:1];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       self.hintLabel.text = old;
                       self.hintLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
                   });
}

@end
