# 设置客户端与框架联动复验

框架：`c5a6a18`。实际 Fluent IME 设置源码另以独立 bundle ID 编译，私有 UserDefaults 域及临时 Rime 用户目录；没有注册输入法服务，没有安装、替换或停止已安装输入法。源码及链接对象哈希在 `settings/source-sha256.txt`。

## 自动原生状态矩阵

- `density/`：32 个 ComboBox/MenuFlyout 状态通过；8 对触控板/鼠标图片逐像素一致，直接触摸保留独立密度。两项 ComboBox 的桌面面板 180×80pt，触摸面板 240×104pt。
- `toggle/`：24 个开关状态；默认滑块常态 12×12、悬停 14×14、按压 17×14pt，轨道保持 40×20pt。旧 IME 固定尺寸样式作为对照保留，确实取消形变；应用源码已在前批移除此覆盖。
- `titlebar/`：深浅色、LTR/RTL、32/48pt 标题栏共 32 个状态；按下未提前调用，隐藏后重现的 8 组图与常态逐像素一致。标题栏尺寸保持，检查输出在 `titlebar/check.txt`。

三套探针顺序运行，避免原生窗口争抢。这里复验已有修复，没有额外修改运行时代码。

## 实际设置界面操作

用 CUA 操作 `Fluent Settings Integration Audit.app`，本地监测仅记录自己窗口的鼠标事件与图层状态。`settings/states.json` 保存 57 个状态；手动记录状态对应 `capture-N.png`。

1. 常规页按住自动纠错开关 350ms，确认 presentation layer 达到 17×14pt；释放回到悬停尺寸。再次点击恢复初始开关值。
2. 默认模式菜单为 180×80pt。菜单保持展开时发送应用级浅色信号，菜单与设置窗口同时变浅，选择没有改变。Escape 正常关闭。
3. 返回按钮回到首页，外观页可重新进入。实际显式选择“深色”后，再发送浅色信号仍保持深色；恢复“跟随系统”后正确跟随。
4. 最大化至 1512×886pt 后，右侧、底部与正文空白处四个背景像素均为 RGB(32,32,32)，未出现旧色条；还原回 640×805pt。图见 `settings/capture-47.png`。动画过程的几何连续性另由前批动态探针验证，本次单张图仅证明到达状态。
5. 在真实 SearchBox 用逐键 h/u/a 触发当前 Fluent 拼音的 marked text，再改变客户端外观。文字仍为组合态、编辑器身份不变，随后 Escape 取消且文字清空。搜索原生视图在所有页面/主题/缩放操作中保持同一实例。图见 `settings/capture-51.png`、`settings/capture-56.png`。

实测开关形变、展开菜单主题和显式主题选择，补充了前批自动状态矩阵；不能将应用级外观信号等同于修改系统全局设置。

## 构建与边界

392 项完整测试、原生验证、Gallery Debug 构建及 Release 门禁见 `../wrapper-content/after-final/`。实际 IME Release 产品在本批也以 warnings-as-errors 构建成功，见 `ime-release.log`。本批原生日志未出现约束诊断。

真实候选浮层的跨进程位置仍未关闭：编辑器报告输入源 `org.fluentime.inputmethod.FluentIME.Hans`，但工具只读取得已安装输入法的设置窗口，未获得候选窗口坐标。`settings/run.log` 还出现 IMK mach-port 消息错误，不能据此宣称候选链路正常。录屏中蓝色候选条的归属、真实 IMK 行矩形、移动/缩放回调及屏幕边界仍需专项验证。既有同进程探针的 6pt 边框重叠和移动后滞后证据保留在 `../candidate-popup/REPORT.md`，未盲目添加固定偏移。

已安装输入法是旧静态链接客户端，不会因本仓库编译而自动更新。Windows 对拍、真实触屏、高刷帧时和 VoiceOver 仍保留在总计划；本批不把这些标记为通过。

## 重跑入口

```sh
zsh audits/2026-10-31/pointer-popup-density/run.sh audits/2026-11-01/integration/density
zsh audits/2026-10-31/toggle-pressed-review/run.sh audits/2026-11-01/integration/toggle
zsh audits/2026-11-01/titlebar-button/run.sh audits/2026-11-01/integration/titlebar
python3 audits/2026-11-01/titlebar-button/check_results.py audits/2026-11-01/integration/titlebar
python3 audits/2026-11-01/integration/check_results.py audits/2026-11-01/integration
```

`build-settings-review.sh` 只构建隔离客户端，交互需要用 CUA 重做；不要以程序直接填入数据代替真实输入。本次图像来自应用 layer tree；CUA 截图用于现场核对。
