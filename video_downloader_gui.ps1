<#
    图形界面版多平台视频下载器
    便携运行：所有路径基于当前脚本所在文件夹。
#>

param([switch]$SmokeTest)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === WebView2 登录模块 ===
$WebView2ModulePath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "functions\webview2_login.ps1"
$script:WebView2Available = $false
if (Test-Path $WebView2ModulePath) {
    . $WebView2ModulePath
    $initResult = Initialize-WebView2 -ToolDir (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $script:WebView2Available = $initResult
}

[System.Windows.Forms.Application]::EnableVisualStyles()

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
$Uv = Join-Path $ToolDir "uv.exe"
$DouyinBackendDir = Join-Path $ToolDir "external\douyin-downloader"
$DouyinConfigPath = Join-Path $StateDir "douyin_backend_config.yml"
$ConfigPath = Join-Path $StateDir "settings.json"
$CliScript = Join-Path $ToolDir "video_downloader.ps1"
$ShareMaker = Join-Path $ToolDir "make_share_package.ps1"
$HelpFile = Join-Path $ToolDir "使用指南.txt"

New-Item -ItemType Directory -Force -Path $CookieDir, $StateDir, $LogDir, $PackageDir | Out-Null

$PlatformInfo = [ordered]@{
    bilibili = [pscustomobject]@{ Label = "B站"; Home = "https://www.bilibili.com/"; Domains = @("bilibili.com", "b23.tv"); CookiePatterns = @("cookies_bilibili_*.txt", "cookies.txt") }
    douyin = [pscustomobject]@{ Label = "抖音"; Home = "https://www.douyin.com/"; Domains = @("douyin.com", "v.douyin.com", "iesdouyin.com", "amemv.com", "snssdk.com"); CookiePatterns = @("cookies_douyin_*.txt") }
    twitter = [pscustomobject]@{ Label = "Twitter/X"; Home = "https://x.com/"; Domains = @("x.com", "twitter.com"); CookiePatterns = @("cookies_twitter_*.txt") }
    youtube = [pscustomobject]@{ Label = "YouTube"; Home = "https://www.youtube.com/"; Domains = @("youtube.com", "youtu.be"); CookiePatterns = @("cookies_youtube_*.txt") }
    instagram = [pscustomobject]@{ Label = "Instagram"; Home = "https://www.instagram.com/"; Domains = @("instagram.com"); CookiePatterns = @("cookies_instagram_*.txt") }
    generic = [pscustomobject]@{ Label = "通用"; Home = "https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md"; Domains = @(); CookiePatterns = @("cookies_*.txt", "cookies.txt") }
}

$PlatformKeys = @("bilibili", "douyin", "twitter", "youtube", "instagram", "generic")
$PlatformComboMap = [ordered]@{
    "B站" = "bilibili"
    "抖音" = "douyin"
    "Twitter/X" = "twitter"
    "YouTube" = "youtube"
    "Instagram" = "instagram"
    "通用" = "generic"
}

$script:CurrentJob = $null
$script:CurrentJobOutput = New-Object System.Collections.Generic.List[string]
$script:CurrentJobProbe = $false
$script:CurrentJobOpenAfter = $true
$script:CurrentJobDownloadDir = ""
$script:CurrentJobPlatform = ""
$script:CurrentJobStartTime = $null
$script:CurrentChildPid = $null
$script:CurrentJobUrl = ""
$script:LastDetectedPlatform = "generic"

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

function Get-PlatformLabel {
    param([string]$Platform)
    if ($PlatformInfo.Contains($Platform)) { return $PlatformInfo[$Platform].Label }
    return "通用"
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

function Resolve-RedirectUrl {
    param([string]$Url)
    $current = $Url
    for ($i = 0; $i -lt 8; $i++) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($current)
            $req.Method = "GET"
            $req.AllowAutoRedirect = $false
            $req.Timeout = 15000
            $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
            $res = $req.GetResponse()
            $location = $res.Headers["Location"]
            $res.Close()
            if ([string]::IsNullOrWhiteSpace($location)) { return $current }
            if ($location -notmatch '^https?://') {
                $baseUri = New-Object System.Uri($current)
                $location = (New-Object System.Uri($baseUri, $location)).AbsoluteUri
            }
            $current = $location
        } catch [System.Net.WebException] {
            if ($_.Exception.Response) {
                $location = $_.Exception.Response.Headers["Location"]
                $_.Exception.Response.Close()
                if ([string]::IsNullOrWhiteSpace($location)) { return $current }
                if ($location -notmatch '^https?://') {
                    $baseUri = New-Object System.Uri($current)
                    $location = (New-Object System.Uri($baseUri, $location)).AbsoluteUri
                }
                $current = $location
            } else {
                return $current
            }
        } catch {
            return $current
        }
    }
    return $current
}

function Normalize-DouyinUrl {
    param([string]$Url, [scriptblock]$Log)
    $work = $Url
    if ($work -match 'v\.douyin\.com|iesdouyin\.com|snssdk\.com') {
        if ($Log) { & $Log "正在展开抖音短链接..." }
        $expanded = Resolve-RedirectUrl $work
        if ($expanded -and $expanded -ne $work) {
            if ($Log) { & $Log "短链接已展开：$expanded" }
            $work = $expanded
        }
    }

    if ($work -match '[?&]modal_id=(\d+)') {
        return "https://www.douyin.com/video/$($Matches[1])"
    }
    if ($work -match '[?&]aweme_id=(\d+)') {
        return "https://www.douyin.com/video/$($Matches[1])"
    }
    if ($work -match '/share/video/(\d+)') {
        return "https://www.douyin.com/video/$($Matches[1])"
    }
    if ($work -match '/video/(\d+)') {
        return "https://www.douyin.com/video/$($Matches[1])"
    }
    return $work
}

