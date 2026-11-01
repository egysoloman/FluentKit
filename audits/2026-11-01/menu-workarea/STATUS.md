# MenuFlyout 长内容：已复现，待修复

基线运行时：`ae7d469707a768025d4d6a0e75c7e3671286d6ec`。本批暂未修改菜单运行时代码；发现 CI #18 失败后，先处理 tooltip 测试的关闭等待。

`BeforeTests.swift.txt` 使用公开菜单 API 和真实 NSWindow/NSPanel。修正初版测试闭包的 Swift 可选类型推断后，2 项测试共得到 8 个失败断言，见 `before-tests.log`；初版编译错误也保留在 `before-test-compile.log`。

- 50 个条目产生 1804pt 高的面板；当次屏幕工作区高 879pt。面板没有 NSScrollView，测试在检查可滚动容器时失败，未执行后续键盘末项断言。
- 超长标题产生 6630pt 宽的面板，屏幕宽 1512pt；LTR 和 RTL 都越界。

源码目前只裁定弹窗原点，`FluentMenuPresenterView.preferredSize` 直接使用全部内容尺寸。WinUI 的 `CommonStyles/MenuFlyout_themeresources.xaml` 使用纵向 Auto 的 ScrollViewer；`FlyoutBase_Partial.cpp` 约 3380–3405 行根据可用边界限制 presenter 的 MaxWidth/MaxHeight。

下一批顺序：

1. 保存独立 Release 原生复现及渲染结果。
2. 按目标屏工作区限制视口，保留全部条目；核对显式最小宽度契约。
3. 验证 Home/End、方向键、前缀搜索和末项调用；滚动后重新定位或关闭已失去可见锚点的子菜单。
4. 验证动态更新、稳定行身份、RTL、触摸密度及 legacy/overlay 滚动条，然后运行完整门禁。

回归源文件暂保存为文本，避免把明确尚未修复的新需求并入现有通过的测试基线。后续实现时应恢复到 `Tests/FluentKitTests/MenuWorkAreaTests.swift`。本批不算菜单修复完成，也不算物理多显示器验收。
