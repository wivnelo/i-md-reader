# iCloud 多端同步技术方案（草案）

状态：2026-11-03 起草；同日用户确认第 8 节 6 项全部按建议执行，P0 签名与 Mac CloudKit 往返已通过；P1 同步模型与 P2 GitHub 来源、布局、配色、阅读位置同步已实现，Mac 单机双实例端到端通过；P3 iCloud 云盘文件夹同步已实现；跨设备增量拉取待真机验证，阅读位置已改为顶层内容块锚点（用户同意）；P4 开关与状态、隐私政策已完成；三台真机联测五项通过（配色改为不同步），待发布。本文是计划，不代表已实现或已验收。

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
| `readerPalette` | 配色 | 不同步（§8-2，联测后改为各设备独立） |
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
2. **外观与语言**：配色、明暗与界面语言均各设备独立（2026-11-03 真机联测后用户决定不再同步配色）。
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

### P1 · 2026-11-03

- 新增 `ReaderCore/Sources/ReaderCore/SyncState.swift`（纯 Swift，不依赖 CloudKit）：`SyncStamp`（时间 + 设备，时间相同按设备名决出，各端结果一致）、`Stamped` 字段级最后修改者胜、`SyncSource`（GitHub / iCloud 云盘文件夹）、删除墓碑、`SyncState.merge` 与去重重映射，以及 `CloudDrivePath.identity` 识别 iCloud 云盘相对路径（统一 Unicode 规范化，非 iCloud 位置返回 nil）。
- 合并规则：与合并方向无关；墓碑晚于来源修改时来源视为已移除，并清理其置顶、排序和阅读位置，后来写入的置顶不能复活已移除来源；同一内容（GitHub 规范化后的 owner/repo/路径/ref，或同一 iCloud 路径）保留添加最早者，把置顶、排序、阅读位置迁移过去并返回 `remapped` 供 App 迁移本机书签。
- 首次开启：本机旧数据使用 `SyncStamp.legacy`（1970 年），远端已有值优先，本机独有项保留并上传。
- 阅读位置上限 200 条，按最近读取时间淘汰；修正现有 `ReaderStore.recordProgress` 按键名字母序淘汰的问题需在 P2 接入时替换。
- 测试：`SyncStateTests` 7 项通过；ReaderCore 全部 49 项通过（1 项真实网络测试按默认跳过）。仅为模型层，App 尚未接入，不代表任何同步行为已可用。

### P2 · 2026-11-03

- ReaderCore `SyncRecords.swift`：`SyncSnapshot`（App 当前可同步内容，不含戳）与 `SyncState.absorb`（只给变化字段打新戳，快照缺少的来源记墓碑）；`SyncRecords` 负责 Source / Layout / Position 三类记录的编解码、两状态间待保存/删除记录、回声识别（`matches`）与删除记录的键恢复；`mergeSyncedOrder` 让远端置顶/排序生效，同时保留本机独有来源在原相邻位置。置顶/排序以逗号字符串存储：CloudKit 开发环境无法用空列表推断新字段类型（实测 Layout 首次保存因此被拒）。
- ReaderStore：仅新增 `syncSnapshot()`、`applySynced(_:)` 与保存 `sampleURL`，原有修改路径未改。本地文件夹（P3 前）不进入快照，其置顶/排序与阅读位置保持本机；正在打开的文档只更新保存值，不跳动，下次打开生效。
- App `ReaderSync.swift`（`CKSyncEngine`，私有库 Zone `ReaderState`）：本机改动静止 5 秒或 App 失去前台时记录并上传；合并远端前先吸收本机最新改动；全新启动先拉取合并再上传，且不重传与刚拉取内容一致的记录；`serverRecordChanged` 合并后重发；账户退出/切换或已同步区域被删时只重置同步记录，本机数据不动。系统字段与引擎状态存于 Application Support/Sync。`ReaderScreen` 启动时创建一次，未改界面。
- 测试：ReaderCore 53 项通过（新增 SyncRecords 4 项）；状态测试临时包重建后 40 项通过（新增 SyncStore 3 项：跨实例无回声、本机文件夹保留与移除来源、示例双向）；两项真实网络测试按默认跳过。Mac 与 iOS 模拟器编译通过，无新增警告。
- Mac 实际 CloudKit（开发环境）：临时无界面入口用两个独立 UserDefaults 套件和同步目录模拟设备 A/B，不创建 App 窗口、不读写用户资料库。A 添加公开 GitHub 文档、置顶、配色、阅读位置 → B 全部收到；B 移除来源 → 来源墓碑、Layout 上传并删除阅读位置记录；A 以新同步状态拉取后与 B 一致，过程中服务器冲突按合并规则处理。测试结束已删除开发环境 Zone 与临时数据，临时入口和跟踪代码已移除。
- 限制：同一台 Mac 上两个实例被 CloudKit 视为同一设备，增量拉取不会返回本设备写入的变更，因此“已同步设备收到另一设备的增量变更”尚未验证，需 iPhone/iPad 或已登录 iCloud 的模拟器与 Mac 联测；未打开 App 界面做同步交互/视觉回归。当前构建启动即同步且无开关，P4 加入“•••”开关前不得发布。