function Resolve-InputUrl {
    param([string]$InputText, [scriptblock]$Log)
    $url = Extract-FirstUrl $InputText
    if (-not $url) { return "" }
    $platform = Detect-PlatformFromUrl $url
    if ($platform -eq "douyin") {
        $normalized = Normalize-DouyinUrl -Url $url -Log $Log
        if ($normalized -and $normalized -ne $url -and $Log) { & $Log "抖音链接已规范化：$normalized" }
        return $normalized
    }
    return $url
}

function Load-Config {
    $config = [ordered]@{ defaultCookies = @{}; downloadDir = $null; updatedAt = $null }
    if (-not (Test-Path $ConfigPath)) { return $config }

    try {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $ConfigPath | ConvertFrom-Json
        if ($raw.defaultCookieName) { $config.defaultCookies["bilibili"] = [string]$raw.defaultCookieName }
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

function Set-DownloadDirValue {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return }
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $cfg = Load-Config
    Save-Config -DefaultCookies $cfg.defaultCookies -DownloadDir $Dir
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

function Quote-Arg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Get-FriendlyError {
    param([string]$Text)
    if ($Text -match "Requested format is not available|Only images are available|n challenge") {
        return "YouTube 解析失败：通常是缺少或没有正确调用 Deno。请确认 deno.exe 在工具文件夹中。"
    }
    if ($Text -match "cookies are no longer valid|Sign in to confirm|HTTP Error 401|Unauthorized") {
        return "账号 cookies 可能失效：请点击'登录/切换账号'，重新导出该平台 cookies。"
    }
    if ($Text -match "Fresh cookies .* needed|Failed to parse JSON") {
        return "抖音专用后端解析失败。请先点击'登录/切换账号'重新登录抖音；如果仍失败，说明抖音接口再次变动，请运行 portable_update_tools.ps1。"
    }
    if ($Text -match "Private video|This video is private|not available|Video unavailable|permission|forbidden|HTTP Error 403") {
        return "当前账号没有访问权限，或视频受地区/年龄/会员/隐私限制。"
    }
    if ($Text -match "Unsupported URL|No suitable extractor") {
        if ($Text -match "douyin|iesdouyin|snssdk") {
            return "抖音链接不支持：请优先复制视频详情页链接，或把完整分享文案粘贴进来。程序会自动提取并展开短链。"
        }
        return "这个链接当前不被 yt-dlp 支持，或链接不是视频详情页。"
    }
    if ($Text -match "Unable to download webpage|timed out|resolve|network|TLS|SSL|connection") {
        return "网络连接失败：请检查网络、代理、DNS，或稍后再试。"
    }
    if ($Text -match "ffmpeg") {
        return "FFmpeg 相关错误：可能是 ffmpeg.exe 缺失或被安全软件拦截。"
    }
    return ""
}

function Ensure-DenoRuntime {
    param([scriptblock]$Log)
    if (Test-Path $Deno) { return }
    & $Log "缺少 YouTube 需要的 deno.exe，正在自动下载..."

    $tmpDir = Join-Path $UserDataDir "tmp_deno_gui"
    $zip = Join-Path $tmpDir "deno.zip"
    if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    $urls = @(
        "https://dl.deno.land/release/latest/deno-x86_64-pc-windows-msvc.zip",
        "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip",
        "https://mirror.ghproxy.com/https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip",
        "https://gh-proxy.com/https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip"
    )

    $ok = $false
    foreach ($url in $urls) {
        try {
            & $Log "下载 Deno：$url"
            if (Test-Path $zip) { Remove-Item -Force $zip }
            curl.exe --fail --location --retry 2 --connect-timeout 20 --output $zip $url
            if ($LASTEXITCODE -eq 0 -and (Test-Path $zip) -and ((Get-Item $zip).Length -gt 1000000)) { $ok = $true; break }
        } catch {
            & $Log "Deno 下载失败：$($_.Exception.Message)"
        }
    }

    if (-not $ok) { throw "Deno 下载失败，请稍后重试。" }
    Expand-Archive -Force -Path $zip -DestinationPath $tmpDir
    $found = Get-ChildItem -Path $tmpDir -Recurse -Filter "deno.exe" | Select-Object -First 1 -ExpandProperty FullName
    if (-not $found) { throw "Deno 压缩包解压后未找到 deno.exe" }
    Copy-Item -Force -LiteralPath $found -Destination $Deno
    Remove-Item -Recurse -Force $tmpDir
    & $Log "Deno 已安装。"
}

function Build-YtDlpArgs {
    param(
        [string]$VideoUrl,
        [string]$Platform,
        [System.IO.FileInfo]$CookieFile,
        [switch]$ProbeOnly
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
        "--progress-template", "postprocess:正在合并/处理：%(info.title).120B"
    )

    if ($ProbeOnly) {
        $args += @("--skip-download", "--print", "标题：%(title)s", "--print", "上传者：%(uploader)s", "--print", "选择格式：%(format_id)s", "--print", "清晰度：%(resolution)s", "--print", "视频编码：%(vcodec)s", "--print", "音频编码：%(acodec)s")
    } else {
        $args += @("--print", "after_move:保存文件：%(filepath)s", "-o", $outputTemplate)
    }

    if ($Platform -eq "youtube") {
        $args += @("--js-runtimes", "deno:$Deno", "--remote-components", "ejs:github")
    }
    if ($Platform -eq "douyin") {
        $args += @("--user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36", "--referer", "https://www.douyin.com/")
    }

    if ($CookieFile) { $args += @("--cookies", $CookieFile.FullName) }
    $args += $VideoUrl
    return $args
}

function Convert-NetscapeCookiesToMap {
    param([System.IO.FileInfo]$CookieFile)
    $map = @{}
    if (-not $CookieFile -or -not (Test-Path $CookieFile.FullName)) { return $map }
    Get-Content -LiteralPath $CookieFile.FullName -Encoding UTF8 | Where-Object { $_ -and $_ -notmatch '^#' } | ForEach-Object {
        $parts = $_ -split "`t"
        if ($parts.Count -ge 7 -and $parts[5]) { $map[$parts[5]] = $parts[6] }
    }
    return $map
}

function Write-DouyinBackendConfig {
    param([string]$VideoUrl, [string]$DownloadDir, [System.IO.FileInfo]$CookieFile)

    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $cookies = Convert-NetscapeCookiesToMap -CookieFile $CookieFile
    $keys = @("msToken", "ttwid", "odin_tt", "passport_csrf_token", "sid_guard", "sessionid", "sessionid_ss", "sid_tt", "uid_tt", "uid_tt_ss", "s_v_web_id", "__ac_nonce", "__ac_signature", "x-web-secsdk-uid")
    $pathForYaml = $DownloadDir.Replace("\", "/")

    $yaml = @(
        "link:",
        "  - $VideoUrl",
        "path: $pathForYaml",
        "music: false",
        "cover: false",
        "avatar: false",
        "json: false",
        "folderstyle: true",
        'filename_template: "{title}_{author}_{id}"',
        'folder_template: "{author}"',
        "mode:",
        "  - post",
        "number:",
        "  post: 1",
        "  like: 0",
        "  allmix: 0",
        "  mix: 0",
        "  music: 0",
        "  collect: 0",
        "  collectmix: 0",
        "thread: 1",
        "retry_times: 3",
        'proxy: ""',
        "database: false",
        "manifest:",
        "  enabled: false",
        "progress:",
        "  quiet_logs: false",
        "browser_fallback:",
        "  enabled: false",
        "cookies:"
    )

    foreach ($key in $keys) {
        $value = if ($cookies.ContainsKey($key)) { [string]$cookies[$key] } else { "" }
        $value = $value.Replace('"', '\"')
        $yaml += ('  {0}: "{1}"' -f $key, $value)
    }

    Set-Content -LiteralPath $DouyinConfigPath -Encoding UTF8 -Value ($yaml -join "`n")
    return $DouyinConfigPath
}

function Build-DouyinBackendArgs {
    param([string]$VideoUrl, [System.IO.FileInfo]$CookieFile)
    if (-not (Test-Path $Uv)) { throw "缺少 uv.exe，无法运行抖音专用后端。请手动下载对应组件。" }
    if (-not (Test-Path $DouyinBackendDir)) { throw "缺少抖音专用后端目录：$DouyinBackendDir" }

    $downloadDir = Get-DownloadDir
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $config = Write-DouyinBackendConfig -VideoUrl $VideoUrl -DownloadDir $downloadDir -CookieFile $CookieFile
    return @("run", "--project", $DouyinBackendDir, "python", "run.py", "-c", $config, "-u", $VideoUrl, "-p", $downloadDir, "--show-warnings")
}

function Ensure-DouyinBackendRuntime {
    param([scriptblock]$Log)
    $venv = Join-Path $DouyinBackendDir ".venv"
    $pyvenv = Join-Path $venv "pyvenv.cfg"
    $pythonBase = Join-Path $ToolDir "external\python"
    $pythonDirs = @(Get-ChildItem -Path $pythonBase -Directory -Filter "cpython-*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    $expectedHome = if ($pythonDirs.Count -gt 0) { $pythonDirs[0].FullName } else { Join-Path $pythonBase "cpython-3.14-windows-x86_64-none" }
    if (Test-Path $pyvenv) {
        $cfgText = Get-Content -Raw -Encoding UTF8 -LiteralPath $pyvenv
        if ($cfgText -notmatch [regex]::Escape($expectedHome)) {
            if ($Log) { & $Log "检测到抖音后端虚拟环境路径已变化，正在修正..." }
            $cfgText = [regex]::Replace($cfgText, '(?m)^home = .+$', "home = $expectedHome")
            Set-Content -LiteralPath $pyvenv -Encoding UTF8 -Value $cfgText
        }
    }
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($W, $H)
    return $button
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($W, $H)
    $label.AutoEllipsis = $true
    return $label
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "多平台视频下载器"
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(940, 680)
$form.MinimumSize = New-Object System.Drawing.Size(860, 620)
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

$lblUrl = New-Label "视频链接" 16 18 80 24
$txtUrl = New-Object System.Windows.Forms.TextBox
$txtUrl.Location = New-Object System.Drawing.Point(92, 14)
$txtUrl.Size = New-Object System.Drawing.Size(632, 28)
$txtUrl.Anchor = "Top,Left,Right"

$btnPaste = New-Button "粘贴" 736 12 82 30
$btnClear = New-Button "清空" 824 12 82 30
$btnPaste.Anchor = "Top,Right"
$btnClear.Anchor = "Top,Right"

$lblPlatform = New-Label "平台：自动识别" 16 54 260 24
$lblCookie = New-Label "账号：未检测" 292 54 560 24
$lblCookie.Anchor = "Top,Left,Right"

$lblDir = New-Label "下载目录" 16 86 80 24
$txtDir = New-Object System.Windows.Forms.TextBox
$txtDir.Location = New-Object System.Drawing.Point(92, 82)
$txtDir.Size = New-Object System.Drawing.Size(632, 28)
$txtDir.ReadOnly = $true
$txtDir.Anchor = "Top,Left,Right"
$btnChooseDir = New-Button "选择目录" 736 80 82 30
$btnOpenDir = New-Button "打开目录" 824 80 82 30
$btnChooseDir.Anchor = "Top,Right"
$btnOpenDir.Anchor = "Top,Right"

$group = New-Object System.Windows.Forms.GroupBox
$group.Text = "账号与维护"
$group.Location = New-Object System.Drawing.Point(16, 122)
$group.Size = New-Object System.Drawing.Size(890, 86)
$group.Anchor = "Top,Left,Right"

$comboPlatform = New-Object System.Windows.Forms.ComboBox
$comboPlatform.DropDownStyle = "DropDownList"
$comboPlatform.Location = New-Object System.Drawing.Point(16, 32)
$comboPlatform.Size = New-Object System.Drawing.Size(130, 28)
[void]$comboPlatform.Items.AddRange([object[]]$PlatformComboMap.Keys)
$comboPlatform.SelectedIndex = 0

$btnExportCookie = New-Button "登录/切换账号" 156 30 116 30
$btnSetDefaultCookie = New-Button "设置默认账号" 282 30 108 30
$btnRefresh = New-Button "刷新状态" 400 30 82 30
$btnPackage = New-Button "制作分享包" 492 30 102 30
$btnCli = New-Button "备用菜单" 604 30 64 30

$group.Controls.AddRange(@($comboPlatform, $btnExportCookie, $btnSetDefaultCookie, $btnRefresh, $btnPackage, $btnCli))

$btnProbe = New-Button "检测画质" 16 222 116 38
$btnDownload = New-Button "开始下载" 144 222 116 38
$btnCancel = New-Button "取消任务" 272 222 116 38
$btnCancel.Enabled = $false
$chkOpenAfter = New-Object System.Windows.Forms.CheckBox
$chkOpenAfter.Text = "完成后打开下载目录"
$chkOpenAfter.Location = New-Object System.Drawing.Point(408, 231)
$chkOpenAfter.Size = New-Object System.Drawing.Size(170, 24)
$chkOpenAfter.Checked = $true
$btnHelp = New-Button "使用教程" 588 226 78 30
$btnCopyLog = New-Button "复制日志" 672 226 78 30
$btnClearLog = New-Button "清空日志" 756 226 78 30

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(16, 274)
$progress.Size = New-Object System.Drawing.Size(890, 18)
$progress.Style = "Blocks"
$progress.Minimum = 0
$progress.Maximum = 1000
$progress.Value = 0
$progress.Anchor = "Top,Left,Right"

$lblProgressStatus = New-Label "进度：等待开始" 16 298 890 24
$lblProgressStatus.Anchor = "Top,Left,Right"

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(16, 328)
$txtLog.Size = New-Object System.Drawing.Size(890, 294)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.Anchor = "Top,Bottom,Left,Right"
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)

$form.Controls.AddRange(@($lblUrl, $txtUrl, $btnPaste, $btnClear, $lblPlatform, $lblCookie, $lblDir, $txtDir, $btnChooseDir, $btnOpenDir, $group, $btnProbe, $btnDownload, $btnCancel, $chkOpenAfter, $btnHelp, $btnCopyLog, $btnClearLog, $progress, $lblProgressStatus, $txtLog))

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.SetToolTip($btnProbe, "只查看可用画质，不下载视频")
$toolTip.SetToolTip($btnDownload, "下载当前链接的最高质量视频")
$toolTip.SetToolTip($btnCancel, "停止正在运行的下载任务")
$toolTip.SetToolTip($btnHelp, "打开详细小白教程")
$toolTip.SetToolTip($btnCopyLog, "复制当前链接、账号状态和日志，便于求助")
$toolTip.SetToolTip($btnClearLog, "只清空界面日志，不删除视频")
$toolTip.SetToolTip($btnPackage, "生成可发给别人的便携 zip，自动排除个人数据")
$toolTip.SetToolTip($btnExportCookie, "切换或导出平台账号 cookies")

$jobTimer = New-Object System.Windows.Forms.Timer
$jobTimer.Interval = 500
$jobTimer.Add_Tick({ Finish-JobIfDone })

function Append-Log {
    param([string]$Line)
    if ($form.IsDisposed) { return }
    $action = {
        param($text)
        $txtLog.AppendText($text + [Environment]::NewLine)
        $txtLog.SelectionStart = $txtLog.TextLength
        $txtLog.ScrollToCaret()
    }
    if ($txtLog.InvokeRequired) { [void]$txtLog.BeginInvoke($action, $Line) } else { & $action $Line }
}

function Set-ProgressStatus {
    param(
        [string]$Text,
        [Nullable[double]]$Percent = $null
    )
    if ($form.IsDisposed) { return }
    $action = {
        param($statusText, $percentValue)
        $lblProgressStatus.Text = $statusText
        if ($null -ne $percentValue) {
            $value = [int]([Math]::Round([Math]::Max(0, [Math]::Min(100, [double]$percentValue)) * 10))
            $progress.Style = "Blocks"
            $progress.Value = [Math]::Max($progress.Minimum, [Math]::Min($progress.Maximum, $value))
        }
    }
    if ($lblProgressStatus.InvokeRequired) {
        [void]$lblProgressStatus.BeginInvoke($action, $Text, $Percent)
    } else {
        & $action $Text $Percent
    }
}

function Try-UpdateProgressFromLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }

    if ($Line -match '下载进度：\s*([0-9]+(?:\.[0-9]+)?)%') {
        $percent = [double]$Matches[1]
        Set-ProgressStatus -Text $Line.Trim() -Percent $percent
        return $true
    }

    if ($Line -match '\[download\]\s+([0-9]+(?:\.[0-9]+)?)%') {
        $percent = [double]$Matches[1]
        Set-ProgressStatus -Text ("下载进度：{0}%" -f $Matches[1]) -Percent $percent
        return $true
    }

    if ($Line -match '^正在合并/处理：') {
        Set-ProgressStatus -Text $Line.Trim() -Percent 100
        return $true
    }

    return $false
}

function Set-Busy {
    param([bool]$Busy)
    $controls = @($btnProbe, $btnDownload, $btnPaste, $btnClear, $btnChooseDir, $btnOpenDir, $btnExportCookie, $btnSetDefaultCookie, $btnRefresh, $btnCli, $btnPackage, $btnClearLog)
    foreach ($control in $controls) { $control.Enabled = -not $Busy }
    $btnCancel.Enabled = $Busy
    $progress.Style = "Blocks"
    if ($Busy) {
        $progress.Value = 0
    }
}

function Show-StartupHealth {
    $missing = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path $YtDlp)) { $missing.Add("yt-dlp.exe") }
    if (-not (Test-Path $Ffmpeg)) { $missing.Add("ffmpeg.exe") }
    if (-not (Test-Path $Deno)) { $missing.Add("deno.exe（YouTube 需要）") }
    if (-not (Test-Path $Uv)) { $missing.Add("uv.exe（抖音需要）") }
    if (-not (Test-Path $DouyinBackendDir)) { $missing.Add("抖音专用后端") }
    if ($missing.Count -gt 0) {
        Append-Log "基础组件检查：缺少 $($missing -join '、')。请手动下载对应组件。"
        Set-ProgressStatus -Text "进度：缺少组件，请运行 portable_update_tools.ps1" -Percent 0
    } else {
        Append-Log "基础组件检查通过。"
    }
    if ($script:WebView2Available) {
        Append-Log "WebView2 已就绪，支持内嵌浏览器登录。"
    } else {
        Append-Log "WebView2 不可用，将使用浏览器扩展方式导出 cookies。"
    }
}

