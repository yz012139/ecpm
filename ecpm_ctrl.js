/* =====================================================================
 * eCPM 数值控制 (Frida 版)  —— 同款悬浮面板
 * 目标：iOS 穿山甲/ABU (Pangle) 广告 SDK 的 eCPM / price / bid 数值
 * 用法：
 *   frida -U -f com.example.app -l ecpm_ctrl.js --no-pause
 *   或在已注入 Frida Gadget 的 App 里加载本脚本
 * 面板：三秒内出现，可拖动；应用 / 模式 / 范围 三个按钮
 * ===================================================================== */

'use strict';

var CFG = {
    value: 50000,        // 目标 eCPM
    mode: 'replace',     // replace = 强制等于；add = 原值 + 输入
    range: 'all',        // all = 全部候选方法；ecpm = 只挂 ecpm 相关
    logging: true,
    hookedCount: 0,
    hitCount: 0,
    recent: ''
};

/* ---------------- 日志 ---------------- */
function log(msg) {
    CFG.recent = msg;
    if (CFG.logging) console.log('[eCPM] ' + msg);
    try { if (global.__ecpmLogCb) global.__ecpmLogCb(msg); } catch (e) {}
}

/* ---------------- 候选方法筛选 ---------------- */
var SEL_RE = /ecpm|cpm|price|bid|revenue|payprice|income/i;
var SKIP_RE = /set[A-Z]|init|dealloc|description|debugDescription|hash|isEqual/i;

function isNumericType(t) {
    return t === 'd' || t === 'f' || t === 'q' || t === 'Q' ||
           t === 'i' || t === 'I' || t === 'l' || t === 's';
}

function objcNumberFromRetval(retval, val) {
    // 仅做替换，不新建对象
    try { retval.replace(val); } catch (e) {}
}

function hookClass(cls) {
    var n = 0;
    var methods;
    try { methods = cls.$ownMethods; } catch (e) { return 0; }
    if (!methods) return 0;

    for (var i = 0; i < methods.length; i++) {
        var sig = methods[i];                    // 形如 "-[Foo bar:]"
        var m = sig.match(/^([+-])\[(\S+) (\S+)\]$/);
        if (!m) continue;
        var sel = m[3];
        if (!SEL_RE.test(sel)) continue;
        if (SKIP_RE.test(sel)) continue;
        if (CFG.range === 'ecpm' && !/ecpm/i.test(sel)) continue;

        var method;
        try { method = cls[sel]; } catch (e) { continue; }
        if (!method) continue;

        var rt;
        try { rt = method.returnType; } catch (e) { continue; }

        try {
            if (isNumericType(rt)) {
                Interceptor.attach(method.implementation, {
                    onLeave: function (retval) {
                        try {
                            var orig = rt === 'f' ? retval.toFloat() : retval.toNumber();
                            var out = CFG.mode === 'add' ? (orig + CFG.value) : CFG.value;
                            if (rt === 'f') retval.replace(out); else retval.replace(out);
                            CFG.hitCount++;
                            if (CFG.hitCount % 50 === 1) log('命中 ' + CFG.hitCount +
                                ' · 已改写 ' + CFG.hitCount + ' · ' + m[2] + '.' + sel);
                        } catch (e) {}
                    }
                });
                n++;
            } else if (rt === '@') {
                // 返回 NSNumber 的情况
                Interceptor.attach(method.implementation, {
                    onLeave: function (retval) {
                        try {
                            var v = new ObjC.Object(retval);
                            if (!v || v.$class !== ObjC.classes.NSNumber) return;
                            var orig = v.doubleValue();
                            var out = CFG.mode === 'add' ? (orig + CFG.value) : CFG.value;
                            var nn = ObjC.classes.NSNumber.numberWithDouble_(out);
                            retval.replace(nn);
                            CFG.hitCount++;
                            if (CFG.hitCount % 50 === 1) log('命中 ' + CFG.hitCount +
                                ' · ' + m[2] + '.' + sel + ' (NSNumber)');
                        } catch (e) {}
                    }
                });
                n++;
            }
        } catch (e) {}
    }
    return n;
}

function scanAll() {
    var classes = ObjC.classes;
    var total = 0, clsCount = 0;
    for (var name in classes) {
        // 只扫广告相关类，减少开销
        if (!/^(ABU|CSJ|BU|BD|Pangle|TTAd|GM|PAG)/i.test(name)) continue;
        var c;
        try { c = classes[name]; } catch (e) { continue; }
        var n = hookClass(c);
        if (n) { clsCount++; total += n; }
    }
    CFG.hookedCount += total;
    log('范围:' + CFG.range + ' · 类 ' + clsCount + ' · 已挂 ' + total + ' 条');
    return total;
}

