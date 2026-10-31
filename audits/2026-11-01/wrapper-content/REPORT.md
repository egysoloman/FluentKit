# 包装层旧内容捕获：独立复现与修复

基线：`f2b79e2`。本批修复 15 个源文件中的 24 条内容更新路径；没有改变公开 API。

## 根因与改动

23 个包装器在挂载时保存了捕获首次 `content` 的闭包，后续声明式更新仍调用旧闭包。结果是底层主题可能已更新，但文字、按钮角色和点击行为仍属于旧正文。现在更新路径直接使用本轮 `content`。FormField 的类型替换也使用当前内容工厂，避免重新挂载旧类型。

第二轮扩大搜索发现 SettingsCard 尾部 action 的相同问题。该控件在原生外观事务中还会调用保存的回调，因此保留回调并在声明式更新时刷新捕获，避免主题变化把新内容恢复成旧值。

FocusScope 原闭包还强引用自己的宿主，造成循环引用；移除闭包后宿主可释放。合并无障碍标签改为先更新子项，再计算标签。ContextMenu 会刷新捕获，Expander/SettingsExpander 直接更新当前正文，未对这些正常路径套用修复。

## 修复前后证据

同一原生窗口矩阵包含 29 种宿主：24 条受影响路径与 5 个对照。每种依次显示初始、深色新正文、浅色新正文，共 87 个状态。

| 指标 | 旧 Release 对象 | 修复后 Release 对象 |
| --- | ---: | ---: |
| 错误包装路径 | 24 | 0 |
| 错误文字/角色/动作属性 | 144 | 0 |
| 原生按钮身份变化 | 0 | 0 |
| 合并标签更新 | Before → Before | Before → After |

权威结果为 `before-final/results.json`、`after-final/results.json`、各自 `semantic-labels.json` 与 `checks.json`。原生 layer-tree 图片也保留。早期 26 种宿主的结果在 `before/`、`after/`，不替代最终矩阵。

7 项回归覆盖矩阵、FormField 不兼容内容替换、FocusScope 释放、合并标签、生命周期次数、动态键盘焦点链，以及 SettingsCard 原生主题回调。最终 392 项测试零失败，原生验证 PASS，Gallery Debug 构建成功，Release 质量门禁通过；日志在 `after-final/`。门禁继续检查刷新次数、挂载身份、外部重置、排版和材质，不只检查编译。

## 复现

```sh
swift build -c release --scratch-path "${TMPDIR}/fluentkit-quality-release"
zsh audits/2026-11-01/wrapper-content/run.sh audits/2026-11-01/wrapper-content/after-final
python3 audits/2026-11-01/wrapper-content/check_results.py audits/2026-11-01/wrapper-content
swift test --scratch-path /tmp/fluentkit-repair-tests --filter WrapperContentUpdateTests
```

旧对象比较使用 `FLUENTKIT_WRAPPER_LIBRARY=/tmp/fluentkit-wrapper-before.o`；该临时文件可能被系统清理，长期复现应从基线提交单独构建。两批对象哈希在各自目录中。

## 验证边界与无效夹具

早期合并标签测试把隔离进程中未显式标记为无障碍元素的原生按钮当作可合并元素，产生了 2 个无效断言。保留 `before/test.log`、`after/test-initial.log` 和 `before/native-ax-name-probe.log`，不能把这些断言计作框架缺陷。最终夹具显式标记叶子及标签，并用独立旧对象探针确认真实的旧标签捕获。探索过的原生标题回退没有进入运行时代码。

这些结果证明更新路径、身份、焦点链和显式标签传播，不代表真实 VoiceOver、系统全局外观事件或所有第三方组合的完整验收。实际 Gallery 的 21 个主题状态在 `after/gallery-theme/`；真实设置客户端联动检查继续在 `../integration/` 记录。
