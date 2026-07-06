$ProgressPreference = 'SilentlyContinue'

$url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.19.6-stable.zip"
$zipPath = "$env:USERPROFILE\Downloads\flutter.zip"
$extractPath = "C:\"

Write-Host "Downloading Flutter FAST MODE (this will take 1-2 minutes)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $url -OutFile $zipPath

Write-Host "Extracting Flutter to C:\flutter..." -ForegroundColor Cyan
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

Write-Host "Adding Flutter to System PATH..." -ForegroundColor Cyan
$oldPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($oldPath -notmatch "C:\\flutter\\bin") {
    $newPath = $oldPath + ";C:\flutter\bin"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
}

Write-Host "Cleaning up zip file..." -ForegroundColor Cyan
Remove-Item $zipPath -Force

Write-Host "===============================================" -ForegroundColor Green
Write-Host "FLUTTER INSTALLATION COMPLETE!" -ForegroundColor Green
Write-Host "Please close this VS Code window completely and reopen it." -ForegroundColor Yellow
Write-Host "Then type: flutter --version" -ForegroundColor Yellow
Write-Host "===============================================" -ForegroundColor Green
