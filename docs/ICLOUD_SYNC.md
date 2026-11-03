# iCloud 多端同步技术方案（草案）

状态：2026-11-03 起草；同日用户确认第 8 节 6 项全部按建议执行，P0 签名与 Mac CloudKit 往返已通过，下一步 P1。本文是计划，不代表已实现或已验收。

## 1. 目标与边界

同一 Apple 账户下的 Mac、iPhone、iPad 之间同步**阅读状态**，换设备后看到相同的来源列表、置顶/排序和阅读进度。

- 只同步 App 自己产生的状态，不上传、复制或修改任何文档内容；本地原文件仍由系统文件提供方（如 iCloud 云盘）负责。
- 数据只存于用户自己的 iCloud 私有数据库，开发者无法读取；不新增自有账号、服务器或分析。
- iCloud 未登录、已关闭本 App 的 iCloud 或网络不可用时，行为与现在完全一致（纯本地）。
- 不改变已确认的品牌、布局、置顶/排序/移除交互；新增入口只放在现有“•••”应用设置中。

## 2. 现有本地状态盘点

全部在 `ReaderStore`/`@AppStorage` 的 `UserDefaults` 中：

| 键 | 内容 | 同步建议 |
| --- | --- | --- |
| `githubSources` | GitHub 来源（UUID、URL、ref、已解析提交） | **同步**（不含 `resolvedReference`，各端自行解析） |
| `sources` | 本地文件夹（UUID、名称、授权书签） | 书签与设备绑定不可同步；**仅 iCloud 云盘内的文件夹**同步“描述”，其他设备需重新授权（见 §5） |
| `pinnedSources`、`sourceOrder` | 来源 UUID 列表 | **同步** |
| `positions` | `来源UUID|/相对路径` → 0–1 进度 | **同步**（GitHub 和已同步的本地来源） |
| `readerPalette` | 配色 | **同步**（§8-2） |
| `readerTheme`、`readerLanguage` | 明暗、界面语言 | 不同步（§8-2） |
| `fontSize` | 字号 | 建议**不同步**（屏幕尺寸差异大） |
| `readingSampleRemoved` | 是否移除阅读示例 | 同步 |
| `expanded`、`lastDocument`、`recentFiles`、`offlineCacheCapacityMB` | 展开状态、上次文档、最近单文件、缓存容量 | 不同步（设备相关；最近单文件书签不可跨设备） |
| GitHub 令牌（Keychain） | — | **永不同步**，维持 `WhenUnlockedThisDeviceOnly` 已确认约束 |
| 离线缓存 | — | 永不同步 |

阅读位置以来源 UUID 为前缀，因此**同一来源在各设备必须使用同一 UUID**，这是方案的核心约束。

## 3. 技术选型

**采用 CloudKit 私有数据库 + `CKSyncEngine`。**

| 方案 | 结论 |
| --- | --- |
| `CKSyncEngine`（CloudKit） | ✅ 选用。系统负责推送、变更令牌、批量与重试；最低 iOS 17 / macOS 14，与本项目现有部署目标完全一致，无需提高最低系统 |
| `NSUbiquitousKeyValueStore` | ❌ 总量 1 MB / 1024 键，只有整键覆盖，阅读位置增多后受限，冲突粒度粗 |
| SwiftData/Core Data + CloudKit | ❌ 需把整套持久化迁出 UserDefaults，改动面大，违反“不借机重构” |
| iCloud 文稿中放 JSON 文件 | ❌ 多端同时写需要自行处理文件版本冲突 |

已核实（Apple “Supported capabilities (macOS)”）：Developer ID 分发的 Mac App 支持 iCloud CloudKit、键值存储、iCloud 文稿和推送，因此 GitHub Release 直装版可以使用，无需上 Mac App Store。

## 4. 架构

```
ReaderStore（现有，仍以 UserDefaults 为本机真值与离线缓存）
   │  状态变更事件 / 应用远端变更
   ▼
SyncCoordinator（App 层，新增）── CKSyncEngine ── iCloud 私有库 · 自定义 Zone "ReaderState"
   │
   ▼
ReaderCore/SyncModel（新增，纯 Swift，无 CloudKit 依赖）
   记录模型 · 合并规则 · UUID 去重重映射 · 单元测试
```