function Remove-DouyinManifestFile {
    param([string]$DownloadDir)
    if ([string]::IsNullOrWhiteSpace($DownloadDir)) { return }
    $manifest = Join-Path $DownloadDir "download_manifest.jsonl"
    if (Test-Path -LiteralPath $manifest) {
        Remove-Item -LiteralPath $manifest -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $manifest)) {
            Append-Log "已清理抖音下载清单文件：download_manifest.jsonl"
        }
    }
}

function Stop-CurrentDownloadProcess {
    if ($script:CurrentChildPid) {
        try {
            & taskkill.exe /PID ([string]$script:CurrentChildPid) /T /F | Out-Null
        } catch {}
    }

    foreach ($line in $script:CurrentJobOutput) {
        if ([string]$line -match '^__YTDLP_CHILD_PID__=(\d+)$') {
            try {
                & taskkill.exe /PID $Matches[1] /T /F | Out-Null
            } catch {}
        }
    }

    $url = $script:CurrentJobUrl
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        $names = @("yt-dlp.exe", "uv.exe", "python.exe", "python3.exe", "ffmpeg.exe")
        try {
            Get-CimInstance Win32_Process | Where-Object {
                $names -contains $_.Name -and $_.CommandLine -and $_.CommandLine.Contains($url)
            } | ForEach-Object {
                & taskkill.exe /PID ([string]$_.ProcessId) /T /F | Out-Null
            }
        } catch {
            try {
                Get-WmiObject Win32_Process | Where-Object {
                    $names -contains $_.Name -and $_.CommandLine -and $_.CommandLine.Contains($url)
                } | ForEach-Object {
                    & taskkill.exe /PID ([string]$_.ProcessId) /T /F | Out-Null
                }
            } catch {}
        }
    }
}