### P3 · 2026-11-03

- 本地文件夹的授权记录新增可选 `cloudPath`（iCloud 云盘内相对位置）；旧记录在可访问时启动补写，无法访问且无记录的旧文件夹仍视为本机独有。只有 iCloud 云盘内的文件夹进入同步，其他位置不上传。
- 其他设备同步来的 iCloud 文件夹在本机显示为“待授权”行：沿用授权失效行样式，按钮由“重试”变为“授权”，内容区提示“在这台设备上授权后即可阅读。”；点按打开系统文件夹选择器，所选位置的 iCloud 路径一致才绑定到同一来源 ID，否则提示“所选文件夹不是同一个 iCloud 云盘位置，未完成授权。”，取消选择保留待授权。通过“＋”自行添加同一 iCloud 文件夹也会自动绑定；已同步的阅读位置在绑定时保留。
- 两台设备在同步前各自添加同一 iCloud 文件夹：合并保留最早添加的 ID，本机书签、阅读位置、展开、置顶/排序随之迁移（`rebind`）。暂时无法访问的已同步 iCloud 文件夹仍保留在同步内容中，不会被误判为删除；只有用户移除才会同步删除。
- 新增 3 条中英文案（授权 / 待授权提示 / 位置不一致），`Localizable.xcstrings` 按原格式只追加。
- 测试：状态测试 43 项通过（新增 3 项：待授权保留进度与位置校验绑定、独立添加重绑、不可访问 iCloud 文件夹仍同步且本机文件夹不同步）；ReaderCore 53 项通过；两项真实网络测试按默认跳过。Mac 与 iOS 编译通过，无新增警告。
- 模拟器（iPhone 17，签名构建，独立数据）：写入一条待授权“Notes”，侧栏显示“Notes · 授权”与提示文案，品牌、加号与示例来源不变；点“授权”弹出系统文件夹选择器，取消后仍为待授权。测试后已卸载 App、关闭模拟器。模拟器未登录 iCloud，选中真实 iCloud 文件夹完成绑定的界面流程未测，由状态测试覆盖逻辑。
- 发现：未签名（不含 iCloud 授权）的构建在创建 CKContainer 时会退出；正式签名构建均含授权，不影响用户，但测试须使用签名构建。

### 阅读位置锚点 · 2026-11-03

用户同意把阅读位置从“全文百分比”改为“按标题/段落加段内偏移”。实现为 `<article>` 顶层内容块（标题、段落、列表、代码块、表格等，不含日期行）的序号加块内比例，仍存为一个数字：0–1 为旧全文比例，照旧恢复；≥2 为锚点（2 + 块序号 + 块内比例）。同步模型、本机存储和已有数据无需迁移；底部百分比仍显示全文比例。

- `reader.js` 上报全文比例与锚点；`ReaderWebView.positionScript` 恢复：锚点定位到原块内同一比例，上方懒加载图片加载完成时重新对齐，用户滚动/点按/按键或 10 秒后停止；块数变少时落到最后一块末尾。
- `ReaderStore.recordProgress` 保存锚点；刷新来源、单文件转入文件夹时保留已存锚点，不再用显示比例覆盖。顺带修正超过 200 条按键名字母序淘汰的问题：改为按最近阅读顺序淘汰（新增本机 `positionRecency`，旧数据无顺序视为最旧）。
- `SyncState.position` 放开同步模型的取值范围：锚点原样保留，旧比例仍限定 0–1。
- 测试：ReaderCore 54 项（新增取值范围 1 项）、状态测试 44 项（新增锚点保存与按最近阅读淘汰 1 项）通过；WebKit 实际脚本 64 组合通过，其中 32 组非空正文验证滚到某块后上报锚点、字号 17→26 后恢复同一块在顶部，以及旧 0.5 比例恢复误差 <2px。Mac 与 iOS 编译通过，无新增警告。
- 模拟器（iPhone 17，签名构建，独立数据）：示例文章滚动后保存值 11.2（锚点格式），重启后回到同一画面、显示同一百分比；测试后已卸载、关闭模拟器。真机、iPad 双栏宽度变化及含大量图片的长文未实测。

