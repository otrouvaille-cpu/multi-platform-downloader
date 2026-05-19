# Multi-Platform Video Downloader

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Platform-Windows-blue)]()
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)]()

> 多平台视频下载工具，支持 B站 / 抖音 / YouTube / Twitter(X) / Instagram 及数千个其他网站。  
> 自带图形界面，内嵌浏览器登录，开箱即用。

![screenshot](https://via.placeholder.com/800x500?text=Screenshot)

## Features

- **多平台支持** — B站、抖音（专用后端）、YouTube、Twitter/X、Instagram，以及 yt-dlp 支持的数千个站点
- **图形界面** — PowerShell 原生 GUI，无需 Electron 臃肿依赖
- **内嵌浏览器登录** — 一键登录账号，支持密码/扫码/手机验证码，cookie 自动管理
- **抖音整段文案解析** — 粘贴分享文案自动提取链接
- **多账号管理** — 每个平台可保存多份 cookie，随时切换
- **最高画质下载** — 自动选择可用最佳画质
- **便携设计** — 所有依赖一键更新，单目录携带，USB 即插即用
- **分享包制作** — 一键打包可分发版本，自动排除个人数据

## Quick Start

```powershell
# 克隆仓库
git clone https://github.com/otrouvaille-cpu/multi-platform-downloader.git
cd multi-platform-downloader

# 一键安装运行时依赖（deno / ffmpeg / yt-dlp / uv / 抖音后端）
.\setup.bat

# 启动图形界面
.\video_downloader_gui.ps1
```

或者从 [Releases](https://github.com/otrouvaille-cpu/multi-platform-downloader/releases) 下载完整包，解压即用。

## Requirements

- Windows 10 / Windows 11
- PowerShell 5.1+（Windows 10/11 自带）

首次运行 `setup.bat` 会自动下载以下组件：

| Component | Role |
|-----------|------|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 核心下载引擎 |
| [FFmpeg](https://ffmpeg.org/) | 视频合并与处理 |
| [Deno](https://deno.com/) | JavaScript 运行环境 |
| [uv](https://github.com/astral-sh/uv) | Python 包管理器 |
| [douyin-downloader](https://github.com/jiji262/douyin-downloader) | 抖音专用下载后端 |

## Usage

### GUI 模式（推荐）

```powershell
.\video_downloader_gui.ps1
```

1. 复制视频链接（或抖音分享文案）→ 点击 **粘贴**
2. 如需登录，选择平台 → 点击 **登录/切换账号**
3. 点击 **开始下载**

### 命令行模式

```powershell
.\video_downloader.ps1 -Url "https://www.youtube.com/watch?v=xxx"
```

或通过备用菜单选择：

```powershell
.\命令行备用菜单.bat
```

### 更新运行时

```powershell
.\portable_update_tools.ps1
```

### 制作分享包

```powershell
.\04_制作分享包.bat
```

## Supported Platforms

| Platform | Login | Notes |
|----------|-------|-------|
| B站 (Bilibili) | 内嵌浏览器 | 自动获取昵称作为文件名 |
| 抖音 (Douyin) | 内嵌浏览器 | 使用专用 Python 后端，支持整段文案解析 |
| YouTube | 内嵌浏览器 | Google API 限制，建议手动备注账号名 |
| Twitter / X | 内嵌浏览器 | |
| Instagram | 内嵌浏览器 | Meta API 限制，建议手动备注账号名 |
| 其他数千站点 | — | 通过 yt-dlp 通用引擎支持 |

## Project Structure

```
multi-platform-downloader/
├── video_downloader_gui.ps1    # 图形界面
├── video_downloader.ps1        # 命令行下载器
├── portable_update_tools.ps1   # 运行时一键更新
├── functions/                  # PowerShell 功能模块
│   └── webview2_login.ps1      # 内嵌浏览器登录
├── external/
│   ├── douyin-downloader/      # 抖音专用后端
│   ├── python/                 # 便携 Python（首次运行自动下载）
│   └── webview2/               # WebView2 运行时
├── setup.bat                   # 一键安装运行环境
├── 使用指南.txt                # 详细使用说明
└── 项目治理说明.md             # 项目结构与治理策略
```

## Build from Source

本项目为纯 PowerShell + Python，无需编译。克隆后运行 `setup.bat` 即可。

如需制作可分发 ZIP 包：

```powershell
.\04_制作分享包.bat
```

分享包会自动排除 `_user_data`、`_packages` 等个人数据。

## License

MIT