- **ReaderStore 改动最小化**：保留现有读写路径，只在写 `defaults` 的位置额外发出“某记录已变更”通知；收到远端变更后经同一组方法更新 `@Published` 状态。
- **合并逻辑放 ReaderCore**，可脱离 CloudKit 单测；`SyncCoordinator` 只做 CKRecord ↔ 模型转换和引擎委托。
- 引擎状态序列化（`CKSyncEngine.State.Serialization`）存入 App Support 目录，不入 UserDefaults。

### 记录类型（Zone `ReaderState`）

| recordType | recordName | 字段 |
| --- | --- | --- |
| `Source` | 来源 UUID | `kind`(github/icloudFolder)、`url`、`reference`、`cloudPath`、`displayName`、`addedAt`、`modifiedAt` |
| `Layout` | 固定 `layout` | `pinned:[UUID]`、`order:[UUID]`、`sampleRemoved`、`modifiedAt` |
| `Position` | `sha256(文档键)` | `key`、`progress`、`modifiedAt`、`deviceName`(可选，用于“在某设备读到”提示) |
| `Preferences` | 固定 `preferences` | 按 §8-2 决定的字段 + 各字段 `modifiedAt` |

Position 单独成记录，避免滚动时频繁改写一个大记录；记录名用哈希避免路径中的特殊字符及长度问题。

## 5. 关键设计

### 5.1 iCloud 云盘文件夹的跨设备识别

授权书签不能跨设备，但 iCloud 云盘中的路径在各设备一致：

- 添加或启动时用 `URLResourceValues.isUbiquitousItem` 及路径判断文件夹是否位于 `Mobile Documents/<容器>/…`，记录 `cloudPath = 容器ID + 容器内相对路径`（如 `com~apple~CloudDocs/Notes/Project`）。
- 非 iCloud 云盘来源（我的 iPad、外接盘、第三方提供方）**不上传**，仅留在本机。
- 其他设备收到这类 `Source` 后，在列表中显示为“需要授权”的同名来源（沿用现有授权失效行的样式，不新增视觉元素）；点按时打开系统选择器（尽量定位到对应目录），用户选中后**校验 `cloudPath` 一致**再保存本机书签，绑定到同一 UUID，阅读位置随即生效。选错目录则提示，不绑定。
- 文件未下载、离线等沿用 [FILE_OPENING](FILE_OPENING.md) 已有的等待/重试处理。

### 5.2 冲突与合并

- **字段级“最后修改者胜”**：每条记录/字段带 `modifiedAt`；CloudKit 返回 `serverRecordChanged` 时取较新者重新保存。
- **阅读位置**：取 `modifiedAt` 较新者；本机正在阅读的文档不被远端覆盖跳动，只在下次打开时采用（避免“看着看着被拉走”）。
- **置顶/排序**：整列表最后修改者胜；合并后剔除不存在的 UUID，新出现的来源按现有 `unknownFirst` 规则排在前面。
- **重复来源去重**：两台设备在开启同步前各自添加了同一 GitHub 仓库（规范化后 owner/repo/路径/ref 相同）或同一 `cloudPath`，保留 `addedAt` 较早者的 UUID，把另一方的置顶、排序、阅读位置键重映射过去后删除重复记录。规则确定性，各端独立得出相同结果。
- **删除**：移除来源 = 删除 `Source` 记录及其 Position 记录；是否跨设备生效见 §8-3。

### 5.3 写入节流

- 阅读位置在离开文档、切换文档、App 进入后台或停止滚动约 5 秒后才提交，不随每次滚动写入。
- `CKSyncEngine` 自动合并批量发送；其余状态仅在用户操作时变化，量很小。

### 5.4 首次开启与迁移

- 现有本地数据视为 `modifiedAt = 0`：远端已有的值优先，本地独有的项上传。保证老用户在第二台设备开启时不会覆盖第一台的进度。
- 关闭同步：停止引擎、保留本机数据；可选“同时删除 iCloud 中的数据”（删除 Zone）。
- iCloud 账户切换/退出（`accountChange` 事件）：停止同步并清除引擎状态，不删除本机数据，不把旧账户数据混入新账户。

## 6. 签名、配置与发布影响