### P4 · 2026-11-03（进行中）

- 用户确认方案后实现：三端“•••”在“GitHub 授权”下新增“iCloud 同步”（云朵图标）；弹窗含“在设备间同步”开关（默认开启）、状态（已关闭 / iCloud 未登录 / 正在同步… / 已同步 / 暂时无法同步，稍后自动重试）与说明。关闭只停止 CloudKit 通信，保留本机数据、iCloud 数据与同步记录，重新开启后补记期间改动再交换；已停止或替换的引擎事件被忽略。不提供删除 iCloud 数据与立即同步按钮。英文采用与现有菜单一致的句首大写（iCloud sync / Sync across devices / Up to date 等）。
- 隐私政策中英文：删除“不提供跨设备同步”，新增“iCloud 同步”一段（同步内容、存于用户私有库、开发者无法访问、不含正文/令牌/缓存、关闭后不再上传）。页面由 main 的 `docs/` 发布，须随 0.3.0 推送，生效日期届时改为实际发布日；README 功能说明同样随发布更新。
- 验证：Mac 与 iOS 编译通过；iPhone 17 模拟器（签名构建、独立数据）检查菜单四项、中文浅色弹窗（未登录状态）、关闭后“已关闭”、英文深色菜单与弹窗及重新开启后状态，测试后已卸载并恢复浅色；Mac 弹窗画面与 iPad 未截。
- 待办：真机联测；正式发布前生成 Mac Developer ID 与 iOS App Store 描述文件、在 CloudKit Console 将开发环境 Schema 部署到生产、版本号 0.3.0（53）；Mac 公证与 GitHub Release、iOS 上传与审核（须等 0.2.1 审核结果）均需用户分别授权。

### 真机联测与改进 · 2026-11-03

- 三台同一 Apple 账户设备（Mac、iPhone 15、iPad Air）安装开发签名 Release 构建（CloudKit 开发环境），原标识与本机数据保留；Mac 0.2.2 正式版已备份。三台均已合并上传本机旧数据（iCloud 29 条记录，4 个来源，跨设备重复来源按规则折叠 3 个）。联测第 1 项（GitHub 来源与置顶）用户确认三端一致，但反馈有时较慢、需重进 App。
- 原因：Apple 文档要求 `CKSyncEngine` 具备 CloudKit 与远程通知能力；iOS 缺少 `remote-notification` 后台模式，收不到其他设备变更的静默推送，只能靠引擎定时或重启时拉取。
- 用户同意后改进：iOS `Info.plist` 增加 `UIBackgroundModes: remote-notification`；开启同步时注册远程推送（静默推送，无用户提示）；三端回到前台时自动同步一次；iPhone/iPad 侧栏增加系统下拉刷新（立即与 iCloud 交换变更并重新读取本地文件夹，GitHub 来源仍用各自刷新以避免 API 限流）。Mac 不加 ⌘R。状态测试 44 项通过，两端 Release 编译通过，已重新安装三台设备；推送时效与下拉刷新的真机效果待用户联测确认。

### 联测结果与配色调整 · 2026-11-03

- 三台真机联测（开发环境）：GitHub 来源与置顶三端一致；iPad 新增来源很快出现在 iPhone 与 Mac；阅读位置以锚点格式从 iPhone 接续到 iPad；iCloud 文件夹在 iPhone/iPad 授权后可读、无重复来源；iPad 上移除来源同步到其他设备并清理其阅读位置（用户确认时间线与本人操作一致）。
- 发现并修复：macOS 开启“桌面与文稿”时，`~/Documents`、`~/Desktop` 中的文件夹位于主目录而非 `Mobile Documents`，原识别规则将其视为本机独有，导致 iPhone/iPad 上移除的同一文件夹在 Mac 上不受影响。现于 macOS 对这两处且系统标记为 iCloud 项目的文件夹映射为 `com~apple~CloudDocs/Documents|Desktop/…`，与 iPhone/iPad 路径一致（ReaderCore 新增 1 项测试）。
- 配色同步联测不符合预期（开启时其他设备也未跟随）。用户决定：同步只处理文件相关内容，配色与明暗、语言一样各设备独立。已从同步模型、CloudKit 记录、ReaderStore、弹窗说明与隐私政策中移除配色；旧本机状态与服务器 Layout 记录中的配色字段读取时忽略，无需迁移。第 5 项开关改用置顶重测：iPad 关闭同步后置顶不传到 iPhone/Mac，重新开启后补同步，符合预期。五项联测全部通过；联测期间的只读 CloudKit 检查代码仅在本地使用，已删除未提交。
