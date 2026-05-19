<# 便携版 yt-dlp / FFmpeg 更新脚本 #>
$ErrorActionPreference="Stop"
$ProgressPreference="SilentlyContinue"
$ToolDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$UserDataDir=Join-Path $ToolDir "_user_data"
$LogDir=Join-Path $UserDataDir "logs"
$TempDir=Join-Path $UserDataDir "tmp_update"
New-Item -ItemType Directory -Force -Path $LogDir,$TempDir|Out-Null
$Log=Join-Path $LogDir "update.log"
function Step($m){$line="[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$m; Write-Host $line; Add-Content -Encoding UTF8 -Path $Log -Value $line}
function Download($urls,$dest){foreach($u in $urls){try{Step "下载：$u"; $tmp="$dest.tmp"; if(Test-Path $tmp){Remove-Item -Force $tmp}; curl.exe --fail --location --retry 3 --connect-timeout 20 --output $tmp $u; if($LASTEXITCODE -eq 0 -and (Test-Path $tmp) -and ((Get-Item $tmp).Length -gt 0)){if(Test-Path $dest){Remove-Item -Force $dest}; Move-Item -Force $tmp $dest; return}; throw "curl exit $LASTEXITCODE"}catch{Step "失败：$($_.Exception.Message)"; if(Test-Path $tmp){Remove-Item -Force $tmp -ErrorAction SilentlyContinue}}}; throw "所有下载源失败：$dest"}
$YtDlp=Join-Path $ToolDir "yt-dlp.exe"
$Ffmpeg=Join-Path $ToolDir "ffmpeg.exe"
$Ffprobe=Join-Path $ToolDir "ffprobe.exe"
$Deno=Join-Path $ToolDir "deno.exe"
$Uv=Join-Path $ToolDir "uv.exe"
$ExternalDir=Join-Path $ToolDir "external"
$DouyinBackend=Join-Path $ExternalDir "douyin-downloader"
Download @("https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe","https://mirror.ghproxy.com/https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe","https://gh-proxy.com/https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe") $YtDlp
$uvZip=Join-Path $TempDir "uv.zip"
$uvExtract=Join-Path $TempDir "uv_extract"
Download @("https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip","https://mirror.ghproxy.com/https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip","https://gh-proxy.com/https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip") $uvZip
if(Test-Path $uvExtract){Remove-Item -Recurse -Force $uvExtract}
Expand-Archive -Force -Path $uvZip -DestinationPath $uvExtract
$foundUv=Get-ChildItem -Path $uvExtract -Recurse -Filter uv.exe|Select-Object -First 1 -ExpandProperty FullName
if(-not $foundUv){throw "解压后未找到 uv.exe"}
Copy-Item -Force $foundUv $Uv
$denoZip=Join-Path $TempDir "deno.zip"
$denoExtract=Join-Path $TempDir "deno_extract"
Download @("https://dl.deno.land/release/latest/deno-x86_64-pc-windows-msvc.zip","https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip","https://mirror.ghproxy.com/https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip","https://gh-proxy.com/https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip") $denoZip
if(Test-Path $denoExtract){Remove-Item -Recurse -Force $denoExtract}
Expand-Archive -Force -Path $denoZip -DestinationPath $denoExtract
$foundDeno=Get-ChildItem -Path $denoExtract -Recurse -Filter deno.exe|Select-Object -First 1 -ExpandProperty FullName
if(-not $foundDeno){throw "解压后未找到 deno.exe"}
Copy-Item -Force $foundDeno $Deno
$zip=Join-Path $TempDir "ffmpeg.zip"
$extract=Join-Path $TempDir "ffmpeg_extract"
Download @("https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip","https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip","https://mirror.ghproxy.com/https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip") $zip
if(Test-Path $extract){Remove-Item -Recurse -Force $extract}
Expand-Archive -Force -Path $zip -DestinationPath $extract
$foundFfmpeg=Get-ChildItem -Path $extract -Recurse -Filter ffmpeg.exe|Select-Object -First 1 -ExpandProperty FullName
$foundFfprobe=Get-ChildItem -Path $extract -Recurse -Filter ffprobe.exe|Select-Object -First 1 -ExpandProperty FullName
if(-not $foundFfmpeg){throw "解压后未找到 ffmpeg.exe"}
Copy-Item -Force $foundFfmpeg $Ffmpeg
if($foundFfprobe){Copy-Item -Force $foundFfprobe $Ffprobe}
Step "更新抖音专用后端"
New-Item -ItemType Directory -Force -Path $ExternalDir|Out-Null
$dyZip=Join-Path $TempDir "douyin-downloader.zip"
$dyExtract=Join-Path $TempDir "douyin_extract"
Download @("https://codeload.github.com/jiji262/douyin-downloader/zip/refs/heads/main","https://mirror.ghproxy.com/https://codeload.github.com/jiji262/douyin-downloader/zip/refs/heads/main","https://gh-proxy.com/https://codeload.github.com/jiji262/douyin-downloader/zip/refs/heads/main") $dyZip
if(Test-Path $dyExtract){Remove-Item -Recurse -Force $dyExtract}
Expand-Archive -Force -Path $dyZip -DestinationPath $dyExtract
$src=Get-ChildItem -Path $dyExtract -Directory|Where-Object{$_.Name -like "douyin-downloader-*"}|Select-Object -First 1
if(-not $src){throw "解压后未找到抖音后端源码"}
$preserveVenv=Join-Path $DouyinBackend ".venv"
$tempVenv=Join-Path $TempDir "preserve_douyin_venv"
if(Test-Path $tempVenv){Remove-Item -Recurse -Force $tempVenv}
if(Test-Path $preserveVenv){Move-Item -LiteralPath $preserveVenv -Destination $tempVenv}
if(Test-Path $DouyinBackend){Remove-Item -Recurse -Force $DouyinBackend}
Move-Item -LiteralPath $src.FullName -Destination $DouyinBackend
if(Test-Path $tempVenv){Move-Item -LiteralPath $tempVenv -Destination (Join-Path $DouyinBackend ".venv")}
Remove-Item -LiteralPath (Join-Path $DouyinBackend "config.yml"),(Join-Path $DouyinBackend ".cookies.json") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $DouyinBackend "tests"),(Join-Path $DouyinBackend "img"),(Join-Path $DouyinBackend "server"),(Join-Path $DouyinBackend "__pycache__") -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $DouyinBackend "AGENTS.md"),(Join-Path $DouyinBackend "CLAUDE.md"),(Join-Path $DouyinBackend "Dockerfile"),(Join-Path $DouyinBackend "PROJECT_SUMMARY.md"),(Join-Path $DouyinBackend ".dockerignore"),(Join-Path $DouyinBackend ".gitignore") -Force -ErrorAction SilentlyContinue

