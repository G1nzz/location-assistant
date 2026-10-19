# 定位助手（开发验证版）

中文 iPhone / iPad 工具，集成 SideStore 自身续签和 StikDebug 位置模拟。需要独立的 LocalDevVPN、开发者模式，以及每台设备自己的配对文件。

0.2.1（5）完成内部审查修复，并延续 0.2.0 的重构启动、定位与续签的边界：定位页不再等待签名数据库、远端软件源或 JIT 发现；续签单独管理进度和失败状态，到期时间直接读取当前安装包描述文件。保留 0.1.2 的本机钥匙串、证书读回校验和双重验证补丁。[重构说明与验证限制](overlay/docs/0.2.0-重构说明.md)。

**Apple 登录错误 -80045、-22421、-90010 仍可能发生。重构不代表上游认证问题已解决，也不代表已在真机通过定位或自身续签验收。**

**当前不能以源码存在代替可用性验证。** Actions 构建完成后仍需设备安装、定位恢复和自身续签测试；状态见 `overlay/docs/验收记录.md`。

内部审查的缺陷、修复及剩余限制见 [0.2.1 内部审查](overlay/docs/0.2.1-内部审查.md)。本轮不安排真机验收。

## 获取安装包

进入 Actions → Build Chinese Location Assistant → 选择成功运行 → 下载 `LocationAssistant-unsigned-for-local-signing`。解压后的 IPA 需要通过 iloader 本地签名安装，不是可直接安装的永久签名包。

## 源码与构建

仓库保存修改覆盖文件，原始完整源码由 `upstream-lock.json` 指定的提交还原，保留上游许可证。不会跟随上游分支自动升级。

macOS 使用：

```sh
python3 -B scripts/materialize.py
brew install ldid
bash project/scripts/assistant/build.sh
```

产物在 `project/.build/artifacts/`。GitHub Actions 使用 macOS / Xcode；Windows 不能直接运行 iOS 编译步骤。

主界面为定位、续签、设置。选点不会自动修改位置；清除操作失败时显示未知状态。位置收藏只保存在设备上。第一版仅手动续签，不提供其他 IPA 安装、JIT 或路线模拟。

## 首批设备

- iPhone 12 / iOS 18.6.2。
- iPad 9 / 用户提供的 iPadOS 26.6。
- 最低安装版本暂设 17.4，具体系统能否定位和续签以实测为准。

安装流程与恢复位置见 `overlay/docs/安装与恢复指南.md`。不要上传 Apple 账号、配对文件、UDID、证书或私人收藏。项目采用 AGPL-3.0，来源详见 `THIRD_PARTY_NOTICES.md`。

当前修复版本：0.2.3（构建 7）。新增独立的映像提前下载入口，允许先完成下载，再切换到 LocalDevVPN 挂载；失败时保留安全的阶段、错误域和代码。详见 overlay/docs/0.2.3-映像提前下载与诊断.md。0.2.3 尚未真机验证。

本版 0.2.4（8）修复首次签名初始化删除刚导入私钥的问题，并分别显示安装包日期和本设备续签回执。详见 `overlay/docs/0.2.4-续签私钥保留与回执.md`。
