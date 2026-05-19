<# 制作分享包，自动排除个人数据和临时文件。 #>
$ErrorActionPreference="Stop"
$ToolDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageDir=Join-Path $ToolDir "_packages"
New-Item -ItemType Directory -Force -Path $PackageDir|Out-Null
$date=Get-Date -Format "yyyyMMdd-HHmmss"
$zip=Join-Path $PackageDir "yt-dlp-portable-$date.zip"
$temp=Join-Path $PackageDir "_pack_$date"
if(Test-Path $temp){Remove-Item -Recurse -Force $temp}
New-Item -ItemType Directory -Force -Path $temp|Out-Null

$skipRoot=@("_user_data","_packages")
$skipNames=@("config.yml",".cookies.json","download_manifest.jsonl")
$skipPatterns=@(
    "\\cookies.*\.txt$",
    "\\settings\.json$",
    "\\update_status\.json$",
    "\\douyin_backend_config\.yml$",
    "\\external\\uv-cache(\\|$)",
    "\\event_test",
    "\\douyin_page_test",
    "\\\.git\\",
    "\\\.temp\\",
    "\\\.lock$"
)

Get-ChildItem -Force $ToolDir|Where-Object{$skipRoot -notcontains $_.Name}|ForEach-Object{
    $source=$_.FullName
    $dest=Join-Path $temp $_.Name
    if($_.PSIsContainer){
        Get-ChildItem -LiteralPath $source -Recurse -Force|ForEach-Object{
            $rel=$_.FullName.Substring($source.Length).TrimStart("\")
            if([string]::IsNullOrWhiteSpace($rel)){return}
            if($skipNames -contains $_.Name){return}
            foreach($pattern in $skipPatterns){ if($_.FullName -match $pattern){ return } }
            $target=Join-Path $dest $rel
            if($_.PSIsContainer){ New-Item -ItemType Directory -Force -Path $target|Out-Null }
            else{
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null
                Copy-Item -LiteralPath $_.FullName -Destination $target -Force
            }
        }
    } else {
        if($skipNames -contains $_.Name){return}
        foreach($pattern in $skipPatterns){ if($_.FullName -match $pattern){ return } }
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
}

Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $zip -Force
Remove-Item -Recurse -Force $temp
Write-Host "分享包已生成：$zip"
Write-Host "已排除 _user_data、_packages、cookies、设置、日志状态和临时文件。"
Read-Host "按 Enter 退出"