function Finish-JobIfDone {
    if (-not $script:CurrentJob) { return }

    $newOutput = Receive-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
    foreach ($line in $newOutput) {
        $text = [string]$line
        $script:CurrentJobOutput.Add($text)
        if ($text -match '^__YTDLP_CHILD_PID__=(\d+)$') {
            $script:CurrentChildPid = [int]$Matches[1]
            continue
        }
        if ($text -match '^__YTDLP_EXIT_CODE__=') { continue }
        if (Try-UpdateProgressFromLine -Line $text) { continue }
        Append-Log $text
    }

    if ($script:CurrentJob.State -in @("Completed", "Failed", "Stopped")) {
        $job = $script:CurrentJob
        $state = $job.State
        $exitCode = if ($state -eq "Stopped") { -1 } else { 1 }

        foreach ($line in $script:CurrentJobOutput) {
            if ($line -match '^__YTDLP_EXIT_CODE__=(-?\d+)$') {
                $exitCode = [int]$Matches[1]
            }
        }

        $allText = ($script:CurrentJobOutput -join [Environment]::NewLine)
        $friendly = Get-FriendlyError $allText
        $isProbe = $script:CurrentJobProbe
        $openAfter = $script:CurrentJobOpenAfter
        $downloadDir = $script:CurrentJobDownloadDir
        $jobPlatform = $script:CurrentJobPlatform

        Remove-Job -Job $job -ErrorAction SilentlyContinue
        $script:CurrentJob = $null
        $script:CurrentJobOutput = New-Object System.Collections.Generic.List[string]
        $script:CurrentJobPlatform = ""
        $script:CurrentJobStartTime = $null
        $script:CurrentChildPid = $null
        $script:CurrentJobUrl = ""
        Set-Busy $false
        $jobTimer.Stop()

        Append-Log ""
        if ($jobPlatform -eq "douyin") {
            Remove-DouyinManifestFile -DownloadDir $downloadDir
        }

        if ($exitCode -eq 0) {
            if ($isProbe) {
                Set-ProgressStatus -Text "进度：检测完成" -Percent 100
                Append-Log "检测完成。"
            } else {
                Set-ProgressStatus -Text "进度：下载完成" -Percent 100
                Append-Log "下载完成。"
                if ($openAfter -and (Test-Path $downloadDir)) { Start-Process explorer.exe $downloadDir }
            }
            return
        }

        if ($exitCode -eq -1) {
            Set-ProgressStatus -Text "进度：任务已取消" -Percent 0
            Append-Log "任务已取消。"
            return
        }

        if ($friendly) {
            Set-ProgressStatus -Text "进度：任务失败" -Percent 0
            Append-Log "中文提示：$friendly"
            Append-Log "需要求助时，点击'复制日志'，把日志发给维护者。"
            [System.Windows.Forms.MessageBox]::Show("$friendly`n`n需要求助时，请点击'复制日志'，把日志发给维护者。", "下载失败", "OK", "Warning") | Out-Null
        } else {
            Set-ProgressStatus -Text "进度：任务失败" -Percent 0
            Append-Log "任务失败，退出码：$exitCode"
            Append-Log "需要求助时，点击'复制日志'，把日志发给维护者。"
            [System.Windows.Forms.MessageBox]::Show("任务失败，退出码：$exitCode。`n`n需要求助时，请点击'复制日志'，把日志发给维护者。", "下载失败", "OK", "Warning") | Out-Null
        }
    }
}

