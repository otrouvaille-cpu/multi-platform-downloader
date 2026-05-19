<#
    便携版多平台视频下载器
    所有程序路径基于当前脚本所在文件夹，不依赖固定盘符。
    用户数据统一放入 _user_data，便于分享时自动排除。
#>

$ErrorActionPreference = "Stop"

$ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UserDataDir = Join-Path $ToolDir "_user_data"
$CookieDir = Join-Path $UserDataDir "cookies"
$StateDir = Join-Path $UserDataDir "state"
$LogDir = Join-Path $UserDataDir "logs"
$PackageDir = Join-Path $ToolDir "_packages"
$DefaultOutDir = Join-Path $env:USERPROFILE "Downloads\Videos"
$YtDlp = Join-Path $ToolDir "yt-dlp.exe"
$Ffmpeg = Join-Path $ToolDir "ffmpeg.exe"
$Deno = Join-Path $ToolDir "deno.exe"
$ConfigPath = Join-Path $StateDir "settings.json"
New-Item -ItemType Directory -Force -Path $CookieDir, $StateDir, $LogDir, $PackageDir | Out-Null

$PlatformInfo = [ordered]@{
    bilibili = [pscustomobject]@{
        Label = "B站"
        Home = "https://www.bilibili.com/"
        Domains = @("bilibili.com", "b23.tv")
        CookiePatterns = @("cookies_bilibili_*.txt", "cookies.txt")
    }
    douyin = [pscustomobject]@{
        Label = "抖音"
        Home = "https://www.douyin.com/"
        Domains = @("douyin.com", "v.douyin.com", "iesdouyin.com", "amemv.com", "snssdk.com")
        CookiePatterns = @("cookies_douyin_*.txt")
    }
    twitter = [pscustomobject]@{
        Label = "Twitter/X"
        Home = "https://x.com/"
        Domains = @("x.com", "twitter.com")
        CookiePatterns = @("cookies_twitter_*.txt")
    }
    youtube = [pscustomobject]@{
        Label = "YouTube"
        Home = "https://www.youtube.com/"
        Domains = @("youtube.com", "youtu.be")
        CookiePatterns = @("cookies_youtube_*.txt")
    }
    instagram = [pscustomobject]@{
        Label = "Instagram"
        Home = "https://www.instagram.com/"
        Domains = @("instagram.com")
        CookiePatterns = @("cookies_instagram_*.txt")
    }
    generic = [pscustomobject]@{
        Label = "通用"
        Home = "https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md"
        Domains = @()
        CookiePatterns = @("cookies_*.txt", "cookies.txt")
    }
}

function Pause-Exit {
    Write-Host ""
    Read-Host "按 Enter 继续"
}

function Is-Url {
    param([string]$Text)
    return $Text -match '^https?://'
}

function Extract-FirstUrl {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $match = [regex]::Match($Text, 'https?://[^\s"''<>，。；、]+')
    if (-not $match.Success) { return "" }
    return $match.Value.TrimEnd('.', ',', ';', ')', ']', '}', '。', '，')
}

function Ensure-File {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { throw "未找到 $Name：$Path" }
}

function Download-FileWithFallback {
    param([string[]]$Urls, [string]$Destination)

    foreach ($url in $Urls) {
        try {
            Write-Host "下载：$url"
            if (Test-Path $Destination) { Remove-Item -Force $Destination }
            curl.exe --fail --location --retry 3 --connect-timeout 20 --output $Destination $url
            if ($LASTEXITCODE -eq 0 -and (Test-Path $Destination)) { return }
            throw "curl 退出码：$LASTEXITCODE"
        } catch {
            Write-Host "下载失败：$($_.Exception.Message)"
        }
    }
    throw "所有下载源都失败：$Destination"
}

