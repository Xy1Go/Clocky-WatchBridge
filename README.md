# Clocky → WatchBridge 未签名 IPA 打包流水线

把 [pookjw/Clocky](https://github.com/pookjw/Clocky) 编译成可被 Windows **WatchBridge** 侧载到
Apple Watch（watchOS 26.6.1）的**未签名 `.ipa`**，结构为 iOS + WatchKit 嵌套：

```
Payload/ClockyCompanion.app                       (iOS 宿主, com.custom.Clocky)
Payload/ClockyCompanion.app/Watch/Clocky.app      (Watch 端, com.custom.Clocky.watchkitapp)
```

## 环境要求

- 在 **macOS + Xcode 26（含 watchOS 26 SDK）** 上运行，本地或 GitHub Actions `macos-26` 均可。
- 全程**无签名编译**，不嵌入任何 `.mobileprovision`。

## 目录

```
Clocky-WatchBridge/
├── build.sh                      # 一键：克隆→编译→组装→打包 IPA
├── Companion/
│   ├── CompanionApp.swift        # 极简 iOS 宿主壳源码
│   └── Info.plist                # 宿主壳 Info.plist
└── .github/workflows/build.yml   # GitHub Actions 工作流
```

## 方式一：GitHub Actions（推荐，无需本机 Mac）

1. 把整个 `Clocky-WatchBridge` 目录推到一个 GitHub 仓库（新建一个仓库即可）。
   ```bash
   git init
   git add .
   git commit -m "Clocky WatchBridge build"
   git remote add origin https://github.com/<你的账号>/clocky-watchbridge.git
   git push -u origin main
   ```
2. 打开仓库 **Actions** 标签 → 左侧 `Build Clocky WatchBridge IPA` → **Run workflow**。
3. 跑完后在该次运行页面底部 **Artifacts** 下载 `Clocky-WatchBridge`（解压得到 `Clocky-WatchBridge.ipa`）。

> 如果 `macos-26` runner 不存在导致工作流无法启动，把 `build.yml` 里的 `runs-on: macos-26`
> 改成 GitHub 当前可用的最新 macOS runner（如 `macos-26` → 查一下可用标签）。

## 方式二：本机 macOS

```bash
git clone https://github.com/<你的账号>/clocky-watchbridge.git   # 或直接拿到本目录
cd Clocky-WatchBridge
bash build.sh
# 产物在 build/ipa/Clocky-WatchBridge.ipa
```

## 脚本做了什么

1. 克隆 Clocky `main` 分支。
2. `xcodebuild` 无签名编译 watchOS 端 `Clocky.app`（若 `arm64e.x1` 不被识别，自动退回 `ARCHS="arm64 arm64e"`）。
3. 用 `swiftc` 无签名编译极简 iOS 宿主 `ClockyCompanion.app`。
4. 组装嵌套结构，并用 `PlistBuddy` 修正 Watch 端 `Info.plist`：
   - `CFBundleIdentifier` = `com.custom.Clocky.watchkitapp`
   - 删除 `WKWatchOnly`
   - 添加 `WKCompanionAppBundleIdentifier` = `com.custom.Clocky`
5. 清除残留 `embedded.mobileprovision`，打包成 `Clocky-WatchBridge.ipa` 并校验目录结构。

## 注意

- 产物是**未签名** IPA，交给 WatchBridge 时由它用你的 Apple ID 重新签名。
- 使用 Apple 私有框架（NanoTimeKit 等），仅侧载用途，不可上架 App Store。
