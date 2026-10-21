# 用 TrollFools / 轻松签 注入（无越狱）

你的环境：**巨魔（TrollStore）+ 轻松签 + TrollFools**，不需要越狱，也不需要 frida-server。

思路：**编出一个纯 dylib → 用 TrollFools 注进 App**。

我们这套代码已经是纯 dylib 形态：

- 不用 CydiaSubstrate
- 不用 `%hook` / Logos
- 启动靠 `__attribute__((constructor))`，dylib 一被加载就执行

---

## 第一步：把 dylib 编出来

你手上没有 macOS，两条路：

### 路线 1：GitHub Actions 自动编译（最省事，免费）

1. 在 GitHub 建一个空仓库
2. 把 `ecpm/` 整个目录推上去（`.github/workflows/build.yml` 已经写好）
3. 打开仓库的 **Actions → build-dylib → Run workflow**
4. 跑完在 **Artifacts** 里下载 `EcpmCtrl-dylib.zip`，里面有 `EcpmCtrl.dylib`

> workflow 用的是 Theos + iPhoneOS SDK，产出 arm64 + arm64e 双架构，TrollFools 直接吃。

### 路线 2：WSL 本地编

```bash
sudo apt install -y make git curl unzip xz-utils libssl-dev libplist-dev ldid clang
git clone --recursive https://github.com/theos/theos.git ~/theos
# SDK：下载 https://github.com/theos/sdks 的 iPhoneOS14.5.sdk 放进 ~/theos/sdks
export THEOS=~/theos
cd ecpm/theos
make -j4
# 产物：.theos/obj/EcpmCtrl.dylib
```

---

## 第二步：把 dylib 弄到手机上

任意方式：AirDrop / 微信文件传输 / iCloud 云盘 / 轻松签的「导入文件」。

建议放到「文件」App 的 **我的 iPhone → 下载** 里，TrollFools 和轻松签都能直接选到。

---

## 第三步 A：TrollFools 注入（推荐）

1. 确认红果短剧是**用巨魔（TrollStore）安装的**（TrollFools 只能注入 TrollStore 安装的 App）
2. 打开 **TrollFools**
3. 在应用列表里找到 **红果短剧**
4. 点进去 → **注入** → 选择 `EcpmCtrl.dylib`
5. 提示成功后，**从后台划掉红果短剧**再重开

打开 App 后 1.5 秒，左上角会出现 `eCPM 数值控制 v3.8` 面板。

> TrollFools 注入原理是往 Mach-O 的 Load Commands 里插一条 `LC_LOAD_DYLIB`，dylib 会被放到 App 的 Frameworks 或 Documents 下，不破坏签名（TrollStore 本身就是伪签名环境）。

---

## 第三步 B：轻松签 注入（做成 IPA 再装）

1. 打开 **轻松签**
2. **签名** → 选择红果短剧的 IPA（App Store 下的包需要先砸壳，轻松签有「脱壳」功能）
3. 进入签名设置 → **注入插件 / 添加 dylib** → 选 `EcpmCtrl.dylib`
4. 签名并安装（需要证书，或者用 TrollStore 的免签通道）

轻松签的注入本质也是往 IPA 里的可执行文件加 `LC_LOAD_DYLIB`，效果和 TrollFools 一样。

---

## 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 面板不出来 | dylib 没被加载 | TrollFools 里确认注入成功；重开 App；看 `log stream --predicate 'process == "红果短剧"'` 有没有 `[eCPM] 面板已显示` |
| 面板出来但数字不变 | App 还没刷新广告 | 按视频里说的：点应用 → 让 App 重新拉一次广告或重进页面 |
| 注入后 App 闪退 | dylib 架构不对（缺 arm64e） | 确认编译时 `ARCHS = arm64 arm64e` |
| 数字改了但收益没变 | 只挂了 getter，上报层没改 | 见 README 里 `frida-trace` 找序列化层的部分，补 hook |
| 轻松签签名失败 | 没砸壳 | 先用轻松签的「脱壳」功能处理 App Store 包 |

---

## 验证是否注入成功

TrollFools 注入后，用手机连电脑看日志：

```bash
# macOS / WSL 里
idevicesyslog | grep eCPM
```

看到下面几行就说明跑起来了：

```
[eCPM] 扫描完成：类 3 · 已挂 12 条
[eCPM] 面板已显示
[eCPM] 已应用 50000
```

没装 libimobiledevice 的话，直接在 App 里看面板状态栏文字也行。