function Ensure-DenoRuntime {
    if (Test-Path $Deno) { return }

    Write-Host ""
    Write-Host "检测到缺少 YouTube 需要的 Deno JavaScript Runtime，正在自动安装便携版..."
    $tmpDir = Join-Path $UserDataDir "tmp_deno"
    $zip = Join-Path $tmpDir "deno.zip"
    if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    Download-FileWithFallback -Urls @(
        "https://dl.deno.land/release/latest/deno-x86_64-pc-windows-msvc.zip",
        "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip",
        "https://mirror.ghproxy.com/https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip",
        "https://gh-proxy.com/https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip"
    ) -Destination $zip

    Expand-Archive -Force -Path $zip -DestinationPath $tmpDir
    $found = Get-ChildItem -Path $tmpDir -Recurse -Filter "deno.exe" | Select-Object -First 1 -ExpandProperty FullName
    if (-not $found) { throw "Deno 压缩包解压后未找到 deno.exe" }
    Copy-Item -Force -LiteralPath $found -Destination $Deno
    Remove-Item -Recurse -Force $tmpDir

    & $Deno --version | Select-Object -First 1
    Write-Host "Deno 已安装到：$Deno"
}

function Safe-ReadClipboardUrl {
    try {
        $clip = (Get-Clipboard -Raw -ErrorAction Stop).Trim()
        if (Is-Url $clip) { return $clip }
    } catch {}
    return ""
}

function Detect-PlatformFromUrl {
    param([string]$Url)
    $Url = Extract-FirstUrl $Url
    foreach ($key in $PlatformInfo.Keys) {
        if ($key -eq "generic") { continue }
        foreach ($domain in $PlatformInfo[$key].Domains) {
            if ($Url -match [regex]::Escape($domain)) { return $key }
        }
    }
    return "generic"
}

function Normalize-DouyinUrl {
    param([string]$Url)
    if ($Url -match '[?&]modal_id=(\d+)') { return "https://www.douyin.com/video/$($Matches[1])" }
    if ($Url -match '[?&]aweme_id=(\d+)') { return "https://www.douyin.com/video/$($Matches[1])" }
    if ($Url -match '/share/video/(\d+)') { return "https://www.douyin.com/video/$($Matches[1])" }
    if ($Url -match '/video/(\d+)') { return "https://www.douyin.com/video/$($Matches[1])" }
    return $Url
}

function Resolve-InputUrl {
    param([string]$InputText)
    $url = Extract-FirstUrl $InputText
    if (-not $url) { return "" }
    if ((Detect-PlatformFromUrl $url) -eq "douyin") { return Normalize-DouyinUrl $url }
    return $url
}

function Get-PlatformLabel {
    param([string]$Platform)
    if ($PlatformInfo.Contains($Platform)) { return $PlatformInfo[$Platform].Label }
    return "通用"
}

function Select-Platform {
    Write-Host "选择平台："
    $keys = @("bilibili", "douyin", "twitter", "youtube", "instagram", "generic")
    for ($i = 0; $i -lt $keys.Count; $i++) {
        Write-Host ("{0}. {1}" -f ($i + 1), (Get-PlatformLabel $keys[$i]))
    }
    Write-Host ""
    $choice = Read-Host "请输入编号，直接回车默认 1"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $keys.Count) { throw "无效编号：$choice" }
    return $keys[$index]
}

function Load-Config {
    $config = [ordered]@{
        defaultCookies = @{}
        downloadDir = $null
        updatedAt = $null
    }

    if (-not (Test-Path $ConfigPath)) { return $config }

    try {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $ConfigPath | ConvertFrom-Json
        if ($raw.defaultCookieName) {
            # 兼容旧版设置：旧默认账号只用于 B 站。
            $config.defaultCookies["bilibili"] = [string]$raw.defaultCookieName
        }
        if ($raw.defaultCookies) {
            foreach ($prop in $raw.defaultCookies.PSObject.Properties) {
                if ($prop.Value) { $config.defaultCookies[$prop.Name] = [string]$prop.Value }
            }
        }
        if ($raw.downloadDir) { $config.downloadDir = [string]$raw.downloadDir }
        if ($raw.updatedAt) { $config.updatedAt = [string]$raw.updatedAt }
    } catch {}

    return $config
}