function Refresh-UiState {
    $txtDir.Text = Get-DownloadDir
    $url = Extract-FirstUrl $txtUrl.Text.Trim()
    $platform = if (Is-Url $url) { Detect-PlatformFromUrl $url } else { $PlatformComboMap[[string]$comboPlatform.SelectedItem] }
    if (-not $platform) { $platform = "generic" }
    $script:LastDetectedPlatform = $platform

    $lblPlatform.Text = "平台：$(Get-PlatformLabel $platform)"
    $cookie = Resolve-DefaultCookie -Platform $platform
    if ($cookie) {
        $lblCookie.Text = "账号：$(Get-CookieLabel $cookie)"
    } else {
        $lblCookie.Text = "账号：未设置。公开内容可尝试下载，受限内容需要先导出 cookies。"
    }
}

function Validate-Ready {
    param([string]$Url, [string]$Platform)
    if ($Platform -eq "douyin") {
        if (-not (Test-Path $Uv)) { throw "缺少 uv.exe，无法运行抖音专用后端。请手动下载对应组件。" }
        if (-not (Test-Path $DouyinBackendDir)) { throw "缺少抖音专用后端目录：$DouyinBackendDir" }
    } elseif (-not (Test-Path $YtDlp)) {
        throw "缺少 yt-dlp.exe，请手动下载对应组件。"
    }
    if (-not (Test-Path $Ffmpeg)) { throw "缺少 ffmpeg.exe，请手动下载对应组件。" }
    if (-not (Is-Url $Url)) { throw "请先粘贴有效的视频链接。" }
    $dir = Get-DownloadDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

function Show-DefaultCookieDialog {
    $platform = $PlatformComboMap[[string]$comboPlatform.SelectedItem]
    if (-not $platform) { $platform = $script:LastDetectedPlatform }
    $files = Get-CookieFiles -Platform $platform
    if ($files.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("当前平台还没有 cookies。请先点击'登录/切换账号'。", "没有账号", "OK", "Information") | Out-Null
        return
    }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "设置默认账号 - $(Get-PlatformLabel $platform)"
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(560, 340)
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false
    $dialog.Font = $form.Font

    $label = New-Label "选择这个平台默认使用的账号 cookies：" 16 16 500 24
    $list = New-Object System.Windows.Forms.ListBox
    $list.Location = New-Object System.Drawing.Point(16, 48)
    $list.Size = New-Object System.Drawing.Size(508, 190)
    for ($i = 0; $i -lt $files.Count; $i++) {
        [void]$list.Items.Add((Get-CookieLabel $files[$i]))
    }
    $list.SelectedIndex = 0

    $ok = New-Button "设为默认" 314 252 100 32
    $cancel = New-Button "取消" 424 252 100 32
    $ok.Add_Click({
        if ($list.SelectedIndex -lt 0) { return }
        $selected = $files[$list.SelectedIndex]
        $cfg = Load-Config
        $cfg.defaultCookies[$platform] = $selected.Name
        Save-Config -DefaultCookies $cfg.defaultCookies -DownloadDir $cfg.downloadDir
        Append-Log "已设置 $(Get-PlatformLabel $platform) 默认账号：$(Get-CookieLabel $selected)"
        Refresh-UiState
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dialog.Close()
    })
    $cancel.Add_Click({
        $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dialog.Close()
    })

    $dialog.Controls.AddRange(@($label, $list, $ok, $cancel))
    [void]$dialog.ShowDialog($form)
}

function Start-YtDlpJob {
    param([switch]$ProbeOnly)

    try {
        if ($script:CurrentJob) { throw "当前已有任务在运行，请先等待完成或取消任务。" }
        $url = Resolve-InputUrl -InputText $txtUrl.Text.Trim() -Log ${function:Append-Log}
        if ($url -and $url -ne $txtUrl.Text.Trim()) { $txtUrl.Text = $url }
        $platform = Detect-PlatformFromUrl $url
        Validate-Ready -Url $url -Platform $platform
        $cookie = Resolve-DefaultCookie -Platform $platform
        if ($platform -eq "youtube") { Ensure-DenoRuntime -Log ${function:Append-Log} }

        Refresh-UiState
        Set-Busy $true
        Set-ProgressStatus -Text "进度：准备开始" -Percent 0
        $txtLog.Clear()
        Append-Log "平台：$(Get-PlatformLabel $platform)"
        Append-Log "下载目录：$(Get-DownloadDir)"

        if ($platform -eq "bilibili" -and $cookie -and -not (Test-BilibiliCookie $cookie)) {
            Append-Log "警告：B站 cookies 缺少 SESSDATA / DedeUserID / bili_jct，可能已过期。"
            Append-Log "将尝试下载，但可能无法获取最高画质。建议点击'登录/切换账号'重新登录。"
            Append-Log ""
        }

        if ($cookie) { Append-Log "使用账号：$(Get-CookieLabel $cookie)" } else { Append-Log "未使用 cookies。受限内容可能失败。" }
        if ($ProbeOnly -and $platform -eq "douyin") {
            Append-Log "抖音专用后端会自动选择最高码率，但不支持只检测不下载。请直接点击'开始下载'。"
            Set-Busy $false
            return
        }
        if ($ProbeOnly) { Append-Log "开始检测可用画质，不下载视频..." } else { Append-Log "开始下载最高质量..." }
        if ($ProbeOnly) {
            Set-ProgressStatus -Text "进度：正在检测画质" -Percent 0
        } else {
            Set-ProgressStatus -Text "进度：等待下载器返回百分比" -Percent 0
        }
        Append-Log ""

        if ($platform -eq "douyin") {
            Ensure-DouyinBackendRuntime -Log ${function:Append-Log}
            Append-Log "使用抖音专用后端：jiji262/douyin-downloader"
            Append-Log "该后端会优先选择无水印和最高码率源。"
            Set-ProgressStatus -Text "进度：抖音专用后端下载中" -Percent 0
            Remove-DouyinManifestFile -DownloadDir (Get-DownloadDir)
            $exePath = $Uv
            $workingDir = $DouyinBackendDir
            $args = Build-DouyinBackendArgs -VideoUrl $url -CookieFile $cookie
        } else {
            $exePath = $YtDlp
            $workingDir = $ToolDir
            $args = Build-YtDlpArgs -VideoUrl $url -Platform $platform -CookieFile $cookie -ProbeOnly:$ProbeOnly
        }

        $script:CurrentJobOutput = New-Object System.Collections.Generic.List[string]
        $script:CurrentJobProbe = [bool]$ProbeOnly
        $script:CurrentJobOpenAfter = $chkOpenAfter.Checked
        $script:CurrentJobDownloadDir = Get-DownloadDir
        $script:CurrentJobPlatform = $platform
        $script:CurrentJobStartTime = Get-Date
        $script:CurrentChildPid = $null
        $script:CurrentJobUrl = $url
        $script:CurrentJob = Start-Job -ScriptBlock {
            param($ExePath, $ArgList, $WorkingDir, $EnvVars)
            Set-Location -LiteralPath $WorkingDir
            foreach ($key in $EnvVars.Keys) { [Environment]::SetEnvironmentVariable($key, [string]$EnvVars[$key], "Process") }
            & $ExePath @ArgList 2>&1 | ForEach-Object { $_.ToString() }
            $code = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            "__YTDLP_EXIT_CODE__=$code"
        } -ArgumentList $exePath, $args, $workingDir, @{
            PYTHONIOENCODING = "utf-8"
            PYTHONUTF8 = "1"
            NO_COLOR = "1"
            UV_CACHE_DIR = (Join-Path $ToolDir "external\uv-cache")
            UV_PYTHON_INSTALL_DIR = (Join-Path $ToolDir "external\python")
        }

        $jobTimer.Start()
    } catch {
        Set-Busy $false
        $script:CurrentJobPlatform = ""
        $script:CurrentJobStartTime = $null
        $script:CurrentChildPid = $null
        $script:CurrentJobUrl = ""
        Set-ProgressStatus -Text "进度：无法开始" -Percent 0
        $msg = $_.Exception.Message
        Append-Log "错误：$msg"
        [System.Windows.Forms.MessageBox]::Show($msg, "无法开始任务", "OK", "Warning") | Out-Null
    }
}

$txtUrl.Add_TextChanged({ Refresh-UiState })
$comboPlatform.Add_SelectedIndexChanged({ Refresh-UiState })

$btnPaste.Add_Click({
    try {
        $clip = [System.Windows.Forms.Clipboard]::GetText().Trim()
        if ($clip) { $txtUrl.Text = $clip }
    } catch {}
})

$btnClear.Add_Click({
    $txtUrl.Clear()
    $txtLog.Clear()
    Set-ProgressStatus -Text "进度：等待开始" -Percent 0
    Refresh-UiState
})

$btnChooseDir.Add_Click({
    $currentDir = Get-DownloadDir
    New-Item -ItemType Directory -Force -Path $currentDir | Out-Null
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "请选择视频下载目录"
    $dialog.SelectedPath = $currentDir
    $dialog.ShowNewFolderButton = $true
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-DownloadDirValue -Dir $dialog.SelectedPath
        Refresh-UiState
        Append-Log "已设置下载目录：$($dialog.SelectedPath)"
    }
})

