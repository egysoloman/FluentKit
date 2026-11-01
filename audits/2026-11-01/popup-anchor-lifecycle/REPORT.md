# 菜单与 ComboBox 锚点尺寸、卸载和滚动生命周期

基线 `640206c16a784c12b1b610ae05fb92348d660b6d`。本批接续工作区尺寸检查，使用真实 Auto Layout 和视图卸载，不手动发屏幕变化通知来替代实际布局。

## 独立复现

- ComboBox 已打开时，同一窗口内将锚点宽度从 220pt 改为 400pt，旧面板仍为 220pt，LTR 起点也未移动。
- MenuFlyout 的普通锚点改宽同样漏更新。根窗口自身缩放则能正常重排，保留为对照，未把该路径列为旧缺陷。
- 保留锚点实例但从窗口移除后，两类面板都继续可见并保留 parent；Menu 的 onDismiss 没有触发。不能依靠锚点 deinit 清理。

最初 4 项测试在旧代码中有 3 项失败、7 处断言失败，见 `BeforeTests.swift.txt`、`before-tests.log`。后增的测试不计作已在旧代码复现。

公开 API Release 探针分别使用深浅色、LTR/RTL、ComboBox/Menu、改宽/根窗口缩放/卸载，共 48 个前后状态。旧代码有 16 个状态失败：8 个改宽状态、8 个卸载状态；根窗口缩放对照正常。见 `before/results.json`。PNG 由探针自己窗口的 layer tree 合成，不是桌面截图或 Windows 像素对拍。

## WinUI 依据和实现

对照本地 `microsoft-ui-xaml-winui3-release-2.3.1/src/dxaml/xcp/dxaml/lib/`：

- `ComboBox_Partial.cpp:2145–2161`：OnUnloaded 关闭下拉框，OnSizeChanged 重新 ArrangePopup。
- `FlyoutBase_Partial.cpp:2980–3011`：注册目标 Unloaded 后调用 Hide，同时观察目标主题。

这两条直接支持尺寸刷新及卸载关闭。本批通用祖先移动跟随是在补齐 FluentKit 已有的锚定策略，并不据此声称 WinUI 对任意 transform 都采用相同策略。

内部 `FluentPopupAnchorObserver` 观察锚点和祖先的 frame/bounds，使用零尺寸、忽略命中和 AX 的附件视图接收卸载/隐藏回调；不轮询、不 swizzle，不修改客户的通知开关。主队列合并通知并完成布局后更新原面板；同一轮中的同窗口重挂载保留面板，跨窗口、隐藏、卸载或完全滚出视口关闭。释放时移除观察者和附件；ComboBox deinit 同时解除 child-window 关系。

## 扩展验证发现的两个边界

1. 测试夹具直接把子视图移到同一 root 的后代时，旧 root 的外部约束仍然有效，使测试窗口缩至 268×252pt。修正为先 removeFromSuperview，再建立新父级约束；翻转文档向下滚动时，屏幕坐标中的锚点 y 增大，原断言符号也已更正。原始失败与几何值保留在 `expanded-initial.log`、`scroll-diagnostic*.log`。
2. 夹具修正后，ComboBox 完全滚出视口仍有 2 个失败断言。带图层视图的 visibleRect 会在滚动通知处理时暂时保留旧值；不能只依赖它。现在同时把当前锚点矩形转换到 NSClipView 和窗口内容坐标，与当前 bounds 求交。见 `expanded-scroll-remaining.log`、`scroll-diagnostic-3.log`。

11 项新测试覆盖普通改宽、根窗口对照、保留目标卸载、换窗口再开、同窗口重挂载后祖先移动、隐藏/关闭、祖先滚动与裁切、通知开关不变/观察者释放、直接释放 ComboBox 的 child-window 清理。相关 54 项已通过；完整验证结果在下节记录。

## 最终验证

- 相关 **54 项通过**，包含本批新增 11 项：`expanded-tests.log`。
- 完整 **544 项、0 失败**，87.060 秒，未检测到 AppKit 约束冲突：`full-tests.log`。
- 相同探针源码链接修复后 Release 产物，**48 个状态全部通过**，旧代码的 16 个失败状态归零：`after/results.json`、`before-check.json`、`after-check.json`。几何更新保留面板、内容和 responder，选择没有变化；卸载关闭并解除 parent，菜单回调一次。
- 两批共 96 张 PNG；已检查深色 LTR ComboBox 改宽、浅色 RTL 菜单改宽原图。源码哈希相同；当次显示器工作区从基线的 1512×884pt 变为 1512×886pt，检查分别使用实际锚点坐标，不将两批 PNG 当作像素基线比较。
- Release 构建成功，143.43 秒：`release-build.log`；Gallery 构建成功：`gallery-build.log`。
- `FluentKitValidation: PASS`；Release 更新次数、挂载身份、外部重置、字体/材质和 Gallery 门禁通过：`native-validation.log`、`quality.log`、`quality/`。

复现：`zsh run-native.sh <Release products目录> <新输出目录>`，然后 `python3 check_native.py <输出目录> --expect-pass`。回归：`swift test --filter PopupAnchorLifecycleTests`。

## 范围

没有安装或替换运行中的 Fluent IME，没有调用合成 NSScrollView.scrollWheel 或修改全局滚动条偏好。只有一块实际 2× 显示器；真实多屏/热插拔、混合倍率、真实滚轮与触摸、VoiceOver、实际中文输入上下文及 Windows 逐像素对照仍开放。客户主动禁用几何通知、CALayer-only transform 等路径不在本批保证范围。

上一批 `640206c` 的 GitHub CI #20 已通过：533 项、1 项平台能力跳过、0 失败，Release 构建 230.52 秒；原始日志保存在 `previous-batch-ci.log`。这不能替代本批提交后的 CI。
