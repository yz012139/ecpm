# XSao —— 芭蕉 App 扫码原理的 iOS 实现

> 分析的 APK：`com.bajiao.lib_base.App.apk`（芭蕉 / 星星，包名特征 `com.bajiao.xingxing`）
> 结论：它没有自研识别，扫码 = **Camera1 取帧 + ZXing 解码**，用的是开源封装 `com.uuzuche.lib_zxing`。
> 本目录是同一套流程的苹果版：**AVFoundation 取帧 + Vision 解码**，外加悬浮按钮和相册识别。

---

## 一、APK 里到底是什么（证据）

包结构（APK 就是个 zip）：

```
classes.dex        10.0 MB   ← 主代码（含 zxing、uuzuche、bajiao）
classes2..13.dex             ← 分包（业务 UI、HookPlugin 等）
assets/xposed_init           ← com.tencent.mm.plugin.base.xp.HookPlugin（Xposed 模块）
assets/com.tencent.mm.andserver
AndroidManifest.xml          ← 权限含 CAMERA；注册了 CaptureActivity 与 SaoActivity1..4
```

关键类字符串（DEX 里原样可见）：

| 类 | 作用 |
|---|---|
| `com.uuzuche.lib_zxing.camera.CameraManager` | 打开后置 Camera1、选预览尺寸、连续对焦、闪光灯 |
| `com.uuzuche.lib_zxing.camera.PreviewCallback` | `onPreviewFrame(byte[] data, Camera)` 取 NV21 帧 |
| `com.uuzuche.lib_zxing.decoding.DecodeThread` / `DecodeHandler` | 独立 HandlerThread 解码，`buildLuminanceSource` + `decodeWithState` |
| `com.uuzuche.lib_zxing.decoding.DecodeFormatManager` | `ONE_D_FORMATS` / `PRODUCT_FORMATS` / `QR_CODE_FORMATS` 三组码制 |
| `com.uuzuche.lib_zxing.activity.CaptureActivity` / `CaptureFragment` | 预览 SurfaceView + 取景框 + 结果回传 |
| `com.uuzuche.lib_zxing.activity.CodeUtils` | `createQRCode`（生成）、`decodeQRCode`（相册图解码）、`AnalyzeCallback` |
| `com.google.zxing.*` | 真正的解码器：`MultiFormatReader`、`PlanarYUVLuminanceSource`、`RGBLuminanceSource` |

`AndroidManifest.xml` 里能直接读到：
`android.permission.CAMERA`、`com.uuzuche.lib_zxing.activity.CaptureActivity`、
`com.bajiao.xingxing.ui.sao.SaoActivity1/2/3/4`、`SaoActivity` 相关 `FuSaoListActivity`。
业务层（`com.bajiao.xingxing`）字符串被 StringFog 加密（DEX 里是 base64 密文），但扫码入口就是这些 SaoActivity。

### 原版流程（Android）

```
CameraManager.openDriver()                  Camera1 后置摄像头
    ├─ parameters.setPreviewSize(...)       预览尺寸（取接近屏幕比例）
    ├─ setFocusMode(CONTINUOUS_PICTURE)     连续对焦
    └─ setFlashMode / 手电筒按钮
SurfaceView 预览
    ↓ onPreviewFrame(NV21)
DecodeHandler.decode(data, width, height)
    ├─ getFramingRectInPreview()            取景框 → 预览坐标系裁剪
    ├─ buildLuminanceSource(...)            Y 平面 → PlanarYUVLuminanceSource
    └─ MultiFormatReader.decodeWithState()  hints: POSSIBLE_FORMATS / TRY_HARDER / CHARACTER_SET=utf-8
    ↓ 命中
CaptureActivityHandler → 播放提示音/震动 → setResult(文本, 格式) → finish()
相册：CodeUtils.decodeQRCode(bitmap) → RGBLuminanceSource → 同样走 MultiFormatReader
生成：CodeUtils.createQRCode(content, size, logo) → MultiFormatWriter(QR_CODE) + 贴 logo
```

---

## 二、苹果版怎么对应

| Android | iOS（本目录） |
|---|---|
| `CameraManager` + `Camera.open()` | `AVCaptureSession` + `AVCaptureDevice`（后置广角，1280×720） |
| `SurfaceView` + `Camera.setPreviewDisplay` | `AVCaptureVideoPreviewLayer` |
| `PreviewCallback.onPreviewFrame(NV21)` | `AVCaptureVideoDataOutput` 的 `captureOutput:didOutputSampleBuffer:`（420f 双平面，零拷贝进 Vision） |
| `getFramingRectInPreview` 裁剪 | `metadataOutputRectOfInterestForRect:` 把取景框换算成归一化 ROI，再筛 `boundingBox` |
| `MultiFormatReader` + POSSIBLE_FORMATS | `VNDetectBarcodesRequest`，`symbologies` 一次给全（QR/Aztec/PDF417/DataMatrix/Code128/39/93/EAN13/8/UPCE/ITF14） |
| `TRY_HARDER` | Vision 默认全帧多尺度，无需开关 |
| 相册 `CodeUtils.decodeQRCode` | `+[QRCodeUtil stringFromImage:]`（Vision，失败回落 CIDetector） |
| `CodeUtils.createQRCode` | `+[QRCodeUtil qrImageWithString:size:logo:]`（CIQRCodeGenerator，容错 H + 贴 logo） |
| `CaptureActivity` 结果回传 | `completion` 回调 + `QRScannerDelegate` |
| 手电筒 / 点按对焦 | `torchMode` / `focusPointOfInterest` |
| 震动 | `AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)` |

### 目录

```
QRScanKit/
├─ QRScannerViewController.h/.m   扫码页（取帧→Vision→ROI 过滤→回调，手电筒/对焦/相册）
├─ QRCodeUtil.h/.m                生成二维码 / 图片解码
├─ XSao.xm                        插件入口：悬浮「扫」按钮 + 全屏扫码 + 复制结果
├─ XSao.plist                     过滤器（改成宿主 Bundle ID）
├─ Makefile / control             Theos 工程
└─ README.md
```

### 单独用（不注入）

```objc
#import "QRScannerViewController.h"

QRScannerViewController *vc =
    [QRScannerViewController scannerWithCompletion:^(NSString *text, NSString *format) {
        NSLog(@"扫到 %@: %@", format, text);
    }];
vc.continuous = NO;
vc.scanRect = CGRectMake(40, 160, 280, 280);
[self presentViewController:vc animated:YES completion:nil];
```

生成 / 解码：

```objc
UIImage *qr = [QRCodeUtil qrImageWithString:@"https://example.com" size:600 logo:nil];
NSString *text = [QRCodeUtil stringFromImage:someImage];
```

### 注入用（Theos）

1. 把 `XSao.plist` 的 `com.example.app` 改成宿主 Bundle ID；
2. 宿主 `Info.plist` 必须有 `NSCameraUsageDescription`、`NSPhotoLibraryUsageDescription`，没有就自己加；
3. 编译：

```bash
export THEOS=~/theos
cd QRScanKit && make package
```

没 Mac 就走 GitHub Actions（`.github/workflows/qrkit.yml` 会做语法检查）。

### 权限与注意

- 相机权限被拒时页面给提示，不闪退；
- `AVCaptureSession` 只在 `viewWillAppear` 起、`viewWillDisappear` 停，进后台自动停；
- 取景框外的码不认（和 Android 的 framingRect 一致）；
- 解码跑在串行队列，单帧处理 + 150ms 节流，不卡主线程；
- 相册识别不依赖相机权限。