$btnOpenDir.Add_Click({
    $dir = Get-DownloadDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Start-Process explorer.exe $dir
})

$btnExportCookie.Add_Click({
    try {
        $platformKey = $PlatformComboMap[[string]$comboPlatform.SelectedItem]
        if (-not $platformKey) { $platformKey = $script:LastDetectedPlatform }
        if ($platformKey -eq "generic") {
            [System.Windows.Forms.MessageBox]::Show("请先选择一个具体平台再登录。", "提示", "OK", "Information") | Out-Null
            return
        }

        if ($script:WebView2Available) {
            # WebView2 内嵌登录
            Append-Log "正在打开 $(Get-PlatformLabel $platformKey) 登录窗口..."
            $result = Start-WebView2Login -Platform $platformKey -ToolDir $ToolDir -Owner $form

            if ($result.Cancelled) {
                Append-Log "已取消 WebView2 登录。"
                return
            }
            if (-not $result.Success) {
                Append-Log "登录失败：$($result.ErrorMessage)"
                [System.Windows.Forms.MessageBox]::Show($result.ErrorMessage, "登录失败", "OK", "Warning") | Out-Null
                return
            }

            # Save cookies
            $saved = Save-WebView2Cookies -Platform $platformKey -AccountName $result.AccountName -AccountId $result.AccountId -NetscapeContent $result.CookiesNetscape -CookieDir $CookieDir

            # Auto-set as default
            $cfg = Load-Config
            $cfg.defaultCookies[$platformKey] = $saved.FileName
            Save-Config -DefaultCookies $cfg.defaultCookies -DownloadDir $cfg.downloadDir

            Append-Log "已保存 cookies: $($saved.FileName)"
            Append-Log "已自动设为 $(Get-PlatformLabel $platformKey) 默认账号。"
            Refresh-UiState
            [System.Windows.Forms.MessageBox]::Show("登录成功！已保存 cookies: $($saved.FileName)`n已自动设为 $(Get-PlatformLabel $platformKey) 默认账号。", "登录成功", "OK", "Information") | Out-Null
        } else {
            Append-Log "WebView2 组件不可用，无法使用内嵌浏览器登录。请手动下载对应组件。"
            [System.Windows.Forms.MessageBox]::Show("WebView2 组件不可用，无法使用内嵌登录。`n请运行工具文件夹中的 portable_update_tools.ps1 下载所需组件。", "功能不可用", "OK", "Warning") | Out-Null
        }
    } catch {
        Append-Log "错误：$($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "操作失败", "OK", "Warning") | Out-Null
    }
})

