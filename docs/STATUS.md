# iMDReader 开发与发行状态

## 首版最终候选：0.1.0（27） · 2026-10-26

本节优先于下方build26草稿与历史HOLD记录。用户批准本版最小修复原生菜单语言P2；已完成并由独立只读reviewer复审，无新增功能、布局或文件行为变更。

- Commands订阅应用语言，四个自定义命令显式使用该locale，补齐“添加本地文件夹”英文资源；动作/快捷键不变。真实Mac中文→English、English→中文及跟随系统菜单正确，英文外观面板标签完整；浅色/深色/系统选择切换正常，最终恢复系统语言与主题。CUA菜单关闭偶有失效，通过正常退出重开恢复；未绕过安全控制。
- build27 Mac Universal Release与iOS Simulator编译通过；新增真实语言目录测试先失败后通过，与两项语言回归共3项通过；最终包128组视图矩阵、9组受控标题检查通过。前一基线64项核心/状态含2项网络补跑通过；菜单补丁后未无故重跑全部。此前真实文件/GitHub/搜索流程证据继续保留，不冒称本轮全部重做。
- 新公证 **Accepted**：`31b93933-d5f9-49bf-80c5-5304c4ae404e`；Developer ID、时间戳、hardened runtime、无get-task-allow，staple/严格签名/Gatekeeper通过。最终ZIP解压后同样验证通过，Gatekeeper为Notarized Developer ID。未沿用build26公证。
- 最终ZIP `iMDReader-0.1.0-macOS-universal.zip`；SHA256 `f459eb829684932a0e1f91c1ff553d5cc21ded9369413a8971cf3f9323dfdcca`。arm64+x86_64，macOS14起；Intel/最低系统运行、中等宽度长标题最终像素、外观内部滚动、完整无障碍/性能、移动真机动效仍未覆盖。极小窗口隐藏标题是接受行为。
- 独立代码与安全审查无确认阻断级问题，菜单P2已解决并增量复审通过；未进行完整依赖漏洞数据库审计。仅净化公开历史快照/noreply作者，不推本地master、不强推。本地历史和开发成果保留。
- GitHub Release仍待本轮最终资产替换和公开核验；旧build26资产已在本地build/archive/build26保存，可恢复，不丢弃旧包。发布页：https://github.com/wivnelo/i-md-reader/releases/tag/v0.1.0 。

## 下一版本（本版功能冻结）

本版不增加新功能，所有新增功能进入下一版本。此次新增仅两项：

1. Mac App图标当前偏浅色，用户希望跟随系统明暗。具体指Dock/AppIcon还是界面品牌，待确认；本版不更换品牌或图标素材。
2. 启动App时自动更新一次，不增加手动更新入口。具体是检查新版还是下载/安装，待确认；本版未接入更新器。

## 固定约束

保留完整ReaderBrand/iMDReader与已确认布局、配色；加号三个添加选项与独立应用设置；只读源文件；置顶/排序行为不变；保留本机数据。iPhone同一单栏模式旋转保留列表，iPad跨单双栏行为仍待单独确认。未测试项不写成通过，编译不代替视觉或交互验证。
