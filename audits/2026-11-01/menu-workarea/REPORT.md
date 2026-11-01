# MenuFlyout 工作区与滚动修复

基线 `79b612afcfedcc019bc7c44e658ad68072cbaecf`，运行时与 `ae7d469` 相同。初始记录、失败测试和原生结果保留，不以现有控件名称或测试数量代替验收。

## 问题与结果

旧实现只限制面板原点，直接使用全文宽度和所有条目的总高度，没有滚动容器。独立 Release 程序通过公开 API 创建真实 NSWindow/NSPanel，覆盖深浅色、LTR/RTL、长标题、长根菜单、长子菜单和 End 选中末项。

| 同一原生场景 | 修复前 | 修复后 |
| --- | --- | --- |
| 长标题宽度 | 6630pt | 1504pt |
| 50 项菜单高度 | 1804pt | 876pt 可滚动视口 |
| 41 项根菜单高度 | 1480pt | 876pt 可滚动视口 |
| 越出工作区的状态 | 32 / 32 | 0 / 32 |
| 要求可见却被裁切的末项 | 16 / 16 | 0 / 16 |

当次工作区为 1512×884pt，保留已有 4pt 边缘间距。全部条目仍在文档内，面板、根内容及 responder 身份保持。结果见 `before/results.json`、`after/results.json` 和两个 `*-check.json`。两次探针源码相同，源码和实际链接的 Release 对象 SHA256 在各自 `source-sha256.txt`。

64 张 PNG 是探针自己窗口的 layer tree 合成，透明外部区域显示为黑色，不是桌面截图或 Windows 像素对拍。已检查深色嵌套末项和浅色 RTL 长标题的原图。

## WinUI 依据与实现

对照本地 `microsoft-ui-xaml-winui3-release-2.3.1/src/`：

- `controls/dev/CommonStyles/MenuFlyout_themeresources.xaml:276–292`：横向滚动关闭，纵向 Auto，ScrollViewer 包含 ItemsPresenter。标题的 `MenuFlyoutItemTextTrimming` 默认为 **Clip**（43/126/209 行）。
- `dxaml/xcp/dxaml/lib/FlyoutBase_Partial.cpp:3380–3405`：根据可用窗口或显示器边界限制 presenter MaxWidth/MaxHeight。
- `dxaml/xcp/core/core/elements/framework.cpp:1174–1197`：最小尺寸优先于最大尺寸。因此保留 FluentKit 已有的显式 minimumWidth / 匹配锚点宽度契约；开发者要求比屏幕更宽时，仍可能越界。

新增内部滚动视口，保留原有行对象和菜单 responder。自然尺寸在内容更新时测量；位置、宽高使用同一个目标屏工作区。Home/End、方向键及前缀搜索在通知子菜单前滚入当前行。数据更新、缩小菜单、滚动条样式变化和锚点改宽后重排文档，并更新浮层动画裁切。

滚动后清除旧指针状态，键盘选择不会被静止鼠标夺走。可见的子菜单锚点继续跟随，完全裁切后关闭分支；关闭时清理回调，旧视口不会操作新菜单。

## 扩展测试发现的问题

第一轮动态子菜单测试出现 4 个失败断言，保留在 `expanded-tests.log`。诊断发现 AppKit 的行 `visibleRect` 可为非空但完全处于自身 `bounds` 外，例如行高 32pt，而可见区域从 y=600 开始。现在检查两者是否相交，不能只检查 `isEmpty`。原始值见 `submenu-diagnostic.log`。

8 项新回归覆盖：宽高边界和末项调用、LTR/RTL 子菜单及滚走关闭、稳定 ID 更新/缩短菜单、touch/desktop 密度下前缀与循环导航、legacy/overlay 重排和改宽、旧 selection-centered 模式可见性、显式最小宽度。最初 2 项旧代码测试共 8 处断言失败；没有把后增 6 项算作已在旧代码复现。

## 最终验证

- 相关 35 项通过：`final-targeted-tests.log`。
- 完整 **533 项、0 失败**，81.015 秒：`full-tests.log`，无 AppKit 约束冲突。
- 独立 Release 32 状态、0 失败：`after-check.json`。
- 最终 Release 构建 49.80 秒；Gallery 构建成功。
- `FluentKitValidation: PASS`，Release 性能/挂载/重置/外观门禁通过：`native-validation.log`、`quality.log` 和 `quality/`。
- 同期 CI #19 的失败发生在菜单改动之前，属于已有 tooltip 开启测试。修正及完整日志见 `../tooltip-ci-wait/REPORT.md`；不能把旧 CI 当成本批成功结果。

重现：使用 `zsh run-native.sh <Release products目录> <新输出目录>`，然后 `python3 check_native.py <输出目录>/results.json`。回归使用 `swift test --filter MenuWorkAreaTests`。探针按目录中的脚本执行，可兼容 Swift Build / native SwiftPM 对象布局。

本批使用原生窗口、程序化键盘事件与直接 clip 滚动，没有调用合成 `NSScrollView.scrollWheel`，也没有更改全局滚动条偏好或安装输入法。真实滚轮/触摸、VoiceOver、物理多屏/混合倍率和 Windows 同尺寸截图继续单独验收；本批不代表 MenuFlyout 全部模板和行为已与 WinUI 一致。