$btnRefresh.Add_Click({
    Refresh-UiState
    Append-Log "账号状态已刷新。"
})

$btnSetDefaultCookie.Add_Click({
    Show-DefaultCookieDialog
})

$btnHelp.Add_Click({
    if (Test-Path $HelpFile) {
        Start-Process notepad.exe -ArgumentList @($HelpFile)
    } else {
        [System.Windows.Forms.MessageBox]::Show("未找到教程文件：$HelpFile", "无法打开教程", "OK", "Warning") | Out-Null
    }
})

$btnCopyLog.Add_Click({
    $urlText = $txtUrl.Text.Trim()
    $logText = $txtLog.Text.Trim()
    $body = @(
        "多平台视频下载器日志",
        "时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "平台：$($lblPlatform.Text)",
        "账号：$($lblCookie.Text)",
        "下载目录：$(Get-DownloadDir)",
        "链接：$urlText",
        $lblProgressStatus.Text,
        "",
        "日志：",
        $logText
    ) -join [Environment]::NewLine

    if ([string]::IsNullOrWhiteSpace($logText) -and [string]::IsNullOrWhiteSpace($urlText)) {
        [System.Windows.Forms.MessageBox]::Show("当前没有可复制的日志。", "复制日志", "OK", "Information") | Out-Null
        return
    }

    [System.Windows.Forms.Clipboard]::SetText($body)
    Append-Log "日志已复制到剪贴板。"
})

