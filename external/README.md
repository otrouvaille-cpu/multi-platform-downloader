# external 目录说明

本目录存放 `多平台下载器` 的第三方运行组件。项目要求 portable 自包含，因此这里的运行依赖默认保留，不从项目中迁出。

## 保留项

- `python\`：抖音专用后端使用的 portable Python 安装目录。
- `douyin-downloader\`：抖音专用后端源码，GUI 通过 `uv run --project external\douyin-downloader python run.py` 调用。
- `douyin-downloader\.venv\`：抖音后端虚拟环境。缺失时工具可尝试重建，但保留能减少首次运行成本。
- `webview2\`：内嵌登录需要的 WebView2 .NET DLL。

## 已归档项

- `uv-cache\` 已移动到 `07_Archive\2026\临时清理\多平台下载器_external_uv-cache\`。

## 原因

`uv-cache\` 是依赖下载/构建缓存，不是项目源代码，也不是必须随项目长期维护的运行资料。GUI 已设置 `UV_CACHE_DIR = external\uv-cache`，如果后续运行需要缓存，uv 会重新创建。