function Save-Config {
    param([hashtable]$DefaultCookies, [string]$DownloadDir)
    [pscustomobject]@{
        defaultCookies = $DefaultCookies
        downloadDir = $DownloadDir
        updatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    } | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -Path $ConfigPath
}

function Get-DownloadDir {
    $cfg = Load-Config
    if ($cfg.downloadDir -and -not [string]::IsNullOrWhiteSpace($cfg.downloadDir)) { return [string]$cfg.downloadDir }
    return $DefaultOutDir
}

function Set-DownloadDir {
    $currentDir = Get-DownloadDir
    New-Item -ItemType Directory -Force -Path $currentDir | Out-Null
    Write-Host "将打开 Windows 文件夹选择窗口。"
    Write-Host "当前下载目录：$currentDir"

    $dir = $null
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "请选择视频下载目录"
        $dialog.SelectedPath = $currentDir
        $dialog.ShowNewFolderButton = $true
        $result = $dialog.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $dir = $dialog.SelectedPath
        }
    } catch {
        # 备用方案：部分 PowerShell 环境无法加载 WinForms 时，使用系统 Shell 文件夹选择器。
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.BrowseForFolder(0, "请选择视频下载目录", 0x00000041, $currentDir)
        if ($folder) { $dir = $folder.Self.Path }
    }

    if ([string]::IsNullOrWhiteSpace($dir)) {
        Write-Host "已取消，下载目录保持不变：$currentDir"
        return
    }

    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $cfg = Load-Config
    Save-Config -DefaultCookies $cfg.defaultCookies -DownloadDir $dir
    Write-Host "已设置下载目录：$dir"
}

function Get-CookieFiles {
    param([string]$Platform = "generic", [switch]$All)

    $patterns = New-Object System.Collections.Generic.List[string]
    if ($All -or $Platform -eq "generic") {
        foreach ($p in @("cookies_*.txt", "cookies.txt")) { $patterns.Add($p) }
    } else {
        foreach ($p in $PlatformInfo[$Platform].CookiePatterns) { $patterns.Add($p) }
    }

    $files = @()
    foreach ($pattern in $patterns) {
        $files += Get-ChildItem -Path $CookieDir -File -Filter $pattern -ErrorAction SilentlyContinue
    }
    return @($files | Sort-Object LastWriteTime -Descending -Unique)
}

function Get-CookieLabel {
    param([System.IO.FileInfo]$File)
    if (-not $File) { return "无" }

    $name = $File.BaseName
    if ($name -eq "cookies") { $name = "旧版默认 cookies" }
    return "{0}  ({1})" -f $name, $File.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
}

function Test-BilibiliCookie {
    param([System.IO.FileInfo]$CookieFile)
    if (-not $CookieFile -or -not (Test-Path $CookieFile.FullName)) { return $false }

    $required = @("SESSDATA", "DedeUserID", "bili_jct")
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $CookieFile.FullName
    foreach ($key in $required) {
        if ($content -notmatch "(?m)^[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t$key\t\S") {
            return $false
        }
    }
    return $true
}

function Resolve-DefaultCookie {
    param([string]$Platform)

    $cfg = Load-Config
    if ($cfg.defaultCookies.ContainsKey($Platform)) {
        $candidate = Join-Path $CookieDir ([string]$cfg.defaultCookies[$Platform])
        if (Test-Path $candidate) { return Get-Item $candidate }
    }

    $platformFiles = Get-CookieFiles -Platform $Platform
    if ($platformFiles.Count -gt 0) { return $platformFiles[0] }

    if ($Platform -eq "bilibili") {
        $legacy = Join-Path $CookieDir "cookies.txt"
        if (Test-Path $legacy) { return Get-Item $legacy }
    }

    return $null
}