Step "更新 WebView2 登录组件"
$wvDir = Join-Path $ExternalDir "webview2"
New-Item -ItemType Directory -Force -Path $wvDir | Out-Null
$wvZip = Join-Path $TempDir "webview2.nupkg"
$wvExtractDir = Join-Path $TempDir "wv_extract"
Download @("https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.2903.40") $wvZip
if (Test-Path $wvExtractDir) { Remove-Item -Recurse -Force $wvExtractDir }
Expand-Archive -Force -Path $wvZip -DestinationPath $wvExtractDir
$wvCore = Get-ChildItem -Path $wvExtractDir -Recurse -Filter "Microsoft.Web.WebView2.Core.dll" | Where-Object { $_.DirectoryName -match "net462" } | Select-Object -First 1
$wvWinForms = Get-ChildItem -Path $wvExtractDir -Recurse -Filter "Microsoft.Web.WebView2.WinForms.dll" | Where-Object { $_.DirectoryName -match "net462" } | Select-Object -First 1
$wvLoader = Get-ChildItem -Path $wvExtractDir -Recurse -Filter "WebView2Loader.dll" | Where-Object { $_.DirectoryName -match "x64" } | Select-Object -First 1
if ((-not $wvCore) -or (-not $wvWinForms) -or (-not $wvLoader)) { throw "WebView2 NuGet package missing required DLLs" }
Copy-Item -Force $wvCore.FullName $wvDir
Copy-Item -Force $wvWinForms.FullName $wvDir
Copy-Item -Force $wvLoader.FullName $ToolDir
Step "WebView2 组件已更新"
Step "验证 yt-dlp"
& $YtDlp --version
Step "验证 uv"
& $Uv --version
Step "验证 ffmpeg"
& $Ffmpeg -version|Select-Object -First 1
Step "验证 deno"
& $Deno --version|Select-Object -First 1
Step "更新完成"
Read-Host "按 Enter 退出"
