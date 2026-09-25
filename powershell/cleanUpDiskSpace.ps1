# ==============================
# Deep Windows Cleanup Script
# Run as Administrator
# ==============================

Write-Host "Starting deep cleanup..." -ForegroundColor Cyan

# ------------------------------
# 1. Clear TEMP folders (all users + system)
# ------------------------------
Write-Host "Clearing TEMP folders..." -ForegroundColor Yellow

Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $userTemp = "$($_.FullName)\AppData\Local\Temp"
    if (Test-Path $userTemp) {
        Write-Host " - $userTemp"
        Get-ChildItem $userTemp -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$systemTemps = @(
    "C:\Windows\Temp",
    $env:TEMP
)

foreach ($path in $systemTemps) {
    if (Test-Path $path) {
        Write-Host " - $path"
        Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------
# 2. Clear crash dumps
# ------------------------------
Write-Host "Clearing User CrashDumps..." -ForegroundColor Yellow
Get-ChildItem "C:\Users" -Directory -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "CrashDumps" } |
    ForEach-Object {
        Write-Host "Deleting $($_.FullName)..."
        Remove-Item $_.FullName -Recurse -Force -ErrorAction Continue
    }

# ------------------------------
# 2. Clear browser caches (Edge / Chrome)
# ------------------------------
Write-Host "Clearing browser caches..." -ForegroundColor Yellow

Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $browserCaches = @(
        "$($_.FullName)\AppData\Local\Microsoft\Edge\User Data\Default\Cache",
        "$($_.FullName)\AppData\Local\Google\Chrome\User Data\Default\Cache"
    )

    foreach ($cache in $browserCaches) {
        if (Test-Path $cache) {
            Write-Host " - $cache"
            Get-ChildItem $cache -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------
# 3. Clear WinINET / IE cache (ALL USERS)
# ------------------------------
Write-Host "Clearing WinINET / IE cache for all users..." -ForegroundColor Yellow

Get-ChildItem "C:\Users" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $inetCache = "$($_.FullName)\AppData\Local\Microsoft\Windows\INetCache"
    $inetCookies = "$($_.FullName)\AppData\Local\Microsoft\Windows\INetCookies"
    $inetHistory = "$($_.FullName)\AppData\Local\Microsoft\Windows\History"

    foreach ($path in @($inetCache, $inetCookies, $inetHistory)) {
        if (Test-Path $path) {
            Write-Host " - $path"
            Get-ChildItem $path -Recurse -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------
# 4. Clear Windows Update cache
# ------------------------------
Write-Host "Clearing Windows Update cache..." -ForegroundColor Yellow

$services = "wuauserv","bits","cryptsvc","msiserver"

foreach ($svc in $services) {
    Get-Service $svc -ErrorAction SilentlyContinue |
        Where-Object {$_.Status -ne "Stopped"} |
        Stop-Service -Force -ErrorAction SilentlyContinue
}

$wuPaths = @(
    "C:\Windows\SoftwareDistribution",
    "C:\Windows\System32\catroot2"
)

foreach ($path in $wuPaths) {
    if (Test-Path $path) {
        Write-Host " - Removing $path"
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

foreach ($svc in $services) {
    Start-Service $svc -ErrorAction SilentlyContinue
}

# ------------------------------
# Done
# ------------------------------
Write-Host "Cleanup complete. Reboot recommended." -ForegroundColor Green
