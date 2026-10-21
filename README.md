# eCPM 数值控制 v3.8.5（视频同款）

> **v3.8.5 面板拖动**：面板整块都能「按住拖」，不用再掐着那 22pt 高的标题字。
> 松手自动记住坐标（`EcpmCtrl38.cardX/cardY`），下次打开还在原地；拖到屏幕外会被吸回边界。
> 成品：`dist/EcpmCtrl_v3.8.5.dylib`（arm64 + arm64e 双切片 fat）。

## 视频里那个面板在做什么

从抽帧看得很清楚：

- 工具名：**eCPM 数值控制 v3.8**
- 输入框：`50000`
- 三个按钮：`应用` / `模式:替换` / `范围:28万表`
- 状态栏：`范围:28万表 80 条（旧9+新71）·类 12/31 ·已挂 13/80`、`旧表 9 条 5/9 ·替换=50000`、`命中 587 · 已改写 587`、`最近 ABUAdPackage.ecpm`
- 说明：`叠加=原值+输入，替换=强制等于输入`；`范围:28万表=只挂新通杀28万那80条类名+方法名`

也就是一个 iOS 越狱插件 / Frida 脚本，运行时把穿山甲（ABU/Pangle，字节广告 SDK）里所有 **eCPM / price / bid** 的 getter 返回值改掉，让「看广告赚钱」类 App（视频里是红果短剧）把你这条广告的单价报成 50000，从而多结算。

**实现原理只有一句话：运行时对 Objective-C 方法做实现替换（method swizzling / inline hook），把返回值换成你的数。**

## 目录

```
ecpm/
├── ecpm_ctrl.js          Frida 版（免编译，直接注入，带同款悬浮面板）
├── theos/
│   ├── Makefile
│   ├── control
│   └── Tweak.xm          Theos 版（编成 deb，永久安装，开机自启）
└── README.md
```

## 方案 A：Frida 版（推荐，几分钟就能跑）

### 环境

- 越狱 iPhone（unc0ver / Dopamine / palera1n 都行），装 `frida-server`
- 电脑装 `pip install frida-tools`

```bash
# 1. 手机端起 frida-server（越狱环境一般自带守护）
ssh root@<手机IP> "/usr/sbin/frida-server -D"

# 2. 找到红果短剧的 bundle id
frida-ps -Uai | grep -i -E "红果|phoenix|read"

# 3. 注入并启动脚本（-f 冷启动，脚本会先挂再跑）
frida -U -f com.phoenix.read -l ecpm_ctrl.js --no-pause
```

面板会在 1.5 秒后浮在屏幕上，`应用` 按钮把输入框的值写进 `CFG.value`，`模式` 在“替换/叠加”之间切，`范围` 切“全部广告类/只挂 ecpm”。

### 不想装 frida-server 的话

用 **Frida Gadget + 重签名**：把 `FridaGadget.dylib` 注入 IPA，重签后侧载（TrollStore 可以直接装未签名 IPA，更方便）。启动时 Gadget 会加载同目录的 `ecpm_ctrl.js`（在 Gadget 配置 `interaction: script` 里指定）。

## 方案 B：Theos 版（做成 deb，永久使用）

在 macOS / Linux / WSL 上装 [Theos](https://theos.dev)：

```bash
export THEOS=~/theos
cd theos
make package                 # 生成 packages/com.fj.ecpmctrl_3.8_iphoneos-arm64.deb
make package install         # 直接推到手机并 respring
```

装完打开红果短剧，面板自动出现（挂在 SpringBoard，App 内可见）。

## 关键：类名/方法名不是固定的

视频里的“28 万表 80 条”是他自己维护的一份方法签名表。**SDK 一升级，类名就变**，所以两个脚本都用「运行时扫描」代替硬编码：

```
扫描所有 ABU* / CSJ* / BU* / BD* / Pangle* / TTAd* / GM* / PAG* 开头的类
→ 遍历它们的实例方法
→ 选中 sel 里含 ecpm / cpm / price / bid / revenue 的
→ 按返回类型（double / float / NSNumber）分别替换实现
```

### 想精确定位到某一个方法

```bash
# 1. 看某个类里所有方法
frida -U -f com.phoenix.read -e "ObjC.classes.ABUAdPackage.$ownMethods"

# 2. 跟踪所有 cpm 相关调用（打印调用栈，找真正的上报点）
frida-trace -U -f com.phoenix.read -m "-[* *cpm*]" -m "-[* *eCPM*]" -m "-[* *price*]"

# 3. 抓某个方法被谁调用
frida-trace -U -f com.phoenix.read -m "-[ABUAdPackage ecpm]" -x "-[ABUAdPackage ecpm]"
```

`frida-trace` 输出的调用栈里，往上翻几层就能看到真正把 eCPM 写进上报 JSON 的那一层，把它也挂上，数值才会真正进结算链路（只挂 getter 有时只影响 UI 显示）。

## 面板行为对照

| 视频里的按钮 | 我们的实现 |
|---|---|
| 应用 | 读取输入框 → 写入 `gValue` / `CFG.value` |
| 模式:替换/叠加 | `replace` 返回固定值；`add` 返回 原值+输入 |
| 范围:28万表 | 我们改成 `all`（前缀匹配全部广告类）/ `ecpm`（只挂含 ecpm 的方法） |
| 日志:开 | 每 50 次命中打一条，跟视频里的 `命中 587 · 已改写 587` 一个意思 |
| 收起 | `window.hidden = YES` |

## 注意

- eCPM 只是“千次展示收益”，真正结算还看 **展示回调/竞价结果**；只改 getter 可能只变界面数字。要真的影响收益，得把上报 JSON 里的字段也改掉（在 `frida-trace` 找到序列化那层，hook `NSJSONSerialization` 或 SDK 的 `-toDictionary`）。
- 每次改完，让 App **重新拉一次广告或重进页面**，新值才会生效（视频里那句“改完点应用，再让游戏刷一次广告或重进页面”就是这个原因）。
- 一次只装一个版本：Frida 和 Theos 同时挂会互相覆盖实现。
