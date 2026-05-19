<# Cookies 快速检查脚本 —— 验证替换 cookies 后是否有效 #>
$ErrorActionPreference = "Stop"
$ToolDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CookieDir = Join-Path $ToolDir "_user_data\cookies"
$YtDlp = Join-Path $ToolDir "yt-dlp.exe"

if (-not (Test-Path $CookieDir)) { Write-Host "Cookies 目录不存在：$CookieDir"; exit 1 }

$platforms = @{
    bilibili  = @{ Name = "B站"; Keys = @("SESSDATA", "DedeUserID", "bili_jct") }
    douyin    = @{ Name = "抖音"; Keys = @("sessionid", "uid_tt") }
    twitter   = @{ Name = "Twitter/X"; Keys = @("auth_token") }
    youtube   = @{ Name = "YouTube"; Keys = @("SAPISID") }
    instagram = @{ Name = "Instagram"; Keys = @("sessionid") }
}

Write-Host "============================================"
Write-Host "Cookies 检查"
Write-Host "============================================"
Write-Host ""

$allOk = $true

foreach ($platform in $platforms.Keys) {
    $info = $platforms[$platform]
    $pattern = "cookies_${platform}_*.txt"
    $files = @(Get-ChildItem -Path $CookieDir -Filter $pattern -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)

    if ($files.Count -eq 0) {
        Write-Host "  $($info.Name)：未找到 cookies 文件           [--]"
        continue
    }

    $file = $files[0]
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    $missing = @()
    foreach ($key in $info.Keys) {
        if ($content -notmatch "(?m)^[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t[^\t]+\t$key\t\S") {
            $missing += $key
        }
    }

    if ($missing.Count -eq 0) {
        Write-Host "  $($info.Name)：$(Get-CookieLabelSimple $file)  [OK]"
    } else {
        $allOk = $false
        Write-Host "  $($info.Name)：$(Get-CookieLabelSimple $file)  [过期] 缺少: $($missing -join ', ')"
    }
}

Write-Host ""
if ($allOk) { Write-Host "所有平台 cookies 检查通过。" } else { Write-Host "部分 cookies 已过期，请重新登录对应平台。工具菜单 → 登录/切换账号。" }
Write-Host ""
Read-Host "按 Enter 退出"

function Get-CookieLabelSimple {
    param([System.IO.FileInfo]$File)
    return $File.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
}
