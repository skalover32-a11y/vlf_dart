$ErrorActionPreference = 'Stop'
$target='D:\releases\VLF_tun_only'
if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
New-Item -ItemType Directory -Path $target | Out-Null
$src='D:\vlf\vlf_dart\release\windows_x64_release\*'
Write-Host 'Copying release contents excluding config files...'
Copy-Item -Path $src -Destination $target -Recurse -Force -Exclude 'config.yaml','config_debug.yaml','config_test.yaml','vlf_gui_config.json','profiles.json'
Write-Host 'Cleaning any stray config files in target (just in case)...'
Get-ChildItem -Path $target -Include 'config*.json','vlf_gui_config.json','profiles.json' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
Write-Host 'Listing target files:'
Get-ChildItem -Path $target | ForEach-Object { Write-Host (" - $($_.Name)") }

# Prepare zip directory
$zipdir='D:\releases\releases_git'
if (-not (Test-Path $zipdir)) { New-Item -ItemType Directory -Path $zipdir | Out-Null }
$zipPath=Join-Path $zipdir 'VLF tun only.zip'
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Write-Host "Creating zip: $zipPath"
Compress-Archive -Path (Join-Path $target '*') -DestinationPath $zipPath -Force
Write-Host "Created zip: $zipPath"