$btnClearLog.Add_Click({
    $txtLog.Clear()
    if (-not $script:CurrentJob) {
        Set-ProgressStatus -Text "进度：等待开始" -Percent 0
    }
})

$btnCli.Add_Click({
    Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $CliScript) -WorkingDirectory $ToolDir
})

$btnPackage.Add_Click({
    if (Test-Path $ShareMaker) {
        Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ShareMaker) -WorkingDirectory $ToolDir
    } else {
        [System.Windows.Forms.MessageBox]::Show("未找到分享包脚本：$ShareMaker", "无法制作分享包", "OK", "Warning") | Out-Null
    }
})

$btnProbe.Add_Click({ Start-YtDlpJob -ProbeOnly })
$btnDownload.Add_Click({ Start-YtDlpJob })

$btnCancel.Add_Click({
    if ($script:CurrentJob) {
        try {
            Append-Log "正在取消任务..."
            Set-ProgressStatus -Text "进度：正在取消任务" -Percent 0
            Stop-CurrentDownloadProcess
            Stop-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
            Finish-JobIfDone
        } catch {
            Append-Log "取消失败：$($_.Exception.Message)"
        }
    }
})

$form.Add_Shown({
    $txtDir.Text = Get-DownloadDir
    try {
        $clip = [System.Windows.Forms.Clipboard]::GetText().Trim()
        if (Is-Url $clip) {
            $txtUrl.Text = $clip
            Append-Log "已自动填入剪贴板链接。"
        }
    } catch {}
    Refresh-UiState
    Show-StartupHealth
    Append-Log "准备就绪。粘贴链接后点击'检测画质'或'开始下载'。"
})

$form.Add_FormClosing({
    if ($script:CurrentJob) {
        $result = [System.Windows.Forms.MessageBox]::Show("当前还有任务在运行，确定要退出并取消任务吗？", "确认退出", "YesNo", "Question")
        if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
            $_.Cancel = $true
            return
        }
        try {
            Stop-CurrentDownloadProcess
            Stop-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
        } catch {}
    }
})

if ($SmokeTest) {
    Refresh-UiState
    if (-not (Test-Path $YtDlp)) { throw "missing yt-dlp.exe" }
    if (-not (Test-Path $Ffmpeg)) { throw "missing ffmpeg.exe" }
    if (-not (Test-Path $Uv)) { throw "missing uv.exe" }
    if (-not (Test-Path $DouyinBackendDir)) { throw "missing douyin backend" }
    $testUrl = "https://www.youtube.com/watch?v=ZZavQ4dCi80"
    $testPlatform = Detect-PlatformFromUrl $testUrl
    if ($testPlatform -ne "youtube") { throw "platform detection failed" }
    $testArgs = Build-YtDlpArgs -VideoUrl $testUrl -Platform $testPlatform -CookieFile (Resolve-DefaultCookie -Platform $testPlatform) -ProbeOnly
    if ($testArgs -notcontains "--js-runtimes") { throw "youtube deno args missing" }
    if ($testArgs -notcontains "--no-playlist") { throw "single-video guard missing" }
    if ($testArgs -notcontains "--newline") { throw "progress output args missing" }
    $douyinTest = Resolve-InputUrl -InputText "复制打开抖音 https://www.douyin.com/discover?modal_id=1234567890" -Log $null
    if ($douyinTest -ne "https://www.douyin.com/video/1234567890") { throw "douyin normalization failed" }
    $douyinArgs = Build-DouyinBackendArgs -VideoUrl "https://www.douyin.com/video/1234567890" -CookieFile (Resolve-DefaultCookie -Platform "douyin")
    if ($douyinArgs -notcontains "run.py") { throw "douyin backend args missing" }
    Write-Output "GUI smoke test ok"
    exit 0
}

[void][System.Windows.Forms.Application]::Run($form)
