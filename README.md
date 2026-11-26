# NASA APOD for Mac

A native macOS menu bar app for NASA's Astronomy Picture of the Day: today's image (or video thumbnail) in the menu, the full explanation in its own window, and a local archive that grows day by day.

一款原生 macOS 菜单栏应用：NASA 每日天文图。菜单里看今日图（视频日显示第一帧），独立窗口读完整说明，本地逐日归档。

## Features / 功能

- Today's APOD in the menu bar, with title, date and credit / 菜单栏直达今日天文图，含标题、日期与署名
- Explanation window with previous/next browsing through your local archive / 说明窗口，可在本地归档里前后翻看
- Video days handled honestly: first frame when available, the video itself archived (up to 100 MB) / 视频日如实处理：有第一帧存第一帧，并归档视频本体（上限 100 MB）
- A `.txt` sidecar saved with every day: title, date, credit, full explanation, source link / 每天另存同名 .txt：标题、日期、署名、说明全文、来源链接
- Shares its config and archive with the SwiftBar plugin and the Windows version (`~/.nasa-apod.conf`) / 与 SwiftBar 插件版、Windows 版共用配置与归档
- English / 简体中文 interface
- Built-in update check against this repository's releases / 内置更新检查（对本仓库 Release）

## Install / 安装

Download the `.pkg` from the latest release and install it, or build from source with `build.sh` (requires Xcode). The app is ad-hoc signed and not sandboxed, so first launch may need right-click → Open.

从最新 Release 下载 .pkg 安装，或用 `build.sh` 自行构建（需 Xcode）。本应用为 ad-hoc 签名、未沙盒，首次打开可能需要右键 → 打开。

## Changelog / 更新记录

### v1.0.1 — 2026-11-26
- Check for Updates now always answers a manual check: up-to-date, check-failed, or download-failed dialogs instead of silence / 手动检查更新必有回执：已是最新、检查失败、下载失败都会弹窗，不再无声无息

### v1.0.0 — 2026-11-26
- First standalone release: menu bar app with explanation window, daily archive with .txt sidecars, video-day support / 独立版首发：菜单栏应用 + 说明窗 + 每日归档（含 .txt）+ 视频日支持
