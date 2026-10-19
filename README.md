# 定位助手（开发验证版）

中文 iPhone / iPad 工具，集成 SideStore 自身续签和 StikDebug 位置模拟，需要独立 LocalDevVPN、开发者模式及每台设备自己的配对文件。

当前版本 **0.2.4（8）** 修复首次签名初始化删除刚导入私钥的问题，并分别显示安装包内日期和本设备续签回执。具体原因、修复与限制见 [续签修复说明](overlay/docs/0.2.4-续签私钥保留与回执.md)。不会自动撤销已有证书；同一签名账号的设备需复用同一份含私钥证书，每台设备仍需自己的配对文件。

2026-10-19，0.2.3 已在 iPhone 12 / iOS 18.6.2 完成映像下载校验、挂载确认，用户报告苹果地图位置生效和清除操作成功；自身续签尚未确认。0.2.4 真机验证待完成，iPad 9 / 用户提供的 iPadOS 26.6 尚未进入本轮。详细状态见 [验收记录](overlay/docs/验收记录.md)。

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

主界面为定位、续签、设置。选点后点击开始才提交位置，清除失败保留未知状态；收藏保存在设备上。提供映像提前下载，可先完成下载及校验，再切换 LocalDevVPN 挂载。只提供手动自身续签，不提供其他 IPA 安装、JIT 或路线模拟。最低安装版本暂设 17.4，系统兼容性以实测为准。

不要上传 Apple 账号、私钥、配对、UDID 或私人收藏。项目采用 AGPL-3.0，来源见 THIRD_PARTY_NOTICES.md；早期内部审查与版本说明保留作历史记录。