function Select-CookieFile {
    param([string]$Platform = "generic", [switch]$AllowNone, [switch]$All)

    $files = Get-CookieFiles -Platform $Platform -All:$All
    if ($files.Count -eq 0) {
        Write-Host "没有找到 cookies 文件。"
        return $null
    }

    Write-Host "可用账号 cookies："
    for ($i = 0; $i -lt $files.Count; $i++) {
        Write-Host ("{0}. {1}" -f ($i + 1), (Get-CookieLabel $files[$i]))
    }
    if ($AllowNone) { Write-Host "0. 不使用 cookies（部分平台可能无法获取最高画质或无法下载）" }
    Write-Host ""

    $choice = Read-Host "请输入编号，直接回车选择第 1 个"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    if ($AllowNone -and $choice -eq "0") { return $null }
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $files.Count) { throw "无效编号：$choice" }
    return $files[$index]
}

function Get-VideoUrl {
    $clipboardUrl = Safe-ReadClipboardUrl
    if ($clipboardUrl) {
        Write-Host "检测到剪贴板链接："
        Write-Host $clipboardUrl
        $inputUrl = Read-Host "直接回车使用剪贴板链接，或粘贴新链接"
        if ([string]::IsNullOrWhiteSpace($inputUrl)) { return $clipboardUrl }
        return $inputUrl.Trim()
    }
    return (Read-Host "请粘贴视频链接").Trim()
}

function Build-YtDlpArgs {
    param(
        [string]$VideoUrl,
        [System.IO.FileInfo]$CookieFile,
        [string]$Platform
    )

    $downloadDir = Get-DownloadDir
    $outputTemplate = Join-Path $downloadDir "%(title).200B_%(uploader).80B.%(ext)s"
    $args = @(
        "--ffmpeg-location", $ToolDir,
        "-f", "bv*+ba/b",
        "-S", "res,fps,hdr,vbr,abr,size",
        "--merge-output-format", "mp4",
        "--windows-filenames",
        "--no-mtime",
        "--no-playlist",
        "--no-overwrites",
        "--retries", "10",
        "--fragment-retries", "10",
        "--extractor-retries", "3",
        "--socket-timeout", "30",
        "--newline",
        "--progress",
        "--progress-template", "download:下载进度：%(progress._percent_str)s  速度：%(progress._speed_str)s  剩余：%(progress._eta_str)s",
        "--progress-template", "postprocess:正在合并/处理：%(info.title).120B",
        "-o", $outputTemplate
    )

    if ($Platform -eq "youtube") {
        Ensure-DenoRuntime
        $args += @("--js-runtimes", "deno:$Deno", "--remote-components", "ejs:github")
    }
    if ($Platform -eq "douyin") {
        $args += @("--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36", "--referer", "https://www.douyin.com/")
    }

    if ($CookieFile) { $args += @("--cookies", $CookieFile.FullName) }
    $args += $VideoUrl
    return $args
}

