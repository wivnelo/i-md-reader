# GitHub 只读授权

当前Mac正式发行0.2.0（46）；Mac/iPhone测试版0.2.1（47），iPad为0.2.1（48）。47/48未改变授权核心语义；Mac授权/添加来源弹窗已修复排版。自动缓存与各平台设置入口见[OFFLINE_CACHE](OFFLINE_CACHE.md)，验证边界见[STATUS](STATUS.md)。

入口：阅读区右上“••• → GitHub 授权”。当前首版采用个人细粒度访问令牌，不是OAuth登录；一个设备保存一份令牌，可替换或清除。公开仓库在未保存令牌时仍可匿名读取。

## 使用

1. 在GitHub创建fine-grained personal access token，选择资源所有者和需要阅读的仓库，设置到期时间。
2. 仓库权限仅将Contents设为Read-only，保持其他可选权限关闭；Metadata为GitHub要求的基础权限。不需要经典令牌的广泛repo权限。
3. 在App安全输入框保存，随后通过“GitHub链接”添加仓库、目录或MD文件。保存只确认本机存储成功，添加来源才检查实际仓库权限。
4. 组织可能要求审批；没有权限时GitHub也可能返回404。App不能通过令牌字符串证明全部权限只读，用户应在GitHub核对授予权限；App自身只发GET请求。

## 存储与清除

令牌仅保存于当前App的系统Keychain，使用WhenUnlockedThisDeviceOnly，不同步到iCloud、不进入UserDefaults、URL或日志，也不回填表单。请求头仅发到https://api.github.com，拒绝HTTP重定向，不使用Cookie或系统凭据。

替换/清除凭据时，旧客户端永久失效，取消在途请求，清空GitHub内存响应、目录、当前远程正文、阅读位置及展开状态；来源链接保留并收起，之后由用户重新打开。本地文件和目录授权不受影响。慢请求不能重新添加来源或恢复内容，旧图片加载器不能继续使用被清除的凭据。移除GitHub来源也触发内存响应清理。

服务器明确返回401时清除失效凭据和远程阅读状态；403可能是仓库权限或限流，不一律删除令牌。断网无法获知服务器刚撤销的权限；当前会话已读内容可能仍可阅读，直到用户清除授权或服务端确认失效。已接入加密磁盘缓存，清除授权也删除对应缓存；见[离线缓存](OFFLINE_CACHE.md)。

“清除授权”清除本机副本，不能撤销GitHub上的令牌。要使其他令牌副本失效，需在GitHub删除该令牌。若Keychain删除失败会显示错误，不声称已清除；服务器已明确拒绝的会话仍停止使用。

## 验证边界

合成响应测试覆盖GET/主机/认证头、不同凭据缓存隔离、畸形值拒绝、在途响应失效、旧图片加载拒绝、状态清理、未完成添加隔离、401、存储失败及普通配置不含令牌。模拟器原生检查另记录在开发状态中。没有使用开发机已有登录、真实令牌或私人知识库作为测试凭据；本期授权功能由用户整体确认通过；组织审批、过期/撤权矩阵等未逐项列出的异常仍为发布专项，不据此虚构新的真实仓库测试。

私有磁盘缓存按令牌隔离并加密；同令牌仍可在断网时解密，无法即时获知远端撤权。

当前方案适合个人安装；未来公开分发时再评估GitHub App或OAuth流程，不将个人令牌方案当作完整登录产品。

依据：[GitHub令牌管理](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)、[仓库内容只读权限](https://docs.github.com/en/rest/repos/contents#get-repository-content)、[Apple Keychain可访问性](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)。

## 阶段收口 · 2026-10-26

用户确认本期全部已交付功能已验证通过。当前授权提示去掉“创建只读令牌”标题，说明放在创建链接下方，使用与保存/清除相同的系统页脚提示。见[阶段总结](STAGE_2026-10-26.md)。
