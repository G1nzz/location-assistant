# 开源来源与许可证

本项目保留 SideStore 的 AGPL-3.0 许可证，见 LICENSE；定位 FFI 适配源于 StikDebug 3.1.13，见 Vendor/StikDebug-LICENSE。原作者声明保留在上游源码中。分发修改后的安装包时，同时向接收者提供对应源码及构建资料。

| 上游 | 固定提交 | 用途 |
|---|---|---|
| https://github.com/SideStore/SideStore | 6032424a0e56c1c319762e786099bdd9186a238b | 账号、签名、自身刷新、数据库 |
| https://github.com/StikDebug/StikDebug | 4bdfc92aa7cebd7a534f1e1ef56415f5727402de | 定位 FFI 及 idevice 库 |
| https://github.com/SideStore/SideSign | a731c0d5a9a6617c7b385ae493e07ffb7f81cd5d | 签名与 Apple 开发者服务 |
| https://github.com/SideStore/minimuxer | 98c3c79982f813878e922ab42f9545314a700f0c | 本机设备连接 |

依赖各自的许可证保留在下载后的源码中。Swift Package Manager 的间接依赖沿用上游 Package.resolved，具体版本以云端构建输出为准。完整来源记录在 upstream-lock.json。

公开仓库以固定版本下载脚本和修改覆盖文件组成，构建时还原完整源码。账号、真实 UDID、配对文件、位置收藏和开发者证书不属于公开源码。