function Start-Download {
    param([System.IO.FileInfo]$CookieFile, [string]$ForcedPlatform = "")

    Ensure-File $YtDlp "yt-dlp.exe"
    Ensure-File $Ffmpeg "ffmpeg.exe"
    $downloadDir = Get-DownloadDir
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

    $videoUrl = Resolve-InputUrl (Get-VideoUrl)
    if ($videoUrl -match '^(q|Q)$') { return }
    if (-not (Is-Url $videoUrl)) { throw "输入的不是有效链接：$videoUrl" }

    $platform = if ($ForcedPlatform) { $ForcedPlatform } else { Detect-PlatformFromUrl $videoUrl }
    Write-Host ""
    Write-Host "识别平台：$(Get-PlatformLabel $platform)"

    if ($platform -eq "bilibili" -and $CookieFile -and -not (Test-BilibiliCookie $CookieFile)) {
        Write-Host "警告：B站 cookies 缺少 SESSDATA / DedeUserID / bili_jct，可能已过期。"
        Write-Host "将尝试下载，但可能无法获取最高画质。建议重新导出 cookies。"
        Write-Host ""
    }

    if ($CookieFile) {
        Write-Host "使用账号 cookies：$(Get-CookieLabel $CookieFile)"
    } else {
        Write-Host "未使用 cookies。公开视频可尝试下载；需要登录权限的平台可能失败或不是最高画质。"
    }

    $args = Build-YtDlpArgs -VideoUrl $videoUrl -CookieFile $CookieFile -Platform $platform
    Write-Host ""
    Write-Host "开始下载账号可访问的最高质量..."
    Write-Host ""

    & $YtDlp @args
    if ($LASTEXITCODE -ne 0) { throw "yt-dlp 下载失败，退出码：$LASTEXITCODE" }

    Write-Host ""
    Write-Host "下载完成。"
    Write-Host "保存目录：$downloadDir"
}

function Start-AutoDownload {
    $videoUrl = Resolve-InputUrl (Get-VideoUrl)
    if ($videoUrl -match '^(q|Q)$') { return }
    if (-not (Is-Url $videoUrl)) { throw "输入的不是有效链接：$videoUrl" }

    $platform = Detect-PlatformFromUrl $videoUrl
    $cookie = Resolve-DefaultCookie -Platform $platform

    if ($platform -eq "bilibili" -and $cookie -and -not (Test-BilibiliCookie $cookie)) {
        Write-Host ""
        Write-Host "警告：B站 cookies 缺少 SESSDATA / DedeUserID / bili_jct，可能已过期。"
        Write-Host "将尝试下载，但可能无法获取最高画质。建议重新导出 cookies。"
        Write-Host ""
    }

    Ensure-File $YtDlp "yt-dlp.exe"
    Ensure-File $Ffmpeg "ffmpeg.exe"
    $downloadDir = Get-DownloadDir
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

    Write-Host ""
    Write-Host "识别平台：$(Get-PlatformLabel $platform)"
    if ($cookie) {
        Write-Host "自动使用：$(Get-CookieLabel $cookie)"
    } else {
        Write-Host "没有找到该平台默认 cookies，将不带登录状态下载。"
        Write-Host "如需账号权限，请先用菜单 3 导出 cookies，再用菜单 4 设置默认账号。"
    }

    $args = Build-YtDlpArgs -VideoUrl $videoUrl -CookieFile $cookie -Platform $platform
    Write-Host ""
    Write-Host "开始下载账号可访问的最高质量..."
    Write-Host ""

    & $YtDlp @args
    if ($LASTEXITCODE -ne 0) { throw "yt-dlp 下载失败，退出码：$LASTEXITCODE" }

    Write-Host ""
    Write-Host "下载完成。"
    Write-Host "保存目录：$downloadDir"
}

function Show-CookieStatus {
    $cfg = Load-Config
    Write-Host "默认账号："
    foreach ($platform in @("bilibili", "douyin", "twitter", "youtube", "instagram")) {
        $label = Get-PlatformLabel $platform
        $cookie = Resolve-DefaultCookie -Platform $platform
        if ($cookie) {
            $mark = ""
            if ($cfg.defaultCookies.ContainsKey($platform) -and $cfg.defaultCookies[$platform] -eq $cookie.Name) { $mark = "已指定" }
            else { $mark = "自动选择最新" }

            $warning = ""
            if ($platform -eq "bilibili" -and -not (Test-BilibiliCookie $cookie)) {
                $warning = " [已过期，缺 SESSDATA！]"
            }
            Write-Host ("  {0}：{1} [{2}]{3}" -f $label, (Get-CookieLabel $cookie), $mark, $warning)
        } else {
            Write-Host ("  {0}：未设置" -f $label)
        }
    }
}

