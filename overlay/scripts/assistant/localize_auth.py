"""Translate the retained upstream sign-in and onboarding storyboard."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPLACEMENTS = {
    "Welcome to SideStore.": "欢迎使用定位助手",
    "Sign in with your Apple ID to get started.": "使用 Apple 账号登录以刷新自身签名。",
    "APPLE ID": "APPLE 账号",
    "PASSWORD": "密码",
    "Sign in": "登录",
    "Why do we need this?": "为什么需要登录？",
    "Close": "关闭",
    "Launch SideStore": "打开定位助手",
    "Leave SideStore running in the background on your idevice.": "首次安装后，导入这台设备自己的配对文件。",
    "Connect to Wi-Fi and VPN": "连接 Wi-Fi 和 LocalDevVPN",
    "Enable LocalDevVPN and use Sidestore on the go.": "启用 LocalDevVPN，再检查设备连接。",
    "Download Apps": "选择模拟位置",
    "Browse and download apps directly from SideStore.": "在定位页搜索、选点或输入 WGS-84 经纬度。",
    "Apps Refresh Automatically": "手动刷新自身签名",
    "Apps are refreshed in the background while you are on SideStore VPN!": "在续签页手动刷新；续签前先清除模拟定位。",
    "Got it": "知道了",
    "How it works": "使用说明",
    "Resign Now": "立即重新签名",
    "Resign Later": "稍后再签名",
    "Resign SideStore": "重新签名定位助手",
    "Select a Team": "选择开发者团队",
}

def main():
    path = ROOT / "AltStore/Authentication/Authentication.storyboard"
    content = path.read_text(encoding="utf-8")
    for old, new in REPLACEMENTS.items():
        for attribute in ("text", "title"):
            content = content.replace(f'{attribute}="{old}"', f'{attribute}="{new}"')
    content = content.replace("Your Apple ID is used to configure apps so they can be installed on this device. Your credentials will be stored securely in this device's Keychain and sent only to Apple for authentication.", "Apple 账号用于向 Apple 验证身份及申请自身续签所需的描述文件。凭据保存在本设备钥匙串。已有证书还需要对应私钥，请先在设置中导入续签证书。")
    path.write_text(content, encoding="utf-8")

if __name__ == "__main__": main()