- 需在 Apple Developer 后台为 iOS 与 Mac 两个 App ID 开启 iCloud（CloudKit），共用一个容器（如 `iCloud.<团队前缀>.imdreader`）；同时开启推送用于静默变更通知。**修改 App ID 能力会使现有描述文件失效**，iOS App Store 描述文件与 Mac Developer ID 描述文件都要重新生成，Mac 包需内嵌描述文件。签名团队与标识继续不入库。
- 授权文件新增 `com.apple.developer.icloud-container-identifiers`、`com.apple.developer.icloud-services = CloudKit`、`aps-environment`（iOS）/`com.apple.developer.aps-environment`（Mac）。
- CloudKit Schema 开发环境验证后必须**部署到生产环境**再发布，否则正式版写入失败；列入发布检查清单。
- 当前审核中的 iOS 0.2.1（51）不受影响；同步功能进入下一个版本（建议三端 0.3.0），Mac 与移动端须一起发布，否则只有一端能同步。
- **文档与政策需同步修改**：[隐私政策](privacy.html) 现写明“应用不提供……跨设备同步”，需改为说明可选的 iCloud 同步及存储内容（来源地址、iCloud 云盘文件夹相对路径、阅读位置、外观偏好；不含文档正文和令牌）；README、知识库总纲的“不跨设备同步”边界同步更新。App Store 隐私标签：数据仅存于用户私有 iCloud 库、开发者无法访问，按 Apple 定义通常仍属“未收集数据”，提交前再按当时规定核对。

## 7. 实施阶段

| 阶段 | 内容 | 完成标准 |
| --- | --- | --- |
| P0 验证 | 配置容器与描述文件；最小 `CKSyncEngine` 在 Mac（Developer ID 签名）与 iOS 模拟器各往返一条记录 | 两端真实读写成功；此前不写业务代码 |
| P1 模型与合并 | ReaderCore `SyncModel`：记录模型、合并、去重重映射、迁移规则 | 单元测试覆盖冲突、删除、去重、首次合并、账户切换 |
| P2 GitHub 与布局 | 同步 GitHub 来源、置顶/排序、示例移除、阅读位置 | 两端增删、置顶、排序、进度往返；离线后恢复补发 |
| P3 iCloud 文件夹 | `cloudPath` 识别、“需要授权”行、选择校验绑定 | 授权前后位置正确；非 iCloud 来源不上传；选错目录不绑定 |
| P4 设置与发布 | “•••”中开关与状态、隐私政策/README/STATUS、Schema 部署、三端发布 | 按 STATUS“已确认行为的固定回归门槛”回归置顶/排序/移除/语言/阅读位置等受影响项 |

测试要求：合并逻辑单测；双模拟器 + Mac 使用同一测试 Apple 账户做端到端验证（账户由用户登录，助手不处理密码）；弱网/离线、iCloud 关闭、账户切换各测一次。编译通过不代替交互验证。

## 8. 已确认决策（2026-11-03）

1. **同步范围**：同步 GitHub 来源、置顶/排序、阅读位置、示例移除；不同步字号、展开状态、最近单文件、上次打开文档。
2. **外观与语言**：只同步配色；明暗与界面语言各设备独立。
3. **移除来源**：一台设备移除，其他设备同步移除（删除的是引用，不是原文件）。
4. **本地文件夹**：只同步 iCloud 云盘内的文件夹，其他设备点一次授权并校验路径后绑定。
5. **开关**：“•••”应用设置新增“iCloud 同步”；iCloud 可用时默认开启，首次启动不弹窗。
6. **版本**：三端 0.3.0 一起发布。

## 9. 进展

### P0 · 2026-11-03

- 用户授权后，在 Apple Developer 后台新建 iCloud 容器 `iCloud.io.github.wivnelo.imdreader`（容器 ID 全局唯一，故不用 `com.example` 前缀）；iOS 与 Mac 两个 App ID 均开启 iCloud（CloudKit）并关联该容器，开启推送。本机 Mac 登记为开发设备。现有描述文件随之失效；已提交审核的 iOS 0.2.1（51）构建不受影响。
- 授权文件：新增 `ReaderApp/ReaderApp.entitlements` 并由 iOS 目标引用；`ReaderMac/ReaderMac.entitlements` 增加同一容器、CloudKit 与推送。签名团队仍只在构建时传入，不入库。
- 自动签名构建：Mac Debug 内嵌开发描述文件，iOS 真机 Debug 生成新开发描述文件；两端签名产物均含该容器、CloudKit 与推送授权。
- Mac 实际往返：临时探针在 App 界面与 `ReaderStore` 创建前运行（不读写本机资料库），iCloud 账户可用，私有库开发环境写入、读回、删除一条记录均成功；探针代码已删除。
- 未完成：iOS 实际 CloudKit 往返（需已登录 iCloud 的模拟器或真机）；Mac Developer ID 发行描述文件、iOS App Store 描述文件及 CloudKit Schema 生产部署留到发布阶段。