function New-SharePackage {
    $date = Get-Date -Format "yyyyMMdd-HHmmss"
    $zip = Join-Path $PackageDir "yt-dlp-portable-$date.zip"
    $temp = Join-Path $PackageDir "_pack_$date"

    if (Test-Path $temp) { Remove-Item -Recurse -Force $temp }
    New-Item -ItemType Directory -Force -Path $temp | Out-Null

    $exclude = @("_user_data", "_packages")
    Get-ChildItem -Force $ToolDir | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $temp $_.Name) -Recurse -Force
    }

    Compress-Archive -Path (Join-Path $temp "*") -DestinationPath $zip -Force
    Remove-Item -Recurse -Force $temp

    Write-Host "分享包已生成：$zip"
    Write-Host "已自动排除 _user_data，里面不包含你的 cookies、设置、日志和更新状态。"
}

function Set-PlatformDefaultCookie {
    $platform = Select-Platform
    $cookie = Select-CookieFile -Platform $platform
    if (-not $cookie) { return }

    $cfg = Load-Config
    $cfg.defaultCookies[$platform] = $cookie.Name
    Save-Config -DefaultCookies $cfg.defaultCookies -DownloadDir $cfg.downloadDir
    Write-Host "已设置 $(Get-PlatformLabel $platform) 默认账号：$(Get-CookieLabel $cookie)"
}

function Show-Menu {
    Clear-Host
    Write-Host "============================================"
    Write-Host "多平台视频下载器 - 便携版 yt-dlp + FFmpeg"
    Write-Host "============================================"
    Write-Host "程序目录：$ToolDir"
    Write-Host "下载目录：$(Get-DownloadDir)"
    Write-Host "用户数据：$UserDataDir"
    Write-Host "支持平台：B站 / 抖音 / Twitter(X) / YouTube / Instagram / yt-dlp 其他站点"
    Show-CookieStatus
    Write-Host ""
    Write-Host "1. 直接下载最高画质（自动识别平台和默认账号）"
    Write-Host "2. 手动选择账号 cookies 后下载"
    Write-Host "3. 打开图形界面版（支持内嵌浏览器一键登录）"
    Write-Host "4. 设置某个平台的默认账号"
    Write-Host "5. 设置下载目录"
    Write-Host "6. 打开下载目录"
    Write-Host "7. 制作分享包（自动排除个人数据）"
    Write-Host "Q. 退出"
    Write-Host ""
}

try {
    while ($true) {
        Show-Menu
        $choice = Read-Host "请选择，直接回车默认 1"
        if ($null -eq $choice) { return }
        $choice = $choice.Trim()
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

        switch -Regex ($choice) {
            "^(1)$" { Start-AutoDownload; Pause-Exit }
            "^(2)$" {
                $platform = Select-Platform
                $cookie = Select-CookieFile -Platform $platform -AllowNone
                Start-Download -CookieFile $cookie -ForcedPlatform $platform
                Pause-Exit
            }
            "^(3)$" {
                $guiScript = Join-Path $ToolDir "video_downloader_gui.ps1"
                if (Test-Path $guiScript) {
                    Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $guiScript) -WorkingDirectory $ToolDir
                } else {
                    Write-Host "未找到图形界面脚本：$guiScript"
                }
                Pause-Exit
            }
            "^(4)$" { Set-PlatformDefaultCookie; Pause-Exit }
            "^(5)$" { Set-DownloadDir; Pause-Exit }
            "^(6)$" { $downloadDir = Get-DownloadDir; New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null; Start-Process explorer.exe $downloadDir }
            "^(7)$" { New-SharePackage; Pause-Exit }
            "^(q|Q)$" { return }
            default { Write-Host "无效选择：$choice"; Pause-Exit }
        }
    }
} catch {
    Write-Host ""
    Write-Host "发生错误："
    Write-Host $_.Exception.Message
    Pause-Exit
    exit 1
}
