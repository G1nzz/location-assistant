# 定位助手（开发验证版）

中文 iPhone / iPad 工具，集成 SideStore 自身续签和 StikDebug 位置模拟，需要独立 LocalDevVPN、开发者模式及每台设备自己的配对文件。

当前版本 **0.2.5（9）** 将两个固定版本的开发者映像随安装包提供；设备先校验本地文件，无需访问 GitHub 下载映像。具体行为与限制见 [本地映像说明](overlay/docs/0.2.5-本地开发者映像.md)。保留 0.2.4 的私钥保存修复和独立续签回执；不会自动撤销已有证书。同一签名账号的设备需复用同一份含私钥证书，每台设备仍需自己的配对文件。

2026-10-19，0.2.4 在 iPhone 12 / iOS 18.6.2 和 iPad 9 / 用户提供的 iPadOS 26.6 均由用户确认账号验证、自身续签和重开后私钥与回执保留成功。随后 iPad 准备映像时报告 BuildManifest.plist / NSURLErrorDomain / -1000；该设备没有外部 VPN。0.2.5 取消正常映像准备对设备下载源的依赖，尚待真机验证，不能将其视为已经查明 -1000 的底层原因。详细状态见 [验收记录](overlay/docs/验收记录.md)。

Apple 登录错误 -80045、-22421、-90010 仍可能发生，代码修复与编译成功不保证 Apple 当前允许登录。安装、定位、恢复与自身续签分别验证。

## 获取安装包

在 Actions → Build Chinese Location Assistant 中选择成功运行，下载 LocationAssistant-unsigned-for-local-signing。解压的 IPA 需要通过 iloader 本地重新签名安装；更新时使用相同签名账号覆盖安装，保留原 App。原版 SideStore 导出完整 p12 的入口在证书列表长按菜单中，具体见 [安装与恢复指南](overlay/docs/安装与恢复指南.md)。

## 源码与构建

仓库保存修改覆盖文件，完整源码由 upstream-lock.json 指定的提交还原，保留上游许可证，不跟随上游分支自动更新。

```sh
python3 -B scripts/materialize.py
brew install ldid
bash project/scripts/assistant/build.sh
```

GitHub Actions 使用 macOS / Xcode，产物在 project/.build/artifacts/。Windows 不能直接执行 iOS 编译。

主界面为定位、续签、设置。选点后点击开始才提交位置，清除失败保留未知状态；收藏保存在设备上。在设置中准备本地开发者映像，再连接 LocalDevVPN 挂载；挂载时仍可能需要 Apple 个性化服务。只提供手动自身续签，不提供其他 IPA 安装、JIT 或路线模拟。最低安装版本暂设 17.4，系统兼容性以实测为准。

不要上传 Apple 账号、私钥、配对、UDID 或私人收藏。项目采用 AGPL-3.0，来源见 THIRD_PARTY_NOTICES.md；早期内部审查与版本说明保留作历史记录。
