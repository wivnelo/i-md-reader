# iMDReader 开发与发行状态

## 独立审查与发布门槛

独立只读代码审查和安全审计已完成，未发现确认的阻断级安全缺陷。覆盖近期差异、主题/语言/布局、只读书签、WebView/CSP/路径、GitHub请求/令牌缓存、权限、依赖锁定及净化快照。最终App无get-task-allow，沙箱外独立严格签名通过；公开快照97文件，无个人路径、团队标识或真实凭据泄漏。未执行完整依赖漏洞数据库审计；不等于所有漏洞均被排除。

确认P2语言一致性问题：App明确English时，阅读区已英文，但File菜单三个自定义条目仍中文；ReaderApp.swift的Commands未读取应用语言，内容视图locale没有覆盖菜单。阅读和数据不受影响。已恢复测试前System语言。用户要求保护已确认行为，尚未修改代码；等待决定本版最小修复并重新签名公证，或列入下一版已知问题后发布。正式Release保持草稿，不将公证通过等同于公开发布。

## 当前发行结果：Mac 0.1.0（26）

本文件记录当前公开发行范围与验证边界；早期阶段决策见STAGE_2026-10-26.md。

- Apple公证最终 **Accepted**：`52ec3e2d-986f-4dc4-bd5c-663c6236ad1f`。首次提交因Xcode额外注入get-task-allow被Invalid，已移除调试权限、使用原沙箱权限重新签名同一build26；应用代码与已测行为未改。工程Mac Release同时设置CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO防止再注入。
- staple与stapler validate通过；严格签名校验通过；Gatekeeper为 **accepted / Notarized Developer ID**。使用既有Developer ID、可信时间戳、hardened runtime；不公开签名团队或凭据。
- 最终ZIP：`iMDReader-0.1.0-macOS-universal.zip`，SHA256 `7def33918f7bb1716c6f3999afa5abd3c2b96d5c4fa7fc852bf751e7deb045b4`。Universal arm64+x86_64，最低macOS14；Apple Silicon实际测试，Intel与最低系统运行未覆盖。
- 本轮实际测试：状态/核心共64项有通过证据（默认跳过的2项真实网络已分别补跑通过）；最终build26 Mac Release/iOS Simulator构建通过；128组受控视图与9组标题检查通过。真实Mac公开GitHub表单和README、文件夹授权/重启书签/相对导航、Finder指定候选冷热打开、⌘O/⌘⇧O、⌘F聚焦输入及回车命中通过；四份隔离源文件哈希不变。
- 不扩大验收：中等宽度长标题最终画面、面板内部滚动分支、最低系统/Intel运行、完整无障碍/性能、移动真机动效等仍未覆盖；极小窗口隐藏文件名是用户接受行为。iPad跨单双栏和SE标题方案仍待决定，不随发行修改。
- GitHub源码将从公开main生成净化快照，只有公开父历史与noreply作者；本地master及未提交开发成果不重置、不整体推送。正式发布链接：[v0.1.0](https://github.com/wivnelo/i-md-reader/releases/tag/v0.1.0)；当前正在完成净化提交与Release上传，以远端核验结果为准。
- 后续：保留现有App数据，移动端不扩展商店发布；继续已列专项与图片放大/安全资源加载计划。README、FILE_OPENING同步本阶段结果，知识库由调度任务单独更新。

## 下一版本（本版功能冻结）

本版不增加新功能，所有新增功能进入下一版本。此次新增仅两项：

1. Mac App图标当前偏浅色，用户希望跟随系统明暗。具体指Dock/AppIcon还是界面品牌，待确认；本版不更换品牌或图标素材。
2. 启动App时自动更新一次，不增加手动更新入口。具体是检查新版还是下载/安装，待确认；本版未接入更新器。

## 固定约束

保留完整ReaderBrand/iMDReader与已确认布局、配色；加号三个添加选项与独立应用设置；只读源文件；置顶/排序行为不变；保留本机数据。iPhone同一单栏模式旋转保留列表，iPad跨单双栏行为仍待单独确认。未测试项不写成通过，编译不代替视觉或交互验证。