/* ---------------- 悬浮面板 ---------------- */
function buildPanel() {
    ObjC.schedule(ObjC.mainQueue, function () {
        var UIApplication = ObjC.classes.UIApplication;
        var app = UIApplication.sharedApplication();
        var keyWindow = app.keyWindow();
        if (!keyWindow) keyWindow = app.windows().objectAtIndex_(0);

        var W = 300, H = 300;
        var win = ObjC.classes.UIWindow.alloc().initWithFrame_(
            ObjC.structs.CGRect ? ObjC.structs.CGRect : {origin:{x:10,y:120},size:{width:W,height:H}});
        // Frida 里没 structs.CGRect，用 NSValue 构造比较麻烦，直接走 alloc/init + setFrame 的 C 结构
        try {
            var rect = { origin: { x: 10, y: 120 }, size: { width: W, height: H } };
            var w2 = ObjC.classes.UIWindow.alloc();
            w2 = w2.initWithFrame_(rect);
            win = w2;
        } catch (e) { log('窗口创建失败: ' + e); return; }

        win.setWindowLevel_(1000);
        win.setBackgroundColor_(ObjC.classes.UIColor.colorWithWhite_alpha_(0.08, 0.92));

        var root = win.rootViewController();
        if (!root) {
            root = ObjC.classes.UIViewController.alloc().init();
            win.setRootViewController_(root);
        }
        var view = root.view();
        view.setFrame_({ origin: { x: 0, y: 0 }, size: { width: W, height: H } });

        function label(text, x, y, w, h, size, color) {
            var l = ObjC.classes.UILabel.alloc().initWithFrame_(
                { origin: { x: x, y: y }, size: { width: w, height: h } });
            l.setText_(text);
            l.setFont_(ObjC.classes.UIFont.boldSystemFontOfSize_(size || 13));
            l.setTextColor_(color || ObjC.classes.UIColor.whiteColor());
            l.setNumberOfLines_(0);
            view.addSubview_(l);
            return l;
        }

        function button(text, x, y, w, h, color, cb) {
            var b = ObjC.classes.UIButton.buttonWithType_(1);
            b.setFrame_({ origin: { x: x, y: y }, size: { width: w, height: h } });
            b.setTitle_forState_(text, 0);
            b.setTitleColor_forState_(ObjC.classes.UIColor.whiteColor(), 0);
            b.setBackgroundColor_(color);
            try { b.layer().setCornerRadius_(6); } catch (e) {}
            var handler = new ObjC.Block({
                retType: 'void',
                argTypes: ['object'],
                implementation: function () { cb(); }
            });
            var action = ObjC.classes.UIAction.actionWithHandler_(handler);
            b.addAction_forControlEvents_(action, 1 << 6); // UIControlEventTouchUpInside
            view.addSubview_(b);
            return b;
        }

        label('eCPM 数值控制 v3.8', 12, 10, 200, 22, 16);
        var info = label('叠加=原值+输入，替换=强制等于输入', 12, 34, 276, 34, 11,
                         ObjC.classes.UIColor.grayColor());

        var field = ObjC.classes.UITextField.alloc().initWithFrame_(
            { origin: { x: 12, y: 72 }, size: { width: 276, height: 34 } });
        field.setText_('' + CFG.value);
        field.setBackgroundColor_(ObjC.classes.UIColor.whiteColor());
        field.setTextColor_(ObjC.classes.UIColor.blackColor());
        field.setKeyboardType_(4); // number pad
        view.addSubview_(field);

        var status = label('范围:' + CFG.range + ' · 已挂 ' + CFG.hookedCount + ' 条',
                           12, 116, 276, 40, 11, ObjC.classes.UIColor.greenColor());

        button('应用', 12, 160, 84, 34, ObjC.classes.UIColor.systemBlueColor(), function () {
            CFG.value = parseFloat(field.text()) || 0;
            log('应用 value=' + CFG.value + ' 模式=' + CFG.mode);
            status.setText_('已应用 ' + CFG.value);
        });
        button('模式:' + (CFG.mode === 'add' ? '叠加' : '替换'), 104, 160, 84, 34,
               ObjC.classes.UIColor.orangeColor(), function () {
            CFG.mode = CFG.mode === 'add' ? 'replace' : 'add';
            log('模式切换为 ' + CFG.mode);
        });
        button('范围:' + CFG.range, 196, 160, 92, 34,
               ObjC.classes.UIColor.systemGreenColor(), function () {
            CFG.range = CFG.range === 'all' ? 'ecpm' : 'all';
            log('范围切换为 ' + CFG.range + '（重新扫描）');
            scanAll();
        });

        button('收起', 12, 204, 276, 34, ObjC.classes.UIColor.darkGrayColor(), function () {
            win.setHidden_(true);
        });

        global.__ecpmLogCb = function (msg) {
            try { status.setText_(msg); } catch (e) {}
        };

        win.makeKeyAndVisible();
        log('面板已显示');
    });
}

/* ---------------- 启动 ---------------- */
function main() {
    if (!ObjC.available) { console.log('不在 ObjC 环境'); return; }
    setTimeout(function () {
        scanAll();
        buildPanel();
        // 定时补挂（App 可能在运行中加载新类）
        setInterval(function () { scanAll(); }, 15000);
    }, 1500);
}

setImmediate(main);
